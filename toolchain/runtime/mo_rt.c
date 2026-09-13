/* mo_rt.c: the runtime a compiled Mo program links (mo_rt.h says what a value is).
 * Each part names the interpreter file it reproduces; where the two could differ, the
 * interpreter is the reference and this file follows it. */
#ifndef _DEFAULT_SOURCE
#define _DEFAULT_SOURCE
#endif
#ifndef _DARWIN_C_SOURCE
#define _DARWIN_C_SOURCE
#endif
#include "mo_rt.h"

#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <math.h>
#include <setjmp.h>
#include <signal.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

extern char **environ;

/* ==== memory (vm.zig: regions, push in place, owned buffers, compaction) ============== */

MoRegion mo_heap;
bool mo_compacts;
bool mo_records;
bool mo_contracts;
static MoRegion scratch;
static char empty_bytes[1];

_Noreturn static void out_of_memory(void) {
    fputs("mo: out of memory\n", stderr);
    exit(70);
}

static void *xmalloc(size_t n) {
    void *p = malloc(n ? n : 1);
    if (!p) out_of_memory();
    return p;
}

static void *xrealloc(void *p, size_t n) {
    void *q = realloc(p, n ? n : 1);
    if (!q) out_of_memory();
    return q;
}

/* As much address space as the system gives, from 64 GiB down to 256 MiB (region.zig). */
static bool reserve(MoRegion *r) {
    for (size_t size = (size_t)64 << 30; size >= (size_t)256 << 20; size /= 2) {
        void *mem = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
        if (mem == MAP_FAILED) continue;
        r->base = r->top = (uintptr_t)mem;
        r->end = r->base + size;
        return true;
    }
    return false;
}

static void *region_alloc(MoRegion *r, size_t n) {
    uintptr_t start = (r->top + 7) & ~(uintptr_t)7;
    if (r->end != 0 && start + n <= r->end) {
        r->top = start + n;
        return (void *)start;
    }
    /* Past the region, or no region at all: memory that lives until the run ends. */
    return xmalloc(n);
}

void *mo_alloc_bytes(size_t n) {
    if (n == 0) return empty_bytes;
    return region_alloc(&mo_heap, n);
}

MoValue *mo_alloc_values(size_t n) {
    if (n == 0) return NULL;
    return region_alloc(&mo_heap, n * sizeof(MoValue));
}

static bool in_heap(uintptr_t addr) { return addr >= mo_heap.base && addr < mo_heap.end; }

/* The lists push can grow in place: the sixteen it grew last. */
typedef struct { uintptr_t ptr; size_t len, cap; } Growth;
static Growth growth[16];
static unsigned growth_next;

typedef struct { uintptr_t ptr; size_t len; } SliceKey;
/* Map and set buffers one var holds alone. */
static SliceKey owned[16];
static unsigned owned_next;

/* Slots a row wrote in place with a value that may be newer than the slot. */
typedef struct { uintptr_t slot; size_t len; uintptr_t at; } Remembered;
static Remembered *remembered;
static size_t nremembered, capremembered;

/* Forgets every buffer a test's memory held: the next test starts a fresh vm. */
static void reset_memory(void) {
    mo_heap.top = mo_heap.base;
    memset(growth, 0, sizeof growth);
    memset(owned, 0, sizeof owned);
    growth_next = owned_next = 0;
    nremembered = 0;
}

static Growth *growth_of(uintptr_t addr, size_t len) {
    for (unsigned i = 0; i < 16; i++) {
        if (growth[i].ptr == addr && growth[i].len == len && growth[i].cap != 0) return &growth[i];
    }
    return NULL;
}

static void drop_growth(uintptr_t lo, uintptr_t hi) {
    for (unsigned i = 0; i < 16; i++) {
        if (growth[i].ptr >= lo && growth[i].ptr < hi) growth[i] = (Growth){0, 0, 0};
        if (owned[i].ptr >= lo && owned[i].ptr < hi) owned[i] = (SliceKey){0, 0};
    }
}

static bool is_owned(const MoValue *xs, size_t len) {
    if (len == 0) return false;
    for (unsigned i = 0; i < 16; i++) {
        if (owned[i].ptr == (uintptr_t)xs && owned[i].len == len) return true;
    }
    return false;
}

static void own(const MoValue *xs, size_t len) {
    if (len == 0 || is_owned(xs, len)) return;
    owned[owned_next] = (SliceKey){(uintptr_t)xs, len};
    owned_next = (owned_next + 1) % 16;
}

static void disown(const MoValue *xs, size_t len) {
    for (unsigned i = 0; i < 16; i++) {
        if (owned[i].ptr == (uintptr_t)xs && owned[i].len == len) owned[i] = (SliceKey){0, 0};
    }
}

void mo_disown_in(MoValue v) {
    switch (v.tag) {
    case MO_MAP:
    case MO_SET:
        if (v.as.m) disown(v.as.m->entries, v.as.m->len);
        break;
    case MO_RECORD:
        for (uint32_t k = 0; k < mo_decls[v.aux].nfields; k++) mo_disown_in(v.as.xs[k]);
        break;
    default:
        break;
    }
}

uint32_t mo_nfields(MoValue v) {
    switch (v.tag) {
    case MO_RECORD: return mo_decls[v.aux].nfields;
    case MO_VARIANT: return mo_vcount(v);
    case MO_TUPLE:
    case MO_LIST: return v.aux;
    default: return 0;
    }
}

/* The newest address a value's own parts start at, when it has a non-empty one. */
static uintptr_t newest_of(MoValue v) {
    switch (v.tag) {
    case MO_STRING: return v.aux ? (uintptr_t)v.as.s : 0;
    case MO_BIG: return (uintptr_t)v.as.big;
    case MO_LIST:
    case MO_TUPLE: return v.aux ? (uintptr_t)v.as.xs : 0;
    case MO_RECORD:
    case MO_VARIANT: return mo_nfields(v) ? (uintptr_t)v.as.xs : 0;
    case MO_MAP:
    case MO_SET: return (uintptr_t)v.as.m;
    case MO_FUNC: return (uintptr_t)v.as.fn;
    default: return 0;
    }
}

/* `n` slots from `slot` were written in place; `x` the value when one was. */
static void remember_write(uintptr_t slot, size_t n, const MoValue *x) {
    if (!mo_compacts || !in_heap(slot)) return;
    if (x) {
        uintptr_t p = newest_of(*x);
        if (p == 0 || !in_heap(p) || p < slot) return;
    }
    if (nremembered == capremembered) {
        capremembered = capremembered ? 2 * capremembered : 256;
        remembered = xrealloc(remembered, capremembered * sizeof(Remembered));
    }
    remembered[nremembered++] = (Remembered){slot, n, mo_heap.top};
}

static void overwrite(MoValue *slot, MoValue x) {
    remember_write((uintptr_t)slot, 1, &x);
    *slot = x;
}

/* `xs.push(x)`: in place when xs ends where its buffer's last push left it and there is room. */
static MoValue *push_list(MoValue *xs, size_t len, MoValue x) {
    if (len > 0) {
        Growth *g = growth_of((uintptr_t)xs, len);
        if (g && g->len < g->cap) {
            MoValue *buf = (MoValue *)g->ptr;
            remember_write(g->ptr + g->len * sizeof(MoValue), 1, &x);
            buf[g->len] = x;
            g->len += 1;
            return buf;
        }
    }
    size_t cap = len * 2 > 4 ? len * 2 : 4;
    MoValue *out = mo_alloc_values(cap);
    if (len) memcpy(out, xs, len * sizeof(MoValue));
    out[len] = x;
    growth[growth_next] = (Growth){(uintptr_t)out, len + 1, cap};
    growth_next = (growth_next + 1) % 16;
    return out;
}

/* ---- the forward table: a compaction copies a slice reached twice once */

typedef struct { uintptr_t ptr; size_t len; MoValue *to; uint32_t gen; } Forward;
static Forward *forwards;
static size_t forward_cap, forward_used;
static uint32_t forward_gen = 1;

static void forward_clear(void) {
    forward_gen++;
    forward_used = 0;
    if (forward_gen == 0) {
        memset(forwards, 0, forward_cap * sizeof(Forward));
        forward_gen = 1;
    }
}

static size_t forward_slot(uintptr_t ptr, size_t len) {
    uint64_t h = (uint64_t)ptr * 0x9e3779b97f4a7c15ull ^ (uint64_t)len * 0xbf58476d1ce4e5b9ull;
    return (size_t)(h ^ (h >> 29)) & (forward_cap - 1);
}

static MoValue *forward_get(uintptr_t ptr, size_t len) {
    if (forward_cap == 0) return NULL;
    for (size_t i = forward_slot(ptr, len);; i = (i + 1) & (forward_cap - 1)) {
        Forward *f = &forwards[i];
        if (f->gen != forward_gen) return NULL;
        if (f->ptr == ptr && f->len == len) return f->to;
    }
}

static void forward_put(uintptr_t ptr, size_t len, MoValue *to) {
    if (2 * (forward_used + 1) > forward_cap) {
        size_t old_cap = forward_cap;
        Forward *old = forwards;
        forward_cap = forward_cap ? 2 * forward_cap : 4096;
        forwards = calloc(forward_cap, sizeof(Forward));
        if (!forwards) out_of_memory();
        forward_used = 0;
        for (size_t i = 0; i < old_cap; i++) {
            if (old[i].gen != forward_gen) continue;
            size_t j = forward_slot(old[i].ptr, old[i].len);
            while (forwards[j].gen == forward_gen) j = (j + 1) & (forward_cap - 1);
            forwards[j] = old[i];
            forward_used++;
        }
        free(old);
    }
    size_t i = forward_slot(ptr, len);
    while (forwards[i].gen == forward_gen) i = (i + 1) & (forward_cap - 1);
    forwards[i] = (Forward){ptr, len, to, forward_gen};
    forward_used++;
}

/* ---- compaction */

typedef struct { uintptr_t lo, hi; MoRegion *dest; bool moves, fresh; } Copy;

static bool inside(uintptr_t addr, const Copy *c) { return addr >= c->lo && addr < c->hi; }

static uint32_t *build_index(MoRegion *dest, const MoValue *entries, size_t len, size_t stride, size_t min_slots, uint32_t *index_len);
static MoValue copy_out(MoValue v, const Copy *c);

static MoValue *copy_slice(MoValue *xs, size_t len, const Copy *c, bool grows) {
    uintptr_t addr = (uintptr_t)xs;
    if (len == 0 || !inside(addr, c)) return xs;
    MoValue *copied = forward_get(addr, len);
    if (copied) return copied;
    Growth *g = grows && c->moves ? growth_of(addr, len) : NULL;
    MoValue *out = region_alloc(c->dest, (g ? g->cap : len) * sizeof(MoValue));
    forward_put(addr, len, out);
    for (size_t i = 0; i < len; i++) out[i] = copy_out(xs[i], c);
    if (g) g->ptr = (uintptr_t)out;
    if (c->moves) {
        for (unsigned i = 0; i < 16; i++) {
            if (owned[i].ptr == addr && owned[i].len == len) owned[i].ptr = (uintptr_t)out;
        }
    }
    return out;
}

static MoMap *copy_map(MoMap *m, size_t stride, const Copy *c) {
    if (!m) return NULL;
    bool header_inside = inside((uintptr_t)m, c);
    MoValue *entries = copy_slice(m->entries, m->len, c, true);
    uint32_t *index = NULL;
    uint32_t index_len = 0;
    if (m->index_len > 0) {
        bool index_inside = inside((uintptr_t)m->index, c);
        if (entries == m->entries && !index_inside) {
            index = m->index;
            index_len = m->index_len;
        } else if (!c->moves || c->fresh || m->index[0] == m->len / stride) {
            index = region_alloc(c->dest, m->index_len * sizeof(uint32_t));
            memcpy(index, m->index, m->index_len * sizeof(uint32_t));
            index_len = m->index_len;
        } else {
            index = build_index(c->dest, entries, m->len, stride, m->index_len - 1, &index_len);
        }
    }
    if (!header_inside && entries == m->entries && index == m->index) return m;
    MoMap *out = region_alloc(c->dest, sizeof(MoMap));
    *out = (MoMap){entries, m->len, index_len, index};
    return out;
}

static MoValue copy_out(MoValue v, const Copy *c) {
    switch (v.tag) {
    case MO_STRING:
        if (v.aux > 0 && inside((uintptr_t)v.as.s, c)) {
            char *s = region_alloc(c->dest, v.aux);
            memcpy(s, v.as.s, v.aux);
            v.as.s = s;
        }
        return v;
    case MO_BIG:
        if (inside((uintptr_t)v.as.big, c)) {
            __int128 *b = region_alloc(c->dest, sizeof(__int128));
            *b = *v.as.big;
            v.as.big = b;
        }
        return v;
    case MO_LIST: v.as.xs = copy_slice(v.as.xs, v.aux, c, true); return v;
    case MO_TUPLE: v.as.xs = copy_slice(v.as.xs, v.aux, c, false); return v;
    case MO_RECORD:
    case MO_VARIANT: v.as.xs = copy_slice(v.as.xs, mo_nfields(v), c, false); return v;
    case MO_MAP: v.as.m = copy_map(v.as.m, 2, c); return v;
    case MO_SET: v.as.m = copy_map(v.as.m, 1, c); return v;
    case MO_FUNC:
        if (inside((uintptr_t)v.as.fn, c)) {
            MoFunc *f = v.as.fn;
            MoFunc *out = region_alloc(c->dest, sizeof(MoFunc) + f->ncap * sizeof(MoValue));
            out->code = f->code;
            out->id = f->id;
            out->ncap = f->ncap;
            for (uint32_t i = 0; i < f->ncap; i++) out->cap[i] = copy_out(f->cap[i], c);
            v.as.fn = out;
        }
        return v;
    default:
        return v;
    }
}

static void copy_roots(MoValue *roots, size_t n, Remembered *slots, size_t nslots, const Copy *c) {
    for (size_t i = 0; i < n; i++) roots[i] = copy_out(roots[i], c);
    for (size_t i = 0; i < nslots; i++) {
        MoValue *xs = (MoValue *)slots[i].slot;
        for (size_t k = 0; k < slots[i].len; k++) xs[k] = copy_out(xs[k], c);
    }
}

/* Copies what `roots` reach past `from` into the scratch region, frees everything past
 * `from`, and copies it back; `roots` then hold the copies. A value points only at older
 * values, except where a row wrote into an older buffer in place, and those slots are
 * remembered: so what `roots` and the remembered slots below `from` reach is all that is kept. */
void mo_compact(size_t from, MoValue *roots, size_t n) {
    if (!mo_compacts) return;
    uintptr_t old_top = mo_heap.top;
    size_t first = nremembered;
    while (first > 0 && remembered[first - 1].at > from) first--;
    size_t k = first;
    for (size_t i = first; i < nremembered; i++) {
        Remembered e = remembered[i];
        if (e.slot >= from && e.slot < old_top) continue;
        remembered[k++] = e;
    }
    nremembered = k;
    Remembered *below = remembered + first;
    size_t nbelow = nremembered - first;
    scratch.top = scratch.base;
    forward_clear();
    Copy out = {from, old_top, &scratch, true, false};
    copy_roots(roots, n, below, nbelow, &out);
    mo_heap.top = from;
    drop_growth(from, old_top);
    forward_clear();
    Copy back = {scratch.base, scratch.top, &mo_heap, true, true};
    copy_roots(roots, n, below, nbelow, &back);
    drop_growth(scratch.base, scratch.end);
    for (size_t i = 0; i < nbelow; i++) below[i].at = mo_heap.top;
}

/* ==== values: building, equality, order, hashing (vm.zig, stdlib.zig) ================== */

MoValue mo_i128(__int128 x) {
    if (x >= INT64_MIN && x <= INT64_MAX) return mo_i64((int64_t)x);
    if (x > 0 && x <= (__int128)UINT64_MAX) return mo_u64((uint64_t)x);
    MoValue v = {MO_BIG, 0, {0}};
    v.as.big = mo_alloc_bytes(sizeof(__int128));
    *v.as.big = x;
    return v;
}

static MoValue *dupe_values(const MoValue *xs, size_t n) {
    MoValue *out = mo_alloc_values(n);
    if (n) memcpy(out, xs, n * sizeof(MoValue));
    return out;
}

MoValue mo_record(uint32_t decl, uint32_t n, const MoValue *fields) {
    MoValue v = {MO_RECORD, decl, {0}};
    v.as.xs = dupe_values(fields, n);
    return v;
}

MoValue mo_variant(uint32_t name, uint32_t n, const MoValue *fields) {
    MoValue v = {MO_VARIANT, name | n << 16, {0}};
    v.as.xs = dupe_values(fields, n);
    return v;
}

MoValue mo_tuple(uint32_t n, const MoValue *elems) { return mo_tuple_of(dupe_values(elems, n), n); }

MoValue mo_list_of(uint32_t n, const MoValue *elems) { return mo_list(dupe_values(elems, n), n); }

MoValue mo_set_field(MoValue obj, uint32_t k, MoValue v) {
    uint32_t n = mo_nfields(obj);
    MoValue *fields = dupe_values(obj.as.xs, n);
    fields[k] = v;
    obj.as.xs = fields;
    return obj;
}

MoValue mo_closure(MoCode code, uint32_t id, uint32_t n, const MoValue *caps) {
    MoFunc *f = mo_alloc_bytes(sizeof(MoFunc) + n * sizeof(MoValue));
    f->code = code;
    f->id = id;
    f->ncap = n;
    if (n) memcpy(f->cap, caps, n * sizeof(MoValue));
    MoValue v = {MO_FUNC, 0, {0}};
    v.as.fn = f;
    return v;
}

static bool all_equal(const MoValue *a, const MoValue *b, size_t n) {
    for (size_t i = 0; i < n; i++) {
        if (!mo_equal(a[i], b[i])) return false;
    }
    return true;
}

bool mo_equal(MoValue a, MoValue b) {
    if (a.tag != b.tag) return false;
    switch (a.tag) {
    case MO_NONE: return true;
    case MO_BOOL: return a.as.b == b.as.b;
    case MO_INT:
    case MO_UINT:
    case MO_TIME:
    case MO_DURATION: return a.as.i == b.as.i;
    case MO_BIG: return *a.as.big == *b.as.big;
    case MO_FLOAT: return a.as.f == b.as.f;
    case MO_STRING: return a.aux == b.aux && (a.aux == 0 || memcmp(a.as.s, b.as.s, a.aux) == 0);
    case MO_LIST:
    case MO_TUPLE: return a.aux == b.aux && all_equal(a.as.xs, b.as.xs, a.aux);
    case MO_MAP:
    case MO_SET: {
        uint32_t la = a.as.m ? a.as.m->len : 0, lb = b.as.m ? b.as.m->len : 0;
        return la == lb && (la == 0 || all_equal(a.as.m->entries, b.as.m->entries, la));
    }
    case MO_RECORD: return a.aux == b.aux && all_equal(a.as.xs, b.as.xs, mo_decls[a.aux].nfields);
    case MO_VARIANT: return a.aux == b.aux && all_equal(a.as.xs, b.as.xs, mo_vcount(a));
    case MO_FUNC: return a.as.fn->id == b.as.fn->id && a.as.fn->ncap == b.as.fn->ncap && all_equal(a.as.fn->cap, b.as.fn->cap, a.as.fn->ncap);
    case MO_CAP: return a.aux == b.aux && a.as.i == b.as.i;
    case MO_HANDLE: return a.as.i == b.as.i;
    default: return false;
    }
}

static int order_of(__int128 a, __int128 b) { return a < b ? -1 : a > b ? 1 : 0; }

int mo_order(MoValue l, MoValue r) {
    switch (l.tag) {
    case MO_INT:
    case MO_UINT:
    case MO_BIG: return order_of(mo_wide(l), mo_wide(r));
    case MO_FLOAT: {
        bool an = isnan(l.as.f), bn = isnan(r.as.f);
        if (an || bn) return an == bn ? 0 : an ? 1 : -1;
        return l.as.f < r.as.f ? -1 : l.as.f > r.as.f ? 1 : 0;
    }
    case MO_STRING: {
        uint32_t n = l.aux < r.aux ? l.aux : r.aux;
        int c = n ? memcmp(l.as.s, r.as.s, n) : 0;
        if (c != 0) return c < 0 ? -1 : 1;
        return l.aux < r.aux ? -1 : l.aux > r.aux ? 1 : 0;
    }
    case MO_TIME:
    case MO_DURATION: return l.as.i < r.as.i ? -1 : l.as.i > r.as.i ? 1 : 0;
    case MO_TUPLE:
        for (uint32_t i = 0; i < l.aux && i < r.aux; i++) {
            int o = mo_order(l.as.xs[i], r.as.xs[i]);
            if (o != 0) return o;
        }
        return 0;
    default: return 0;
    }
}

