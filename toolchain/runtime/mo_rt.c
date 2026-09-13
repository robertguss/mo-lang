/* mo_rt.c: the runtime a compiled Mo program links (mo_rt.h says what a value is).
 * Each part names the interpreter file it reproduces; where the two could differ, the
 * interpreter is the reference and this file follows it. */
#define _DEFAULT_SOURCE
#define _DARWIN_C_SOURCE
#include "mo_rt.h"

#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <math.h>
#include <setjmp.h>
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