bool mo_compare(int op, MoValue l, MoValue r) {
    if (op == MO_EQ) return mo_equal(l, r);
    if (op == MO_NE) return !mo_equal(l, r);
    if (l.tag == MO_FLOAT) {
        double a = l.as.f, b = r.as.f;
        switch (op) {
        case MO_LT: return a < b;
        case MO_LE: return a <= b;
        case MO_GT: return a > b;
        default: return a >= b;
        }
    }
    int o = mo_order(l, r);
    switch (op) {
    case MO_LT: return o < 0;
    case MO_LE: return o <= 0;
    case MO_GT: return o > 0;
    default: return o >= 0;
    }
}

/* Equal values (mo_equal) hash alike. */
static uint64_t mix(uint64_t h, uint64_t x) {
    h ^= x + 0x9e3779b97f4a7c15ull + (h << 6) + (h >> 2);
    h *= 0xff51afd7ed558ccdull;
    return h ^ (h >> 33);
}

static uint64_t hash_value(MoValue v) {
    uint64_t h = mix(0x6d6f, v.tag);
    switch (v.tag) {
    case MO_BOOL: return mix(h, v.as.b);
    case MO_INT:
    case MO_UINT:
    case MO_TIME:
    case MO_DURATION: return mix(h, v.as.u);
    case MO_BIG: return mix(mix(h, (uint64_t)*v.as.big), (uint64_t)(*v.as.big >> 64));
    case MO_FLOAT: return mix(h, v.as.f == 0 ? 0 : v.as.u);
    case MO_STRING:
        h = mix(h, v.aux);
        for (uint32_t i = 0; i < v.aux; i++) h = (h ^ (unsigned char)v.as.s[i]) * 0x100000001b3ull;
        return mix(h, 0);
    case MO_LIST:
    case MO_TUPLE:
        h = mix(h, v.aux);
        for (uint32_t i = 0; i < v.aux; i++) h = mix(h, hash_value(v.as.xs[i]));
        return h;
    case MO_MAP:
    case MO_SET: {
        uint32_t n = v.as.m ? v.as.m->len : 0;
        h = mix(h, n);
        for (uint32_t i = 0; i < n; i++) h = mix(h, hash_value(v.as.m->entries[i]));
        return h;
    }
    case MO_RECORD:
    case MO_VARIANT: {
        h = mix(h, v.aux);
        uint32_t n = mo_nfields(v);
        for (uint32_t i = 0; i < n; i++) h = mix(h, hash_value(v.as.xs[i]));
        return h;
    }
    case MO_FUNC:
        h = mix(h, v.as.fn->id);
        for (uint32_t i = 0; i < v.as.fn->ncap; i++) h = mix(h, hash_value(v.as.fn->cap[i]));
        return h;
    case MO_CAP: return mix(mix(h, v.aux), v.as.u);
    default: return mix(h, v.as.u);
    }
}

/* ---- the map and set index (stdlib.zig: find, buildIndex, put, without) */

#define INDEX_FROM 8

static size_t index_of(const MoValue *xs, size_t len, size_t stride, MoValue key) {
    for (size_t k = 0; k < len; k += stride) {
        if (mo_equal(xs[k], key)) return k;
    }
    return SIZE_MAX;
}

static size_t map_find(const MoMap *m, size_t stride, MoValue key) {
    if (!m) return SIZE_MAX;
    if (m->index_len == 0) return index_of(m->entries, m->len, stride, key);
    uint32_t *table = m->index + 1;
    size_t mask = m->index_len - 2;
    for (size_t i = (size_t)hash_value(key) & mask;; i = (i + 1) & mask) {
        uint32_t slot = table[i];
        if (slot == 0) return SIZE_MAX;
        size_t at = (size_t)(slot - 1) * stride;
        if (at < m->len && mo_equal(m->entries[at], key)) return at;
    }
}

static bool room_for_one(const uint32_t *index, uint32_t index_len) {
    return index_len > 0 && index_len - 1 >= 2 * (index[0] + 1);
}

static void insert_ordinal(uint32_t *index, uint32_t index_len, const MoValue *entries, size_t stride, size_t ordinal) {
    uint32_t *table = index + 1;
    size_t mask = index_len - 2;
    size_t i = (size_t)hash_value(entries[ordinal * stride]) & mask;
    while (table[i] != 0) i = (i + 1) & mask;
    table[i] = (uint32_t)(ordinal + 1);
    index[0] += 1;
}

static uint32_t *build_index(MoRegion *dest, const MoValue *entries, size_t len, size_t stride, size_t min_slots, uint32_t *index_len) {
    size_t keys = len / stride;
    *index_len = 0;
    if (keys < INDEX_FROM) return NULL;
    size_t slots = min_slots > 16 ? min_slots : 16;
    while (slots < 2 * keys) slots *= 2;
    uint32_t *index = region_alloc(dest, (slots + 1) * sizeof(uint32_t));
    memset(index, 0, (slots + 1) * sizeof(uint32_t));
    *index_len = (uint32_t)(slots + 1);
    for (size_t o = 0; o < keys; o++) insert_ordinal(index, *index_len, entries, stride, o);
    return index;
}

static MoMap *map_header(MoValue *entries, size_t len, uint32_t *index, uint32_t index_len) {
    if (len == 0) return NULL;
    MoMap *m = mo_alloc_bytes(sizeof(MoMap));
    *m = (MoMap){entries, (uint32_t)len, index_len, index};
    return m;
}

/* A map or set of these entries, with the index it needs. */
static MoMap *map_of(MoValue *entries, size_t len, size_t stride) {
    uint32_t index_len;
    uint32_t *index = build_index(&mo_heap, entries, len, stride, 0, &index_len);
    return map_header(entries, len, index, index_len);
}

/* `m` with `key` set to `value` (a set passes stride 1): an existing key keeps its place,
 * a new one goes last; on a var that owns the buffer the row writes in place. */
static MoMap *map_put(MoMap *m, size_t stride, MoValue key, MoValue value, uint32_t kind) {
    MoValue *xs = m ? m->entries : NULL;
    size_t len = m ? m->len : 0;
    bool on_var = kind == MO_KIND_UNIQUE;
    bool mine = on_var && is_owned(xs, len);
    size_t k = map_find(m, stride, key);
    if (k != SIZE_MAX) {
        if (stride == 1) return m;
        if (mine) {
            overwrite(&xs[k + 1], value);
            return m;
        }
        MoValue *out = dupe_values(xs, len);
        out[k + 1] = value;
        if (on_var) own(out, len);
        return map_header(out, len, m->index, m->index_len);
    }
    MoValue *out = push_list(xs, len, key);
    size_t out_len = len + 1;
    if (stride == 2) {
        out = push_list(out, out_len, value);
        out_len += 1;
    }
    size_t keys = out_len / stride;
    uint32_t *index = NULL;
    uint32_t index_len = 0;
    if (m && room_for_one(m->index, m->index_len)) {
        if (out == xs) {
            insert_ordinal(m->index, m->index_len, out, stride, keys - 1);
            index = m->index;
            index_len = m->index_len;
        } else if (m->index[0] == keys - 1) {
            index = mo_alloc_bytes(m->index_len * sizeof(uint32_t));
            memcpy(index, m->index, m->index_len * sizeof(uint32_t));
            index_len = m->index_len;
            insert_ordinal(index, index_len, out, stride, keys - 1);
        }
    }
    if (!index) index = build_index(&mo_heap, out, out_len, stride, 0, &index_len);
    if (on_var && (mine || out != xs)) {
        disown(xs, len);
        own(out, out_len);
    }
    return map_header(out, out_len, index, index_len);
}

/* `m` without `key`; unchanged when it is absent. */
static MoMap *map_without(MoMap *m, size_t stride, MoValue key, uint32_t kind) {
    size_t k = map_find(m, stride, key);
    if (k == SIZE_MAX) return m;
    MoValue *xs = m->entries;
    size_t len = m->len;
    bool on_var = kind == MO_KIND_UNIQUE;
    size_t rest = len - stride;
    if (k == rest) {
        if (on_var && is_owned(xs, len)) {
            disown(xs, len);
            own(xs, rest);
        }
        return map_header(xs, rest, m->index, m->index_len);
    }
    uint32_t index_len;
    if (on_var && is_owned(xs, len)) {
        memmove(&xs[k], &xs[k + stride], (rest - k) * sizeof(MoValue));
        remember_write((uintptr_t)&xs[k], rest - k, NULL);
        disown(xs, len);
        own(xs, rest);
        uint32_t *index = build_index(&mo_heap, xs, rest, stride, m->index_len ? m->index_len - 1 : 0, &index_len);
        return map_header(xs, rest, index, index_len);
    }
    MoValue *out = mo_alloc_values(rest);
    memcpy(out, xs, k * sizeof(MoValue));
    memcpy(out + k, xs + k + stride, (rest - k) * sizeof(MoValue));
    if (on_var) own(out, rest);
    uint32_t *index = build_index(&mo_heap, out, rest, stride, m->index_len ? m->index_len - 1 : 0, &index_len);
    return map_header(out, rest, index, index_len);
}

/* ==== text: the streams, value rendering, and reports (vm.zig, runner.zig, main.zig) ==== */

typedef struct { char *p; size_t len, cap; } Buf;

static void buf_put(Buf *b, const char *s, size_t n) {
    if (b->len + n + 1 > b->cap) {
        size_t cap = b->cap ? b->cap : 64;
        while (b->len + n + 1 > cap) cap *= 2;
        b->p = xrealloc(b->p, cap);
        b->cap = cap;
    }
    if (n) memcpy(b->p + b->len, s, n);
    b->len += n;
    b->p[b->len] = 0;
}

static void buf_str(Buf *b, const char *s) { buf_put(b, s, strlen(s)); }
static void buf_byte(Buf *b, char c) { buf_put(b, &c, 1); }

__attribute__((format(printf, 2, 3)))
static void buf_printf(Buf *b, const char *format, ...) {
    char small[256];
    va_list ap;
    va_start(ap, format);
    int n = vsnprintf(small, sizeof small, format, ap);
    va_end(ap);
    if (n < 0) return;
    if ((size_t)n < sizeof small) {
        buf_put(b, small, (size_t)n);
        return;
    }
    char *big = xmalloc((size_t)n + 1);
    va_start(ap, format);
    vsnprintf(big, (size_t)n + 1, format, ap);
    va_end(ap);
    buf_put(b, big, (size_t)n);
    free(big);
}

/* The buffer's text, handed over; the buffer starts empty again. */
static char *buf_take(Buf *b) {
    if (!b->p) buf_put(b, "", 0);
    char *s = b->p;
    *b = (Buf){NULL, 0, 0};
    return s;
}

static void fmt_i128(Buf *b, __int128 x) {
    char digits[48];
    int n = 0;
    bool negative = x < 0;
    unsigned __int128 u = negative ? (unsigned __int128)0 - (unsigned __int128)x : (unsigned __int128)x;
    do {
        digits[n++] = (char)('0' + (int)(u % 10));
        u /= 10;
    } while (u != 0);
    if (negative) buf_byte(b, '-');
    while (n > 0) buf_byte(b, digits[--n]);
}

static void fmt_int(Buf *b, MoValue v) {
    if (v.tag == MO_BIG) {
        fmt_i128(b, *v.as.big);
        return;
    }
    char digits[24];
    int n = sizeof digits;
    bool negative = v.tag == MO_INT && v.as.i < 0;
    uint64_t u = negative ? (uint64_t)0 - v.as.u : v.as.u;
    do {
        digits[--n] = (char)('0' + u % 10);
        u /= 10;
    } while (u != 0);
    if (negative) digits[--n] = '-';
    buf_put(b, digits + n, sizeof digits - (size_t)n);
}

/* A float as Zig's `{d}` spells it: the shortest digits that read back as the same float,
 * in plain decimal notation, never an exponent; "nan", "-nan", "inf", "-inf". */
static void fmt_float(Buf *b, double x) {
    if (isnan(x)) {
        buf_str(b, signbit(x) ? "-nan" : "nan");
        return;
    }
    if (isinf(x)) {
        buf_str(b, x < 0 ? "-inf" : "inf");
        return;
    }
    if (signbit(x)) buf_byte(b, '-');
    double ax = fabs(x);
    if (ax == 0) {
        buf_byte(b, '0');
        return;
    }
    char text[64];
    int precision = 0;
    for (; precision < 17; precision++) {
        snprintf(text, sizeof text, "%.*e", precision, ax);
        if (strtod(text, NULL) == ax) break;
    }
    /* text is d.ddde±XX: the digits, then the exponent of the first. */
    char digits[32];
    int n = 0;
    char *e = text;
    for (; *e && *e != 'e'; e++) {
        if (*e >= '0' && *e <= '9') digits[n++] = *e;
    }
    int exponent = atoi(e + 1);
    while (n > 1 && digits[n - 1] == '0') n--;
    int point = exponent + 1;
    if (point <= 0) {
        buf_str(b, "0.");
        for (int i = 0; i < -point; i++) buf_byte(b, '0');
        buf_put(b, digits, (size_t)n);
    } else if (point >= n) {
        buf_put(b, digits, (size_t)n);
        for (int i = 0; i < point - n; i++) buf_byte(b, '0');
    } else {
        buf_put(b, digits, (size_t)point);
        buf_byte(b, '.');
        buf_put(b, digits + point, (size_t)(n - point));
    }
}

/* `Time.fixture()` and a fixture clock's frozen `now`: 2026-01-01T00:00:00Z. */
#define FIXTURE_TIME INT64_C(1767225600000)

/* Under a program's main: the real platform. In a test: fixtures. */
static bool server_mode;

static void format_value(Buf *b, MoValue v);

static void format_fields(Buf *b, const char *name, const MoValue *values, uint32_t n, const MoField *defs, uint32_t ndefs) {
    buf_str(b, name);
    if (n == 0) return;
    buf_byte(b, '(');
    for (uint32_t i = 0; i < n; i++) {
        if (i > 0) buf_str(b, ", ");
        if (i < ndefs) buf_printf(b, "%s: ", defs[i].name);
        format_value(b, values[i]);
    }
    buf_byte(b, ')');
}

/* A value as Mo source, for reports. */
static void format_value(Buf *b, MoValue v) {
    switch (v.tag) {
    case MO_NONE: buf_str(b, "no value"); return;
    case MO_BOOL: buf_str(b, v.as.b ? "true" : "false"); return;
    case MO_INT:
    case MO_UINT:
    case MO_BIG: fmt_int(b, v); return;
    case MO_FLOAT: fmt_float(b, v.as.f); return;
    case MO_STRING:
        buf_byte(b, '"');
        buf_put(b, v.as.s, v.aux);
        buf_byte(b, '"');
        return;
    case MO_TIME:
        if (v.as.i == FIXTURE_TIME) buf_str(b, "Time.fixture()");
        else if (v.as.i > FIXTURE_TIME) buf_printf(b, "Time.fixture() + %lld.ms", (long long)(v.as.i - FIXTURE_TIME));
        else buf_printf(b, "Time.fixture() - %lld.ms", (long long)(FIXTURE_TIME - v.as.i));
        return;
    case MO_DURATION: buf_printf(b, "%lld.ms", (long long)v.as.i); return;
    case MO_LIST:
    case MO_TUPLE:
        buf_byte(b, v.tag == MO_LIST ? '[' : '(');
        for (uint32_t i = 0; i < v.aux; i++) {
            if (i > 0) buf_str(b, ", ");
            format_value(b, v.as.xs[i]);
        }
        buf_byte(b, v.tag == MO_LIST ? ']' : ')');
        return;
    case MO_RECORD: {
        const MoDecl *d = &mo_decls[v.aux];
        format_fields(b, d->name, v.as.xs, d->nfields, d->fields, d->nfields);
        return;
    }
    case MO_VARIANT: {
        uint32_t n = mo_vcount(v);
        const MoField *defs = NULL;
        uint32_t ndefs = 0;
        for (uint32_t k = 0; k < mo_nvariants; k++) {
            if (mo_variants[k].name == mo_vname(v) && mo_variants[k].nfields == n) {
                defs = mo_variants[k].fields;
                ndefs = n;
                break;
            }
        }
        if (n == 1 || ndefs != n) {
            buf_str(b, mo_names[mo_vname(v)]);
            if (n == 0) return;
            buf_byte(b, '(');
            for (uint32_t i = 0; i < n; i++) {
                if (i > 0) buf_str(b, ", ");
                format_value(b, v.as.xs[i]);
            }
            buf_byte(b, ')');
        } else {
            format_fields(b, mo_names[mo_vname(v)], v.as.xs, n, defs, ndefs);
        }
        return;
    }
    case MO_MAP:
        buf_str(b, "Map.new()");
        for (uint32_t i = 0; v.as.m && i + 1 < v.as.m->len; i += 2) {
            buf_str(b, ".set(");
            format_value(b, v.as.m->entries[i]);
            buf_str(b, ", ");
            format_value(b, v.as.m->entries[i + 1]);
            buf_byte(b, ')');
        }
        return;
    case MO_SET:
        buf_str(b, "Set.new()");
        for (uint32_t i = 0; v.as.m && i < v.as.m->len; i++) {
            buf_str(b, ".add(");
            format_value(b, v.as.m->entries[i]);
            buf_byte(b, ')');
        }
        return;
    case MO_FUNC: buf_str(b, "a function"); return;
    case MO_CAP:
        switch (mo_cap_kind(v)) {
        case MO_CAP_CLOCK: buf_str(b, server_mode ? "a Clock" : "Clock.fixture()"); return;
        case MO_CAP_FS: buf_str(b, server_mode ? "an Fs" : "Fs.fixture()"); return;
        case MO_CAP_EVENTS: buf_str(b, "Events.fixture()"); return;
        case MO_CAP_LEDGER: buf_str(b, "Ledger.fixture()"); return;
        case MO_CAP_PLATFORM: buf_str(b, "the Platform"); return;
        case MO_CAP_ENV: buf_str(b, "an Env"); return;
        case MO_CAP_OUT: buf_str(b, !server_mode ? "Out.fixture()" : mo_cap_handle(v) == 2 ? "an Out (stderr)" : "an Out (stdout)"); return;
        case MO_CAP_NET: buf_str(b, server_mode ? "a Net" : "Net.fixture()"); return;
        case MO_CAP_LISTENER: buf_str(b, "a Listener"); return;
        default: buf_str(b, "a Conn"); return;
        }
    case MO_HANDLE: buf_printf(b, "a handle #%lld", (long long)v.as.i); return;
    default: return;
    }
}

/* Interpolation: a string is its text, anything else as it is written in source. */
static void format_text(Buf *b, MoValue v) {
    if (v.tag == MO_STRING) buf_put(b, v.as.s, v.aux);
    else format_value(b, v);
}

static char *render(MoValue v) {
    Buf b = {0};
    format_value(&b, v);
    return buf_take(&b);
}

/* Text copied into the values heap. */
static MoValue heap_string(const char *s, size_t n) {
    char *p = mo_alloc_bytes(n);
    if (n) memcpy(p, s, n);
    return mo_str(p, (uint32_t)n);
}

MoValue mo_concat(uint32_t n, const MoValue *parts) {
    /* Formatting runs no Mo code, so one buffer serves every interpolation. */
    static Buf b;
    b.len = 0;
    for (uint32_t i = 0; i < n; i++) format_text(&b, parts[i]);
    return heap_string(b.p ? b.p : "", b.len);
}

MoValue mo_range(MoValue lo, MoValue hi) {
    __int128 a = mo_wide(lo), z = mo_wide(hi);
    size_t n = z > a ? (size_t)(z - a) : 0;
    MoValue *xs = mo_alloc_values(n);
    for (size_t k = 0; k < n; k++) xs[k] = mo_i128(a + (__int128)k);
    return mo_list(xs, (uint32_t)n);
}

/* ---- the streams: stdout buffered 4096 bytes and stderr 1024, as main.zig's */

typedef struct { int fd; size_t cap, len; char buf[4096]; } Stream;
static Stream out_stream = {1, 4096, 0, {0}};
static Stream err_stream = {2, 1024, 0, {0}};

/* A stream that is gone (a closed pipe) drops the text. */
static void raw_write(int fd, const char *p, size_t n) {
    while (n > 0) {
        ssize_t w = write(fd, p, n);
        if (w < 0 && errno == EINTR) continue;
        if (w <= 0) return;
        p += w;
        n -= (size_t)w;
    }
}

static void stream_flush(Stream *s) {
    raw_write(s->fd, s->buf, s->len);
    s->len = 0;
}

static void stream_write(Stream *s, const char *p, size_t n) {
    if (s->len + n <= s->cap) {
        memcpy(s->buf + s->len, p, n);
        s->len += n;
        return;
    }
    stream_flush(s);
    if (n >= s->cap) {
        raw_write(s->fd, p, n);
        return;
    }
    memcpy(s->buf, p, n);
    s->len = n;
}

/* ---- reports */

typedef struct { const char *name; char *value; } Involved;

typedef struct {
    uint8_t kind;
    const char *clause;
    const char *within;
    const char *where;
    Involved *values;
    uint32_t nvalues;
} Report;

/* Where a crash, a skip, or a discarded attempt goes in a test; NULL under main. */
enum { JUMP_CRASH = 1, JUMP_SKIP = 2, JUMP_DISCARD = 3 };
static jmp_buf *crash_jump;
static Report last_report;

/* writeReport: where, what tripped, and the values involved. */
static void report_text(Buf *b, const Report *r) {
    if (r->where) buf_printf(b, "%s: ", r->where);
    switch (r->kind) {
    case MO_R_ASSERT: buf_printf(b, "%s failed", r->clause); break;
    case MO_R_REQUIRES:
    case MO_R_ENSURES:
    case MO_R_REFINEMENT:
    case MO_R_INVARIANT: buf_printf(b, "%s tripped in %s", r->clause, r->within); break;
    case MO_R_NEVER: buf_printf(b, "%s tripped", r->clause); break;
    case MO_R_OVERFLOW: buf_printf(b, "overflow in %s", r->clause); break;
    case MO_R_DIVIDE_BY_ZERO: buf_printf(b, "division by zero in %s", r->clause); break;
    default: buf_str(b, r->clause); break;
    }
    for (uint32_t i = 0; i < r->nvalues; i++) buf_printf(b, "%s%s = %s", i == 0 ? "; " : ", ", r->values[i].name, r->values[i].value);
}

_Noreturn static void raise_report(Report r, int jump) {
    last_report = r;
    if (crash_jump) longjmp(*crash_jump, jump);
    /* main crashed: its report on stderr after what stdout holds, and exit 70 (Q18). */
    stream_flush(&out_stream);
    Buf b = {0};
    buf_str(&b, "main crashed: ");
    report_text(&b, &r);
    buf_byte(&b, '\n');
    stream_write(&err_stream, b.p, b.len);
    stream_flush(&err_stream);
    exit(70);
}

static Report clause_report(uint32_t clause) {
    const MoClause *c = &mo_clauses[clause];
    return (Report){c->kind, c->text, c->within, c->where, NULL, 0};
}

_Noreturn void mo_crash(uint32_t clause) {
    raise_report(clause_report(clause), mo_clauses[clause].skip ? JUMP_SKIP : JUMP_CRASH);
}

_Noreturn void mo_crash_values(uint32_t clause, uint32_t n, const char *const *names, const MoValue *values) {
    Report r = clause_report(clause);
    r.values = xmalloc(n * sizeof(Involved));
    r.nvalues = n;
    for (uint32_t i = 0; i < n; i++) r.values[i] = (Involved){names[i], render(values[i])};
    raise_report(r, JUMP_CRASH);
}

_Noreturn void mo_crash_arith(uint8_t kind, uint32_t clause, uint32_t n, const MoValue *operands) {
    static const char *const one[] = {"value"};
    static const char *const two[] = {"left", "right"};
    Report r = clause == UINT32_MAX ? (Report){kind, "an integer past its type", "", NULL, NULL, 0} : clause_report(clause);
    r.kind = kind;
    r.values = xmalloc(n * sizeof(Involved));
    r.nvalues = n;
    for (uint32_t i = 0; i < n; i++) r.values[i] = (Involved){n == 1 ? one[0] : two[i], render(operands[i])};
    raise_report(r, JUMP_CRASH);
}

_Noreturn void mo_overflow2(uint32_t clause, MoValue l, MoValue r) {
    MoValue both[2] = {l, r};
    mo_crash_arith(MO_R_OVERFLOW, clause, 2, both);
}

_Noreturn void mo_div_zero(uint32_t clause, MoValue l, MoValue r) {
    MoValue both[2] = {l, r};
    mo_crash_arith(MO_R_DIVIDE_BY_ZERO, clause, 2, both);
}

_Noreturn void mo_trip(uint32_t clause, uint32_t n, const MoValue *values) {
    const MoNever *never = NULL;
    for (uint32_t k = 0; k < mo_nnevers; k++) {
        if (mo_nevers[k].clause == clause) never = &mo_nevers[k];
    }
    Report r = clause_report(clause);
    r.values = xmalloc(n * sizeof(Involved));
    r.nvalues = n;
    for (uint32_t i = 0; i < n; i++) r.values[i] = (Involved){never && i < never->nnames ? never->names[i] : "", render(values[i])};
    raise_report(r, JUMP_CRASH);
}

_Noreturn void mo_fail(uint8_t kind, const char *within, const char *format, ...) {
    va_list ap;
    va_start(ap, format);
    int n = vsnprintf(NULL, 0, format, ap);
    va_end(ap);
    char *text = xmalloc((size_t)(n > 0 ? n : 0) + 1);
    va_start(ap, format);
    vsnprintf(text, (size_t)(n > 0 ? n : 0) + 1, format, ap);
    va_end(ap);
    raise_report((Report){kind, text, within, NULL, NULL, 0}, JUMP_CRASH);
}

_Noreturn void mo_discard(void) {
    if (crash_jump) longjmp(*crash_jump, JUMP_DISCARD);
    mo_fail(MO_R_OTHER, "", "a property's guard ran outside a property");
}

_Noreturn void mo_no_impl(const char *name, MoValue receiver) {
    mo_fail(MO_R_OTHER, name, "no impl gives %s for %s", name, render(receiver));
}

_Noreturn void mo_not_compiled(const char *what) {
    mo_fail(MO_R_OTHER, what, "%s does not run in a compiled program yet: run it with mo run", what);
}

/* ---- arithmetic past the sized integers (vm.zig: arith, int, time) */

MoValue mo_arith_wide(int op, MoValue l, MoValue r, uint32_t clause) {
    __int128 a = mo_wide(l), b = mo_wide(r), x = 0;
    bool over = false;
    switch (op) {
    case MO_OP_ADD: over = __builtin_add_overflow(a, b, &x); break;
    case MO_OP_SUB: over = __builtin_sub_overflow(a, b, &x); break;
    case MO_OP_MUL: over = __builtin_mul_overflow(a, b, &x); break;
    default:
        if (b == 0) mo_div_zero(clause, l, r);
        __int128 min = (__int128)((unsigned __int128)1 << 127);
        if (op == MO_OP_DIV) {
            over = a == min && b == -1;
            if (!over) x = a / b;
        } else {
            x = b == -1 ? 0 : a % b;
        }
        break;
    }
    if (over) mo_overflow2(clause, l, r);
    return mo_i128(x);
}

MoValue mo_neg_wide(MoValue v, uint32_t clause) {
    __int128 x;
    if (__builtin_sub_overflow((__int128)0, mo_wide(v), &x)) mo_crash_arith(MO_R_OVERFLOW, clause, 1, &v);
    return mo_i128(x);
}

static int64_t checked_ms(int op, int64_t a, int64_t b, MoValue l, MoValue r, uint32_t clause) {
    int64_t x;
    if (op == MO_OP_SUB ? __builtin_sub_overflow(a, b, &x) : __builtin_add_overflow(a, b, &x)) mo_overflow2(clause, l, r);
    return x;
}

MoValue mo_arith(int op, MoValue l, MoValue r, uint32_t clause) {
    switch (l.tag) {
    case MO_INT:
    case MO_UINT:
    case MO_BIG: return mo_arith_wide(op, l, r, clause);
    case MO_FLOAT: {
        double a = l.as.f, b = r.as.f;
        switch (op) {
        case MO_OP_ADD: return mo_f64(a + b);
        case MO_OP_SUB: return mo_f64(a - b);
        case MO_OP_MUL: return mo_f64(a * b);
        case MO_OP_DIV: return mo_f64(a / b);
        default: return mo_f64(fmod(a, b));
        }
    }
    case MO_TIME:
        if (r.tag == MO_TIME) return mo_duration(checked_ms(op, l.as.i, r.as.i, l, r, clause));
        return mo_time(checked_ms(op, l.as.i, r.as.i, l, r, clause));
    case MO_DURATION: return mo_duration(checked_ms(op, l.as.i, r.as.i, l, r, clause));
    default: return MO_NONE_V;
    }
}

MoValue mo_neg(MoValue v, uint32_t clause) {
    switch (v.tag) {
    case MO_FLOAT: return mo_f64(-v.as.f);
    case MO_DURATION: return mo_duration(-v.as.i);
    default: return mo_neg_wide(v, clause);
    }
}

/* ==== the prelude's rows (vm.zig prim, stdlib.zig, server.zig, json.zig) ============== */

static MoValue ok_of(MoValue x) { return mo_variant(MO_N_OK, 1, &x); }
static MoValue error_of(MoValue x) { return mo_variant(MO_N_ERROR, 1, &x); }
static MoValue ok_none(void) { return ok_of(MO_NONE_V); }
static MoValue option_of(bool some, MoValue x) { return some ? mo_some(x) : mo_nothing(); }
static MoValue missing(MoValue path) { return error_of(mo_variant(MO_N_MISSING, 1, &path)); }
static MoValue timed_out(void) { return error_of(mo_variant(MO_N_TIMEOUT, 0, NULL)); }

static char *i128_text(__int128 x) {
    Buf b = {0};
    fmt_i128(&b, x);
    return buf_take(&b);
}

/* Each step of a combinator is a safe point; what `roots` hold is kept (vm.iterate). */
static size_t iterate(size_t from, MoValue *roots, size_t n, size_t kept) {
    if (!mo_compacts) return 0;
    size_t used = mo_heap.top > from ? mo_heap.top - from : 0;
    if (used <= 2 * kept + MO_LOOP_BUDGET) return kept;
    mo_compact(from, roots, n);
    return mo_heap.top - from;
}

static const char *const kind_names[] = {"i8", "i16", "i32", "i64", "u8", "u16", "u32", "u64"};

static __int128 kind_min(uint32_t k) {
    switch (k) {
    case MO_I8: return INT8_MIN;
    case MO_I16: return INT16_MIN;
    case MO_I32: return INT32_MIN;
    case MO_I64: return INT64_MIN;
    default: return 0;
    }
}

static __int128 kind_max(uint32_t k) {
    switch (k) {
    case MO_I8: return INT8_MAX;
    case MO_I16: return INT16_MAX;
    case MO_I32: return INT32_MAX;
    case MO_I64: return INT64_MAX;
    case MO_U8: return UINT8_MAX;
    case MO_U16: return UINT16_MAX;
    case MO_U32: return UINT32_MAX;
    default: return UINT64_MAX;
    }
}

/* The value's low bits as the kind: two's-complement wrapping. */
static __int128 wrap_kind(uint32_t k, __int128 v) {
    switch (k) {
    case MO_I8: return (int8_t)(uint8_t)v;
    case MO_I16: return (int16_t)(uint16_t)v;
    case MO_I32: return (int32_t)(uint32_t)v;
    case MO_I64: return (int64_t)(uint64_t)v;
    case MO_U8: return (uint8_t)v;
    case MO_U16: return (uint16_t)v;
    case MO_U32: return (uint32_t)v;
    default: return (uint64_t)v;
    }
}

/* ---- lists */

MO_ROW(mo_r_List_size) { (void)kind; return mo_u64(a[0].aux); }

MO_ROW(mo_r_List_push) {
    (void)kind;
    return mo_list(push_list(a[0].as.xs, a[0].aux, a[1]), a[0].aux + 1);
}

MO_ROW(mo_r_List_map) {
    (void)kind;
    MoValue xs = a[0], f = a[1];
    MoValue *out = mo_alloc_values(xs.aux);
    size_t from = mo_mark(), kept = 0;
    for (uint32_t i = 0; i < xs.aux; i++) {
        MoValue x = xs.as.xs[i];
        out[i] = mo_invoke(f, &x);
        kept = iterate(from, out, i + 1, kept);
    }
    return mo_list(out, xs.aux);
}

MO_ROW(mo_r_List_filter) {
    (void)kind;
    MoValue xs = a[0], f = a[1];
    MoValue *out = mo_alloc_values(xs.aux);
    size_t from = mo_mark(), kept = 0;
    uint32_t n = 0;
    for (uint32_t i = 0; i < xs.aux; i++) {
        MoValue x = xs.as.xs[i];
        if (mo_invoke(f, &x).as.b) out[n++] = x;
        kept = iterate(from, out, n, kept);
    }
    return mo_list(out, n);
}

MO_ROW(mo_r_List_reduce) {
    (void)kind;
    MoValue xs = a[0], f = a[2];
    MoValue acc[1] = {a[1]};
    size_t from = mo_mark(), kept = 0;
    for (uint32_t i = 0; i < xs.aux; i++) {
        MoValue args[2] = {acc[0], xs.as.xs[i]};
        acc[0] = mo_invoke(f, args);
        kept = iterate(from, acc, 1, kept);
    }
    return acc[0];
}

MO_ROW(mo_r_List_contains_q) {
    (void)kind;
    for (uint32_t i = 0; i < a[0].aux; i++) {
        if (mo_equal(a[0].as.xs[i], a[1])) return mo_bool(true);
    }
    return mo_bool(false);
}

MO_ROW(mo_r_List_first) { (void)kind; return option_of(a[0].aux > 0, a[0].aux ? a[0].as.xs[0] : MO_NONE_V); }
MO_ROW(mo_r_List_last) { (void)kind; return option_of(a[0].aux > 0, a[0].aux ? a[0].as.xs[a[0].aux - 1] : MO_NONE_V); }

MO_ROW(mo_r_List_get) {
    (void)kind;
    __int128 i = mo_wide(a[1]);
    return option_of(i < a[0].aux, i < a[0].aux ? a[0].as.xs[(size_t)i] : MO_NONE_V);
}

/* `xs[from..to]` with both bounds clamped to the list. */
static MoValue cut(MoValue xs, __int128 from, __int128 to) {
    __int128 hi = to < xs.aux ? to : xs.aux;
    __int128 lo = from < hi ? from : hi;
    return mo_list(xs.aux ? xs.as.xs + (size_t)lo : NULL, (uint32_t)(hi - lo));
}

MO_ROW(mo_r_List_slice) { (void)kind; return cut(a[0], mo_wide(a[1]), mo_wide(a[2])); }
MO_ROW(mo_r_List_take) { (void)kind; return cut(a[0], 0, mo_wide(a[1])); }
MO_ROW(mo_r_List_drop) { (void)kind; return cut(a[0], mo_wide(a[1]), a[0].aux); }

MO_ROW(mo_r_List_concat) {
    (void)kind;
    if (a[1].aux == 0) return a[0];
    if (a[0].aux == 0) return a[1];
    MoValue *out = mo_alloc_values((size_t)a[0].aux + a[1].aux);
    memcpy(out, a[0].as.xs, a[0].aux * sizeof(MoValue));
    memcpy(out + a[0].aux, a[1].as.xs, a[1].aux * sizeof(MoValue));
    return mo_list(out, a[0].aux + a[1].aux);
}

MO_ROW(mo_r_List_reverse) {
    (void)kind;
    uint32_t n = a[0].aux;
    MoValue *out = mo_alloc_values(n);
    for (uint32_t k = 0; k < n; k++) out[n - 1 - k] = a[0].as.xs[k];
    return mo_list(out, n);
}

MO_ROW(mo_r_List_flat_map) {
    (void)kind;
    MoValue xs = a[0], f = a[1];
    MoValue *parts = mo_alloc_values(xs.aux);
    size_t from = mo_mark(), kept = 0, len = 0;
    for (uint32_t i = 0; i < xs.aux; i++) {
        MoValue x = xs.as.xs[i];
        parts[i] = mo_invoke(f, &x);
        len += parts[i].aux;
        kept = iterate(from, parts, i + 1, kept);
    }
    MoValue *out = mo_alloc_values(len);
    size_t at = 0;
    for (uint32_t i = 0; i < xs.aux; i++) {
        if (parts[i].aux) memcpy(out + at, parts[i].as.xs, parts[i].aux * sizeof(MoValue));
        at += parts[i].aux;
    }
    return mo_list(out, (uint32_t)len);
}

enum { SCAN_ANY, SCAN_ALL, SCAN_FIND, SCAN_COUNT };

static MoValue scan(int which, MoValue xs, MoValue f) {
    size_t from = mo_mark(), kept = 0;
    uint64_t n = 0;
    for (uint32_t i = 0; i < xs.aux; i++) {
        MoValue x = xs.as.xs[i];
        bool hit = mo_invoke(f, &x).as.b;
        if (which == SCAN_ANY && hit) return mo_bool(true);
        if (which == SCAN_ALL && !hit) return mo_bool(false);
        if (which == SCAN_FIND && hit) return mo_some(x);
        n += hit;
        kept = iterate(from, NULL, 0, kept);
    }
    switch (which) {
    case SCAN_ANY: return mo_bool(false);
    case SCAN_ALL: return mo_bool(true);
    case SCAN_FIND: return mo_nothing();
    default: return mo_u64(n);
    }
}

MO_ROW(mo_r_List_any_q) { (void)kind; return scan(SCAN_ANY, a[0], a[1]); }
MO_ROW(mo_r_List_all_q) { (void)kind; return scan(SCAN_ALL, a[0], a[1]); }
MO_ROW(mo_r_List_find) { (void)kind; return scan(SCAN_FIND, a[0], a[1]); }
MO_ROW(mo_r_List_count) { (void)kind; return scan(SCAN_COUNT, a[0], a[1]); }

/* A stable merge sort of positions by `keys` in the natural order. */
static void sort_positions(uint32_t *pos, uint32_t *tmp, size_t n, const MoValue *keys) {
    if (n < 2) return;
    size_t mid = n / 2;
    sort_positions(pos, tmp, mid, keys);
    sort_positions(pos + mid, tmp, n - mid, keys);
    size_t i = 0, j = mid, k = 0;
    while (i < mid && j < n) {
        if (mo_order(keys[pos[j]], keys[pos[i]]) < 0) tmp[k++] = pos[j++];
        else tmp[k++] = pos[i++];
    }
    while (i < mid) tmp[k++] = pos[i++];
    while (j < n) tmp[k++] = pos[j++];
    memcpy(pos, tmp, n * sizeof(uint32_t));
}

static MoValue sorted_by(MoValue xs, const MoValue *keys) {
    uint32_t n = xs.aux;
    uint32_t *pos = xmalloc(n * sizeof(uint32_t));
    uint32_t *tmp = xmalloc(n * sizeof(uint32_t));
    for (uint32_t i = 0; i < n; i++) pos[i] = i;
    sort_positions(pos, tmp, n, keys);
    MoValue *out = mo_alloc_values(n);
    for (uint32_t i = 0; i < n; i++) out[i] = xs.as.xs[pos[i]];
    free(pos);
    free(tmp);
    return mo_list(out, n);
}

MO_ROW(mo_r_List_sort) { (void)kind; return sorted_by(a[0], a[0].as.xs); }

MO_ROW(mo_r_List_sort_by) {
    (void)kind;
    MoValue xs = a[0], f = a[1];
    MoValue *keys = mo_alloc_values(xs.aux);
    size_t from = mo_mark(), kept = 0;
    for (uint32_t i = 0; i < xs.aux; i++) {
        MoValue x = xs.as.xs[i];
        keys[i] = mo_invoke(f, &x);
        kept = iterate(from, keys, i + 1, kept);
    }
    return sorted_by(xs, keys);
}

static MoValue extreme(MoValue xs, int want) {
    if (xs.aux == 0) return mo_nothing();
    MoValue best = xs.as.xs[0];
    for (uint32_t i = 1; i < xs.aux; i++) {
        if (mo_order(xs.as.xs[i], best) == want) best = xs.as.xs[i];
    }
    return mo_some(best);
}

MO_ROW(mo_r_List_min) { (void)kind; return extreme(a[0], -1); }
MO_ROW(mo_r_List_max) { (void)kind; return extreme(a[0], 1); }

MO_ROW(mo_r_List_sum) {
    __int128 total = 0;
    for (uint32_t i = 0; i < a[0].aux; i++) {
        if (__builtin_add_overflow(total, mo_wide(a[0].as.xs[i]), &total)) mo_fail(MO_R_OVERFLOW, "sum", "the sum passes every integer");
        if (kind == MO_KIND_NONE || kind > MO_U64) continue;
        if (total < kind_min(kind) || total > kind_max(kind)) mo_fail(MO_R_OVERFLOW, "sum", "the sum reaches %s, past its %s elements", i128_text(total), kind_names[kind]);
    }
    return mo_i128(total);
}

static MoValue pairs_of(MoValue xs, MoValue ys, bool zip) {
    uint32_t n = zip ? (xs.aux < ys.aux ? xs.aux : ys.aux) : xs.aux;
    MoValue *pairs = mo_alloc_values(2 * (size_t)n);
    MoValue *out = mo_alloc_values(n);
    for (uint32_t k = 0; k < n; k++) {
        pairs[2 * k] = zip ? xs.as.xs[k] : mo_u64(k);
        pairs[2 * k + 1] = zip ? ys.as.xs[k] : xs.as.xs[k];
        out[k] = mo_tuple_of(pairs + 2 * k, 2);
    }
    return mo_list(out, n);
}

MO_ROW(mo_r_List_zip) { (void)kind; return pairs_of(a[0], a[1], true); }
MO_ROW(mo_r_List_enumerate) { (void)kind; return pairs_of(a[0], MO_NONE_V, false); }

/* A set of values by hash, for unique and group_by: slot i holds a value's ordinal + 1. */
typedef struct { uint32_t *slots; size_t mask; } ValueTable;

static ValueTable table_for(size_t n) {
    size_t cap = 16;
    while (cap < 2 * n + 2) cap *= 2;
    uint32_t *slots = calloc(cap, sizeof(uint32_t));
    if (!slots) out_of_memory();
    return (ValueTable){slots, cap - 1};
}

/* The ordinal of an equal value already in the table, or inserts `ordinal` and gives SIZE_MAX. */
static size_t table_find_or_add(ValueTable *t, const MoValue *values, MoValue v, size_t ordinal) {
    for (size_t i = (size_t)hash_value(v) & t->mask;; i = (i + 1) & t->mask) {
        if (t->slots[i] == 0) {
            t->slots[i] = (uint32_t)(ordinal + 1);
            return SIZE_MAX;
        }
        if (mo_equal(values[t->slots[i] - 1], v)) return t->slots[i] - 1;
    }
}

MO_ROW(mo_r_List_unique) {
    (void)kind;
    MoValue xs = a[0];
    MoValue *out = mo_alloc_values(xs.aux);
    ValueTable t = table_for(xs.aux);
    uint32_t n = 0;
    for (uint32_t i = 0; i < xs.aux; i++) {
        if (table_find_or_add(&t, xs.as.xs, xs.as.xs[i], i) != SIZE_MAX) continue;
        out[n++] = xs.as.xs[i];
    }
    free(t.slots);
    return mo_list(out, n);
}

MO_ROW(mo_r_List_group_by) {
    (void)kind;
    MoValue xs = a[0], f = a[1];
    MoValue *keys = mo_alloc_values(xs.aux);
    size_t from = mo_mark(), kept = 0;
    for (uint32_t i = 0; i < xs.aux; i++) {
        MoValue x = xs.as.xs[i];
        keys[i] = mo_invoke(f, &x);
        kept = iterate(from, keys, i + 1, kept);
    }
    size_t n = xs.aux;
    ValueTable t = table_for(n);
    uint32_t *group_of = xmalloc(n * sizeof(uint32_t));
    uint32_t *firsts = xmalloc(n * sizeof(uint32_t));
    uint32_t *sizes = xmalloc(n * sizeof(uint32_t));
    uint32_t *key_group = xmalloc(n * sizeof(uint32_t));
    size_t groups = 0;
    for (size_t i = 0; i < n; i++) {
        size_t seen = table_find_or_add(&t, keys, keys[i], i);
        if (seen == SIZE_MAX) {
            key_group[i] = (uint32_t)groups;
            firsts[groups] = (uint32_t)i;
            sizes[groups] = 0;
            groups++;
            group_of[i] = key_group[i];
        } else {
            group_of[i] = key_group[seen];
        }
        sizes[group_of[i]]++;
    }
    MoValue *block = mo_alloc_values(n);
    MoValue *entries = mo_alloc_values(2 * groups);
    uint32_t *filled = xmalloc((groups ? groups : 1) * sizeof(uint32_t));
    size_t start = 0;
    for (size_t g = 0; g < groups; g++) {
        filled[g] = (uint32_t)start;
        entries[2 * g] = keys[firsts[g]];
        entries[2 * g + 1] = mo_list(block + start, sizes[g]);
        start += sizes[g];
    }
    for (size_t i = 0; i < n; i++) block[filled[group_of[i]]++] = xs.as.xs[i];
    free(t.slots);
    free(group_of);
    free(firsts);
    free(sizes);
    free(key_group);
    free(filled);
    MoValue m = {MO_MAP, 0, {0}};
    m.as.m = map_of(entries, 2 * groups, 2);
    return m;
}

/* ---- maps and sets */

static MoValue map_value(uint32_t tag, MoMap *m) {
    MoValue v = {tag, 0, {0}};
    v.as.m = m;
    return v;
}

static uint32_t map_len(MoValue v) { return v.as.m ? v.as.m->len : 0; }

MO_ROW(mo_r_Map_new) { (void)a; (void)kind; return map_value(MO_MAP, NULL); }
MO_ROW(mo_r_Set_new) { (void)a; (void)kind; return map_value(MO_SET, NULL); }
MO_ROW(mo_r_Map_size) { (void)kind; return mo_u64(map_len(a[0]) / 2); }
MO_ROW(mo_r_Set_size) { (void)kind; return mo_u64(map_len(a[0])); }

MO_ROW(mo_r_Map_get) {
    (void)kind;
    size_t k = map_find(a[0].as.m, 2, a[1]);
    return option_of(k != SIZE_MAX, k != SIZE_MAX ? a[0].as.m->entries[k + 1] : MO_NONE_V);
}

MO_ROW(mo_r_Map_has_q) { (void)kind; return mo_bool(map_find(a[0].as.m, 2, a[1]) != SIZE_MAX); }
MO_ROW(mo_r_Set_has_q) { (void)kind; return mo_bool(map_find(a[0].as.m, 1, a[1]) != SIZE_MAX); }
MO_ROW(mo_r_Map_set) { return map_value(MO_MAP, map_put(a[0].as.m, 2, a[1], a[2], kind)); }

MO_ROW(mo_r_Map_update) {
    size_t k = map_find(a[0].as.m, 2, a[1]);
    MoValue current = k != SIZE_MAX ? a[0].as.m->entries[k + 1] : a[2];
    MoValue next = mo_invoke(a[3], &current);
    return map_value(MO_MAP, map_put(a[0].as.m, 2, a[1], next, kind));
}

MO_ROW(mo_r_Set_add) { return map_value(MO_SET, map_put(a[0].as.m, 1, a[1], MO_NONE_V, kind)); }
MO_ROW(mo_r_Map_remove) { return map_value(MO_MAP, map_without(a[0].as.m, 2, a[1], kind)); }
MO_ROW(mo_r_Set_remove) { return map_value(MO_SET, map_without(a[0].as.m, 1, a[1], kind)); }

static MoValue map_column(MoValue m, uint32_t offset) {
    uint32_t n = map_len(m) / 2;
    MoValue *out = mo_alloc_values(n);
    for (uint32_t k = 0; k < n; k++) out[k] = m.as.m->entries[2 * k + offset];
    return mo_list(out, n);
}

MO_ROW(mo_r_Map_keys) { (void)kind; return map_column(a[0], 0); }
MO_ROW(mo_r_Map_values) { (void)kind; return map_column(a[0], 1); }

MO_ROW(mo_r_Map_entries) {
    (void)kind;
    uint32_t len = map_len(a[0]);
    MoValue *pairs = dupe_values(len ? a[0].as.m->entries : NULL, len);
    MoValue *out = mo_alloc_values(len / 2);
    for (uint32_t k = 0; k < len / 2; k++) out[k] = mo_tuple_of(pairs + 2 * k, 2);
    return mo_list(out, len / 2);
}

MO_ROW(mo_r_Set_to_list) {
    (void)kind;
    uint32_t len = map_len(a[0]);
    return mo_list(dupe_values(len ? a[0].as.m->entries : NULL, len), len);
}

/* ---- strings: UTF-8, counted in graphemes (a code point and the combining marks after it) */

typedef struct { uint32_t value; size_t len; } CodePoint;

/* The code point at byte `i`; an invalid byte reads as U+FFFD, one byte long. */
static CodePoint code_point(const char *s, size_t n, size_t i) {
    const CodePoint bad = {0xFFFD, 1};
    unsigned char c = (unsigned char)s[i];
    size_t len = c < 0x80 ? 1 : (c & 0xE0) == 0xC0 ? 2 : (c & 0xF0) == 0xE0 ? 3 : (c & 0xF8) == 0xF0 ? 4 : 0;
    if (len == 0 || i + len > n) return bad;
    if (len == 1) return (CodePoint){c, 1};
    uint32_t v = c & (0xFF >> (len + 1));
    for (size_t k = 1; k < len; k++) {
        unsigned char b = (unsigned char)s[i + k];
        if ((b & 0xC0) != 0x80) return bad;
        v = v << 6 | (b & 0x3F);
    }
    if (len == 2 && v < 0x80) return bad;
    if (len == 3 && (v < 0x800 || (v >= 0xD800 && v <= 0xDFFF))) return bad;
    if (len == 4 && (v < 0x10000 || v > 0x10FFFF)) return bad;
    return (CodePoint){v, len};
}

static bool utf8_valid(const char *s, size_t n) {
    for (size_t i = 0; i < n;) {
        CodePoint cp = code_point(s, n, i);
        if (cp.value == 0xFFFD && cp.len == 1) return false;
        i += cp.len;
    }
    return true;
}

static bool combining(uint32_t cp) {
    return (cp >= 0x300 && cp <= 0x36F) || (cp >= 0x1AB0 && cp <= 0x1AFF) || (cp >= 0x1DC0 && cp <= 0x1DFF) || (cp >= 0x20D0 && cp <= 0x20FF) || (cp >= 0xFE20 && cp <= 0xFE2F);
}

/* Past the grapheme that starts at `i`. */
static size_t next_grapheme(const char *s, size_t n, size_t i) {
    i += code_point(s, n, i).len;
    while (i < n) {
        CodePoint cp = code_point(s, n, i);
        if (!combining(cp.value)) break;
        i += cp.len;
    }
    return i;
}

static uint64_t grapheme_count(const char *s, size_t n) {
    uint64_t count = 0;
    for (size_t i = 0; i < n; i = next_grapheme(s, n, i)) count++;
    return count;
}

/* The byte offset where grapheme `index` starts, or the length past the last. */
static size_t byte_offset(const char *s, size_t n, __int128 index) {
    size_t i = 0;
    for (__int128 k = 0; k < index && i < n; k++) i = next_grapheme(s, n, i);
    return i;
}

static bool whitespace(uint32_t cp) {
    return (cp >= 0x09 && cp <= 0x0D) || cp == 0x20 || cp == 0x85 || cp == 0xA0 || cp == 0x1680 || (cp >= 0x2000 && cp <= 0x200A) || cp == 0x2028 || cp == 0x2029 || cp == 0x202F || cp == 0x205F || cp == 0x3000;
}

/* Where `needle` first is in `hay`, or SIZE_MAX; an empty needle is at 0. */
static size_t find_bytes(const char *hay, size_t n, const char *needle, size_t m, size_t from) {
    if (m == 0) return from <= n ? from : SIZE_MAX;
    for (size_t i = from; i + m <= n; i++) {
        if (hay[i] == needle[0] && memcmp(hay + i, needle, m) == 0) return i;
    }
    return SIZE_MAX;
}

/* Non-overlapping occurrences, left to right. */
static size_t count_bytes(const char *hay, size_t n, const char *needle, size_t m) {
    size_t count = 0;
    for (size_t i = 0; (i = find_bytes(hay, n, needle, m, i)) != SIZE_MAX; i += m) count++;
    return count;
}

#define S(v) (v).as.s, (size_t)(v).aux

MO_ROW(mo_r_String_size) { (void)kind; return mo_u64(grapheme_count(S(a[0]))); }
MO_ROW(mo_r_String_byte_size) { (void)kind; return mo_u64(a[0].aux); }

MO_ROW(mo_r_String_bytes) {
    (void)kind;
    MoValue *out = mo_alloc_values(a[0].aux);
    for (uint32_t i = 0; i < a[0].aux; i++) out[i] = mo_i64((unsigned char)a[0].as.s[i]);
    return mo_list(out, a[0].aux);
}

MO_ROW(mo_r_String_starts_with_q) {
    (void)kind;
    return mo_bool(a[1].aux <= a[0].aux && (a[1].aux == 0 || memcmp(a[0].as.s, a[1].as.s, a[1].aux) == 0));
}

MO_ROW(mo_r_String_ends_with_q) {
    (void)kind;
    return mo_bool(a[1].aux <= a[0].aux && (a[1].aux == 0 || memcmp(a[0].as.s + a[0].aux - a[1].aux, a[1].as.s, a[1].aux) == 0));
}

MO_ROW(mo_r_String_contains_q) { (void)kind; return mo_bool(find_bytes(S(a[0]), S(a[1]), 0) != SIZE_MAX); }

MO_ROW(mo_r_String_from_bytes) {
    (void)kind;
    char *out = mo_alloc_bytes(a[0].aux);
    for (uint32_t i = 0; i < a[0].aux; i++) out[i] = (char)(uint8_t)a[0].as.xs[i].as.u;
    if (!utf8_valid(out, a[0].aux)) return mo_nothing();
    return mo_some(mo_str(out, a[0].aux));
}

static MoValue chars_of(MoValue s) {
    uint64_t n = grapheme_count(S(s));
    MoValue *out = mo_alloc_values(n);
    size_t i = 0;
    for (uint64_t k = 0; k < n; k++) {
        size_t next = next_grapheme(S(s), i);
        out[k] = mo_str(s.as.s + i, (uint32_t)(next - i));
        i = next;
    }
    return mo_list(out, (uint32_t)n);
}

MO_ROW(mo_r_String_chars) { (void)kind; return chars_of(a[0]); }

MO_ROW(mo_r_String_split) {
    (void)kind;
    MoValue s = a[0], sep = a[1];
    if (sep.aux == 0) return chars_of(s);
    size_t n = count_bytes(S(s), S(sep)) + 1;
    MoValue *out = mo_alloc_values(n);
    size_t start = 0;
    for (size_t k = 0; k < n; k++) {
        size_t at = k + 1 < n ? find_bytes(S(s), S(sep), start) : s.aux;
        out[k] = mo_str(s.as.s + start, (uint32_t)(at - start));
        start = at + sep.aux;
    }
    return mo_list(out, (uint32_t)n);
}

static MoValue lines_of(MoValue s) {
    if (s.aux == 0) return mo_list(NULL, 0);
    size_t len = s.as.s[s.aux - 1] == '\n' ? s.aux - 1 : s.aux;
    size_t n = count_bytes(s.as.s, len, "\n", 1) + 1;
    MoValue *out = mo_alloc_values(n);
    size_t start = 0;
    for (size_t k = 0; k < n; k++) {
        size_t at = k + 1 < n ? find_bytes(s.as.s, len, "\n", 1, start) : len;
        size_t end = at;
        if (end > start && s.as.s[end - 1] == '\r') end--;
        out[k] = mo_str(s.as.s + start, (uint32_t)(end - start));
        start = at + 1;
    }
    return mo_list(out, (uint32_t)n);
}

MO_ROW(mo_r_String_lines) { (void)kind; return lines_of(a[0]); }

MO_ROW(mo_r_String_trim) {
    (void)kind;
    const char *s = a[0].as.s;
    size_t n = a[0].aux, start = SIZE_MAX, end = 0;
    for (size_t i = 0; i < n;) {
        CodePoint cp = code_point(s, n, i);
        if (!whitespace(cp.value)) {
            if (start == SIZE_MAX) start = i;
            end = i + cp.len;
        }
        i += cp.len;
    }
    if (start == SIZE_MAX) return mo_str(s, 0);
    return mo_str(s + start, (uint32_t)(end - start));
}

MO_ROW(mo_r_String_index_of) {
    (void)kind;
    size_t at = find_bytes(S(a[0]), S(a[1]), 0);
    if (at == SIZE_MAX) return mo_nothing();
    return mo_some(mo_u64(grapheme_count(a[0].as.s, at)));
}

MO_ROW(mo_r_String_slice) {
    (void)kind;
    __int128 from = mo_wide(a[1]), to = mo_wide(a[2]);
    size_t end = byte_offset(S(a[0]), to);
    size_t start = byte_offset(S(a[0]), from < to ? from : to);
    if (start > end) start = end;
    return mo_str(a[0].as.s + start, (uint32_t)(end - start));
}

MO_ROW(mo_r_String_replace) {
    (void)kind;
    MoValue s = a[0], x = a[1], y = a[2];
    if (x.aux == 0) return s;
    size_t n = count_bytes(S(s), S(x));
    if (n == 0) return s;
    size_t len = s.aux - n * x.aux + n * y.aux;
    char *out = mo_alloc_bytes(len);
    size_t from = 0, at = 0, hit;
    while ((hit = find_bytes(S(s), S(x), from)) != SIZE_MAX) {
        memcpy(out + at, s.as.s + from, hit - from);
        at += hit - from;
        memcpy(out + at, y.as.s, y.aux);
        at += y.aux;
        from = hit + x.aux;
    }
    memcpy(out + at, s.as.s + from, s.aux - from);
    return mo_str(out, (uint32_t)len);
}

static MoValue ascii_case(MoValue s, bool upper) {
    char *out = mo_alloc_bytes(s.aux);
    for (uint32_t i = 0; i < s.aux; i++) {
        char c = s.as.s[i];
        if (upper && c >= 'a' && c <= 'z') c = (char)(c - 32);
        if (!upper && c >= 'A' && c <= 'Z') c = (char)(c + 32);
        out[i] = c;
    }
    return mo_str(out, s.aux);
}

MO_ROW(mo_r_String_to_upper) { (void)kind; return ascii_case(a[0], true); }
MO_ROW(mo_r_String_to_lower) { (void)kind; return ascii_case(a[0], false); }

static MoValue pad(const char *name, MoValue s, MoValue width, MoValue ch, bool left) {
    if (grapheme_count(S(ch)) != 1) mo_fail(MO_R_OTHER, name, "%s pads with one grapheme, not \"%.*s\"", name, (int)ch.aux, ch.as.s);
    __int128 n = mo_wide(width);
    __int128 size = grapheme_count(S(s));
    if (size >= n) return s;
    unsigned __int128 extra = (unsigned __int128)(n - size) * ch.aux;
    if (extra > SIZE_MAX / 2) mo_fail(MO_R_OVERFLOW, name, "%s(%s) is too long a string", name, i128_text(n));
    size_t missing_count = (size_t)(n - size);
    char *out = mo_alloc_bytes(s.aux + (size_t)extra);
    char *fill = left ? out : out + s.aux;
    for (size_t k = 0; k < missing_count; k++) memcpy(fill + k * ch.aux, ch.as.s, ch.aux);
    memcpy(left ? out + (size_t)extra : out, s.as.s, s.aux);
    return mo_str(out, (uint32_t)(s.aux + (size_t)extra));
}

MO_ROW(mo_r_String_pad_left) { (void)kind; return pad("pad_left", a[0], a[1], a[2], true); }
MO_ROW(mo_r_String_pad_right) { (void)kind; return pad("pad_right", a[0], a[1], a[2], false); }

MO_ROW(mo_r_String_repeat) {
    (void)kind;
    __int128 times = mo_wide(a[1]);
    unsigned __int128 len = (unsigned __int128)a[0].aux * (unsigned __int128)times;
    if (times < 0 || len > UINT32_MAX) mo_fail(MO_R_OVERFLOW, "repeat", "repeat(%s) is too long a string", i128_text(times));
    char *out = mo_alloc_bytes((size_t)len);
    for (size_t k = 0; k < (size_t)times; k++) memcpy(out + k * a[0].aux, a[0].as.s, a[0].aux);
    return mo_str(out, (uint32_t)len);
}

MO_ROW(mo_r_String_join) {
    (void)kind;
    MoValue xs = a[0], sep = a[1];
    if (xs.aux == 0) return mo_str("", 0);
    size_t len = (size_t)sep.aux * (xs.aux - 1);
    for (uint32_t i = 0; i < xs.aux; i++) len += xs.as.xs[i].aux;
    char *out = mo_alloc_bytes(len);
    size_t at = 0;
    for (uint32_t i = 0; i < xs.aux; i++) {
        if (i > 0) {
            memcpy(out + at, sep.as.s, sep.aux);
            at += sep.aux;
        }
        memcpy(out + at, xs.as.xs[i].as.s, xs.as.xs[i].aux);
        at += xs.as.xs[i].aux;
    }
    return mo_str(out, (uint32_t)len);
}

/* Whole-number text: ASCII digits, at least one, with one leading `-` when `is_signed`. */
static bool parse_whole(MoValue s, bool is_signed, uint32_t k, __int128 *out) {
    bool negative = is_signed && s.aux > 0 && s.as.s[0] == '-';
    size_t start = negative ? 1 : 0;
    size_t digits = s.aux - start;
    if (digits == 0 || digits > 40) return false;
    __int128 v = 0;
    for (size_t i = start; i < s.aux; i++) {
        char d = s.as.s[i];
        if (d < '0' || d > '9') return false;
        if (v > ((__int128)1 << 120)) v = (__int128)1 << 121;
        else v = v * 10 + (d - '0');
    }
    if (negative) v = -v;
    if (v < kind_min(k) || v > kind_max(k)) return false;
    *out = v;
    return true;
}

MO_ROW(mo_r_String_to_u64) {
    (void)kind;
    __int128 v;
    bool some = parse_whole(a[0], false, MO_U64, &v);
    return option_of(some, some ? mo_i128(v) : MO_NONE_V);
}

MO_ROW(mo_r_String_to_i64) {
    (void)kind;
    __int128 v;
    bool some = parse_whole(a[0], true, MO_I64, &v);
    return option_of(some, some ? mo_i128(v) : MO_NONE_V);
}

static size_t digits_from(const char *s, size_t n, size_t i) {
    size_t j = i;
    while (j < n && s[j] >= '0' && s[j] <= '9') j++;
    return j == i ? SIZE_MAX : j;
}

/* Float text: `-`?, digits, then `.` and digits, then `e` or `E`, a sign, and digits. */
static bool parse_float_text(const char *s, size_t n, double *out) {
    size_t i = 0;
    if (i < n && s[i] == '-') i++;
    if ((i = digits_from(s, n, i)) == SIZE_MAX) return false;
    if (i < n && s[i] == '.' && (i = digits_from(s, n, i + 1)) == SIZE_MAX) return false;
    if (i < n && (s[i] == 'e' || s[i] == 'E')) {
        i++;
        if (i < n && (s[i] == '+' || s[i] == '-')) i++;
        if ((i = digits_from(s, n, i)) == SIZE_MAX) return false;
    }
    if (i != n) return false;
    char *text = xmalloc(n + 1);
    memcpy(text, s, n);
    text[n] = 0;
    double x = strtod(text, NULL);
    free(text);
    if (isinf(x)) return false;
    *out = x;
    return true;
}

MO_ROW(mo_r_String_to_f64) {
    (void)kind;
    double x;
    bool some = parse_float_text(S(a[0]), &x);
    return option_of(some, mo_f64(some ? x : 0));
}

/* ---- integers and floats */

static MoValue int_to(MoValue v, uint32_t target, const char *name, const char *type) {
    __int128 x = mo_wide(v);
    if (x < kind_min(target) || x > kind_max(target)) mo_fail(MO_R_OVERFLOW, name, "%s.%s does not fit %s", i128_text(x), name, type);
    return v;
}

MO_ROW(mo_r_Int_to_u8) { (void)kind; return int_to(a[0], MO_U8, "to_u8", "UInt8"); }
MO_ROW(mo_r_Int_to_u16) { (void)kind; return int_to(a[0], MO_U16, "to_u16", "UInt16"); }
MO_ROW(mo_r_Int_to_u32) { (void)kind; return int_to(a[0], MO_U32, "to_u32", "UInt32"); }
MO_ROW(mo_r_Int_to_u64) { (void)kind; return int_to(a[0], MO_U64, "to_u64", "UInt64"); }
MO_ROW(mo_r_Int_to_i64) { (void)kind; return int_to(a[0], MO_I64, "to_i64", "Int64"); }

static MoValue checked_to(MoValue v, uint32_t target) {
    __int128 x = mo_wide(v);
    bool fits = x >= kind_min(target) && x <= kind_max(target);
    return option_of(fits, v);
}

MO_ROW(mo_r_Int_checked_to_u8) { (void)kind; return checked_to(a[0], MO_U8); }
MO_ROW(mo_r_Int_checked_to_u16) { (void)kind; return checked_to(a[0], MO_U16); }
MO_ROW(mo_r_Int_checked_to_u32) { (void)kind; return checked_to(a[0], MO_U32); }
MO_ROW(mo_r_Int_checked_to_u64) { (void)kind; return checked_to(a[0], MO_U64); }
MO_ROW(mo_r_Int_checked_to_i64) { (void)kind; return checked_to(a[0], MO_I64); }
MO_ROW(mo_r_Int_to_f64) { (void)kind; return mo_f64((double)mo_wide(a[0])); }

enum { EDGE_CHECKED, EDGE_SATURATING, EDGE_WRAPPING };

/* checked_, saturating_, and wrapping_: the only behaviours at an integer's edge besides the crash. */
static MoValue edge(int how, int op, uint32_t k, MoValue l, MoValue r) {
    __int128 x = mo_wide(l), y = mo_wide(r), exact;
    bool past = op == MO_OP_ADD ? __builtin_add_overflow(x, y, &exact) : op == MO_OP_SUB ? __builtin_sub_overflow(x, y, &exact) : __builtin_mul_overflow(x, y, &exact);
    if (past) exact = ((x < 0) != (y < 0) && op == MO_OP_MUL) ? kind_min(MO_I64) - 1 : (__int128)UINT64_MAX + 1;
    bool fits = !past && exact >= kind_min(k) && exact <= kind_max(k);
    switch (how) {
    case EDGE_CHECKED: return option_of(fits, mo_i128(exact));
    case EDGE_SATURATING: return mo_i128(exact < kind_min(k) ? kind_min(k) : exact > kind_max(k) ? kind_max(k) : exact);
    default: return mo_i128(wrap_kind(k, exact));
    }
}

MO_ROW(mo_r_Int_checked_add) { return edge(EDGE_CHECKED, MO_OP_ADD, kind, a[0], a[1]); }
MO_ROW(mo_r_Int_checked_sub) { return edge(EDGE_CHECKED, MO_OP_SUB, kind, a[0], a[1]); }
MO_ROW(mo_r_Int_checked_mul) { return edge(EDGE_CHECKED, MO_OP_MUL, kind, a[0], a[1]); }
MO_ROW(mo_r_Int_saturating_add) { return edge(EDGE_SATURATING, MO_OP_ADD, kind, a[0], a[1]); }
MO_ROW(mo_r_Int_saturating_sub) { return edge(EDGE_SATURATING, MO_OP_SUB, kind, a[0], a[1]); }
MO_ROW(mo_r_Int_saturating_mul) { return edge(EDGE_SATURATING, MO_OP_MUL, kind, a[0], a[1]); }
MO_ROW(mo_r_Int_wrapping_add) { return edge(EDGE_WRAPPING, MO_OP_ADD, kind, a[0], a[1]); }
MO_ROW(mo_r_Int_wrapping_sub) { return edge(EDGE_WRAPPING, MO_OP_SUB, kind, a[0], a[1]); }
MO_ROW(mo_r_Int_wrapping_mul) { return edge(EDGE_WRAPPING, MO_OP_MUL, kind, a[0], a[1]); }

static MoValue duration_of(MoValue n, __int128 unit, const char *name) {
    __int128 ms;
    if (__builtin_mul_overflow(mo_wide(n), unit, &ms) || ms > INT64_MAX || ms < INT64_MIN) {
        char *clause = NULL;
        Buf b = {0};
        buf_printf(&b, "%s.%s does not fit a Duration", i128_text(mo_wide(n)), name);
        clause = buf_take(&b);
        raise_report((Report){MO_R_OVERFLOW, clause, "", NULL, NULL, 0}, JUMP_CRASH);
    }
    return mo_duration((int64_t)ms);
}

MO_ROW(mo_r_Int_ms) { (void)kind; return duration_of(a[0], 1, "ms"); }
MO_ROW(mo_r_Int_minute) { (void)kind; return duration_of(a[0], 60000, "minute"); }
MO_ROW(mo_r_Int_days) { (void)kind; return duration_of(a[0], 86400000, "days"); }

#define MAX_PLACES 15

/* `x` with exactly `places` decimals, rounded half away from zero on its shortest decimal
 * spelling. Zero is never negative. */
static char *rounded(double x, size_t places) {
    Buf spelled = {0};
    fmt_float(&spelled, fabs(x));
    const char *text = spelled.p;
    const char *dot = strchr(text, '.');
    size_t whole_len = dot ? (size_t)(dot - text) : strlen(text);
    const char *fraction = dot ? dot + 1 : "";
    size_t fraction_len = strlen(fraction);
    char *digits = xmalloc(whole_len + places + 2);
    size_t n = 0;
    digits[n++] = '0';
    memcpy(digits + n, text, whole_len);
    n += whole_len;
    for (size_t k = 0; k < places; k++) digits[n++] = k < fraction_len ? fraction[k] : '0';
    if (places < fraction_len && fraction[places] >= '5') {
        for (size_t k = n; k > 0; k--) {
            if (digits[k - 1] == '9') {
                digits[k - 1] = '0';
                continue;
            }
            digits[k - 1]++;
            break;
        }
    }
    size_t first = 0;
    while (first + 1 < n - places && digits[first] == '0') first++;
    bool zero = true;
    for (size_t k = first; k < n; k++) zero = zero && digits[k] == '0';
    Buf out = {0};
    if (x < 0 && !zero) buf_byte(&out, '-');
    buf_put(&out, digits + first, n - places - first);
    if (places > 0) {
        buf_byte(&out, '.');
        buf_put(&out, digits + n - places, places);
    }
    free(digits);
    free(spelled.p);
    return buf_take(&out);
}

static MoValue float_places(MoValue v, MoValue places_v, bool round_only) {
    double x = v.as.f;
    __int128 places = mo_wide(places_v);
    const char *name = round_only ? "round" : "to_string";
    if (places > MAX_PLACES) mo_fail(MO_R_OTHER, name, "%s(%s) rounds to at most %d places", name, i128_text(places), MAX_PLACES);
    if (isnan(x) || isinf(x)) {
        if (round_only) return v;
        const char *t = isnan(x) ? "NaN" : x > 0 ? "Infinity" : "-Infinity";
        return mo_str(t, (uint32_t)strlen(t));
    }
    char *text = rounded(x, (size_t)places);
    MoValue out = round_only ? mo_f64(strtod(text, NULL)) : heap_string(text, strlen(text));
    free(text);
    return out;
}

MO_ROW(mo_r_Float64_round) { (void)kind; return float_places(a[0], a[1], true); }
MO_ROW(mo_r_Float64_to_string) { (void)kind; return float_places(a[0], a[1], false); }

/* ---- time */

#define MS_PER_DAY INT64_C(86400000)

static int64_t floor_div(int64_t a, int64_t b) { return a / b - ((a % b != 0) && ((a < 0) != (b < 0))); }
static int64_t floor_mod(int64_t a, int64_t b) { return a - floor_div(a, b) * b; }

/* Days from 1970-01-01 to a proleptic Gregorian date (Hinnant's days_from_civil). */
static int64_t days_from_civil(int64_t year, int64_t month, int64_t day) {
    int64_t y = month <= 2 ? year - 1 : year;
    int64_t era = floor_div(y, 400);
    int64_t of_era = y - era * 400;
    int64_t of_year = floor_div(153 * floor_mod(month + 9, 12) + 2, 5) + day - 1;
    int64_t days = of_era * 365 + floor_div(of_era, 4) - floor_div(of_era, 100) + of_year;
    return era * 146097 + days - 719468;
}

static void civil_from_days(int64_t days, int64_t *year, int64_t *month, int64_t *day) {
    int64_t z = days + 719468;
    int64_t era = floor_div(z, 146097);
    int64_t of_era = z - era * 146097;
    int64_t year_of_era = floor_div(of_era - floor_div(of_era, 1460) + floor_div(of_era, 36524) - floor_div(of_era, 146096), 365);
    int64_t of_year = of_era - (365 * year_of_era + floor_div(year_of_era, 4) - floor_div(year_of_era, 100));
    int64_t mp = floor_div(5 * of_year + 2, 153);
    *month = mp < 10 ? mp + 3 : mp - 9;
    *year = year_of_era + era * 400 + (*month <= 2);
    *day = of_year - floor_div(153 * mp + 2, 5) + 1;
}

static int64_t days_in(int64_t year, int64_t month) {
    switch (month) {
    case 2: return (floor_mod(year, 4) == 0 && (floor_mod(year, 100) != 0 || floor_mod(year, 400) == 0)) ? 29 : 28;
    case 4:
    case 6:
    case 9:
    case 11: return 30;
    default: return 31;
    }
}

static bool instant(int64_t year, int64_t month, int64_t day, int64_t hour, int64_t minute, int64_t second, int64_t *out) {
    if (year < 0 || year > 9999 || month < 1 || month > 12 || day < 1 || day > days_in(year, month)) return false;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59 || second < 0 || second > 59) return false;
    *out = ((days_from_civil(year, month, day) * 24 + hour) * 60 + minute) * 60000 + second * 1000;
    return true;
}

static bool fixed_digits(const char *s, size_t n, int64_t *out) {
    int64_t v = 0;
    for (size_t i = 0; i < n; i++) {
        if (s[i] < '0' || s[i] > '9') return false;
        v = v * 10 + (s[i] - '0');
    }
    *out = v;
    return true;
}

/* RFC 3339: `2026-09-12T10:00:02Z`, optional fractional seconds, `Z` or an offset. */
static bool parse_time(const char *s, size_t n, int64_t *out) {
    if (n < 20) return false;
    if (s[4] != '-' || s[7] != '-' || (s[10] != 'T' && s[10] != 't') || s[13] != ':' || s[16] != ':') return false;
    int64_t year, month, day, hour, minute, second;
    if (!fixed_digits(s, 4, &year) || !fixed_digits(s + 5, 2, &month) || !fixed_digits(s + 8, 2, &day) || !fixed_digits(s + 11, 2, &hour) || !fixed_digits(s + 14, 2, &minute) || !fixed_digits(s + 17, 2, &second)) return false;
    size_t i = 19;
    int64_t ms = 0;
    if (s[i] == '.') {
        i++;
        size_t start = i;
        while (i < n && s[i] >= '0' && s[i] <= '9') i++;
        if (i == start || i - start > 9) return false;
        for (size_t k = 0; k < 3; k++) ms = ms * 10 + (start + k < i ? s[start + k] - '0' : 0);
    }
    if (i >= n) return false;
    int64_t offset = 0;
    if (s[i] == 'Z' || s[i] == 'z') {
        i++;
    } else if (s[i] == '+' || s[i] == '-') {
        if (n - i != 6 || s[i + 3] != ':') return false;
        int64_t hours, minutes;
        if (!fixed_digits(s + i + 1, 2, &hours) || !fixed_digits(s + i + 4, 2, &minutes)) return false;
        if (hours > 23 || minutes > 59) return false;
        offset = (hours * 60 + minutes) * 60000;
        if (s[i] == '-') offset = -offset;
        i += 6;
    } else {
        return false;
    }
    if (i != n) return false;
    int64_t at;
    if (!instant(year, month, day, hour, minute, second, &at)) return false;
    *out = at + ms - offset;
    return true;
}

static void iso8601(Buf *b, int64_t t) {
    int64_t year, month, day;
    civil_from_days(floor_div(t, MS_PER_DAY), &year, &month, &day);
    int64_t in_day = floor_mod(t, MS_PER_DAY);
    if (year >= 0 && year <= 9999) buf_printf(b, "%04lld", (long long)year);
    else buf_printf(b, "%lld", (long long)year);
    buf_printf(b, "-%02lld-%02lldT%02lld:%02lld:%02lld", (long long)month, (long long)day, (long long)(in_day / 3600000), (long long)(in_day / 60000 % 60), (long long)(in_day / 1000 % 60));
    if (in_day % 1000 != 0) buf_printf(b, ".%03lld", (long long)(in_day % 1000));
    buf_byte(b, 'Z');
}

MO_ROW(mo_r_Time_fixture) { (void)a; (void)kind; return mo_time(FIXTURE_TIME); }

MO_ROW(mo_r_Time_parse) {
    (void)kind;
    int64_t t;
    bool some = parse_time(S(a[0]), &t);
    return option_of(some, mo_time(some ? t : 0));
}

MO_ROW(mo_r_Time_from_parts) {
    (void)kind;
    int64_t parts[6];
    for (int k = 0; k < 6; k++) {
        __int128 x = mo_wide(a[k]);
        parts[k] = x > INT64_MAX || x < INT64_MIN ? INT64_MAX : (int64_t)x;
    }
    int64_t t;
    if (!instant(parts[0], parts[1], parts[2], parts[3], parts[4], parts[5], &t)) {
        mo_fail(MO_R_OTHER, "from_parts", "%s-%s-%s %s:%s:%s is not a date and time in the years 0 to 9999", i128_text(mo_wide(a[0])), i128_text(mo_wide(a[1])), i128_text(mo_wide(a[2])), i128_text(mo_wide(a[3])), i128_text(mo_wide(a[4])), i128_text(mo_wide(a[5])));
    }
    return mo_time(t);
}

MO_ROW(mo_r_Time_to_iso8601) {
    (void)kind;
    Buf b = {0};
    iso8601(&b, a[0].as.i);
    MoValue s = heap_string(b.p, b.len);
    free(b.p);
    return s;
}

MO_ROW(mo_r_Time_since) {
    (void)kind;
    int64_t d;
    if (__builtin_sub_overflow(a[0].as.i, a[1].as.i, &d)) mo_fail(MO_R_OVERFLOW, "since", "the span does not fit a Duration");
    return mo_duration(d);
}

MO_ROW(mo_r_Duration_ms) { (void)kind; return mo_i64(a[0].as.i); }
MO_ROW(mo_r_Duration_seconds) { (void)kind; return mo_f64((double)a[0].as.i / 1000.0); }
MO_ROW(mo_r_Duration_minutes) { (void)kind; return mo_f64((double)a[0].as.i / 60000.0); }

static int64_t wall_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_REALTIME, &ts);
    return (int64_t)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

static int64_t awake_ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (int64_t)ts.tv_sec * 1000000000 + ts.tv_nsec;
}

MO_ROW(mo_r_Clock_now) { (void)a; (void)kind; return mo_time(server_mode ? wall_ms() : FIXTURE_TIME); }
MO_ROW(mo_r_Clock_fixture) { (void)a; (void)kind; return mo_cap(MO_CAP_CLOCK, 0, 0); }

/* ---- the platform (server.zig) */

static int program_argc;
static char **program_argv;
static uint8_t exit_code;

static void platform_only(const char *recv, const char *name) {
    if (!server_mode) mo_fail(MO_R_OTHER, name, "%s.%s runs only under mo run", recv, name);
}

MO_ROW(mo_r_Platform_args) {
    (void)a;
    (void)kind;
    platform_only("Platform", "args");
    MoValue *out = mo_alloc_values((size_t)program_argc);
    for (int i = 0; i < program_argc; i++) out[i] = mo_str(program_argv[i], (uint32_t)strlen(program_argv[i]));
    return mo_list(out, (uint32_t)program_argc);
}

MO_ROW(mo_r_Platform_env) { (void)a; (void)kind; platform_only("Platform", "env"); return mo_cap(MO_CAP_ENV, 0, 0); }
MO_ROW(mo_r_Platform_stdout) { (void)a; (void)kind; platform_only("Platform", "stdout"); return mo_cap(MO_CAP_OUT, 1, 0); }
MO_ROW(mo_r_Platform_stderr) { (void)a; (void)kind; platform_only("Platform", "stderr"); return mo_cap(MO_CAP_OUT, 2, 0); }
MO_ROW(mo_r_Platform_fs) { (void)a; (void)kind; platform_only("Platform", "fs"); return mo_cap(MO_CAP_FS, 0, 0); }
MO_ROW(mo_r_Platform_clock) { (void)a; (void)kind; platform_only("Platform", "clock"); return mo_cap(MO_CAP_CLOCK, 0, 0); }
MO_ROW(mo_r_Platform_net) { (void)a; (void)kind; platform_only("Platform", "net"); return mo_cap(MO_CAP_NET, 0, 0); }

/* The last platform.exit(code) is the exit code when main returns. */
MO_ROW(mo_r_Platform_exit) {
    (void)kind;
    platform_only("Platform", "exit");
    exit_code = (uint8_t)a[1].as.u;
    return MO_NONE_V;
}

MO_ROW(mo_r_Env_get) {
    (void)kind;
    platform_only("Env", "get");
    char *name = xmalloc(a[1].aux + 1);
    memcpy(name, a[1].as.s, a[1].aux);
    name[a[1].aux] = 0;
    const char *v = strlen(name) == a[1].aux ? getenv(name) : NULL;
    free(name);
    if (!v) return mo_nothing();
    return mo_some(mo_str(v, (uint32_t)strlen(v)));
}

/* ---- output: the real streams under main, an Out.fixture() in a test */

typedef struct { MoValue *texts; size_t n, cap; } OutFixture;
static OutFixture *out_fixtures;
static size_t nout_fixtures, capout_fixtures;

static void write_out(MoValue out, MoValue text, bool line) {
    if (server_mode) {
        Stream *s = mo_cap_handle(out) == 2 ? &err_stream : &out_stream;
        stream_write(s, text.as.s, text.aux);
        if (line) stream_write(s, "\n", 1);
        return;
    }
    uint32_t h = mo_cap_handle(out);
    if (h == 0 || h > nout_fixtures) return;
    OutFixture *f = &out_fixtures[h - 1];
    if (f->n == f->cap) {
        f->cap = f->cap ? 2 * f->cap : 8;
        f->texts = xrealloc(f->texts, f->cap * sizeof(MoValue));
    }
    char *kept = xmalloc(text.aux + 1);
    memcpy(kept, text.as.s, text.aux);
    if (line) kept[text.aux] = '\n';
    f->texts[f->n++] = mo_str(kept, text.aux + (line ? 1 : 0));
}

MO_ROW(mo_r_Out_write) { (void)kind; write_out(a[0], a[1], false); return MO_NONE_V; }
MO_ROW(mo_r_Out_write_line) { (void)kind; write_out(a[0], a[1], true); return MO_NONE_V; }

MO_ROW(mo_r_Out_flush) {
    (void)kind;
    if (server_mode) stream_flush(mo_cap_handle(a[0]) == 2 ? &err_stream : &out_stream);
    return MO_NONE_V;
}

MO_ROW(mo_r_Out_fixture) {
    (void)a;
    (void)kind;
    if (nout_fixtures == capout_fixtures) {
        capout_fixtures = capout_fixtures ? 2 * capout_fixtures : 8;
        out_fixtures = xrealloc(out_fixtures, capout_fixtures * sizeof(OutFixture));
    }
    out_fixtures[nout_fixtures++] = (OutFixture){NULL, 0, 0};
    return mo_cap(MO_CAP_OUT, (uint32_t)nout_fixtures, 0);
}

MO_ROW(mo_r_Out_written) {
    (void)kind;
    uint32_t h = mo_cap_handle(a[0]);
    if (server_mode || h == 0 || h > nout_fixtures) return mo_list(NULL, 0);
    OutFixture *f = &out_fixtures[h - 1];
    return mo_list(dupe_values(f->texts, f->n), (uint32_t)f->n);
}

/* ---- files: paths */

/* `path` resolved against the absolute `base`: `.` and `..` taken away (std.fs.path.resolve). */
static char *path_resolve(const char *base, const char *path, size_t path_len) {
    size_t cap = strlen(base) + path_len + 2;
    char *out = xmalloc(cap + 1);
    size_t len = 0;
    for (int part = 0; part < 2; part++) {
        const char *p = part == 0 ? base : path;
        size_t n = part == 0 ? strlen(base) : path_len;
        if (n > 0 && p[0] == '/') len = 0;
        size_t i = 0;
        while (i < n) {
            while (i < n && p[i] == '/') i++;
            size_t start = i;
            while (i < n && p[i] != '/') i++;
            size_t seg = i - start;
            if (seg == 0 || (seg == 1 && p[start] == '.')) continue;
            if (seg == 2 && p[start] == '.' && p[start + 1] == '.') {
                while (len > 0 && out[len - 1] != '/') len--;
                if (len > 0) len--;
                continue;
            }
            out[len++] = '/';
            memcpy(out + len, p + start, seg);
            len += seg;
        }
    }
    if (len == 0) out[len++] = '/';
    out[len] = 0;
    return out;
}

/* Whether the resolved absolute `path` is `root` or inside it. */
static bool within_root(const char *root, const char *path) {
    if (strcmp(root, "/") == 0) return true;
    size_t n = strlen(root);
    if (strncmp(path, root, n) != 0) return false;
    return path[n] == 0 || path[n] == '/';
}

/* The folder part of an absolute path, or NULL for "/". */
static char *path_dirname(const char *path) {
    const char *slash = strrchr(path, '/');
    if (!slash || strcmp(path, "/") == 0) return NULL;
    if (slash == path) return strdup("/");
    size_t n = (size_t)(slash - path);
    char *out = xmalloc(n + 1);
    memcpy(out, path, n);
    out[n] = 0;
    return out;
}

static char *path_join(const char *folder, const char *name) {
    size_t a = strlen(folder), b = strlen(name);
    bool slash = a > 0 && folder[a - 1] == '/';
    char *out = xmalloc(a + b + 2);
    memcpy(out, folder, a);
    if (!slash) out[a++] = '/';
    memcpy(out + a, name, b + 1);
    return out;
}

/* ---- files: Mo.Server's scopes */

typedef struct { char *base; char *root; bool read_only, empty; } Scope;
static Scope *scopes;
static size_t nscopes, capscopes;

static uint32_t add_scope(Scope s) {
    if (nscopes == capscopes) {
        capscopes = capscopes ? 2 * capscopes : 16;
        scopes = xrealloc(scopes, capscopes * sizeof(Scope));
    }
    scopes[nscopes] = s;
    return (uint32_t)nscopes++;
}

static bool late(int64_t t0, int64_t within_ms) { return awake_ns() - t0 > (__int128)within_ms * 1000000; }

/* The real path of `path` under the scope, or NULL when it is outside or not there. */
static char *real_scoped(const Scope *scope, const char *path, size_t n) {
    if (scope->empty) return NULL;
    char *full = path_resolve(scope->base, path, n);
    char *real = NULL;
    if (within_root(scope->root, full)) {
        char *real_root = realpath(scope->root, NULL);
        if (real_root) {
            real = realpath(full, NULL);
            if (real && !within_root(real_root, real)) {
                free(real);
                real = NULL;
            }
            free(real_root);
        }
    }
    free(full);
    return real;
}

#define READ_LIMIT ((size_t)64 << 20)

static char *read_scoped(const Scope *scope, const char *path, size_t n, size_t *len) {
    char *real = real_scoped(scope, path, n);
    if (!real) return NULL;
    int fd = open(real, O_RDONLY);
    free(real);
    if (fd < 0) return NULL;
    size_t cap = 4096, got = 0;
    char *text = xmalloc(cap);
    for (;;) {
        if (got == cap) {
            if (cap > READ_LIMIT) break;
            cap *= 2;
            text = xrealloc(text, cap);
        }
        ssize_t r = read(fd, text + got, cap - got);
        if (r < 0 && errno == EINTR) continue;
        if (r < 0) {
            close(fd);
            free(text);
            return NULL;
        }
        if (r == 0) break;
        got += (size_t)r;
    }
    close(fd);
    if (got > READ_LIMIT) {
        free(text);
        return NULL;
    }
    *len = got;
    return text;
}

static int by_name(const void *x, const void *y) { return strcmp(*(char *const *)x, *(char *const *)y); }

/* Where a write to `path` lands, when its folder is inside the scope and a name already
 * there, which may be a link, leads inside it too. */
static char *target_scoped(const Scope *scope, const char *path, size_t n) {
    if (scope->empty) return NULL;
    char *full = path_resolve(scope->base, path, n);
    char *target = NULL;
    char *real_root = NULL, *folder = NULL, *real_folder = NULL;
    if (!within_root(scope->root, full) || strcmp(full, scope->root) == 0) goto done;
    if (!(real_root = realpath(scope->root, NULL))) goto done;
    if (!(folder = path_dirname(full))) goto done;
    if (!(real_folder = realpath(folder, NULL))) goto done;
    if (!within_root(real_root, real_folder)) goto done;
    target = path_join(real_folder, strrchr(full, '/') + 1);
    char *real = realpath(target, NULL);
    if (real && !within_root(real_root, real)) {
        free(target);
        target = NULL;
    }
    free(real);
done:
    free(full);
    free(real_root);
    free(folder);
    free(real_folder);
    return target;
}

static char *file_scoped(const Scope *scope, const char *path, size_t n) {
    char *real = real_scoped(scope, path, n);
    struct stat st;
    if (real && (stat(real, &st) != 0 || !S_ISREG(st.st_mode))) {
        free(real);
        real = NULL;
    }
    return real;
}

/* ---- files: an Fs.fixture()'s, in memory (stdlib.zig FixtureFs) */

typedef struct { char *path; MoValue text; } FixFile;
typedef struct { FixFile *files; size_t n, cap; } FixSystem;
typedef struct { int32_t system; char *folder; bool read_only, empty; int64_t delay; } FixScope;
static FixSystem *fix_systems;
static size_t nfix_systems, capfix_systems;
static FixScope *fix_scopes;
static size_t nfix_scopes, capfix_scopes;

static MoValue add_fix_scope(FixScope s) {
    if (nfix_scopes == capfix_scopes) {
        capfix_scopes = capfix_scopes ? 2 * capfix_scopes : 16;
        fix_scopes = xrealloc(fix_scopes, capfix_scopes * sizeof(FixScope));
    }
    fix_scopes[nfix_scopes++] = s;
    return mo_cap(MO_CAP_FS, (uint32_t)nfix_scopes, s.delay);
}

static FixScope fix_scope_of(MoValue cap) {
    uint32_t h = mo_cap_handle(cap);
    if (h == 0 || h > nfix_scopes) return (FixScope){-1, "/", false, false, cap.as.i};
    return fix_scopes[h - 1];
}

static char *fix_path_in(const FixScope *scope, const char *name, size_t n) {
    if (scope->system < 0 || scope->empty) return NULL;
    char *full = path_resolve(scope->folder, name, n);
    if (within_root(scope->folder, full)) return full;
    free(full);
    return NULL;
}

static FixFile *fix_find(FixSystem *sys, const char *path) {
    for (size_t i = 0; i < sys->n; i++) {
        if (strcmp(sys->files[i].path, path) == 0) return &sys->files[i];
    }
    return NULL;
}

/* A path's text set, keeping its place when it is there, else last. */
static void fix_put(FixSystem *sys, char *path, MoValue text) {
    char *copy = xmalloc(text.aux + 1);
    memcpy(copy, text.as.s, text.aux);
    FixFile *f = fix_find(sys, path);
    if (f) {
        free(path);
        f->text = mo_str(copy, text.aux);
        return;
    }
    if (sys->n == sys->cap) {
        sys->cap = sys->cap ? 2 * sys->cap : 8;
        sys->files = xrealloc(sys->files, sys->cap * sizeof(FixFile));
    }
    sys->files[sys->n++] = (FixFile){path, mo_str(copy, text.aux)};
}

static bool fix_remove(FixSystem *sys, const char *path) {
    FixFile *f = fix_find(sys, path);
    if (!f) return false;
    size_t i = (size_t)(f - sys->files);
    memmove(sys->files + i, sys->files + i + 1, (sys->n - i - 1) * sizeof(FixFile));
    sys->n--;
    return true;
}

static void reset_fixtures(void) {
    nfix_systems = 0;
    nfix_scopes = 0;
    nout_fixtures = 0;
}

enum { FS_READ, FS_READ_LINES, FS_SIZE, FS_LIST, FS_WRITE, FS_APPEND, FS_REMOVE, FS_RENAME };
static const char *const fs_row_names[] = {"read", "read_lines", "size", "list", "write", "append", "remove", "rename"};

static MoValue string_list(char **names, size_t n) {
    MoValue *out = mo_alloc_values(n);
    for (size_t i = 0; i < n; i++) out[i] = heap_string(names[i], strlen(names[i]));
    return mo_list(out, (uint32_t)n);
}

static MoValue fixture_files(int which, const MoValue *a) {
    FixScope scope = fix_scope_of(a[0]);
    int64_t within = which == FS_LIST ? a[1].as.i : which == FS_RENAME || which == FS_WRITE || which == FS_APPEND ? a[3].as.i : a[2].as.i;
    MoValue path = which == FS_LIST ? mo_str(".", 1) : a[1];
    bool writes = which >= FS_WRITE;
    if (writes && scope.read_only) mo_fail(MO_R_OTHER, fs_row_names[which], "fs.%s(\"%.*s\") writes through an Fs narrowed to read_only, which only reads", fs_row_names[which], (int)path.aux, path.as.s);
    if (scope.delay > within) return timed_out();
    FixSystem *sys = scope.system >= 0 ? &fix_systems[scope.system] : NULL;
    if (which == FS_LIST) {
        if (!sys || scope.empty) return ok_of(mo_list(NULL, 0));
        char *prefix = strcmp(scope.folder, "/") == 0 ? strdup("/") : path_join(scope.folder, "");
        size_t plen = strlen(prefix);
        char **names = xmalloc((sys->n ? sys->n : 1) * sizeof(char *));
        size_t count = 0;
        for (size_t i = 0; i < sys->n; i++) {
            const char *key = sys->files[i].path;
            if (strncmp(key, prefix, plen) != 0) continue;
            const char *rest = key + plen;
            const char *slash = strchr(rest, '/');
            size_t len = slash ? (size_t)(slash - rest) : strlen(rest);
            bool seen = false;
            for (size_t k = 0; k < count; k++) seen = seen || (strlen(names[k]) == len && strncmp(names[k], rest, len) == 0);
            if (seen) continue;
            names[count] = xmalloc(len + 1);
            memcpy(names[count], rest, len);
            names[count][len] = 0;
            count++;
        }
        qsort(names, count, sizeof(char *), by_name);
        MoValue listed = string_list(names, count);
        for (size_t k = 0; k < count; k++) free(names[k]);
        free(names);
        free(prefix);
        return ok_of(listed);
    }
    if (!sys) return missing(path);
    char *full = fix_path_in(&scope, S(path));
    if (!full) return missing(path);
    switch (which) {
    case FS_READ:
    case FS_READ_LINES:
    case FS_SIZE: {
        FixFile *f = fix_find(sys, full);
        free(full);
        if (!f) return missing(path);
        if (which == FS_READ) return ok_of(f->text);
        if (which == FS_SIZE) return ok_of(mo_u64(f->text.aux));
        return ok_of(lines_of(f->text));
    }
    case FS_WRITE: fix_put(sys, full, a[2]); break;
    case FS_APPEND: {
        FixFile *f = fix_find(sys, full);
        Buf b = {0};
        if (f) buf_put(&b, f->text.as.s, f->text.aux);
        buf_put(&b, a[2].as.s, a[2].aux);
        fix_put(sys, full, mo_str(b.p ? b.p : "", (uint32_t)b.len));
        free(b.p);
        break;
    }
    case FS_REMOVE: {
        bool gone = fix_remove(sys, full);
        free(full);
        if (!gone) return missing(path);
        break;
    }
    default: {
        FixFile *f = fix_find(sys, full);
        if (!f) {
            free(full);
            return missing(path);
        }
        char *to = fix_path_in(&scope, S(a[2]));
        if (!to) {
            free(full);
            return missing(a[2]);
        }
        MoValue text = f->text;
        fix_remove(sys, full);
        free(full);
        fix_put(sys, to, text);
        break;
    }
    }
    return ok_none();
}

/* ---- files: the rows */

static MoValue server_files(int which, const MoValue *a) {
    const Scope *scope = &scopes[mo_cap_handle(a[0])];
    MoValue path = which == FS_LIST ? mo_str(".", 1) : a[1];
    int64_t within = which == FS_LIST ? a[1].as.i : which == FS_RENAME || which == FS_WRITE || which == FS_APPEND ? a[3].as.i : a[2].as.i;
    if (which >= FS_WRITE && scope->read_only) {
        mo_fail(MO_R_OTHER, fs_row_names[which], "fs.%s(\"%.*s\") writes through an Fs narrowed to read_only, which only reads", fs_row_names[which], (int)path.aux, path.as.s);
    }
    int64_t t0 = awake_ns();
    switch (which) {
    case FS_READ:
    case FS_READ_LINES: {
        size_t len = 0;
        char *text = read_scoped(scope, S(path), &len);
        if (late(t0, within)) {
            free(text);
            return timed_out();
        }
        if (!text) return missing(path);
        MoValue s = heap_string(text, len);
        free(text);
        return ok_of(which == FS_READ ? s : lines_of(s));
    }
    case FS_SIZE: {
        char *real = real_scoped(scope, S(path));
        struct stat st;
        bool found = real && stat(real, &st) == 0 && S_ISREG(st.st_mode);
        free(real);
        if (late(t0, within)) return timed_out();
        if (!found) return missing(path);
        return ok_of(mo_u64((uint64_t)st.st_size));
    }
    case FS_LIST: {
        char *real = real_scoped(scope, ".", 1);
        DIR *dir = real ? opendir(real) : NULL;
        free(real);
        char **names = NULL;
        size_t count = 0, cap = 0;
        if (dir) {
            struct dirent *e;
            while ((e = readdir(dir))) {
                if (strcmp(e->d_name, ".") == 0 || strcmp(e->d_name, "..") == 0) continue;
                if (count == cap) {
                    cap = cap ? 2 * cap : 16;
                    names = xrealloc(names, cap * sizeof(char *));
                }
                names[count++] = strdup(e->d_name);
            }
            closedir(dir);
            qsort(names, count, sizeof(char *), by_name);
        }
        MoValue result = late(t0, within) ? timed_out() : !dir ? missing(path) : ok_of(string_list(names, count));
        for (size_t k = 0; k < count; k++) free(names[k]);
        free(names);
        return result;
    }
    case FS_WRITE:
    case FS_APPEND: {
        char *target = target_scoped(scope, S(path));
        bool wrote = false;
        if (target) {
            int fd = open(target, O_WRONLY | O_CREAT | (which == FS_WRITE ? O_TRUNC : 0), 0666);
            if (fd >= 0) {
                struct stat st;
                off_t at = which == FS_APPEND && fstat(fd, &st) == 0 ? st.st_size : 0;
                wrote = which == FS_WRITE || fstat(fd, &st) == 0;
                size_t done = 0;
                while (wrote && done < a[2].aux) {
                    ssize_t w = pwrite(fd, a[2].as.s + done, a[2].aux - done, at + (off_t)done);
                    if (w < 0 && errno == EINTR) continue;
                    if (w <= 0) wrote = false;
                    else done += (size_t)w;
                }
                if (wrote && fsync(fd) != 0) wrote = false;
                close(fd);
            }
            free(target);
        }
        if (late(t0, within)) return timed_out();
        if (!wrote) return missing(path);
        return ok_none();
    }
    case FS_REMOVE: {
        char *real = file_scoped(scope, S(path));
        bool gone = real && unlink(real) == 0;
        free(real);
        if (late(t0, within)) return timed_out();
        if (!gone) return missing(path);
        return ok_none();
    }
    default: {
        MoValue to = a[2];
        char *real = file_scoped(scope, S(path));
        char *target = real ? target_scoped(scope, S(to)) : NULL;
        MoValue missed = !real ? path : !target || rename(real, target) != 0 ? to : MO_NONE_V;
        free(real);
        free(target);
        if (late(t0, within)) return timed_out();
        if (missed.tag != MO_NONE) return missing(missed);
        return ok_none();
    }
    }
}

static MoValue files(int which, const MoValue *a) { return server_mode ? server_files(which, a) : fixture_files(which, a); }

MO_ROW(mo_r_Fs_read) { (void)kind; return files(FS_READ, a); }
MO_ROW(mo_r_Fs_read_lines) { (void)kind; return files(FS_READ_LINES, a); }
MO_ROW(mo_r_Fs_size) { (void)kind; return files(FS_SIZE, a); }
MO_ROW(mo_r_Fs_list) { (void)kind; return files(FS_LIST, a); }
MO_ROW(mo_r_Fs_write) { (void)kind; return files(FS_WRITE, a); }
MO_ROW(mo_r_Fs_append) { (void)kind; return files(FS_APPEND, a); }
MO_ROW(mo_r_Fs_remove) { (void)kind; return files(FS_REMOVE, a); }
MO_ROW(mo_r_Fs_rename) { (void)kind; return files(FS_RENAME, a); }

/* `fs.scoped(path)` and `fs.read_only`: a new scope, never a wider one. */
static MoValue narrow(MoValue fs, bool read_only, MoValue path) {
    if (server_mode) {
        Scope scope = scopes[mo_cap_handle(fs)];
        if (read_only) {
            scope.read_only = true;
        } else {
            char *full = path_resolve(scope.base, S(path));
            scope.base = full;
            if (within_root(scope.root, full)) scope.root = full;
            else scope.empty = true;
        }
        return mo_cap(MO_CAP_FS, add_scope(scope), 0);
    }
    FixScope scope = fix_scope_of(fs);
    if (read_only) {
        scope.read_only = true;
    } else {
        char *folder = fix_path_in(&scope, S(path));
        if (folder) scope.folder = folder;
        else scope.empty = true;
    }
    return add_fix_scope(scope);
}

MO_ROW(mo_r_Fs_scoped) { (void)kind; return narrow(a[0], false, a[1]); }
MO_ROW(mo_r_Fs_read_only) { (void)kind; return narrow(a[0], true, MO_NONE_V); }

static MoValue fixture_fs(int64_t delay) {
    if (nfix_systems == capfix_systems) {
        capfix_systems = capfix_systems ? 2 * capfix_systems : 8;
        fix_systems = xrealloc(fix_systems, capfix_systems * sizeof(FixSystem));
    }
    fix_systems[nfix_systems++] = (FixSystem){NULL, 0, 0};
    return add_fix_scope((FixScope){(int32_t)(nfix_systems - 1), "/", false, false, delay});
}

MO_ROW(mo_r_Fs_fixture) { (void)a; (void)kind; return fixture_fs(0); }
MO_ROW(mo_r_Fs_fixture_delay) { (void)kind; return fixture_fs(a[0].as.i); }

/* ---- the refund module's stand-ins and the event log (vm.zig) */

MO_ROW(mo_r_Events_emit) { (void)a; (void)kind; return MO_NONE_V; }
MO_ROW(mo_r_Events_fixture) { (void)a; (void)kind; return mo_cap(MO_CAP_EVENTS, 0, 0); }
MO_ROW(mo_r_Ledger_fixture) { (void)a; (void)kind; return mo_cap(MO_CAP_LEDGER, 0, 0); }

static MoValue charge(MoValue id, MoValue at, MoValue amount) {
    if (mo_charge_decl == UINT32_MAX) mo_not_compiled("Charge");
    MoValue fields[4] = {id, at, amount, mo_bool(false)};
    return mo_record(mo_charge_decl, 4, fields);
}

MO_ROW(mo_r_Ledger_find_charge) { (void)kind; return ok_of(charge(a[1], mo_time(FIXTURE_TIME), mo_i64(10000))); }
MO_ROW(mo_r_Ledger_save_charge) { (void)a; (void)kind; return ok_none(); }
MO_ROW(mo_r_Charge_fixture) { (void)kind; return charge(mo_str("ch_1", 4), mo_time(FIXTURE_TIME), a[0]); }
MO_ROW(mo_r_Charge_fixture_at) { (void)kind; return charge(mo_str("ch_1", 4), a[0], a[1]); }
MO_ROW(mo_r_Charge_refunded_q) { (void)kind; return a[0].as.xs[3]; }
MO_ROW(mo_r_Money_cents) { (void)kind; return a[0]; }
MO_ROW(mo_r_Money_zero) { (void)a; (void)kind; return mo_i64(0); }

/* ---- JSON (json.zig) */

static void json_string(Buf *b, const char *s, size_t n) {
    buf_byte(b, '"');
    for (size_t i = 0; i < n; i++) {
        unsigned char c = (unsigned char)s[i];
        switch (c) {
        case '"': buf_str(b, "\\\""); break;
        case '\\': buf_str(b, "\\\\"); break;
        case '\n': buf_str(b, "\\n"); break;
        case '\r': buf_str(b, "\\r"); break;
        case '\t': buf_str(b, "\\t"); break;
        case 0x08: buf_str(b, "\\b"); break;
        case 0x0C: buf_str(b, "\\f"); break;
        default:
            if (c < 0x20) buf_printf(b, "\\u%04x", c);
            else buf_byte(b, (char)c);
        }
    }
    buf_byte(b, '"');
}

static void json_float(Buf *b, double x) {
    if (isnan(x) || isinf(x)) {
        buf_str(b, "null");
        return;
    }
    size_t start = b->len;
    fmt_float(b, x);
    if (!memchr(b->p + start, '.', b->len - start)) buf_str(b, ".0");
}

/* The checked type's base, or NULL when it says nothing the value does not. */
static const MoType *json_known(uint32_t t) {
    if (t == MO_KIND_NONE || t == MO_KIND_UNIQUE) return NULL;
    const MoType *ty = &mo_types[t];
    while (ty->tag == MO_T_ALIAS) ty = &mo_types[ty->b];
    switch (ty->tag) {
    case MO_T_UNKNOWN:
    case MO_T_NEVER:
    case MO_T_VARIABLE:
    case MO_T_PARAM:
    case MO_T_SELF: return NULL;
    default: return ty;
    }
}

static void json_value(Buf *b, MoValue v, uint32_t t);

static void json_fields(Buf *b, const MoValue *values, uint32_t n, const MoField *defs, uint32_t ndefs) {
    buf_byte(b, '{');
    for (uint32_t i = 0; i < n; i++) {
        if (i > 0) buf_str(b, ", ");
        const char *name = i < ndefs ? defs[i].name : "";
        json_string(b, name, strlen(name));
        buf_str(b, ": ");
        json_value(b, values[i], i < ndefs ? defs[i].type : MO_KIND_NONE);
    }
    buf_byte(b, '}');
}

static void json_tagged(Buf *b, uint32_t name, MoValue v, uint32_t t) {
    buf_byte(b, '{');
    json_string(b, mo_names[name], strlen(mo_names[name]));
    buf_str(b, ": ");
    json_value(b, v, t);
    buf_byte(b, '}');
}

/* A Json value is the JSON it holds. */
static void json_json(Buf *b, MoValue r) {
    uint32_t name = mo_vname(r);
    if (name == MO_N_NULL) {
        buf_str(b, "null");
        return;
    }
    MoValue f = r.as.xs[0];
    switch (name) {
    case MO_N_OBJECT:
        buf_byte(b, '{');
        for (uint32_t at = 0; f.as.m && at < f.as.m->len; at += 2) {
            if (at > 0) buf_str(b, ", ");
            json_string(b, S(f.as.m->entries[at]));
            buf_str(b, ": ");
            json_json(b, f.as.m->entries[at + 1]);
        }
        buf_byte(b, '}');
        return;
    case MO_N_ARRAY:
        buf_byte(b, '[');
        for (uint32_t i = 0; i < f.aux; i++) {
            if (i > 0) buf_str(b, ", ");
            json_json(b, f.as.xs[i]);
        }
        buf_byte(b, ']');
        return;
    case MO_N_STRING: json_string(b, S(f)); return;
    case MO_N_NUMBER: json_float(b, f.as.f); return;
    default: buf_str(b, f.as.b ? "true" : "false"); return;
    }
}

static void json_variant(Buf *b, MoValue r, const MoType *ty) {
    uint32_t name = mo_vname(r), n = mo_vcount(r);
    if (ty) {
        if (ty->tag == MO_T_OPTION) {
            if (n == 1) json_value(b, r.as.xs[0], ty->a);
            else buf_str(b, "null");
            return;
        }
        if (ty->tag == MO_T_RESULT) {
            json_tagged(b, name, r.as.xs[0], name == MO_N_OK ? ty->a : ty->b);
            return;
        }
        if (ty->tag == MO_T_DECL && mo_decls[ty->a].kind == MO_D_PRELUDE_ENUM && strcmp(mo_decls[ty->a].name, "Json") == 0) {
            json_json(b, r);
            return;
        }
    } else {
        if (name == MO_N_SOME) {
            json_value(b, r.as.xs[0], MO_KIND_NONE);
            return;
        }
        if (name == MO_N_NONE) {
            buf_str(b, "null");
            return;
        }
        if (name == MO_N_OK || name == MO_N_ERROR) {
            json_tagged(b, name, r.as.xs[0], MO_KIND_NONE);
            return;
        }
    }
    if (n == 0) {
        json_string(b, mo_names[name], strlen(mo_names[name]));
        return;
    }
    const MoField *defs = NULL;
    uint32_t ndefs = 0;
    bool found = false;
    if (ty && ty->tag == MO_T_DECL) {
        const MoDecl *d = &mo_decls[ty->a];
        for (uint32_t k = 0; k < d->nvariants && !found; k++) {
            const MoVariantDef *kv = &mo_variants[d->variants + k];
            if (kv->name == name) {
                defs = kv->fields;
                ndefs = kv->nfields;
                found = true;
            }
        }
    }
    for (uint32_t k = 0; k < mo_nvariants && !found; k++) {
        if (mo_variants[k].name == name && mo_variants[k].nfields == n) {
            defs = mo_variants[k].fields;
            ndefs = n;
            found = true;
        }
    }
    buf_byte(b, '{');
    json_string(b, mo_names[name], strlen(mo_names[name]));
    buf_str(b, ": ");
    json_fields(b, r.as.xs, n, defs, ndefs);
    buf_byte(b, '}');
}

static void json_value(Buf *b, MoValue v, uint32_t t) {
    const MoType *ty = json_known(t);
    switch (v.tag) {
    case MO_NONE: buf_str(b, "null"); return;
    case MO_BOOL: buf_str(b, v.as.b ? "true" : "false"); return;
    case MO_INT:
    case MO_UINT:
    case MO_BIG: fmt_int(b, v); return;
    case MO_FLOAT: json_float(b, v.as.f); return;
    case MO_STRING: json_string(b, S(v)); return;
    case MO_TIME: {
        Buf t8601 = {0};
        iso8601(&t8601, v.as.i);
        json_string(b, t8601.p, t8601.len);
        free(t8601.p);
        return;
    }
    case MO_DURATION: buf_printf(b, "%lld", (long long)v.as.i); return;
    case MO_LIST:
    case MO_SET: {
        const MoValue *xs = v.tag == MO_LIST ? v.as.xs : v.as.m ? v.as.m->entries : NULL;
        uint32_t n = v.tag == MO_LIST ? v.aux : map_len(v);
        uint32_t elem = ty && (ty->tag == MO_T_LIST || ty->tag == MO_T_SET) ? ty->a : MO_KIND_NONE;
        buf_byte(b, '[');
        for (uint32_t i = 0; i < n; i++) {
            if (i > 0) buf_str(b, ", ");
            json_value(b, xs[i], elem);
        }
        buf_byte(b, ']');
        return;
    }
    case MO_TUPLE: {
        uint32_t nelems = ty && ty->tag == MO_T_TUPLE ? ty->b : 0;
        buf_byte(b, '[');
        for (uint32_t i = 0; i < v.aux; i++) {
            if (i > 0) buf_str(b, ", ");
            json_value(b, v.as.xs[i], i < nelems ? ty->items[i] : MO_KIND_NONE);
        }
        buf_byte(b, ']');
        return;
    }
    case MO_MAP: {
        uint32_t len = map_len(v);
        const MoValue *xs = len ? v.as.m->entries : NULL;
        uint32_t key_t = ty && ty->tag == MO_T_MAP ? ty->a : MO_KIND_NONE;
        uint32_t value_t = ty && ty->tag == MO_T_MAP ? ty->b : MO_KIND_NONE;
        bool string_keys;
        const MoType *kt = json_known(key_t);
        if (kt) {
            string_keys = kt->tag == MO_T_STRING;
        } else {
            string_keys = true;
            for (uint32_t at = 0; at < len; at += 2) string_keys = string_keys && xs[at].tag == MO_STRING;
        }
        buf_byte(b, string_keys ? '{' : '[');
        for (uint32_t at = 0; at < len; at += 2) {
            if (at > 0) buf_str(b, ", ");
            if (string_keys) {
                json_string(b, S(xs[at]));
                buf_str(b, ": ");
                json_value(b, xs[at + 1], value_t);
            } else {
                buf_byte(b, '[');
                json_value(b, xs[at], key_t);
                buf_str(b, ", ");
                json_value(b, xs[at + 1], value_t);
                buf_byte(b, ']');
            }
        }
        buf_byte(b, string_keys ? '}' : ']');
        return;
    }
    case MO_RECORD: {
        const MoDecl *d = &mo_decls[v.aux];
        json_fields(b, v.as.xs, d->nfields, d->fields, d->nfields);
        return;
    }
    case MO_VARIANT: json_variant(b, v, ty); return;
    default: mo_fail(MO_R_OTHER, "encode", "%s has no JSON", render(v));
    }
}

MO_ROW(mo_r_Json_encode) {
    Buf b = {0};
    json_value(&b, a[0], kind);
    MoValue s = heap_string(b.p ? b.p : "", b.len);
    free(b.p);
    return s;
}

#define JSON_MAX_DEPTH 512

typedef struct { const char *s; size_t n, i, at; jmp_buf fail; } Decoder;

_Noreturn static void json_bad(Decoder *d, size_t at) {
    d->at = at;
    longjmp(d->fail, 1);
}

static void json_space(Decoder *d) {
    while (d->i < d->n && (d->s[d->i] == ' ' || d->s[d->i] == '\t' || d->s[d->i] == '\n' || d->s[d->i] == '\r')) d->i++;
}

static MoValue json_read(Decoder *d, uint32_t depth);

static bool json_more(Decoder *d, char close) {
    json_space(d);
    if (d->i >= d->n) json_bad(d, d->i);
    if (d->s[d->i] == ',') {
        d->i++;
        return true;
    }
    if (d->s[d->i] != close) json_bad(d, d->i);
    d->i++;
    return false;
}

static uint32_t json_hex4(Decoder *d, size_t at) {
    if (d->i + 4 > d->n) json_bad(d, at);
    uint32_t v = 0;
    for (int k = 0; k < 4; k++) {
        char h = d->s[d->i + (size_t)k];
        int digit = h >= '0' && h <= '9' ? h - '0' : h >= 'a' && h <= 'f' ? h - 'a' + 10 : h >= 'A' && h <= 'F' ? h - 'A' + 10 : -1;
        if (digit < 0) json_bad(d, at);
        v = v * 16 + (uint32_t)digit;
    }
    d->i += 4;
    return v;
}

static void utf8_encode(Buf *b, uint32_t cp) {
    char out[4];
    int n;
    if (cp < 0x80) {
        out[0] = (char)cp;
        n = 1;
    } else if (cp < 0x800) {
        out[0] = (char)(0xC0 | cp >> 6);
        out[1] = (char)(0x80 | (cp & 0x3F));
        n = 2;
    } else if (cp < 0x10000) {
        out[0] = (char)(0xE0 | cp >> 12);
        out[1] = (char)(0x80 | (cp >> 6 & 0x3F));
        out[2] = (char)(0x80 | (cp & 0x3F));
        n = 3;
    } else {
        out[0] = (char)(0xF0 | cp >> 18);
        out[1] = (char)(0x80 | (cp >> 12 & 0x3F));
        out[2] = (char)(0x80 | (cp >> 6 & 0x3F));
        out[3] = (char)(0x80 | (cp & 0x3F));
        n = 4;
    }
    buf_put(b, out, (size_t)n);
}

/* A string's text, past its closing quote. The Buf is freed on the way out, or by the caller
 * of a failed decode (json_decode keeps it). */
static MoValue json_text(Decoder *d, Buf *out) {
    out->len = 0;
    d->i++;
    for (;;) {
        if (d->i >= d->n) json_bad(d, d->i);
        unsigned char c = (unsigned char)d->s[d->i];
        if (c == '"') {
            d->i++;
            return heap_string(out->p ? out->p : "", out->len);
        }
        if (c == '\\') {
            size_t at = d->i;
            if (d->i + 1 >= d->n) json_bad(d, at);
            char e = d->s[d->i + 1];
            d->i += 2;
            switch (e) {
            case '"': buf_byte(out, '"'); break;
            case '\\': buf_byte(out, '\\'); break;
            case '/': buf_byte(out, '/'); break;
            case 'b': buf_byte(out, 0x08); break;
            case 'f': buf_byte(out, 0x0C); break;
            case 'n': buf_byte(out, '\n'); break;
            case 'r': buf_byte(out, '\r'); break;
            case 't': buf_byte(out, '\t'); break;
            case 'u': {
                uint32_t cp = json_hex4(d, at);
                if (cp >= 0xD800 && cp <= 0xDBFF) {
                    if (d->i + 2 > d->n || d->s[d->i] != '\\' || d->s[d->i + 1] != 'u') json_bad(d, at);
                    d->i += 2;
                    uint32_t low = json_hex4(d, at);
                    if (low < 0xDC00 || low > 0xDFFF) json_bad(d, at);
                    cp = 0x10000 + ((cp - 0xD800) << 10) + (low - 0xDC00);
                } else if (cp >= 0xDC00 && cp <= 0xDFFF) {
                    json_bad(d, at);
                }
                utf8_encode(out, cp);
                break;
            }
            default: json_bad(d, at);
            }
            continue;
        }
        if (c < 0x20) json_bad(d, d->i);
        if (c < 0x80) {
            buf_byte(out, (char)c);
            d->i++;
            continue;
        }
        CodePoint cp = code_point(d->s, d->n, d->i);
        if (cp.value == 0xFFFD && cp.len == 1) json_bad(d, d->i);
        buf_put(out, d->s + d->i, cp.len);
        d->i += cp.len;
    }
}

static bool json_digits(Decoder *d) {
    size_t start = d->i;
    while (d->i < d->n && d->s[d->i] >= '0' && d->s[d->i] <= '9') d->i++;
    return d->i > start;
}

typedef struct { MoValue *xs; size_t n, cap; } Values;

static void values_push(Values *v, MoValue x) {
    if (v->n == v->cap) {
        v->cap = v->cap ? 2 * v->cap : 16;
        v->xs = xrealloc(v->xs, v->cap * sizeof(MoValue));
    }
    v->xs[v->n++] = x;
}

/* Scratch that a failed decode leaves behind, freed when the decode ends. */
static Values *json_scratch;
static size_t njson_scratch, capjson_scratch;
static Buf json_texts;

static Values *json_values(void) {
    if (njson_scratch == capjson_scratch) {
        capjson_scratch = capjson_scratch ? 2 * capjson_scratch : 16;
        json_scratch = xrealloc(json_scratch, capjson_scratch * sizeof(Values));
    }
    json_scratch[njson_scratch] = (Values){NULL, 0, 0};
    return &json_scratch[njson_scratch++];
}

static MoValue json_read(Decoder *d, uint32_t depth) {
    json_space(d);
    if (d->i >= d->n || depth > JSON_MAX_DEPTH) json_bad(d, d->i);
    char c = d->s[d->i];
    if (c == '{') {
        Values *entries = json_values();
        d->i++;
        json_space(d);
        if (d->i < d->n && d->s[d->i] == '}') {
            d->i++;
        } else {
            for (;;) {
                json_space(d);
                if (d->i >= d->n || d->s[d->i] != '"') json_bad(d, d->i);
                MoValue key = json_text(d, &json_texts);
                json_space(d);
                if (d->i >= d->n || d->s[d->i] != ':') json_bad(d, d->i);
                d->i++;
                MoValue v = json_read(d, depth + 1);
                size_t k = index_of(entries->xs, entries->n, 2, key);
                if (k != SIZE_MAX) {
                    entries->xs[k + 1] = v;
                } else {
                    values_push(entries, key);
                    values_push(entries, v);
                }
                if (!json_more(d, '}')) break;
            }
        }
        MoValue m = {MO_MAP, 0, {0}};
        m.as.m = map_of(dupe_values(entries->xs, entries->n), entries->n, 2);
        return mo_variant(MO_N_OBJECT, 1, &m);
    }
    if (c == '[') {
        Values *items = json_values();
        d->i++;
        json_space(d);
        if (d->i < d->n && d->s[d->i] == ']') {
            d->i++;
        } else {
            do values_push(items, json_read(d, depth + 1));
            while (json_more(d, ']'));
        }
        MoValue list = mo_list(dupe_values(items->xs, items->n), (uint32_t)items->n);
        return mo_variant(MO_N_ARRAY, 1, &list);
    }
    if (c == '"') {
        MoValue s = json_text(d, &json_texts);
        return mo_variant(MO_N_STRING, 1, &s);
    }
    if (c == 't' || c == 'f' || c == 'n') {
        const char *word = c == 't' ? "true" : c == 'f' ? "false" : "null";
        size_t len = strlen(word);
        if (d->n - d->i < len || memcmp(d->s + d->i, word, len) != 0) json_bad(d, d->i);
        d->i += len;
        if (c == 'n') return mo_variant(MO_N_NULL, 0, NULL);
        MoValue b = mo_bool(c == 't');
        return mo_variant(MO_N_BOOL, 1, &b);
    }
    if (c == '-' || (c >= '0' && c <= '9')) {
        size_t start = d->i;
        if (d->s[d->i] == '-') d->i++;
        if (d->i < d->n && d->s[d->i] == '0') d->i++;
        else if (!json_digits(d)) json_bad(d, d->i);
        if (d->i < d->n && d->s[d->i] == '.') {
            d->i++;
            if (!json_digits(d)) json_bad(d, d->i);
        }
        if (d->i < d->n && (d->s[d->i] == 'e' || d->s[d->i] == 'E')) {
            d->i++;
            if (d->i < d->n && (d->s[d->i] == '+' || d->s[d->i] == '-')) d->i++;
            if (!json_digits(d)) json_bad(d, d->i);
        }
        char *text = xmalloc(d->i - start + 1);
        memcpy(text, d->s + start, d->i - start);
        text[d->i - start] = 0;
        double x = strtod(text, NULL);
        free(text);
        if (isinf(x)) json_bad(d, start);
        MoValue f = mo_f64(x);
        return mo_variant(MO_N_NUMBER, 1, &f);
    }
    json_bad(d, d->i);
}

static void json_scratch_free(void) {
    for (size_t k = 0; k < njson_scratch; k++) free(json_scratch[k].xs);
    njson_scratch = 0;
}

MO_ROW(mo_r_Json_decode) {
    (void)kind;
    Decoder d;
    d.s = a[0].as.s;
    d.n = a[0].aux;
    d.i = d.at = 0;
    MoValue result;
    if (setjmp(d.fail) == 0) {
        MoValue v = json_read(&d, 0);
        json_space(&d);
        if (d.i != d.n) {
            MoValue at = mo_u64(d.i);
            result = error_of(mo_variant(MO_N_SYNTAX, 1, &at));
        } else {
            result = ok_of(v);
        }
    } else {
        MoValue at = mo_u64(d.at);
        result = error_of(mo_variant(MO_N_SYNTAX, 1, &at));
    }
    json_scratch_free();
    return result;
}

/* ==== any(T), zero values, and what a run records (vm.zig generate and zero, sim.zig) === */

/* Xoshiro256++ seeded through SplitMix64: std.Random.DefaultPrng, draw for draw. */
typedef struct { uint64_t s[4]; } Rng;
static Rng rng;

static uint64_t splitmix(uint64_t *s) {
    *s += 0x9e3779b97f4a7c15ull;
    uint64_t z = *s;
    z = (z ^ (z >> 30)) * 0xbf58476d1ce4e5b9ull;
    z = (z ^ (z >> 27)) * 0x94d049bb133111ebull;
    return z ^ (z >> 31);
}

static void rng_seed(uint64_t seed) {
    for (int k = 0; k < 4; k++) rng.s[k] = splitmix(&seed);
}

static uint64_t rotl(uint64_t x, int k) { return (x << k) | (x >> (64 - k)); }

static uint64_t rng_next(void) {
    uint64_t *s = rng.s;
    uint64_t r = rotl(s[0] + s[3], 23) + s[0];
    uint64_t t = s[1] << 17;
    s[2] ^= s[0];
    s[3] ^= s[1];
    s[1] ^= s[2];
    s[0] ^= s[3];
    s[2] ^= t;
    s[3] = rotl(s[3], 45);
    return r;
}

/* Random.int(uN) for N <= 64 reads one draw and keeps its low bits. */
static uint64_t rng_bits(int bits) {
    uint64_t x = rng_next();
    return bits == 64 ? x : x & ((1ull << bits) - 1);
}

/* Random.uintLessThan (Lemire's method, with the tweak std.Random makes). */
static uint64_t rng_less_than(int bits, uint64_t less_than) {
    unsigned __int128 m = (unsigned __int128)rng_bits(bits) * less_than;
    uint64_t mask = bits == 64 ? UINT64_MAX : (1ull << bits) - 1;
    uint64_t l = (uint64_t)m & mask;
    if (l < less_than) {
        uint64_t t = (0 - less_than) & mask;
        if (t >= less_than) {
            t -= less_than;
            if (t >= less_than) t %= less_than;
        }
        while (l < t) {
            m = (unsigned __int128)rng_bits(bits) * less_than;
            l = (uint64_t)m & mask;
        }
    }
    return (uint64_t)(m >> bits);
}

/* Random.intRangeAtMost(i64, lo, hi). */
static int64_t rng_range_at_most(int64_t lo, int64_t hi) {
    uint64_t span = (uint64_t)hi - (uint64_t)lo;
    uint64_t pick = span == UINT64_MAX ? rng_bits(64) : rng_less_than(64, span + 1);
    return (int64_t)((uint64_t)lo + pick);
}

static bool rng_boolean(void) { return rng_bits(1) != 0; }

/* Random.float(f64). */
static double rng_float(void) {
    uint64_t r = rng_bits(64);
    uint64_t lz = r == 0 ? 64 : (uint64_t)__builtin_clzll(r);
    if (lz >= 12) {
        lz = 12;
        for (;;) {
            uint64_t x = rng_bits(64);
            uint64_t more = x == 0 ? 64 : (uint64_t)__builtin_clzll(x);
            lz += more;
            if (more != 64) break;
            if (lz >= 1022) {
                lz = 1022;
                break;
            }
        }
    }
    uint64_t bits = ((1022 - lz) << 52) | (r & 0xFFFFFFFFFFFFFull);
    double f;
    memcpy(&f, &bits, sizeof f);
    return f;
}

/* The values any(T) produced in this attempt, in order, for a property's report. */
typedef struct { const char *name; MoValue value; } Generated;
static Generated *generated;
static size_t ngenerated, capgenerated;

static MoValue generate(uint32_t t, uint32_t depth) {
    const MoType *ty = &mo_types[t];
    switch (ty->tag) {
    case MO_T_INT: {
        uint32_t k = ty->a;
        __int128 lo = kind_min(k), hi = kind_max(k);
        switch (rng_less_than(8, 10)) {
        case 0: return mo_i128(lo > 0 ? lo : 0);
        case 1: return mo_i128(hi < 1 ? hi : 1);
        case 2: return mo_i128(hi);
        case 3: return mo_i128(lo);
        case 4: return mo_i128(hi - 1);
        case 5:
        case 6: return mo_i128((__int128)rng_less_than(8, 101));
        default: return mo_i128(wrap_kind(k, (__int128)rng_bits(64)));
        }
    }
    case MO_T_BOOL: return mo_bool(rng_boolean());
    case MO_T_FLOAT: return mo_f64((rng_float() - 0.5) * 2e6);
    case MO_T_STRING: {
        static const char alphabet[] = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 -_";
        size_t len = (size_t)rng_less_than(64, 13);
        char *out = mo_alloc_bytes(len);
        for (size_t i = 0; i < len; i++) out[i] = alphabet[rng_less_than(64, 65)];
        return mo_str(out, (uint32_t)len);
    }
    case MO_T_TIME: return mo_time(FIXTURE_TIME + rng_range_at_most(-365 * MS_PER_DAY, 365 * MS_PER_DAY));
    case MO_T_DURATION: return mo_duration(rng_range_at_most(0, 100 * MS_PER_DAY));
    case MO_T_LIST: {
        size_t len = depth > 3 ? 0 : (size_t)rng_less_than(64, 7);
        MoValue *out = mo_alloc_values(len);
        for (size_t i = 0; i < len; i++) out[i] = generate(ty->a, depth + 1);
        return mo_list(out, (uint32_t)len);
    }
    case MO_T_OPTION:
        if (rng_less_than(8, 4) == 0) return mo_nothing();
        return mo_some(generate(ty->a, depth + 1));
    case MO_T_TUPLE: {
        MoValue *out = mo_alloc_values(ty->b);
        for (uint32_t i = 0; i < ty->b; i++) out[i] = generate(ty->items[i], depth + 1);
        return mo_tuple_of(out, ty->b);
    }
    case MO_T_MAP:
    case MO_T_SET: {
        size_t stride = ty->tag == MO_T_MAP ? 2 : 1;
        size_t tries = depth > 3 ? 0 : (size_t)rng_less_than(64, 7);
        Values out = {NULL, 0, 0};
        for (size_t i = 0; i < tries; i++) {
            MoValue key = generate(ty->a, depth + 1);
            if (index_of(out.xs, out.n, stride, key) != SIZE_MAX) continue;
            values_push(&out, key);
            if (stride == 2) values_push(&out, generate(ty->b, depth + 1));
        }
        MoValue m = {ty->tag == MO_T_MAP ? MO_MAP : MO_SET, 0, {0}};
        m.as.m = map_of(dupe_values(out.xs, out.n), out.n, stride);
        free(out.xs);
        return m;
    }
    case MO_T_ALIAS: {
        const MoDecl *d = &mo_decls[ty->a];
        for (uint32_t attempt = 0;; attempt++) {
            MoValue v = generate(ty->b, depth);
            bool holds = true;
            for (uint32_t r = 0; r < d->nrefines && holds; r++) holds = d->refines[r](v).as.b;
            if (holds || attempt == 100) return v;
        }
    }
    case MO_T_DECL: {
        const MoDecl *d = &mo_decls[ty->a];
        if (d->kind == MO_D_STRUCT) {
            MoValue *out = mo_alloc_values(d->nfields);
            for (uint32_t i = 0; i < d->nfields; i++) out[i] = generate(d->fields[i].type, depth + 1);
            MoValue v = {MO_RECORD, ty->a, {0}};
            v.as.xs = out;
            return v;
        }
        if (d->kind == MO_D_ENUM || d->kind == MO_D_PRELUDE_ENUM) {
            const MoVariantDef *def = &mo_variants[d->variants + rng_less_than(32, d->nvariants)];
            MoValue *out = mo_alloc_values(def->nfields);
            for (uint32_t i = 0; i < def->nfields; i++) out[i] = generate(def->fields[i].type, depth + 1);
            MoValue v = {MO_VARIANT, def->name | def->nfields << 16, {0}};
            v.as.xs = out;
            return v;
        }
        break;
    }
    default: break;
    }
    mo_fail(MO_R_OTHER, "", "any(%s) does not generate values yet", ty->name);
}

MoValue mo_generate(uint32_t type, const char *name) {
    MoValue v = generate(type, 0);
    if (ngenerated == capgenerated) {
        capgenerated = capgenerated ? 2 * capgenerated : 8;
        generated = xrealloc(generated, capgenerated * sizeof(Generated));
    }
    generated[ngenerated++] = (Generated){name, v};
    return v;
}

static bool zero_of(uint32_t t, MoValue *out) {
    const MoType *ty = &mo_types[t];
    while (ty->tag == MO_T_ALIAS) ty = &mo_types[ty->b];
    switch (ty->tag) {
    case MO_T_INT: *out = mo_i64(0); return true;
    case MO_T_FLOAT: *out = mo_f64(0); return true;
    case MO_T_BOOL: *out = mo_bool(false); return true;
    case MO_T_STRING: *out = mo_str("", 0); return true;
    case MO_T_DURATION: *out = mo_duration(0); return true;
    case MO_T_LIST: *out = mo_list(NULL, 0); return true;
    case MO_T_OPTION: *out = mo_nothing(); return true;
    case MO_T_MAP: *out = map_value(MO_MAP, NULL); return true;
    case MO_T_SET: *out = map_value(MO_SET, NULL); return true;
    case MO_T_TUPLE: {
        MoValue *xs = mo_alloc_values(ty->b);
        for (uint32_t i = 0; i < ty->b; i++) {
            if (!zero_of(ty->items[i], &xs[i])) return false;
        }
        *out = mo_tuple_of(xs, ty->b);
        return true;
    }
    case MO_T_DECL: {
        const MoDecl *d = &mo_decls[ty->a];
        if (d->kind != MO_D_STRUCT) return false;
        MoValue *xs = mo_alloc_values(d->nfields);
        for (uint32_t i = 0; i < d->nfields; i++) {
            if (!zero_of(d->fields[i].type, &xs[i])) return false;
        }
        MoValue v = {MO_RECORD, ty->a, {0}};
        v.as.xs = xs;
        *out = v;
        return true;
    }
    default: return false;
    }
}

MoValue mo_zero(uint32_t type, uint32_t clause) {
    MoValue v;
    if (!zero_of(type, &v)) mo_crash(clause);
    return v;
}

MoValue mo_platform(void) { return mo_cap(MO_CAP_PLATFORM, 0, 0); }

/* Per recorded type, the distinct values the run held, in the order it first held them. */
static Values *produced;

static void keep(uint32_t index, MoValue v) {
    Values *kept = &produced[index];
    for (size_t i = 0; i < kept->n; i++) {
        if (mo_equal(kept->xs[i], v)) return;
    }
    values_push(kept, v);
}

static void observe_fields(const MoValue *values, uint32_t n, const MoField *defs, uint32_t ndefs) {
    if (n != ndefs) return;
    for (uint32_t i = 0; i < n; i++) mo_observe(values[i], defs[i].type);
}

void mo_observe(MoValue v, uint32_t t) {
    if (!mo_records) return;
    const MoType *ty = &mo_types[t];
    if (!ty->may_hold) return;
    if (ty->recorded != UINT32_MAX) keep(ty->recorded, v);
    switch (ty->tag) {
    case MO_T_ALIAS: mo_observe(v, ty->b); return;
    case MO_T_LIST:
        if (v.tag == MO_LIST) {
            for (uint32_t i = 0; i < v.aux; i++) mo_observe(v.as.xs[i], ty->a);
        }
        return;
    case MO_T_SET:
        if (v.tag == MO_SET) {
            for (uint32_t i = 0; i < map_len(v); i++) mo_observe(v.as.m->entries[i], ty->a);
        }
        return;
    case MO_T_MAP:
        if (v.tag == MO_MAP) {
            for (uint32_t i = 0; i + 1 < map_len(v); i += 2) {
                mo_observe(v.as.m->entries[i], ty->a);
                mo_observe(v.as.m->entries[i + 1], ty->b);
            }
        }
        return;
    case MO_T_OPTION:
        if (v.tag == MO_VARIANT && mo_vcount(v) == 1) mo_observe(v.as.xs[0], ty->a);
        return;
    case MO_T_RESULT:
        if (v.tag == MO_VARIANT && mo_vcount(v) == 1) mo_observe(v.as.xs[0], mo_vname(v) == MO_N_OK ? ty->a : ty->b);
        return;
    case MO_T_TUPLE:
        if (v.tag == MO_TUPLE && v.aux == ty->b) {
            for (uint32_t i = 0; i < v.aux; i++) mo_observe(v.as.xs[i], ty->items[i]);
        }
        return;
    case MO_T_DECL:
    case MO_T_STATE:
    case MO_T_MESSAGE: {
        const MoDecl *d = &mo_decls[ty->a];
        if (v.tag == MO_RECORD) {
            observe_fields(v.as.xs, d->nfields, d->fields, d->nfields);
        } else if (v.tag == MO_VARIANT) {
            for (uint32_t k = 0; k < d->nvariants; k++) {
                const MoVariantDef *def = &mo_variants[d->variants + k];
                if (def->name == mo_vname(v)) {
                    observe_fields(v.as.xs, mo_vcount(v), def->fields, def->nfields);
                    break;
                }
            }
        }
        return;
    }
    default: return;
    }
}

MoValue mo_all(uint32_t index) {
    if (!produced || index >= mo_nrecorded) return mo_list(NULL, 0);
    return mo_list(produced[index].xs, (uint32_t)produced[index].n);
}

/* ==== the test runner (runner.zig) ======================================================= */

#define SEEDS_PER_PROPERTY 200
#define BASE_SEED UINT64_C(0x4d6f0003)
#define ATTEMPTS_PER_SEED 100

enum { PASSED, FAILED, TRIPPED_AS_EXPECTED, DID_NOT_TRIP, SKIPPED };

typedef struct {
    int outcome;
    bool has_report;
    Report report;
    uint64_t seed;
    char *generated_text;
    const char *note;
} Result;

/* A test or property run starts from nothing: its memory, fixtures, and records. */
static void fresh_run(void) {
    reset_fixtures();
    mo_records = mo_nnevers > 0;
    if (mo_nrecorded > 0) {
        if (!produced) produced = calloc(mo_nrecorded, sizeof(Values));
        for (uint32_t k = 0; k < mo_nrecorded; k++) produced[k].n = 0;
    }
}

/* Every never, over the values the run held; the first that is true crashes the run. */
static void check_nevers(void) {
    if (!mo_records) return;
    mo_records = false;
    for (uint32_t k = 0; k < mo_nnevers; k++) mo_nevers[k].fn();
    mo_records = true;
}

static bool trips_rejects(uint8_t kind) {
    return kind == MO_R_REQUIRES || kind == MO_R_REFINEMENT || kind == MO_R_INVARIANT || kind == MO_R_NEVER;
}

static Result run_test(const MoTest *t) {
    Result r = {PASSED, false, {0}, 0, NULL, NULL};
    reset_memory();
    fresh_run();
    rng_seed(BASE_SEED);
    jmp_buf here;
    crash_jump = &here;
    int jumped = setjmp(here);
    if (jumped == 0) {
        t->fn();
        check_nevers();
        if (t->kind == MO_TEST_REJECTS) {
            r.outcome = DID_NOT_TRIP;
            r.note = "the body ran to its end without tripping a requires, a refinement, an invariant, or a never";
        }
    } else if (jumped == JUMP_SKIP) {
        r.outcome = SKIPPED;
        r.has_report = true;
        r.report = last_report;
    } else {
        r.has_report = true;
        r.report = last_report;
        r.outcome = t->kind == MO_TEST_REJECTS && trips_rejects(last_report.kind) ? TRIPPED_AS_EXPECTED : FAILED;
    }
    crash_jump = NULL;
    return r;
}

static Result run_property(const MoTest *t) {
    Result r = {PASSED, false, {0}, 0, NULL, NULL};
    uint32_t held = 0;
    reset_memory();
    for (uint64_t i = 0; i < SEEDS_PER_PROPERTY; i++) {
        uint64_t seed = BASE_SEED + i;
        rng_seed(seed);
        for (uint32_t attempt = 0; attempt < ATTEMPTS_PER_SEED; attempt++) {
            ngenerated = 0;
            fresh_run();
            jmp_buf here;
            crash_jump = &here;
            int jumped = setjmp(here);
            if (jumped == 0) {
                t->fn();
                check_nevers();
                crash_jump = NULL;
                held++;
                break;
            }
            crash_jump = NULL;
            if (jumped == JUMP_DISCARD) continue;
            if (jumped == JUMP_SKIP) {
                r.outcome = SKIPPED;
                r.has_report = true;
                r.report = last_report;
                return r;
            }
            r.outcome = FAILED;
            r.has_report = true;
            r.report = last_report;
            r.seed = seed;
            Buf b = {0};
            for (size_t g = 0; g < ngenerated; g++) {
                char *value = render(generated[g].value);
                buf_printf(&b, "%s%s = %s", g == 0 ? " with " : ", ", generated[g].name, value);
                free(value);
            }
            r.generated_text = buf_take(&b);
            return r;
        }
    }
    if (held == 0) {
        r.outcome = FAILED;
        r.note = "the guard held for no generated value under any seed";
    }
    return r;
}

static void write_result(Buf *b, const MoTest *t, const Result *r) {
    const char *tag = r->outcome == PASSED || r->outcome == TRIPPED_AS_EXPECTED ? "pass" : r->outcome == SKIPPED ? "skip" : "FAIL";
    const char *kind = t->kind == MO_TEST ? "test" : t->kind == MO_TEST_REJECTS ? "test rejects" : "property";
    buf_printf(b, "%s  %s \"%s\"", tag, kind, t->name);
    switch (r->outcome) {
    case PASSED:
        if (t->kind == MO_PROPERTY) buf_printf(b, ": %d seeds", SEEDS_PER_PROPERTY);
        break;
    case TRIPPED_AS_EXPECTED: buf_printf(b, ": tripped %s", r->report.clause); break;
    case SKIPPED: buf_printf(b, ": %s", r->report.clause); break;
    default:
        buf_str(b, ": ");
        if (t->kind == MO_PROPERTY && r->has_report) buf_printf(b, "seed %llu%s: ", (unsigned long long)r->seed, r->generated_text ? r->generated_text : "");
        if (r->has_report) report_text(b, &r->report);
        else buf_str(b, r->note ? r->note : "");
        break;
    }
    buf_byte(b, '\n');
}

/* A count as chapter 5 spells it: 1_000. */
static void grouped(Buf *b, uint32_t n) {
    if (n < 1000) {
        buf_printf(b, "%u", n);
        return;
    }
    grouped(b, n / 1000);
    buf_printf(b, "_%03u", n % 1000);
}

int mo_run_tests(void) {
    server_mode = false;
    mo_contracts = true;
    if (!reserve(&mo_heap)) mo_heap = (MoRegion){0, 0, 0};
    mo_compacts = false;
    uint32_t tests = 0, failures = 0, skipped = 0, seeds = 0;
    Buf b = {0};
    for (uint32_t k = 0; k < mo_ntests; k++) {
        const MoTest *t = &mo_tests[k];
        Result r = t->kind == MO_PROPERTY ? run_property(t) : run_test(t);
        switch (r.outcome) {
        case PASSED:
        case TRIPPED_AS_EXPECTED:
            tests++;
            if (t->kind == MO_PROPERTY) seeds = SEEDS_PER_PROPERTY;
            break;
        case SKIPPED: skipped++; break;
        default: failures++; break;
        }
        write_result(&b, t, &r);
    }
    buf_printf(&b, "%u passed, %u failed, %u skipped\n", tests, failures, skipped);
    if (failures > 0) {
        buf_str(&b, "verified: types\n");
    } else {
        buf_str(&b, "verified: types, contracts, tests (");
        grouped(&b, tests);
        buf_str(&b, "), property (");
        grouped(&b, seeds);
        buf_str(&b, " seeds), sim (not run)\n");
    }
    buf_str(&b, "          proven: not run\n");
    stream_write(&out_stream, b.p, b.len);
    stream_flush(&out_stream);
    return failures > 0 ? 1 : 0;
}

/* ==== main on Mo.Server (server.zig, main.zig) =========================================== */

void mo_program_start(int argc, char **argv) {
    server_mode = true;
    signal(SIGPIPE, SIG_IGN);
    const char *said = getenv("MO_CONTRACTS");
    mo_contracts = said ? strcmp(said, "0") != 0 : mo_contracts_built;
    /* Values live in a region freed at safe points; without the address space, every value
     * lives until the run ends. */
    if (reserve(&mo_heap) && reserve(&scratch)) {
        mo_compacts = true;
    } else {
        mo_heap = scratch = (MoRegion){0, 0, 0};
        mo_compacts = false;
    }
    program_argc = argc > 0 ? argc - 1 : 0;
    program_argv = argv + 1;
    char *cwd = getcwd(NULL, 0);
    add_scope((Scope){cwd ? cwd : strdup("/"), "/", false, false});
}

int mo_program_end(void) {
    stream_flush(&out_stream);
    stream_flush(&err_stream);
    return exit_code;
}
