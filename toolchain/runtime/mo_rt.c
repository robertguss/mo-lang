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

#include <arpa/inet.h>
#include <ctype.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <math.h>
#include <netdb.h>
#include <netinet/in.h>
#include <poll.h>
#include <pthread.h>
#include <setjmp.h>
#include <signal.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/socket.h>
#if defined(__APPLE__) || defined(__FreeBSD__) || defined(__NetBSD__) || defined(__OpenBSD__)
#define MO_KQUEUE 1
#include <sys/event.h>
#elif defined(__linux__)
#include <sys/epoll.h>
#endif
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>
#if defined(__APPLE__)
#include <mach/mach.h>
#endif

extern char **environ;

/* ==== memory (vm.zig: regions, push in place, owned buffers, compaction) ============== */

MoRegion mo_heap;
MoHandleFrame *mo_handle_frames;
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

#define GROW_ARRAY(ptr, n, cap)                                                              \
    do {                                                                                     \
        if ((n) == (cap)) {                                                                  \
            (cap) = (cap) ? 2 * (cap) : 8;                                                   \
            (ptr) = xrealloc((ptr), (cap) * sizeof *(ptr));                                  \
        }                                                                                    \
    } while (0)

static void *xrealloc(void *p, size_t n) {
    void *q = realloc(p, n ? n : 1);
    if (!q) out_of_memory();
    return q;
}

/* As much address space as the system gives, from `most` down to 256 MiB (region.zig). */
static bool reserve_up_to(MoRegion *r, size_t most) {
    for (size_t size = most; size >= (size_t)256 << 20; size /= 2) {
        void *mem = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
        if (mem == MAP_FAILED) continue;
        r->base = r->top = (uintptr_t)mem;
        r->end = r->base + size;
        return true;
    }
    return false;
}

static bool reserve(MoRegion *r) { return reserve_up_to(r, (size_t)64 << 30); }

/* Counts MO_STATS=1 prints (step 21): allocations and their bytes, values packed and their bytes,
 * processes a sweep ended and the time it took. */
static uint64_t stat_allocations, stat_bytes, stat_packed, stat_packed_bytes, stat_packed_capacity, stat_freed, stat_freed_ns;

static void print_stats(void) {
    char line[256];
    int n = snprintf(line, sizeof line, "mo stats: allocations %llu bytes %llu packed %llu packed_bytes %llu packed_capacity %llu freed %llu freed_ns %llu\n", (unsigned long long)stat_allocations, (unsigned long long)stat_bytes, (unsigned long long)stat_packed, (unsigned long long)stat_packed_bytes, (unsigned long long)stat_packed_capacity, (unsigned long long)stat_freed, (unsigned long long)stat_freed_ns);
    if (n > 0) {
        ssize_t w = write(2, line, (size_t)n);
        (void)w;
    }
}

static void stats_on_term(int sig) {
    (void)sig;
    print_stats();
    _exit(0);
}

static void *region_alloc(MoRegion *r, size_t n) {
    stat_allocations++;
    stat_bytes += n;
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

typedef struct { uintptr_t ptr; size_t len, cap; } Growth;
/* A table from where a buffer starts to what the runtime keeps of it (step 28): open addressing on
 * the address, holding every buffer rather than the sixteen used last. */
typedef struct { Growth *slots; size_t cap, used; } PtrTable;
/* The lists push can grow in place: their length and room. */
static PtrTable growth;
/* The strings an interpolation can grow in place, as push grows a list (mo_concat). */
static Growth text_growth[16];
static unsigned text_growth_next;
/* Map and set entries, and struct fields, one holder holds alone: the length it sees (vm.zig,
 * owned). */
static PtrTable owned;

/* Slots a row wrote in place with a value that may be newer than the slot. */
typedef struct { uintptr_t slot; size_t len; uintptr_t at; } Remembered;
static Remembered *remembered;
static size_t nremembered, capremembered;

/* Under an update (sim.zig): what each slot older than the update held before the update wrote
 * it, so a crash shows the state as it was. undo_mark is 0 when no update keeps one; buffers
 * older than frozen_below are never written in place (an invariant reads old(state)). */
/* A remove (stride 1 or 2) took the entry old, second out at slot of the len entries, moving the
 * slots after it down; undone, they move back and the map's table is built again (vm.zig, Undo). */
typedef struct {
    uintptr_t slot;
    MoValue old;
    uint32_t stride;
    MoValue second;
    MoValue *entries;
    size_t len;
    uint32_t *index;
    uint32_t index_len;
} Undo;
static Undo *undos;
static size_t nundos, capundos;
static uintptr_t undo_mark, frozen_below;
/* What the region held after its last full compaction (sim.zig, settleRegion). */
static size_t full_kept;

static size_t ptab_home(const PtrTable *t, uintptr_t ptr) {
    uint64_t h = ((uint64_t)ptr >> 3) * 0x9E3779B97F4A7C15ull;
    return (size_t)(h ^ (h >> 29)) & (t->cap - 1);
}

/* Address 0 is no buffer: an empty slot holds it. */
static Growth *ptab_get(const PtrTable *t, uintptr_t ptr) {
    if (t->used == 0 || ptr == 0) return NULL;
    for (size_t i = ptab_home(t, ptr);; i = (i + 1) & (t->cap - 1)) {
        if (t->slots[i].ptr == ptr) return &t->slots[i];
        if (t->slots[i].ptr == 0) return NULL;
    }
}

static void ptab_insert(PtrTable *t, Growth g) {
    for (size_t i = ptab_home(t, g.ptr);; i = (i + 1) & (t->cap - 1)) {
        if (t->slots[i].ptr != 0 && t->slots[i].ptr != g.ptr) continue;
        if (t->slots[i].ptr == 0) t->used++;
        t->slots[i] = g;
        return;
    }
}

static void ptab_rebuild(PtrTable *t, size_t cap, uintptr_t lo, uintptr_t hi) {
    PtrTable old = *t;
    t->cap = cap;
    t->slots = xmalloc(cap * sizeof(Growth));
    memset(t->slots, 0, cap * sizeof(Growth));
    t->used = 0;
    for (size_t i = 0; i < old.cap; i++) {
        uintptr_t p = old.slots[i].ptr;
        if (p != 0 && (p < lo || p >= hi)) ptab_insert(t, old.slots[i]);
    }
    free(old.slots);
}

static void ptab_put(PtrTable *t, uintptr_t ptr, size_t len, size_t cap) {
    if (2 * (t->used + 1) > t->cap) ptab_rebuild(t, t->cap ? 2 * t->cap : 64, 0, 0);
    ptab_insert(t, (Growth){ptr, len, cap});
}

/* Backward-shift deletion: every probe run stays whole. */
static void ptab_remove(PtrTable *t, uintptr_t ptr) {
    Growth *g = ptab_get(t, ptr);
    if (!g) return;
    size_t mask = t->cap - 1, i = (size_t)(g - t->slots), j = i;
    for (;;) {
        j = (j + 1) & mask;
        if (t->slots[j].ptr == 0) break;
        size_t home = ptab_home(t, t->slots[j].ptr);
        bool stays = i <= j ? (home > i && home <= j) : (home > i || home <= j);
        if (stays) continue;
        t->slots[i] = t->slots[j];
        i = j;
    }
    t->slots[i] = (Growth){0, 0, 0};
    t->used--;
}

/* Forgets the buffers in [lo, hi). */
static void ptab_drop(PtrTable *t, uintptr_t lo, uintptr_t hi) {
    if (t->used == 0) return;
    for (size_t i = 0; i < t->cap; i++) {
        uintptr_t p = t->slots[i].ptr;
        if (p != 0 && p >= lo && p < hi) {
            ptab_rebuild(t, t->cap, lo, hi);
            return;
        }
    }
}

static void ptab_clear(PtrTable *t) {
    if (t->slots) memset(t->slots, 0, t->cap * sizeof(Growth));
    t->used = 0;
}

/* Forgets every buffer a test's memory held: the next test starts a fresh vm. */
static void reset_memory(void) {
    mo_heap.top = mo_heap.base;
    memset(text_growth, 0, sizeof text_growth);
    ptab_clear(&growth);
    ptab_clear(&owned);
    nremembered = 0;
}

static Growth *growth_of(uintptr_t addr, size_t len) {
    Growth *g = ptab_get(&growth, addr);
    return g && g->len == len && g->cap != 0 ? g : NULL;
}

static void drop_growth(uintptr_t lo, uintptr_t hi) {
    ptab_drop(&growth, lo, hi);
    for (unsigned i = 0; i < 16; i++) {
        if (text_growth[i].ptr >= lo && text_growth[i].ptr < hi) text_growth[i] = (Growth){0, 0, 0};
    }
    ptab_drop(&owned, lo, hi);
}

static bool is_owned(const MoValue *xs, size_t len) {
    if (len == 0) return false;
    Growth *o = ptab_get(&owned, (uintptr_t)xs);
    return o && o->len == len;
}

static void own(const MoValue *xs, size_t len) {
    if (len > 0) ptab_put(&owned, (uintptr_t)xs, len, 0);
}

static void disown(const MoValue *xs, size_t len) {
    if (len == 0) return;
    Growth *o = ptab_get(&owned, (uintptr_t)xs);
    if (o && o->len == len) ptab_remove(&owned, (uintptr_t)xs);
}

/* A read that shares `v` (moves.zig): every map, set, or struct it holds, itself or inside a
 * struct, tuple, or variant, may now be held twice (vm.zig, disownIn). */
void mo_disown_in(MoValue v) {
    if (owned.used == 0) return;
    switch (v.tag) {
    case MO_MAP:
    case MO_SET:
        if (v.as.m) disown(v.as.m->entries, v.as.m->len);
        break;
    case MO_RECORD:
        disown(v.as.xs, mo_decls[v.aux].nfields);
        for (uint32_t k = 0; k < mo_decls[v.aux].nfields; k++) mo_disown_in(v.as.xs[k]);
        break;
    case MO_TUPLE:
        for (uint32_t k = 0; k < v.aux; k++) mo_disown_in(v.as.xs[k]);
        break;
    case MO_VARIANT:
        for (uint32_t k = 0; k < mo_vcount(v); k++) mo_disown_in(v.as.xs[k]);
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
    /* A write inside the slots the last one remembered moves that one's mark forward instead of
     * adding another (vm.zig, rememberWrite; step 21). */
    if (nremembered > 0) {
        Remembered *last = &remembered[nremembered - 1];
        if (slot >= last->slot && slot + n * sizeof(MoValue) <= last->slot + last->len * sizeof(MoValue)) {
            last->at = mo_heap.top;
            return;
        }
    }
    if (nremembered == capremembered) {
        capremembered = capremembered ? 2 * capremembered : 256;
        remembered = xrealloc(remembered, capremembered * sizeof(Remembered));
    }
    remembered[nremembered++] = (Remembered){slot, n, mo_heap.top};
}

/* A remove moved the slots of `xs` from `k + stride` on down by `stride` in place: only when one of
 * them was remembered may a remembered value now sit where no remembered slot reaches it, and then
 * the moved slots are remembered (vm.zig, rememberShift). */
static void remember_shift(MoValue *xs, size_t len, size_t k, size_t stride) {
    if (!mo_compacts || !in_heap((uintptr_t)xs)) return;
    uintptr_t lo = (uintptr_t)&xs[k + stride], hi = (uintptr_t)&xs[len];
    for (size_t i = 0; i < nremembered; i++) {
        if (remembered[i].slot < hi && remembered[i].slot + remembered[i].len * sizeof(MoValue) > lo) {
            remember_write((uintptr_t)&xs[k], len - stride - k, NULL);
            return;
        }
    }
}

/* Whether `addr` was allocated since `mark` in the region. */
static bool since(uintptr_t mark, uintptr_t addr) { return addr >= mark && addr < mo_heap.end; }

/* Whether a row may overwrite a buffer at `buf` in place. */
static bool overwritable(uintptr_t buf) { return frozen_below == 0 || since(frozen_below, buf); }


/* Writes `x` into a slot in place: remembered for compaction, and under an update what the slot
 * held before, when that is older than the update and so still there on a crash. */
static void overwrite(MoValue *slot, MoValue x) {
    uintptr_t addr = (uintptr_t)slot;
    if (undo_mark != 0 && !since(undo_mark, addr)) {
        uintptr_t p = newest_of(*slot);
        if (p == 0 || !since(undo_mark, p)) {
            GROW_ARRAY(undos, nundos, capundos);
            undos[nundos++] = (Undo){addr, *slot};
        }
    }
    remember_write(addr, 1, &x);
    *slot = x;
}

/* A remove is about to take the entry at `k` out of `xs` in place (step 28): under an update, from a
 * buffer older than it, what a crash needs to put the entries back (vm.zig, keepRemove). Without
 * compaction an update's undo_mark is past every address, so it is always kept. */
static void keep_remove(MoValue *xs, size_t len, size_t k, size_t stride, uint32_t *index, uint32_t index_len) {
    if (undo_mark == 0 || since(undo_mark, (uintptr_t)xs)) return;
    GROW_ARRAY(undos, nundos, capundos);
    undos[nundos++] = (Undo){(uintptr_t)&xs[k], xs[k], (uint32_t)stride, stride == 2 ? xs[k + 1] : MO_NONE_V, xs, len, index, index_len};
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
    ptab_put(&growth, (uintptr_t)out, len + 1, cap);
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

/* A value copied whole into memory of its own (vm.zig, Parcel), so it outlives the region it
 * was made in: under main, a message on its way to another process, a reply on its way back, and
 * a process's start arguments and first state. */
typedef struct Chunk { struct Chunk *next; size_t used, cap; } Chunk;
typedef struct { MoValue value; Chunk *chunks; } Parcel;

static void *parcel_alloc(Parcel *p, size_t n) {
    size_t need = (n + 7) & ~(size_t)7;
    Chunk *c = p->chunks;
    if (!c || c->used + need > c->cap) {
        size_t cap = need > 4072 ? need : 4072;
        c = xmalloc(sizeof(Chunk) + cap);
        c->next = p->chunks;
        c->used = 0;
        c->cap = cap;
        p->chunks = c;
    }
    void *out = (char *)(c + 1) + c->used;
    c->used += need;
    return out;
}

static void parcel_free(Parcel *p) {
    if (!p) return;
    while (p->chunks) {
        Chunk *next = p->chunks->next;
        free(p->chunks);
        p->chunks = next;
    }
    free(p);
}

typedef struct { uintptr_t lo, hi; MoRegion *dest; bool moves, fresh; Parcel *parcel; } Copy;

static void *copy_alloc(const Copy *c, size_t n) { return c->parcel ? parcel_alloc(c->parcel, n) : region_alloc((c)->dest, n); }

static bool inside(uintptr_t addr, const Copy *c) { return addr >= c->lo && addr < c->hi; }

static uint32_t *build_index(MoRegion *dest, const MoValue *entries, size_t len, size_t stride, size_t min_slots, uint32_t *index_len);
static MoValue copy_out(MoValue v, const Copy *c);

static MoValue *copy_slice(MoValue *xs, size_t len, const Copy *c, bool grows) {
    uintptr_t addr = (uintptr_t)xs;
    if (len == 0 || !inside(addr, c)) return xs;
    MoValue *copied = forward_get(addr, len);
    if (copied) return copied;
    /* By value: copying what the slice holds may grow the table it is in. */
    Growth *found = grows && c->moves ? growth_of(addr, len) : NULL;
    Growth g = found ? *found : (Growth){0, 0, 0};
    MoValue *out = copy_alloc(c, (found ? g.cap : len) * sizeof(MoValue));
    forward_put(addr, len, out);
    for (size_t i = 0; i < len; i++) out[i] = copy_out(xs[i], c);
    if (found) ptab_put(&growth, (uintptr_t)out, g.len, g.cap);
    if (c->moves && is_owned(xs, len)) own(out, len);
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
            index = copy_alloc(c, m->index_len * sizeof(uint32_t));
            memcpy(index, m->index, m->index_len * sizeof(uint32_t));
            index_len = m->index_len;
        } else {
            index = build_index(c->dest, entries, m->len, stride, m->index_len - 1, &index_len);
        }
    }
    if (!header_inside && entries == m->entries && index == m->index) return m;
    MoMap *out = copy_alloc(c, sizeof(MoMap));
    *out = (MoMap){entries, m->len, index_len, index};
    return out;
}

static MoValue copy_out(MoValue v, const Copy *c) {
    switch (v.tag) {
    case MO_STRING:
        if (v.aux > 0 && inside((uintptr_t)v.as.s, c)) {
            char *s = copy_alloc(c, v.aux);
            memcpy(s, v.as.s, v.aux);
            v.as.s = s;
        }
        return v;
    case MO_BIG:
        if (inside((uintptr_t)v.as.big, c)) {
            __int128 *b = copy_alloc(c, sizeof(__int128));
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
            MoFunc *out = copy_alloc(c, sizeof(MoFunc) + f->ncap * sizeof(MoValue));
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

/* Moves everything `roots` reach into a fresh reservation of `size` bytes, which takes the heap's
 * place, and releases the old one. Only where nothing but `roots` reaches into the heap: after a
 * process's update, whose new state is the one root (settle_region; vm.zig, relocate). */
static void relocate_heap(size_t size, MoValue *roots, size_t n) {
    MoRegion fresh;
    if (!reserve_up_to(&fresh, size)) return;
    if (fresh.end - fresh.base <= mo_heap.end - mo_heap.base) {
        munmap((void *)fresh.base, fresh.end - fresh.base);
        return;
    }
    scratch.top = scratch.base;
    forward_clear();
    Copy out = {mo_heap.base, mo_heap.top, &scratch, true, false};
    copy_roots(roots, n, NULL, 0, &out);
    drop_growth(mo_heap.base, mo_heap.end);
    /* Every remembered slot was in the old heap. */
    nremembered = 0;
    forward_clear();
    Copy back = {scratch.base, scratch.top, &fresh, true, true};
    copy_roots(roots, n, NULL, 0, &back);
    drop_growth(scratch.base, scratch.end);
    munmap((void *)mo_heap.base, mo_heap.end - mo_heap.base);
    mo_heap = fresh;
}

/* `v` copied whole into a parcel of its own. */
static Parcel *pack(MoValue v) {
    Parcel *p = xmalloc(sizeof(Parcel));
    p->chunks = NULL;
    forward_clear();
    Copy c = {0, UINTPTR_MAX, NULL, false, false, p};
    p->value = copy_out(v, &c);
    stat_packed++;
    for (const Chunk *k = p->chunks; k; k = k->next) {
        stat_packed_bytes += k->used;
        stat_packed_capacity += sizeof(Chunk) + k->cap;
    }
    return p;
}

/* A parcel's value copied whole onto this vm's heap, so the parcel can be freed. */
static MoValue unpack(const Parcel *p) {
    forward_clear();
    Copy c = {0, UINTPTR_MAX, &mo_heap, false, false, NULL};
    return copy_out(p->value, &c);
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

/* `x.field = v` on a var or a field path under one: in place when the var holds the fields alone
 * (an earlier set made them, and nothing has read the var since) and they may be written (step 21);
 * otherwise a copy, which the var then holds alone (vm.zig, set_field). */
MoValue mo_set_field(MoValue obj, uint32_t k, MoValue v) {
    uint32_t n = mo_nfields(obj);
    /* Only on the heap: there an update's undo and an invariant's old(state) keep what it overwrites
     * (deliver); without one a set copies. */
    if (n > 0 && mo_compacts && in_heap((uintptr_t)obj.as.xs) && is_owned(obj.as.xs, n) && overwritable((uintptr_t)obj.as.xs)) {
        overwrite(&obj.as.xs[k], v);
        return obj;
    }
    MoValue *fields = dupe_values(obj.as.xs, n);
    fields[k] = v;
    own(fields, n);
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

static size_t map_find(const MoMap *m, size_t stride, MoValue key);

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
        /* Equal keys with equal values, or equal elements, in any order (design-v0/09, step 18). */
        uint32_t la = a.as.m ? a.as.m->len : 0, lb = b.as.m ? b.as.m->len : 0;
        if (la != lb) return false;
        size_t stride = a.tag == MO_MAP ? 2 : 1;
        for (size_t k = 0; k < la; k += stride) {
            size_t at = map_find(b.as.m, stride, a.as.m->entries[k]);
            if (at == SIZE_MAX) return false;
            if (stride == 2 && !mo_equal(a.as.m->entries[k + 1], b.as.m->entries[at + 1])) return false;
        }
        return true;
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
        /* Equal maps and sets can hold their entries in different orders (mo_equal), so each
         * entry hashes on its own and the hashes add up. */
        uint32_t n = v.as.m ? v.as.m->len : 0;
        size_t stride = v.tag == MO_MAP ? 2 : 1;
        uint64_t sum = 0;
        for (size_t i = 0; i < n; i += stride) {
            uint64_t one = hash_value(v.as.m->entries[i]);
            if (stride == 2) one = mix(one, hash_value(v.as.m->entries[i + 1]));
            sum += one;
        }
        return mix(mix(h, n), sum);
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

/* A table slot whose entry a remove took out in place (step 28; stdlib.zig, removed_slot): a probe
 * goes on past it, and it stays counted in use until the table is built again. */
#define REMOVED_SLOT UINT32_MAX

/* A table built again in place over entries it has room for: a crashed update's remove undone. */
static void rebuild_index(uint32_t *index, uint32_t index_len, const MoValue *entries, size_t len, size_t stride) {
    memset(index, 0, index_len * sizeof(uint32_t));
    for (size_t o = 0; o < len / stride; o++) insert_ordinal(index, index_len, entries, stride, o);
}

/* The entry `key`, at ordinal `gone`, was taken out and the ones after it moved down one: its slot,
 * found as a lookup finds it, is marked removed, and every later ordinal counts one less, in one pass
 * without a branch (stdlib.zig, dropOrdinal). */
static void drop_ordinal(uint32_t *index, uint32_t index_len, MoValue key, size_t gone) {
    uint32_t *table = index + 1;
    size_t mask = index_len - 2;
    uint32_t past = (uint32_t)(gone + 1);
    size_t i = (size_t)hash_value(key) & mask;
    while (table[i] != past) i = (i + 1) & mask;
    table[i] = REMOVED_SLOT;
    for (size_t j = 0; j + 1 < index_len; j++) table[j] -= (uint32_t)((table[j] > past) & (table[j] != REMOVED_SLOT));
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
        if (mine && overwritable((uintptr_t)xs)) {
            overwrite(&xs[k + 1], value);
            return m;
        }
        /* A copy nobody owns shares the table; an owned one may be removed from in place, which
         * changes its table, so it takes a copy (stdlib.zig, put). */
        MoValue *out = dupe_values(xs, len);
        out[k + 1] = value;
        if (!on_var) return map_header(out, len, m->index, m->index_len);
        own(out, len);
        uint32_t *index = m->index;
        if (m->index_len > 0) {
            index = mo_alloc_bytes(m->index_len * sizeof(uint32_t));
            memcpy(index, m->index, m->index_len * sizeof(uint32_t));
        }
        return map_header(out, len, index, m->index_len);
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
    /* Held alone, the entries after the key move down in place and the table, the buffer's own,
     * drops the key's slot (step 28); under an update a buffer older than it keeps what a crash
     * puts back. */
    if (on_var && is_owned(xs, len) && overwritable((uintptr_t)xs)) {
        keep_remove(xs, len, k, stride, m->index, m->index_len);
        if (m->index_len > 0) drop_ordinal(m->index, m->index_len, key, k / stride);
        memmove(&xs[k], &xs[k + stride], (rest - k) * sizeof(MoValue));
        remember_shift(xs, len, k, stride);
        disown(xs, len);
        own(xs, rest);
        return map_header(xs, rest, m->index, m->index_len);
    }
    uint32_t index_len;
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
static const char *handle_name(int64_t id);

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
        case MO_CAP_CONN: buf_str(b, "a Conn"); return;
        case MO_CAP_HTTP: buf_str(b, server_mode ? "an Http" : "Http.fixture()"); return;
        case MO_CAP_HTTP_LISTENER: buf_str(b, "an HttpListener"); return;
        case MO_CAP_EXCHANGE: buf_str(b, "an Exchange"); return;
        default: buf_str(b, !server_mode ? "Runtime.fixture()" : mo_cap_handle(v) == 1 ? "a read-only Runtime" : "a Runtime"); return;
        }
    case MO_HANDLE:
        if (handle_name(v.as.i)) buf_printf(b, "%s #%lld", handle_name(v.as.i), (long long)v.as.i);
        else buf_printf(b, "a handle #%lld", (long long)v.as.i);
        return;
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

/* `"#{a}#{b}..."`: when the first part is a string on the heap that ends where its buffer's last
 * interpolation left it and the rest fits past it, the rest is written there in place (vm.zig,
 * concatText; step 21); otherwise a new string, with room to grow when its first part was made at
 * run time. */
MoValue mo_concat(uint32_t n, const MoValue *parts) {
    /* Formatting runs no Mo code, so one buffer serves every interpolation. */
    static Buf b;
    b.len = 0;
    bool headed = n > 0 && parts[0].tag == MO_STRING && parts[0].aux > 0;
    for (uint32_t i = headed ? 1 : 0; i < n; i++) format_text(&b, parts[i]);
    const char *tail = b.p ? b.p : "";
    size_t head_len = headed ? parts[0].aux : 0;
    bool grows = headed && mo_compacts && in_heap((uintptr_t)parts[0].as.s);
    if (grows) {
        for (unsigned i = 0; i < 16; i++) {
            Growth *g = &text_growth[i];
            if (g->ptr != (uintptr_t)parts[0].as.s || g->len != head_len || g->cap - g->len < b.len) continue;
            if (b.len) memcpy((char *)g->ptr + g->len, tail, b.len);
            g->len += b.len;
            return mo_str((char *)g->ptr, (uint32_t)g->len);
        }
    }
    size_t len = head_len + b.len;
    size_t cap = grows ? (2 * len > 16 ? 2 * len : 16) : len;
    char *out = mo_alloc_bytes(cap);
    if (head_len) memcpy(out, parts[0].as.s, head_len);
    if (b.len) memcpy(out + head_len, tail, b.len);
    if (grows) {
        text_growth[text_growth_next] = (Growth){(uintptr_t)out, len, cap};
        text_growth_next = (text_growth_next + 1) % 16;
    }
    return mo_str(out, (uint32_t)len);
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
    /* A crash inside a process: the process, the seed, every message since it started, and its
     * state before the last one (chapter 3, failure). */
    const char *process;
    uint64_t seed;
    char **log;
    uint32_t nlog;
    char *state;
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
    case MO_R_REFINEMENT: buf_printf(b, "%s tripped in %s", r->clause, r->within); break;
    case MO_R_INVARIANT: buf_printf(b, "%s no longer holds in %s", r->clause, r->within); break;
    case MO_R_NEVER: buf_printf(b, "%s tripped", r->clause); break;
    case MO_R_OVERFLOW: buf_printf(b, "overflow in %s", r->clause); break;
    case MO_R_DIVIDE_BY_ZERO: buf_printf(b, "division by zero in %s", r->clause); break;
    default: buf_str(b, r->clause); break;
    }
    for (uint32_t i = 0; i < r->nvalues; i++) buf_printf(b, "%s%s = %s", i == 0 ? "; " : ", ", r->values[i].name, r->values[i].value);
    if (r->process) {
        buf_printf(b, "\n      in process %s, seed %llu\n      messages since it started: ", r->process, (unsigned long long)r->seed);
        for (uint32_t i = 0; i < r->nlog; i++) buf_printf(b, "%s%s", i == 0 ? "" : ", ", r->log[i]);
        buf_printf(b, "\n      state before the last message: %s", r->state);
    }
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

_Thread_local uint32_t mo_depth;

_Noreturn void mo_too_deep(const char *name) {
    mo_fail(MO_R_OTHER, name, "%s is called %u calls deep, and calls nest at most %u deep", name, (unsigned)MO_DEPTH_LIMIT + 1, (unsigned)MO_DEPTH_LIMIT);
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
        /* In a list, an element never holds a buffer alone (mo_disown_in). */
        mo_disown_in(out[i]);
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
/* A merge sort, so stable: keys that order level keep their positions' order, ascending or
 * descending. */
static void sort_positions(uint32_t *pos, uint32_t *tmp, size_t n, const MoValue *keys, bool descending) {
    if (n < 2) return;
    size_t mid = n / 2;
    sort_positions(pos, tmp, mid, keys, descending);
    sort_positions(pos + mid, tmp, n - mid, keys, descending);
    size_t i = 0, j = mid, k = 0;
    while (i < mid && j < n) {
        int o = mo_order(keys[pos[j]], keys[pos[i]]);
        if (descending ? o > 0 : o < 0) tmp[k++] = pos[j++];
        else tmp[k++] = pos[i++];
    }
    while (i < mid) tmp[k++] = pos[i++];
    while (j < n) tmp[k++] = pos[j++];
    memcpy(pos, tmp, n * sizeof(uint32_t));
}

static MoValue sorted_by(MoValue xs, const MoValue *keys, bool descending) {
    uint32_t n = xs.aux;
    uint32_t *pos = xmalloc(n * sizeof(uint32_t));
    uint32_t *tmp = xmalloc(n * sizeof(uint32_t));
    for (uint32_t i = 0; i < n; i++) pos[i] = i;
    sort_positions(pos, tmp, n, keys, descending);
    MoValue *out = mo_alloc_values(n);
    for (uint32_t i = 0; i < n; i++) out[i] = xs.as.xs[pos[i]];
    free(pos);
    free(tmp);
    return mo_list(out, n);
}

MO_ROW(mo_r_List_sort) { (void)kind; return sorted_by(a[0], a[0].as.xs, false); }

static MoValue sorted_by_key(const MoValue *a, bool descending) {
    MoValue xs = a[0], f = a[1];
    MoValue *keys = mo_alloc_values(xs.aux);
    size_t from = mo_mark(), kept = 0;
    for (uint32_t i = 0; i < xs.aux; i++) {
        MoValue x = xs.as.xs[i];
        keys[i] = mo_invoke(f, &x);
        kept = iterate(from, keys, i + 1, kept);
    }
    return sorted_by(xs, keys, descending);
}

MO_ROW(mo_r_List_sort_by) { (void)kind; return sorted_by_key(a, false); }
MO_ROW(mo_r_List_sort_by_desc) { (void)kind; return sorted_by_key(a, true); }

/* The first of two that order level, as min and max give the first of a list's. */
MO_ROW(mo_r_min_of) { (void)kind; return mo_order(a[1], a[0]) < 0 ? a[1] : a[0]; }
MO_ROW(mo_r_max_of) { (void)kind; return mo_order(a[1], a[0]) > 0 ? a[1] : a[0]; }

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
        mo_disown_in(keys[i]);
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
    /* In a map, a value never holds a buffer alone. */
    mo_disown_in(next);
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
    /* Only UInt64.max squared passes an __int128. The builtin then leaves the low 128 bits in
     * exact, which are still wrapping's answer; the product is past every width. */
    bool past = op == MO_OP_ADD ? __builtin_add_overflow(x, y, &exact) : op == MO_OP_SUB ? __builtin_sub_overflow(x, y, &exact) : __builtin_mul_overflow(x, y, &exact);
    bool fits = !past && exact >= kind_min(k) && exact <= kind_max(k);
    switch (how) {
    case EDGE_CHECKED: return option_of(fits, mo_i128(exact));
    case EDGE_SATURATING:
        if (past) return mo_i128((x < 0) != (y < 0) ? kind_min(k) : kind_max(k));
        return mo_i128(exact < kind_min(k) ? kind_min(k) : exact > kind_max(k) ? kind_max(k) : exact);
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
MO_ROW(mo_r_Int_seconds) { (void)kind; return duration_of(a[0], 1000, "seconds"); }
MO_ROW(mo_r_Int_minute) { (void)kind; return duration_of(a[0], 60000, "minute"); }

/* Some(x) is Some of the function's value, None stays None (step 28; stdlib.zig, option_map). */
MO_ROW(mo_r_Option_map) {
    (void)kind;
    if (!mo_is(a[0], MO_N_SOME)) return a[0];
    MoValue x = a[0].as.xs[0];
    return mo_some(mo_invoke(a[1], &x));
}

/* `String.grouped(n)`: the integer with `_` between each three digits from the right (step 28;
 * stdlib.zig, groupedText). */
MO_ROW(mo_r_String_grouped) {
    (void)kind;
    __int128 n = mo_wide(a[0]);
    unsigned __int128 u = n < 0 ? (unsigned __int128)0 - (unsigned __int128)n : (unsigned __int128)n;
    char digits[48], out[72];
    size_t nd = 0, len = 0;
    do {
        digits[nd++] = (char)('0' + (int)(u % 10));
        u /= 10;
    } while (u > 0);
    if (n < 0) out[len++] = '-';
    for (size_t k = 0; k < nd; k++) {
        if (k > 0 && (nd - k) % 3 == 0) out[len++] = '_';
        out[len++] = digits[nd - 1 - k];
    }
    return heap_string(out, len);
}
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

/* MO_CLOCK: how far main's clock is from the wall's (server.zig, startClock). */
static int64_t clock_offset;

static int64_t wall_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_REALTIME, &ts);
    return (int64_t)ts.tv_sec * 1000 + ts.tv_nsec / 1000000 + clock_offset;
}

static int64_t awake_ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (int64_t)ts.tv_sec * 1000000000 + ts.tv_nsec;
}

/* Under main, the wall clock, frozen for the running update; in a test, the fixture's. */
static int64_t clock_now_ms(void);
MO_ROW(mo_r_Clock_now) { (void)a; (void)kind; return mo_time(clock_now_ms()); }
MO_ROW(mo_r_Clock_fixture) { (void)a; (void)kind; return mo_cap(MO_CAP_CLOCK, 0, 0); }

/* ---- the platform (server.zig) */

static int program_argc;
static char **program_argv;
static uint8_t exit_code;
/* main called exit: once it returns, the runtime's loops stop (sources.zig). */
static bool exited;

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
MO_ROW(mo_r_Platform_http) { (void)a; (void)kind; platform_only("Platform", "http"); return mo_cap(MO_CAP_HTTP, 0, 0); }

/* The last platform.exit(code) is the exit code when main returns. */
MO_ROW(mo_r_Platform_exit) {
    (void)kind;
    platform_only("Platform", "exit");
    exit_code = (uint8_t)a[1].as.u;
    exited = true;
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

/* The run's clock in a test (defined with the processes below); fixture waits move it. */
static int64_t sim_waited;

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

/* Whether `name`, taken from `folder` (or the root when it is absolute), climbs above `folder` at any
 * `..` (stdlib.zig, climbsOut). */
static bool climbs_out(const char *folder, const char *name, size_t n) {
    size_t base = 0;
    for (const char *p = folder; *p; p++) {
        if (*p != '/' && (p == folder || p[-1] == '/')) base++;
    }
    size_t depth = n > 0 && name[0] == '/' ? 0 : base;
    size_t i = 0;
    while (i < n) {
        while (i < n && name[i] == '/') i++;
        size_t start = i;
        while (i < n && name[i] != '/') i++;
        size_t seg = i - start;
        if (seg == 0 || (seg == 1 && name[start] == '.')) continue;
        if (seg == 2 && name[start] == '.' && name[start + 1] == '.') {
            if (depth <= base) return true;
            depth--;
        } else {
            depth++;
        }
    }
    return false;
}

/* The path a name in the scope is at, or NULL when it leaves the scope: a name that climbs above the
 * scope's folder leaves it, even above the fixture's root, as the real Fs refuses it (step 21). */
static char *fix_path_in(const FixScope *scope, const char *name, size_t n) {
    if (scope->system < 0 || scope->empty) return NULL;
    if (climbs_out(scope->folder, name, n)) return NULL;
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

enum { FS_READ, FS_READ_LINES, FS_READ_BYTES, FS_SIZE, FS_LIST, FS_LIST_KINDS, FS_FOLD_LINES, FS_WRITE, FS_APPEND, FS_REMOVE, FS_RENAME, FS_MKDIR };
static const char *const fs_row_names[] = {"read", "read_lines", "read_bytes", "size", "list", "list_kinds", "fold_lines", "write", "append", "remove", "rename", "mkdir"};

/* Names sorted byte by byte, each folder flag moving with its name. */
static void sort_listing(char **names, bool *folders, size_t n) {
    for (size_t i = 1; i < n; i++) {
        char *name = names[i];
        bool folder = folders[i];
        size_t j = i;
        for (; j > 0 && strcmp(names[j - 1], name) > 0; j--) {
            names[j] = names[j - 1];
            folders[j] = folders[j - 1];
        }
        names[j] = name;
        folders[j] = folder;
    }
}

/* An `Entry` of `Fs.list_kinds` (step 28; stdlib.zig, entryOf). */
static MoValue entry_of(const char *name, bool folder) {
    MoValue f[2] = {heap_string(name, strlen(name)), mo_variant(folder ? MO_N_FOLDER : MO_N_FILE, 0, NULL)};
    return mo_record(mo_entry_decl, 2, f);
}

static MoValue string_list(char **names, size_t n);

/* The names of a listing, sorted, as strings or, for list_kinds, as entries. */
static MoValue listed_of(char **names, bool *folders, size_t n, bool kinds) {
    if (!kinds) return string_list(names, n);
    MoValue *out = mo_alloc_values(n);
    for (size_t i = 0; i < n; i++) out[i] = entry_of(names[i], folders[i]);
    return mo_list(out, (uint32_t)n);
}

static MoValue not_text(void) { return error_of(mo_variant(MO_N_NOT_TEXT, 0, NULL)); }

/* What read, read_lines, and read_bytes give for a file's bytes: its text, its lines, or its
 * bytes; NotText for text or lines that are not UTF-8 (stdlib.zig, readResult). */
static MoValue read_result(int which, MoValue s) {
    if (which == FS_READ_BYTES) {
        MoValue *out = mo_alloc_values(s.aux);
        for (uint32_t i = 0; i < s.aux; i++) out[i] = mo_i64((unsigned char)s.as.s[i]);
        return ok_of(mo_list(out, s.aux));
    }
    if (!utf8_valid(s.as.s, s.aux)) return not_text();
    return ok_of(which == FS_READ ? s : lines_of(s));
}

/* Fs.fold_lines: bytes as they are read, split as String.lines splits a whole text, each line
 * handed to the function in turn with the value so far, so a file of any size is read in the
 * memory of its longest line and the value (stdlib.zig, LineFeed). */
typedef struct {
    MoValue f;
    size_t from, kept;
    Buf partial;
    /* The value so far, from its init, handed with each line and replaced by what the call gives,
     * the safe point's one root. */
    MoValue acc[1];
} LineFeed;

/* A line as fold_lines hands it on (step 27): its bytes when they are UTF-8, and otherwise each byte
 * that begins no UTF-8 character replaced by U+FFFD, so the caller counts the line and folds on
 * (stdlib.zig, replaced). */
static MoValue replaced_line(const char *s, size_t n) {
    if (utf8_valid(s, n)) return heap_string(s, n);
    Buf out = {0};
    for (size_t i = 0; i < n;) {
        CodePoint cp = code_point(s, n, i);
        if (cp.value == 0xFFFD && cp.len == 1) buf_put(&out, "\xEF\xBF\xBD", 3);
        else buf_put(&out, s + i, cp.len);
        i += cp.len;
    }
    MoValue line = heap_string(out.p, out.len);
    free(out.p);
    return line;
}

static void feed_line(LineFeed *l, const char *s, size_t n) {
    if (n > 0 && s[n - 1] == '\r') n--;
    MoValue line = replaced_line(s, n);
    MoValue args[2] = {l->acc[0], line};
    l->acc[0] = mo_invoke(l->f, args);
    l->kept = iterate(l->from, l->acc, 1, l->kept);
}

static void feed_bytes(LineFeed *l, const char *s, size_t n) {
    size_t start = 0;
    for (size_t i = 0; i < n; i++) {
        if (s[i] != '\n') continue;
        if (l->partial.len > 0) {
            buf_put(&l->partial, s + start, i - start);
            feed_line(l, l->partial.p, l->partial.len);
            l->partial.len = 0;
        } else {
            feed_line(l, s + start, i - start);
        }
        start = i + 1;
    }
    if (start < n) buf_put(&l->partial, s + start, n - start);
}

static void feed_end(LineFeed *l) {
    if (l->partial.len > 0) feed_line(l, l->partial.p, l->partial.len);
    free(l->partial.p);
}

static MoValue string_list(char **names, size_t n) {
    MoValue *out = mo_alloc_values(n);
    for (size_t i = 0; i < n; i++) out[i] = heap_string(names[i], strlen(names[i]));
    return mo_list(out, (uint32_t)n);
}

static MoValue fixture_files(int which, const MoValue *a) {
    FixScope scope = fix_scope_of(a[0]);
    bool lists = which == FS_LIST || which == FS_LIST_KINDS;
    int64_t within = lists ? a[1].as.i : which == FS_FOLD_LINES ? a[4].as.i : which == FS_RENAME || which == FS_WRITE || which == FS_APPEND ? a[3].as.i : a[2].as.i;
    MoValue path = lists ? mo_str(".", 1) : a[1];
    bool writes = which >= FS_WRITE;
    if (writes && scope.read_only) mo_fail(MO_R_OTHER, fs_row_names[which], "fs.%s(\"%.*s\") writes through an Fs narrowed to read_only, which only reads", fs_row_names[which], (int)path.aux, path.as.s);
    if (scope.delay > within) {
        /* Past its deadline the call waited the whole of it (step 22). */
        sim_waited += within > 0 ? within : 0;
        return timed_out();
    }
    /* A call that answers after the fixture's delay waited it: the clock moves (step 22). */
    if (scope.delay > 0) sim_waited += scope.delay;
    FixSystem *sys = scope.system >= 0 ? &fix_systems[scope.system] : NULL;
    if (lists) {
        if (!sys) return ok_of(mo_list(NULL, 0));
        /* A scope that climbed out of the one it narrowed holds nothing, as the real Fs's. */
        if (scope.empty) return missing(path);
        char *prefix = strcmp(scope.folder, "/") == 0 ? strdup("/") : path_join(scope.folder, "");
        size_t plen = strlen(prefix);
        char **names = xmalloc((sys->n ? sys->n : 1) * sizeof(char *));
        bool *folders = xmalloc((sys->n ? sys->n : 1) * sizeof(bool));
        size_t count = 0;
        /* A folder is there when a file is under it or mkdir made it; the root always is. */
        bool there = strcmp(scope.folder, "/") == 0;
        for (size_t i = 0; i < sys->n; i++) {
            const char *key = sys->files[i].path;
            if (strncmp(key, prefix, plen) != 0) continue;
            there = true;
            const char *rest = key + plen;
            const char *slash = strchr(rest, '/');
            size_t len = slash ? (size_t)(slash - rest) : strlen(rest);
            /* A folder's own mark (mkdir) under the listed folder names nothing. */
            if (len == 0) continue;
            bool seen = false;
            for (size_t k = 0; k < count; k++) {
                if (strlen(names[k]) != len || strncmp(names[k], rest, len) != 0) continue;
                seen = true;
                folders[k] = folders[k] || slash != NULL;
            }
            if (seen) continue;
            names[count] = xmalloc(len + 1);
            memcpy(names[count], rest, len);
            names[count][len] = 0;
            folders[count] = slash != NULL;
            count++;
        }
        free(prefix);
        /* As the real Fs answers a scope that is not a readable folder (step 22). */
        if (!there) {
            free(names);
            free(folders);
            return missing(path);
        }
        sort_listing(names, folders, count);
        MoValue listed = listed_of(names, folders, count, which == FS_LIST_KINDS);
        for (size_t k = 0; k < count; k++) free(names[k]);
        free(names);
        free(folders);
        return ok_of(listed);
    }
    if (!sys) return missing(path);
    char *full = fix_path_in(&scope, S(path));
    if (!full) return missing(path);
    switch (which) {
    case FS_FOLD_LINES: {
        FixFile *f = fix_find(sys, full);
        free(full);
        if (!f) return missing(path);
        MoValue text = f->text;
        LineFeed l = {.f = a[3], .from = mo_mark(), .acc = {a[2]}};
        feed_bytes(&l, text.as.s, text.aux);
        feed_end(&l);
        return ok_of(l.acc[0]);
    }
    case FS_READ:
    case FS_READ_LINES:
    case FS_READ_BYTES:
    case FS_SIZE: {
        FixFile *f = fix_find(sys, full);
        free(full);
        if (!f) return missing(path);
        if (which == FS_SIZE) return ok_of(mo_u64(f->text.aux));
        return read_result(which, f->text);
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
    case FS_MKDIR: {
        /* A folder is a mark, its path and a slash, so list shows it before a file is in it. */
        if (fix_find(sys, full)) {
            free(full);
            return missing(path);
        }
        char *mark = path_join(full, "");
        free(full);
        if (fix_find(sys, mark)) free(mark);
        else fix_put(sys, mark, mo_str("", 0));
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
    bool lists = which == FS_LIST || which == FS_LIST_KINDS;
    MoValue path = lists ? mo_str(".", 1) : a[1];
    int64_t within = lists ? a[1].as.i : which == FS_FOLD_LINES ? a[4].as.i : which == FS_RENAME || which == FS_WRITE || which == FS_APPEND ? a[3].as.i : a[2].as.i;
    if (which >= FS_WRITE && scope->read_only) {
        mo_fail(MO_R_OTHER, fs_row_names[which], "fs.%s(\"%.*s\") writes through an Fs narrowed to read_only, which only reads", fs_row_names[which], (int)path.aux, path.as.s);
    }
    int64_t t0 = awake_ns();
    switch (which) {
    case FS_READ:
    case FS_READ_LINES:
    case FS_READ_BYTES: {
        size_t len = 0;
        char *text = read_scoped(scope, S(path), &len);
        if (late(t0, within)) {
            free(text);
            return timed_out();
        }
        if (!text) return missing(path);
        MoValue s = heap_string(text, len);
        free(text);
        return read_result(which, s);
    }
    case FS_FOLD_LINES: {
        char *real = real_scoped(scope, S(path));
        int fd = real ? open(real, O_RDONLY) : -1;
        free(real);
        if (fd < 0) return late(t0, within) ? timed_out() : missing(path);
        /* The deadline is checked before each read; lines already handed stay handed. A line
         * longer than a whole read may be is Missing, as that file is to read. */
        enum { READING, DONE, LATE, FAILED } ended = READING;
        LineFeed l = {.f = a[3], .from = mo_mark(), .acc = {a[2]}};
        char chunk[1 << 16];
        while (ended == READING) {
            if (late(t0, within)) {
                ended = LATE;
                break;
            }
            ssize_t r = read(fd, chunk, sizeof chunk);
            if (r < 0 && errno == EINTR) continue;
            if (r < 0) ended = FAILED;
            else if (r == 0) ended = DONE;
            else feed_bytes(&l, chunk, (size_t)r);
            if (l.partial.len > READ_LIMIT) ended = FAILED;
        }
        close(fd);
        if (ended == DONE) feed_end(&l);
        else free(l.partial.p);
        return ended == DONE ? ok_of(l.acc[0]) : ended == LATE ? timed_out() : missing(path);
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
    case FS_LIST:
    case FS_LIST_KINDS: {
        char *real = real_scoped(scope, ".", 1);
        DIR *dir = real ? opendir(real) : NULL;
        char **names = NULL;
        bool *folders = NULL;
        size_t count = 0, cap = 0;
        if (dir) {
            struct dirent *e;
            while ((e = readdir(dir))) {
                if (strcmp(e->d_name, ".") == 0 || strcmp(e->d_name, "..") == 0) continue;
                if (count == cap) {
                    cap = cap ? 2 * cap : 16;
                    names = xrealloc(names, cap * sizeof(char *));
                    folders = xrealloc(folders, cap * sizeof(bool));
                }
                /* A link counts as what it points at (server.zig, listScoped). */
                struct stat st;
                char *full = path_join(real, e->d_name);
                folders[count] = stat(full, &st) == 0 && S_ISDIR(st.st_mode);
                free(full);
                names[count++] = strdup(e->d_name);
            }
            closedir(dir);
            sort_listing(names, folders, count);
        }
        free(real);
        MoValue result = late(t0, within) ? timed_out() : !dir ? missing(path) : ok_of(listed_of(names, folders, count, which == FS_LIST_KINDS));
        for (size_t k = 0; k < count; k++) free(names[k]);
        free(names);
        free(folders);
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
    case FS_MKDIR: {
        char *target = target_scoped(scope, S(path));
        struct stat st;
        bool made = target && (mkdir(target, 0777) == 0 || (errno == EEXIST && stat(target, &st) == 0 && S_ISDIR(st.st_mode)));
        free(target);
        if (late(t0, within)) return timed_out();
        if (!made) return missing(path);
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
MO_ROW(mo_r_Fs_read_bytes) { (void)kind; return files(FS_READ_BYTES, a); }
MO_ROW(mo_r_Fs_fold_lines) { (void)kind; return files(FS_FOLD_LINES, a); }
MO_ROW(mo_r_Fs_size) { (void)kind; return files(FS_SIZE, a); }
MO_ROW(mo_r_Fs_list) { (void)kind; return files(FS_LIST, a); }
MO_ROW(mo_r_Fs_list_kinds) { (void)kind; return files(FS_LIST_KINDS, a); }
MO_ROW(mo_r_Fs_write) { (void)kind; return files(FS_WRITE, a); }
MO_ROW(mo_r_Fs_append) { (void)kind; return files(FS_APPEND, a); }
MO_ROW(mo_r_Fs_remove) { (void)kind; return files(FS_REMOVE, a); }
MO_ROW(mo_r_Fs_rename) { (void)kind; return files(FS_RENAME, a); }
MO_ROW(mo_r_Fs_mkdir) { (void)kind; return files(FS_MKDIR, a); }

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

/* json.to_i64: the whole number a Number holds when it is below 2^53 either side of 0, so it reads
 * back as the text spelled it; None otherwise (json.zig, whole). */
MO_ROW(mo_r_Json_to_i64) {
    (void)kind;
    if (mo_vname(a[0]) != MO_N_NUMBER) return option_of(false, MO_NONE_V);
    double x = a[0].as.xs[0].as.f;
    bool some = x > -9007199254740992.0 && x < 9007199254740992.0 && trunc(x) == x;
    return option_of(some, some ? mo_i64((int64_t)x) : MO_NONE_V);
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

/* contracts.refined_base_candidates and refined_candidates. */
#define REFINED_BASE_CANDIDATES 100
#define REFINED_CANDIDATES 200

/* A generated integer from lo to hi: each edge a fifth of the time, else uniform. */
static __int128 between(__int128 lo, __int128 hi) {
    switch (rng_less_than(8, 5)) {
    case 0: return lo;
    case 1: return hi;
    default: {
        uint64_t span = (uint64_t)(hi - lo);
        return lo + (__int128)(span == UINT64_MAX ? rng_bits(64) : rng_less_than(64, span + 1));
    }
    }
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
        /* Only what the alias admits: the base type's candidates, then its bounds', then MO0325. */
        const MoDecl *d = &mo_decls[ty->a];
        for (uint32_t attempt = 0; attempt < REFINED_CANDIDATES; attempt++) {
            MoValue v = attempt >= REFINED_BASE_CANDIDATES && d->bounded ? mo_i128(between(d->lo, d->hi)) : generate(ty->b, depth);
            bool holds = true;
            for (uint32_t r = 0; r < d->nrefines && holds; r++) holds = d->refines[r](v).as.b;
            if (holds) return v;
        }
        mo_crash(d->none_admitted);
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
    /* What the run keeps is a second holder: a later write in place must not reach it. */
    mo_disown_in(v);
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

/* ==== processes: Mo.Sim's scheduler, and under main Mo.Server's turns (sim.zig, turns.zig) ==== */

/* A child line with no max_restarts: three restarts within five seconds. */
#define DEFAULT_MAX_RESTARTS 3
#define DEFAULT_WINDOW_MS 5000
/* Deliveries one settle makes in a test before the processes count as never settling. */
#define SETTLE_LIMIT 1000000
/* The test runner, or main, as a supervisor; no process as the one running. */
#define NOBODY UINT32_MAX
/* Under main, the messages a process's log keeps for a crash report: the last ones. */
#define LOG_KEPT 16
/* Region bytes a process may leave past twice what its last full compaction kept. */
#define FULL_BUDGET ((size_t)4 << 20)
/* The address space a process's region reserves, at most: many processes each reserve one, and a
 * region that fills allocates past itself (region_alloc). */
#define PROCESS_REGION ((size_t)1 << 30)
/* The most address space a process's heap grows to (settle_region). */
#define MAX_REGION ((size_t)16 << 30)
/* A fiber's stack: address space reserved whole, committed as it is touched. */
#define FIBER_STACK ((size_t)16 << 20)
#define FIBER_GUARD ((size_t)1 << 20)

/* A call a process's update waits in on a peer: a listener's next client or a connection's next
 * line, by handle, and the call as a report names it (sim.zig, Wait). */
typedef struct { bool listener; uint32_t handle; const char *call; } Wait;

/* A message in a mailbox or an outbox; under main it came in a parcel the mailbox, then the
 * log, owns. */
/* `deadline`, when `has_deadline`: an ask's, on the runtime's clock (deadline_now), which the update
 * that takes it sees as reply_by (sim.zig, Entry). */
typedef struct { MoValue message; uint64_t seq; Parcel *parcel; bool has_deadline; int64_t deadline; } Entry;
/* `delay`: a send with delay: (step 24), in milliseconds; 0 for a plain send. */
typedef struct { uint32_t to; MoValue message; Parcel *parcel; int64_t delay; } Outgoing;
typedef struct { uint8_t restart; uint32_t max_restarts; int64_t window_ms; } Policy;

typedef struct {
    uint32_t process;
    MoValue *args;
    uint32_t nargs;
    MoValue state;
    /* Index in `sups`, or NOBODY. */
    uint32_t supervisor;
    Policy policy;
    Entry *mailbox;
    size_t mailbox_len, mailbox_cap, head;
    /* Every message since the last (re)start; under main the last LOG_KEPT, in their parcels. */
    MoValue *log;
    size_t nlog, caplog;
    Parcel *log_parcels[LOG_KEPT];
    size_t nlog_parcels;
    /* Under main, the parcel its start arguments and first state live in for the run. */
    Parcel *start;
    int64_t *restarts;
    size_t nrestarts, caprestarts;
    bool up;
    /* Its update is on a stack. */
    bool busy;
    /* The running update's sends, delivered only when it commits. */
    Outgoing *outbox;
    size_t noutbox, capoutbox;
    /* Under main, the wall clock when its running update began: clock.now is frozen per update. */
    int64_t now;
    /* Under main, a sweep ended it: its id waits in free_ids. */
    bool ended;
    /* The running update's reply_by: its message's ask deadline, or when it was taken for a message
     * that came with none (step 22). */
    int64_t reply_by;
    /* Its update waits in an ask to this process, or NOBODY; or in a call on a peer. */
    uint32_t asking;
    bool has_wait;
    Wait wait;
    /* A wait elsewhere found that this update's ask can end only after a send it holds: the ask
     * crashes the update with `doom` when it returns. */
    bool doomed;
    Report doom;
    /* Restarts since it started, never trimmed to the window; the surface holds its deliveries;
     * the running update's time in calls that wait and the call it waited longest in (step 23). */
    uint64_t restarted;
    bool paused;
    uint64_t waited_us, longest_us;
    const char *longest;
    /* The call its update waits in now, for the surface; NULL or "" when none. */
    const char *waiting;
} Proc;

static Proc **procs;
static uint32_t nprocs, capprocs;
/* Each started supervisor's index in mo_supervisors. */
static uint32_t *sups;
static uint32_t nsups, capsups;
static uint32_t running = NOBODY;
static uint64_t next_seq;
/* A supervisor gave up: last_report says which, and the run stops. */
static bool gave_up;
/* The first process crash of a test, its report complete. */
static Report first_crash;
static bool crashed_once;
/* Milliseconds fixture calls have waited in a test: an ask in flight counts them. */
static int64_t sim_waited;
/* The seed a crash report names: the test runner's, or 0 under main. */
static uint64_t sim_seed;
static const char *test_name = "";
/* Under main with regions: a value that goes from one process to another goes packed. */
static bool packs;
/* Under main with processes: each process's updates run on a fiber of its own on main's thread. */
static bool turns_on;
/* Under main, the ids of processes a sweep ended, the last ended last: the next start takes the
 * last one (turns.zig, sweep). */
static uint32_t *free_ids;
static size_t nfree_ids, capfree_ids;
/* The fewest quiet events between two sweeps, the ended processes whose regions wait for the next
 * processes given their ids, and the idle fibers the pool keeps, at most. */
#define SWEEP_MIN 64
#define KEPT_WORKERS 64
#define KEPT_FIBERS 64
/* Under main, events after which a process a start call began may have finished: its start, and
 * each update of it that left its mailbox empty. A sweep runs at sweep_at. */
static uint32_t quiet;
static uint32_t sweep_at = SWEEP_MIN;

static MoValue turns_ask(uint32_t to, MoValue message, int64_t within);
static void turns_settle(void);
static bool turns_awaits(uint64_t seq);
static void turns_answer(uint64_t seq, bool has, MoValue reply, Parcel *parcel);
static void turns_wake_all(void);
static void turns_spawning(void);
static void close_held(const MoValue *args, uint32_t n);
static bool connection_of(uint32_t h, uint32_t *listener);
static bool unanswered_conn(uint32_t exchange, uint32_t *conn);
/* Sends held in every outbox: while none is, no wait looks for one. */
static size_t held;
/* The loops the runtime owns (sources.zig), below the Http rows. */
static bool sources_pump_fixture(void);
static void sources_pump_server(void);
static bool sources_active(void);
static void sources_mark(void);
/* Under main (turns): whether a source can do something now, the earliest time one must be looked
 * at again, and the poller reporting one's socket ready. */
struct Source;
static bool sources_has_work(void);
static bool sources_next_deadline(int64_t *at);
static void sources_fired(struct Source *s);
/* Under main, a message went into process `id`'s mailbox (turns). */
static void mark_runnable(uint32_t id);

static const char *handle_name(int64_t id) {
    return id >= 0 && id < (int64_t)nprocs ? mo_processes[procs[id]->process].name : NULL;
}

/* `clock.now`, frozen when the running update began: under main the wall clock, and in a test the
 * simulator's, Time.fixture() moved by every fixture wait and delayed send (sim.zig, clockNow). */
static int64_t clock_now_ms(void) {
    if (running != NOBODY) return procs[running]->now;
    return server_mode ? wall_ms() : FIXTURE_TIME + sim_waited;
}

static const char *name_of(uint32_t id) { return mo_processes[procs[id]->process].name; }
static size_t queued(const Proc *p) { return p->mailbox_len - p->head; }

/* ---- the events (events.zig, step 23): a bounded ring of what the processes did, read by the
 * runtime surface. MO_EVENTS=N keeps the last N, 4,096 by default, and 0 none. Each event's `at` is
 * the awake clock in microseconds under main, pinned to the wall clock when the run began, and in a
 * test the run's clock, which only fixture waits move. */

enum { EV_UPDATED, EV_STARTED, EV_ENDED, EV_RESTARTED, EV_CRASHED, EV_OVERFLOWED, EV_TIMED_OUT, EV_SOURCE_PAUSED, EV_SOURCE_RESUMED, EV_SENT, EV_PAUSED, EV_RESUMED };

typedef struct {
    uint8_t kind;
    int64_t at;
    uint32_t process, other;
    const char *process_name, *other_name, *name, *call;
    uint64_t took_us, waited_us, count, seed;
    const char *clause, *message, *state;
} Event;

static Event *ring;
/* The process mo run --surface starts to serve the surface, which the surface does not list and the
 * ring does not record: its index in mo_processes, or NOBODY (step 23). */
static uint32_t hidden_process = NOBODY;
static bool is_hidden(uint32_t id) { return hidden_process != NOBODY && procs[id]->process == hidden_process; }
static size_t ring_cap = 4096, ring_len, ring_head;
static uint64_t ring_total;
static int64_t ring_wall_ms, ring_mono_us;

static int64_t event_now(void) { return server_mode ? awake_ns() / 1000 : (FIXTURE_TIME + sim_waited) * 1000; }

static Event event_of(uint8_t kind, uint32_t process) {
    Event e;
    memset(&e, 0, sizeof e);
    e.kind = kind;
    e.process = process;
    e.other = NOBODY;
    e.process_name = e.other_name = e.name = e.call = e.clause = e.message = e.state = "";
    return e;
}

/* The whole ring is reserved at the first event, in pages the system gives as they are touched. */
static void record_event(Event e) {
    if (ring_cap == 0) return;
    if (e.process != NOBODY && e.process < nprocs && is_hidden(e.process)) return;
    if (!ring) {
        void *at = mmap(NULL, ring_cap * sizeof(Event), PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
        if (at == MAP_FAILED) return;
        ring = at;
    }
    e.at = event_now();
    if (e.process != NOBODY && !e.process_name[0]) e.process_name = name_of(e.process);
    if (e.other != NOBODY && !e.other_name[0]) e.other_name = name_of(e.other);
    if (ring_len < ring_cap) {
        ring[ring_len++] = e;
    } else {
        ring[ring_head] = e;
        ring_head = (ring_head + 1) % ring_cap;
    }
    ring_total++;
}

static bool is_timeout(MoValue v) { return mo_is(v, MO_N_ERROR) && mo_vcount(v) == 1 && mo_is(v.as.xs[0], MO_N_TIMEOUT); }

/* A call that waits, begun at `since` on the events' clock, gave `result`: its time counts toward the
 * running update's waits, and a Timeout is an event; `target` is an ask's (sim.zig, waitedIn). */
static void waited_in(const char *call, int64_t since, MoValue result, uint32_t target) {
    int64_t took = event_now() - since;
    if (took < 0) took = 0;
    if (running != NOBODY) {
        Proc *p = procs[running];
        p->waiting = "";
        p->waited_us += (uint64_t)took;
        if ((uint64_t)took >= p->longest_us) {
            p->longest_us = (uint64_t)took;
            p->longest = call;
        }
    }
    if (is_timeout(result)) {
        Event e = event_of(EV_TIMED_OUT, running);
        e.call = call;
        e.other = target;
        record_event(e);
    }
}

/* A call that waits begins: the events' clock now, and the call the running update waits in. */
static int64_t begin_wait(const char *call) {
    if (running != NOBODY) procs[running]->waiting = call;
    return event_now();
}

MoValue mo_wait_begin(const char *call) { return mo_time(begin_wait(call)); }

MoValue mo_waited(const char *call, MoValue since, MoValue result) {
    waited_in(call, since.as.i, result, NOBODY);
    return result;
}

static MoValue handle_value(uint32_t id) {
    MoValue v = {MO_HANDLE, 0, {0}};
    v.as.i = id;
    return v;
}

static MoValue ask_error(uint32_t name) { return error_of(mo_variant(name, 0, NULL)); }

/* Delayed sends not yet due (sim.zig, Later; step 24): a heap by due time, `order` keeping two due at
 * once in the order they were sent. */
typedef struct { int64_t at; uint64_t order; uint32_t from, to; MoValue message; Parcel *parcel; } Later;
static Later *later;
static size_t nlater, caplater;
static uint64_t later_sent;

/* A test starts with no process. */
static void reset_processes(void) {
    for (uint32_t i = 0; i < nprocs; i++) {
        Proc *p = procs[i];
        free(p->mailbox);
        free(p->log);
        free(p->restarts);
        free(p->outbox);
        free(p);
    }
    nprocs = nsups = 0;
    nfree_ids = 0;
    held = 0;
    running = NOBODY;
    next_seq = 0;
    gave_up = crashed_once = false;
    /* A test packs no parcel, so a delayed send left over holds nothing to free. */
    nlater = 0;
    later_sent = 0;
    sim_waited = 0;
    ring_len = ring_head = 0;
    ring_total = 0;
}

static char *text_of(const char *format, ...) __attribute__((format(printf, 1, 2)));
static char *text_of(const char *format, ...) {
    va_list ap;
    va_start(ap, format);
    int n = vsnprintf(NULL, 0, format, ap);
    va_end(ap);
    char *text = xmalloc((size_t)(n > 0 ? n : 0) + 1);
    va_start(ap, format);
    vsnprintf(text, (size_t)(n > 0 ? n : 0) + 1, format, ap);
    va_end(ap);
    return text;
}

/* ---- starting */

static int64_t window_of(const MoChild *c) { return c->per ? c->per(NULL, NULL).as.i : DEFAULT_WINDOW_MS; }

/* A state that cannot be built crashes whoever called start: the process never began. */
static uint32_t start_under(uint32_t process, uint32_t n, const MoValue *args, uint32_t supervisor, Policy policy) {
    MoValue *kept = dupe_values(args, n);
    MoValue state = mo_processes[process].init(NULL, kept);
    bool reused = nfree_ids > 0;
    uint32_t id = reused ? free_ids[--nfree_ids] : nprocs;
    Proc *p = reused ? procs[id] : calloc(1, sizeof(Proc));
    if (!p) out_of_memory();
    p->ended = false;
    p->asking = NOBODY;
    p->process = process;
    p->args = kept;
    p->nargs = n;
    p->state = state;
    p->supervisor = supervisor;
    p->policy = policy;
    p->up = true;
    if (packs) {
        /* Packed together, what the state shares with the arguments is copied once. */
        MoValue *both = mo_alloc_values(n + 1);
        if (n) memcpy(both, kept, n * sizeof(MoValue));
        both[n] = state;
        p->start = pack(mo_tuple_of(both, n + 1));
        p->args = p->start->value.as.xs;
        p->state = p->start->value.as.xs[n];
    }
    if (!reused) {
        GROW_ARRAY(procs, nprocs, capprocs);
        procs[nprocs++] = p;
    }
    if (turns_on && supervisor == NOBODY) quiet++;
    record_event(event_of(EV_STARTED, id));
    return id;
}

/* `Name.start(args)`: the test runner, or main, supervises it with :always, and with the
 * max_restarts of a child line that names the process. */
MoValue mo_spawn(uint32_t process, uint32_t n, const MoValue *args) {
    /* Under main, main starting processes faster than a statement settles them hands out their
     * turns first, so the ones that finished end. */
    if (turns_on) turns_spawning();
    Policy policy = {MO_RESTART_ALWAYS, DEFAULT_MAX_RESTARTS, DEFAULT_WINDOW_MS};
    for (uint32_t s = 0; s < mo_nsupervisors; s++) {
        const MoSupervisor *sup = &mo_supervisors[s];
        for (uint32_t k = 0; k < sup->nchildren; k++) {
            const MoChild *c = &sup->children[k];
            if (c->process == process && c->max_restarts != UINT32_MAX) {
                policy = (Policy){MO_RESTART_ALWAYS, c->max_restarts, window_of(c)};
                break;
            }
        }
    }
    return handle_value(start_under(process, n, args, NOBODY, policy));
}

/* Each child in order, with the arguments its line passes. */
MoValue mo_start_supervisor(uint32_t supervisor, uint32_t n, const MoValue *args) {
    (void)n;
    const MoSupervisor *s = &mo_supervisors[supervisor];
    uint32_t sid = nsups;
    GROW_ARRAY(sups, nsups, capsups);
    sups[nsups++] = supervisor;
    MoValue *ids = mo_alloc_values(s->nchildren);
    for (uint32_t k = 0; k < s->nchildren; k++) {
        const MoChild *c = &s->children[k];
        MoValue child = c->args(NULL, args);
        uint32_t max = c->max_restarts == UINT32_MAX ? DEFAULT_MAX_RESTARTS : c->max_restarts;
        Policy policy = {c->restart, max, window_of(c)};
        ids[k] = handle_value(start_under(c->process, child.aux, child.as.xs, sid, policy));
    }
    if (s->nchildren == 0) return MO_NONE_V;
    if (s->nchildren == 1) return ids[0];
    return mo_tuple_of(ids, s->nchildren);
}

/* ---- messages */

static uint64_t enqueue(uint32_t to, MoValue message, Parcel *parcel) {
    uint64_t seq = next_seq++;
    Proc *p = procs[to];
    GROW_ARRAY(p->mailbox, p->mailbox_len, p->mailbox_cap);
    p->mailbox[p->mailbox_len++] = (Entry){message, seq, parcel, false, 0};
    if (turns_on) mark_runnable(to);
    return seq;
}

/* A mailbox at its bound crashes the sender, and the report names both (d33). */
static void room_for(uint32_t to, MoValue message) {
    Proc *target = procs[to];
    size_t waiting = queued(target);
    if (running != NOBODY) {
        Proc *from = procs[running];
        for (size_t i = 0; i < from->noutbox; i++) waiting += from->outbox[i].to == to && from->outbox[i].delay == 0;
    }
    uint32_t bound = mo_processes[target->process].mailbox;
    if (waiting < bound) return;
    const char *from = running != NOBODY ? name_of(running) : server_mode ? "main" : text_of("the test \"%s\"", test_name);
    Event overflow = event_of(EV_OVERFLOWED, to);
    overflow.other = running;
    record_event(overflow);
    Involved *values = xmalloc(sizeof(Involved));
    values[0] = (Involved){"message", render(message)};
    Report r = {MO_R_MAILBOX, text_of("%s sent to %s, whose mailbox is full at its bound of %u", from, name_of(to), bound), from, NULL, values, 1, NULL, 0, NULL, 0, NULL};
    raise_report(r, JUMP_CRASH);
}

/* `h.send(message)`: never blocks. From inside an update the message waits in the sender's
 * outbox until the update commits. A target that is down drops it. */
MoValue mo_send(MoValue handle, MoValue message) {
    uint32_t to = (uint32_t)handle.as.i;
    if (!procs[to]->up) return MO_NONE_V;
    room_for(to, message);
    Parcel *parcel = packs ? pack(message) : NULL;
    MoValue sent = parcel ? parcel->value : message;
    if (running != NOBODY) {
        Proc *from = procs[running];
        GROW_ARRAY(from->outbox, from->noutbox, from->capoutbox);
        from->outbox[from->noutbox++] = (Outgoing){to, sent, parcel};
        held++;
    } else {
        enqueue(to, sent, parcel);
    }
    return MO_NONE_V;
}

/* The slowest fixture the process was started with. */
static int64_t delay_of(uint32_t id) {
    int64_t delay = 0;
    const Proc *p = procs[id];
    for (uint32_t i = 0; i < p->nargs; i++) {
        if (p->args[i].tag == MO_CAP && p->args[i].as.i > delay) delay = p->args[i].as.i;
    }
    return delay;
}

typedef struct { uint64_t seq; bool has_reply; MoValue reply; } Delivered;
static Delivered deliver(uint32_t id);

/* ---- held sends (sim.zig, step 19) */

/* A send an update holds (`holder`'s outbox) to `to`, which a wait can hear from only after it. */
typedef struct { bool found; uint32_t holder, to; MoValue message; } Held;

/* Process `to` was started with a connection a wait on `w` hears from only through it: one still
 * open that the listener `w` names accepted, or the connection `w` names. An exchange counts while
 * it is unanswered. */
static bool ties(uint32_t to, const Wait *w) {
    const Proc *p = procs[to];
    for (uint32_t i = 0; i < p->nargs; i++) {
        MoValue a = p->args[i];
        if (a.tag != MO_CAP) continue;
        uint32_t kind = mo_cap_kind(a), conn = mo_cap_handle(a), from = 0;
        if (kind == MO_CAP_EXCHANGE) {
            if (!unanswered_conn(conn, &conn)) continue;
        } else if (kind != MO_CAP_CONN) {
            continue;
        }
        bool open = connection_of(conn, &from);
        if (open && (w->listener ? from == w->handle : conn == w->handle)) return true;
    }
    return false;
}

/* The first send, of `waiter`'s update and then of each update waiting on it through asks, to a
 * process started with a connection a wait on `w` hears from only through it. */
static Held held_for(uint32_t waiter, const Wait *w) {
    Held h = {false, 0, 0, MO_NONE_V};
    uint32_t *queue = NULL;
    size_t n = 0, cap = 0;
    GROW_ARRAY(queue, n, cap);
    queue[n++] = waiter;
    for (size_t i = 0; i < n && !h.found; i++) {
        const Proc *x = procs[queue[i]];
        for (size_t k = 0; k < x->noutbox; k++) {
            if (!ties(x->outbox[k].to, w)) continue;
            h = (Held){true, queue[i], x->outbox[k].to, x->outbox[k].message};
            break;
        }
        if (h.found) break;
        for (uint32_t id = 0; id < nprocs; id++) {
            const Proc *p = procs[id];
            if (!p->busy || p->asking != queue[i]) continue;
            bool seen = false;
            for (size_t j = 0; j < n; j++) seen = seen || queue[j] == id;
            if (seen) continue;
            GROW_ARRAY(queue, n, cap);
            queue[n++] = id;
        }
    }
    free(queue);
    return h;
}

static Report held_report(Held h, uint32_t waiter, const Wait *w) {
    const char *holder = name_of(h.holder), *target = name_of(h.to);
    const char *call = h.holder == waiter ? w->call : text_of("ask, and %s waits in %s,", name_of(waiter), w->call);
    const char *with = w->listener ? "a connection from that listener that it cannot answer until then" : "that connection, which it cannot write to until then";
    Involved *values = xmalloc(sizeof(Involved));
    values[0] = (Involved){"message", render(h.message)};
    Report r = {MO_R_HELD, text_of("%s waits in %s while it holds a send to %s #%u, and sends are held until its update ends: %s #%u was started with %s", holder, call, target, h.to, target, h.to, with), holder, NULL, values, 1, NULL, 0, NULL, 0, NULL};
    return r;
}

/* `holder`'s update waits in an ask: the ask crashes it when it returns, and under main at once. */
static void doom(uint32_t holder, Report r) {
    Proc *p = procs[holder];
    if (!p->doomed) {
        p->doomed = true;
        p->doom = r;
    }
    if (turns_on) turns_wake_all();
}

/* The running update is about to wait in `w.call` on a peer (sim.zig, waitOn). */
static void wait_on(Wait w) {
    if (running == NOBODY) return;
    uint32_t me = running;
    procs[me]->wait = w;
    procs[me]->has_wait = true;
    if (held == 0) return;
    Held h = held_for(me, &w);
    if (!h.found) return;
    Report r = held_report(h, me, &w);
    if (h.holder != me) {
        doom(h.holder, r);
        return;
    }
    procs[me]->has_wait = false;
    raise_report(r, JUMP_CRASH);
}

static void end_wait(void) {
    if (running != NOBODY) procs[running]->has_wait = false;
}

/* The running update is about to wait in an ask to `to` (sim.zig, askOn). */
static void ask_on(uint32_t to) {
    if (running == NOBODY) return;
    uint32_t me = running;
    procs[me]->asking = to;
    if (held == 0) return;
    uint32_t x = to;
    const Wait *w = NULL;
    for (uint32_t steps = 0; steps < nprocs && !w; steps++) {
        const Proc *q = procs[x];
        if (!q->busy) return;
        if (q->has_wait) {
            w = &q->wait;
        } else {
            if (q->asking == NOBODY) return;
            x = q->asking;
        }
    }
    if (!w) return;
    Held h = held_for(x, w);
    /* The waiter's own send was found when its wait began. */
    if (!h.found || h.holder == x) return;
    Report r = held_report(h, x, w);
    if (h.holder != me) {
        doom(h.holder, r);
        return;
    }
    procs[me]->asking = NOBODY;
    raise_report(r, JUMP_CRASH);
}

static void end_ask(void) {
    if (running != NOBODY) procs[running]->asking = NOBODY;
}

static void check_doomed(void) {
    if (running == NOBODY || !procs[running]->doomed) return;
    Proc *p = procs[running];
    p->doomed = false;
    raise_report(p->doom, JUMP_CRASH);
}

static MoValue ask_inline(uint32_t to, MoValue message, MoValue within);
static int64_t now_ms(void);
static bool due_later(void);
static void others_round(uint32_t skip, uint32_t *delivered);

/* The clock deadlines are points on (step 22): under main the runtime's monotonic clock, and in a
 * test the run's, which only fixture waits move (sim.zig, deadlineNow). */
static int64_t deadline_now(void) { return turns_on ? now_ms() : sim_waited; }

/* reply_by in the running update. */
MoValue mo_reply_by(void) { return mo_time(running != NOBODY ? procs[running]->reply_by : deadline_now()); }

/* A Deadline given to within:: the Duration that remains of it, or -1 ms when nothing does. */
MoValue mo_deadline_left(MoValue deadline) {
    int64_t left = deadline.as.i - deadline_now();
    return mo_duration(left > 0 ? left : -1);
}

/* A call whose deadline has nothing left: Timeout at once, and the call is not made (step 22). */
MoValue mo_timed_out_now(void) { return error_of(mo_variant(MO_N_TIMEOUT, 0, NULL)); }

/* Deadline.fixture(d): a test has no asker, so a deadline d from now on the run's clock. */
MO_ROW(mo_r_Deadline_fixture) { (void)kind; return mo_time(deadline_now() + a[0].as.i); }

/* deadline.remaining: what remains of it on the runtime's clock, zero once it has passed (step 24). */
MO_ROW(mo_r_Deadline_remaining) {
    (void)kind;
    int64_t left = a[0].as.i - deadline_now();
    return mo_duration(left > 0 ? left : 0);
}

/* deadline.at_most(d): the earlier of the deadline and now plus d. */
MO_ROW(mo_r_Deadline_at_most) {
    (void)kind;
    int64_t later = deadline_now() + a[1].as.i;
    return mo_time(a[0].as.i < later ? a[0].as.i : later);
}

/* `h.ask(message, within: d)`: the target's waiting messages run, then this one, and the
 * reply is the value of its arm. Timeout when the target's fixtures are slower than d, or its
 * fixture calls waited longer than d while it answered; Down when the target is down or
 * crashed before replying. A Timeout's message still arrives. */
MoValue mo_ask(MoValue handle, MoValue message, MoValue within) {
    /* Nothing remains of the deadline: Timeout at once, and nothing is sent (step 22). */
    if (within.as.i < 0) return ask_error(MO_N_TIMEOUT);
    uint32_t to = (uint32_t)handle.as.i;
    ask_on(to);
    int64_t since = begin_wait("ask");
    MoValue reply = turns_on ? turns_ask(to, message, within.as.i) : ask_inline(to, message, within);
    waited_in("ask", since, reply, to);
    end_ask();
    check_doomed();
    return reply;
}

static MoValue ask_inline(uint32_t to, MoValue message, MoValue within) {
    if (!procs[to]->up) return ask_error(MO_N_DOWN);
    /* A target whose update is on the stack is waiting on this very call. */
    if (procs[to]->busy) return ask_error(MO_N_TIMEOUT);
    int64_t waited = sim_waited;
    /* Delayed sends whose time has come are in their mailboxes before this message (step 24). */
    due_later();
    room_for(to, message);
    uint64_t seq = enqueue(to, message, NULL);
    Proc *target = procs[to];
    target->mailbox[target->mailbox_len - 1].has_deadline = true;
    target->mailbox[target->mailbox_len - 1].deadline = waited + within.as.i;
    /* The surface holds its deliveries (step 23): the message waits, and the ask is Timeout. */
    if (target->paused) return ask_error(MO_N_TIMEOUT);
    MoValue reply;
    uint32_t delivered = 0;
    for (;;) {
        /* While a test's ask waits, every other process takes a message too, a round at a time in
         * start order, so a test polling one process starves none (sim.zig, othersRound; step 24).
         * An update's ask delivers only its target's. */
        if (running == NOBODY) others_round(to, &delivered);
        Proc *p = procs[to];
        /* A restart empties the mailbox, this message with it. */
        if (!p->up || queued(p) == 0 || p->mailbox[p->head].seq > seq) return ask_error(MO_N_DOWN);
        Delivered d = deliver(to);
        if (d.seq == seq) {
            if (!d.has_reply) return ask_error(MO_N_DOWN);
            reply = d.reply;
            break;
        }
    }
    /* A fixture call's wait moves the clock (step 22): the ask is Timeout once the target's waits
     * pass its deadline, or when its slowest fixture is slower than it. A target whose calls wait on
     * reply_by never passes it, since none of them waits longer than what remains. */
    if (delay_of(to) > within.as.i || sim_waited - waited > within.as.i) return ask_error(MO_N_TIMEOUT);
    return ok_of(reply);
}

/* ---- delayed sends (sim.zig, Later; step 24) */


static bool later_sooner(const Later *a, const Later *b) { return a->at < b->at || (a->at == b->at && a->order < b->order); }

static void later_swap(size_t a, size_t b) {
    Later t = later[a];
    later[a] = later[b];
    later[b] = t;
}

static void push_later(uint32_t from, uint32_t to, MoValue message, Parcel *parcel, int64_t at) {
    GROW_ARRAY(later, nlater, caplater);
    size_t i = nlater++;
    later[i] = (Later){at, later_sent++, from, to, message, parcel};
    while (i > 0 && later_sooner(&later[i], &later[(i - 1) / 2])) {
        later_swap(i, (i - 1) / 2);
        i = (i - 1) / 2;
    }
}

static Later pop_later(void) {
    Later first = later[0];
    later[0] = later[--nlater];
    size_t i = 0;
    for (;;) {
        size_t l = 2 * i + 1, r = l + 1, least = i;
        if (l < nlater && later_sooner(&later[l], &later[least])) least = l;
        if (r < nlater && later_sooner(&later[r], &later[least])) least = r;
        if (least == i) break;
        later_swap(i, least);
        i = least;
    }
    return first;
}

/* Every delayed send whose time has come goes in its target's mailbox, in the order they were due;
 * one to a target that is down, or whose mailbox is full, is dropped, and a full mailbox is an
 * Overflowed event naming the sender (sim.zig, dueLater). True when one went in. */
static bool due_later(void) {
    bool moved = false;
    while (nlater > 0 && later[0].at <= deadline_now()) {
        Later l = pop_later();
        Proc *target = procs[l.to];
        if (!target->up || target->ended) {
            parcel_free(l.parcel);
            continue;
        }
        if (queued(target) >= mo_processes[target->process].mailbox) {
            Event overflow = event_of(EV_OVERFLOWED, l.to);
            overflow.other = l.from;
            record_event(overflow);
            parcel_free(l.parcel);
            continue;
        }
        enqueue(l.to, l.message, l.parcel);
        moved = true;
    }
    return moved;
}

/* `h.send(message, delay: d)` (step 24): in `to`'s mailbox no earlier than `d` after the sending
 * update ends; from a test or main, `d` after now. A crash drops it with the update's other sends. */
MoValue mo_send_later(MoValue handle, MoValue message, MoValue delay) {
    if (delay.as.i <= 0) return mo_send(handle, message);
    uint32_t to = (uint32_t)handle.as.i;
    if (!procs[to]->up) return MO_NONE_V;
    Parcel *parcel = packs ? pack(message) : NULL;
    MoValue sent = parcel ? parcel->value : message;
    if (running != NOBODY) {
        Proc *from = procs[running];
        GROW_ARRAY(from->outbox, from->noutbox, from->capoutbox);
        from->outbox[from->noutbox++] = (Outgoing){to, sent, parcel, delay.as.i};
        held++;
    } else {
        push_later(NOBODY, to, sent, parcel, deadline_now() + delay.as.i);
    }
    return MO_NONE_V;
}

/* One message to each waiting process that is up and not on a stack, in start order; true when
 * one was delivered. A process an update starts waits for the next round. `delivered` counts the
 * messages across a settle's rounds, or a fixture call's (Http.fixture()'s send), up to
 * SETTLE_LIMIT. */
static bool deliver_round(uint32_t *delivered) {
    /* What the runtime's loops took goes in first (sources.zig); under main, step does it. */
    bool progressed = !server_mode && sources_pump_fixture();
    /* Delayed sends whose time has come go in next (step 24). */
    if (!turns_on && due_later()) progressed = true;
    uint32_t n = nprocs;
    for (uint32_t id = 0; id < n; id++) {
        Proc *p = procs[id];
        if (!p->up || p->busy || p->paused || queued(p) == 0) continue;
        deliver(id);
        progressed = true;
        if (++*delivered == SETTLE_LIMIT && !server_mode) {
            mo_fail(MO_R_OTHER, test_name, "the processes did not settle: a million messages delivered and mailboxes still waiting");
        }
    }
    return progressed;
}

/* One message to each waiting process but `skip` that is up and not on a stack, in start order,
 * after the delayed sends now due: the round a test's ask gives the other processes before its
 * target's next message (sim.zig, othersRound; step 24). The runtime's loops are not pumped here. */
static void others_round(uint32_t skip, uint32_t *delivered) {
    due_later();
    uint32_t n = nprocs;
    for (uint32_t id = 0; id < n; id++) {
        Proc *p = procs[id];
        if (id == skip || !p->up || p->busy || p->paused || queued(p) == 0) continue;
        deliver(id);
        if (++*delivered == SETTLE_LIMIT) {
            mo_fail(MO_R_OTHER, test_name, "the processes did not settle while an ask waited: a million messages delivered and mailboxes still waiting");
        }
    }
}

/* Delivers waiting messages a round at a time until every mailbox is empty. */
static void drain(void) {
    uint32_t delivered = 0;
    for (;;) {
        while (deliver_round(&delivered)) {}
        /* Nothing waits: simulated time passes to the next delayed send (step 24). */
        if (turns_on || nlater == 0) return;
        if (later[0].at > sim_waited) sim_waited = later[0].at;
    }
}

void mo_settle(void) {
    if (turns_on) turns_settle();
    else drain();
}

/* ---- one message */

static void log_message(Proc *p, Entry e) {
    if (e.parcel) {
        if (p->nlog_parcels == LOG_KEPT) {
            parcel_free(p->log_parcels[0]);
            memmove(p->log_parcels, p->log_parcels + 1, (LOG_KEPT - 1) * sizeof(Parcel *));
            p->nlog_parcels--;
            memmove(p->log, p->log + 1, (p->nlog - 1) * sizeof(MoValue));
            p->nlog--;
        }
        p->log_parcels[p->nlog_parcels++] = e.parcel;
    }
    GROW_ARRAY(p->log, p->nlog, p->caplog);
    p->log[p->nlog++] = e.message;
}

/* One update, then every invariant against the state before it. Gives (reply, state). */
static MoValue update(uint32_t id, MoValue message, MoValue before) {
    const Proc *p = procs[id];
    const MoProcess *def = &mo_processes[p->process];
    uint32_t n = p->nargs;
    MoValue *args = mo_alloc_values(n + 2);
    if (n) memcpy(args, p->args, n * sizeof(MoValue));
    args[n] = before;
    args[n + 1] = message;
    MoValue out = def->update(NULL, args);
    args[n] = out.as.xs[1];
    args[n + 1] = before;
    for (uint32_t k = 0; k < def->ninvariants; k++) {
        if (def->invariants[k].fn(NULL, args).as.b) continue;
        static const char *const state_name[] = {"state"};
        mo_crash_values(def->invariants[k].clause, 1, state_name, &out.as.xs[1]);
    }
    return out;
}

/* The update, with its crash caught: 0 when it committed, else how it jumped. */
static int run_update(uint32_t id, MoValue message, MoValue before, MoValue *out) {
    jmp_buf here;
    jmp_buf *saved = crash_jump;
    uint32_t depth = mo_depth;
    MoHandleFrame *frames = mo_handle_frames;
    crash_jump = &here;
    int jumped = setjmp(here);
    if (jumped == 0) {
        *out = update(id, message, before);
    } else {
        mo_depth = depth;
        mo_handle_frames = frames;
    }
    crash_jump = saved;
    return jumped;
}

static void rollback(void) {
    while (nundos > 0) {
        Undo u = undos[--nundos];
        if (u.stride == 0) {
            *(MoValue *)u.slot = u.old;
            continue;
        }
        size_t k = (u.slot - (uintptr_t)u.entries) / sizeof(MoValue);
        memmove(&u.entries[k + u.stride], &u.entries[k], (u.len - u.stride - k) * sizeof(MoValue));
        u.entries[k] = u.old;
        if (u.stride == 2) u.entries[k + 1] = u.second;
        if (u.index_len > 0) rebuild_index(u.index, u.index_len, u.entries, u.len, u.stride);
    }
}

/* After an update under main: what it allocated that the new state does not reach is freed,
 * message, reply, and outgoing messages included, since those left packed. Once the region
 * holds more than twice what its last full compaction kept, it is compacted whole. */
static void settle_region(uint32_t id, size_t mark) {
    MoValue roots[1] = {procs[id]->state};
    if (mo_heap.top > mark) mo_compact(mark, roots, 1);
    if (mo_heap.top - mo_heap.base > 2 * full_kept + FULL_BUDGET) {
        mo_compact(mo_heap.base, roots, 1);
        full_kept = mo_heap.top - mo_heap.base;
        /* A process's heap keeps what its state reaches in a quarter of its reservation at most;
         * past that it moves into one four times as large. main's never moves. */
        size_t reserved = mo_heap.end - mo_heap.base;
        if (turns_on && 4 * full_kept > reserved) {
            relocate_heap(4 * reserved < MAX_REGION ? 4 * reserved : MAX_REGION, roots, 1);
            full_kept = mo_heap.top - mo_heap.base;
        }
    }
    procs[id]->state = roots[0];
}

static void process_crashed(const Report *r) {
    Buf b = {0};
    buf_str(&b, "process crashed: ");
    report_text(&b, r);
    buf_byte(&b, '\n');
    stream_write(&err_stream, b.p, b.len);
    free(b.p);
}

/* The child crashed more than max_restarts times within the window: its supervisor crashes,
 * every child of that supervisor goes down, and the run stops. */
_Noreturn static void give_up(uint32_t id, Report last) {
    const Proc *p = procs[id];
    const char *sup = p->supervisor == NOBODY ? (server_mode ? "main" : "the test runner") : mo_supervisors[sups[p->supervisor]].name;
    for (uint32_t i = 0; i < nprocs; i++) {
        Proc *q = procs[i];
        if (q->supervisor != p->supervisor) continue;
        q->up = false;
        close_held(q->args, q->nargs);
    }
    gave_up = true;
    Involved *values = xmalloc(sizeof(Involved));
    values[0] = (Involved){"last crash", (char *)last.clause};
    Report r = {MO_R_SUPERVISOR, text_of("%s gave up: %s crashed more than %u times within %lld.ms", sup, name_of(id), p->policy.max_restarts, (long long)p->policy.window_ms), sup, last.where, values, 1, last.process, last.seed, last.log, last.nlog, last.state};
    raise_report(r, JUMP_CRASH);
}

static bool run_init(uint32_t process, const MoValue *args, MoValue *out) {
    jmp_buf here;
    jmp_buf *saved = crash_jump;
    uint32_t depth = mo_depth;
    MoHandleFrame *frames = mo_handle_frames;
    crash_jump = &here;
    int jumped = setjmp(here);
    if (jumped == 0) {
        *out = mo_processes[process].init(NULL, args);
    } else {
        mo_depth = depth;
        mo_handle_frames = frames;
    }
    crash_jump = saved;
    if (jumped != 0 && jumped != JUMP_CRASH) raise_report(last_report, jumped);
    return jumped == 0;
}

/* Keeps the crash with its complete report, then does what the child line says. :always and
 * :on_crash restart alike: an update never ends a process but by crashing. */
static void crashed(uint32_t id, MoValue before) {
    Report report = last_report;
    Proc *p = procs[id];
    report.process = name_of(id);
    report.seed = sim_seed;
    report.log = xmalloc((p->nlog ? p->nlog : 1) * sizeof(char *));
    report.nlog = (uint32_t)p->nlog;
    for (size_t i = 0; i < p->nlog; i++) report.log[i] = render(p->log[i]);
    report.state = render(before);
    if (!crashed_once) {
        first_crash = report;
        crashed_once = true;
    }
    Event crash = event_of(EV_CRASHED, id);
    crash.seed = report.seed;
    crash.clause = report.clause;
    crash.message = report.nlog > 0 ? report.log[report.nlog - 1] : "";
    crash.state = report.state;
    record_event(crash);
    if (server_mode) process_crashed(&report);
    /* A connection closes when the process holding it stops, restarted or not. */
    close_held(p->args, p->nargs);
    if (turns_on) turns_wake_all();
    if (p->policy.restart == MO_RESTART_NEVER) {
        p->up = false;
        return;
    }
    /* Restarts are counted in simulated time under a test, and wall-clock time under main. */
    int64_t at = server_mode ? wall_ms() : FIXTURE_TIME;
    size_t kept = 0;
    for (size_t i = 0; i < p->nrestarts; i++) {
        if (p->restarts[i] > at - p->policy.window_ms) p->restarts[kept++] = p->restarts[i];
    }
    p->nrestarts = kept;
    if (kept >= p->policy.max_restarts) give_up(id, report);
    GROW_ARRAY(p->restarts, p->nrestarts, p->caprestarts);
    p->restarts[p->nrestarts++] = at;
    p->restarted++;
    /* An ask whose message the restart drops is Down. */
    if (turns_on) {
        for (size_t i = p->head; i < p->mailbox_len; i++) turns_answer(p->mailbox[i].seq, false, MO_NONE_V, NULL);
    }
    for (size_t i = p->head; i < p->mailbox_len; i++) parcel_free(p->mailbox[i].parcel);
    p->mailbox_len = p->head = 0;
    p->nlog = 0;
    for (size_t i = 0; i < p->nlog_parcels; i++) parcel_free(p->log_parcels[i]);
    p->nlog_parcels = 0;
    MoValue state;
    if (!run_init(p->process, p->args, &state)) give_up(id, last_report);
    procs[id]->state = state;
    Event restart = event_of(EV_RESTARTED, id);
    restart.count = procs[id]->restarted;
    record_event(restart);
}

/* Runs the next message in the mailbox of `id` as one transaction. No reply: it crashed. */
static Delivered deliver(uint32_t id) {
    Proc *p = procs[id];
    Entry entry = p->mailbox[p->head];
    p->head++;
    if (p->head == p->mailbox_len) {
        p->mailbox_len = p->head = 0;
    } else if (p->head >= 64 && 2 * p->head >= p->mailbox_len) {
        /* A mailbox that never empties does not grow: what was taken is dropped. */
        size_t waiting = p->mailbox_len - p->head;
        memmove(p->mailbox, p->mailbox + p->head, waiting * sizeof(Entry));
        p->mailbox_len = waiting;
        p->head = 0;
    }
    log_message(p, entry);
    p->now = server_mode ? wall_ms() : FIXTURE_TIME + sim_waited;
    p->reply_by = entry.has_deadline ? entry.deadline : deadline_now();
    int64_t since = event_now();
    p->waited_us = p->longest_us = 0;
    p->longest = "";
    MoValue before = p->state;
    /* Under main, everything the update allocates is past this mark, the message copied out of
     * its parcel first. What it overwrites older than the mark is undone on a crash, and not
     * overwritten at all when an invariant reads old(state). */
    size_t mark = mo_mark();
    bool regioned = mo_compacts && mo_heap.end != 0;
    MoValue message = entry.parcel ? unpack(entry.parcel) : entry.message;
    if (regioned) {
        undo_mark = mark;
        frozen_below = mo_processes[p->process].reads_old ? mark : 0;
    } else {
        /* Without compaction nothing tells an older buffer from a newer one: every write is kept for
         * a crash, and an invariant that reads old(state) sees nothing written in place. */
        undo_mark = UINTPTR_MAX;
        frozen_below = mo_processes[p->process].reads_old ? UINTPTR_MAX : 0;
    }
    uint32_t outer = running;
    running = id;
    p->busy = true;
    MoValue after = MO_NONE_V;
    int jumped = run_update(id, message, before, &after);
    p = procs[id];
    p->busy = false;
    running = outer;
    if (jumped != 0) {
        undo_mark = frozen_below = 0;
        if (jumped != JUMP_CRASH) raise_report(last_report, jumped);
        rollback();
        for (size_t i = 0; i < p->noutbox; i++) parcel_free(p->outbox[i].parcel);
        held -= p->noutbox;
        p->noutbox = 0;
        p->has_wait = p->doomed = false;
        p->asking = NOBODY;
        if (gave_up) raise_report(last_report, JUMP_CRASH);
        crashed(id, before);
        if (turns_on) turns_answer(entry.seq, false, MO_NONE_V, NULL);
        if (regioned) settle_region(id, mark);
        return (Delivered){entry.seq, false, MO_NONE_V};
    }
    undo_mark = frozen_below = 0;
    nundos = 0;
    p->state = after.as.xs[1];
    Event update = event_of(EV_UPDATED, id);
    update.name = entry.message.tag == MO_VARIANT ? mo_names[mo_vname(entry.message)] : "";
    update.took_us = (uint64_t)(event_now() - since > 0 ? event_now() - since : 0);
    update.waited_us = p->waited_us;
    update.call = p->longest ? p->longest : "";
    record_event(update);
    held -= p->noutbox;
    for (size_t i = 0; i < p->noutbox; i++) {
        Outgoing o = p->outbox[i];
        if (!procs[o.to]->up) parcel_free(o.parcel);
        /* No earlier than its delay after the update ends (step 24). */
        else if (o.delay > 0) push_later(id, o.to, o.message, o.parcel, deadline_now() + o.delay);
        else enqueue(o.to, o.message, o.parcel);
    }
    p->noutbox = 0;
    MoValue reply = after.as.xs[0];
    if (turns_on && turns_awaits(entry.seq)) {
        Parcel *parcel = packs ? pack(reply) : NULL;
        turns_answer(entry.seq, true, parcel ? parcel->value : reply, parcel);
    }
    if (regioned) settle_region(id, mark);
    return (Delivered){entry.seq, true, reply};
}

/* ---- turns: under main, every update runs on main's thread, one at a time, each on a fiber of
 * its own with a vm of its own (turns.zig, fiber.zig). A process gives up the thread when it waits,
 * in a Net call or in an ask its target cannot answer yet: its fiber switches back to whoever
 * handed it the thread, keeping its stack, and is switched to again when its wait ends. main's
 * thread runs main's code whenever no update does, and hands the thread out: first to a process
 * whose wait ended, then to the next process with a message waiting, round by round in start
 * order; with none, it waits in the poller for a socket something waits on, or for the earliest
 * deadline. A delivery borrows a fiber from a pool and gives it back when the update ends, so a
 * process at rest holds no stack. */

#define MAIN_TURN UINT32_MAX

static int64_t now_ms(void) { return awake_ns() / 1000000; }

/* ---- fibers: the switch pushes the registers a call must preserve onto the stack it leaves, saves
 * that stack pointer, loads the other, and pops them back (fiber.zig: the same assembly). */

typedef struct { void *sp; } FiberContext;

typedef struct Fiber {
    FiberContext context;
    void *memory;
    size_t size;
    /* The process whose delivery it runs next. */
    uint32_t id;
} Fiber;

void mo_fiber_swap(FiberContext *from, FiberContext *to);
void mo_fiber_entry(void);
void mo_fiber_start(Fiber *f);

#ifdef __APPLE__
#define MO_SYM(name) "_" #name
#else
#define MO_SYM(name) #name
#endif

#if defined(__aarch64__)
__asm__(".text\n.p2align 2\n"
        ".globl " MO_SYM(mo_fiber_swap) "\n"
        MO_SYM(mo_fiber_swap) ":\n"
        "  sub sp, sp, #160\n"
        "  stp x19, x20, [sp, #0]\n"
        "  stp x21, x22, [sp, #16]\n"
        "  stp x23, x24, [sp, #32]\n"
        "  stp x25, x26, [sp, #48]\n"
        "  stp x27, x28, [sp, #64]\n"
        "  stp x29, x30, [sp, #80]\n"
        "  stp d8, d9, [sp, #96]\n"
        "  stp d10, d11, [sp, #112]\n"
        "  stp d12, d13, [sp, #128]\n"
        "  stp d14, d15, [sp, #144]\n"
        "  mov x2, sp\n"
        "  str x2, [x0]\n"
        "  ldr x2, [x1]\n"
        "  mov sp, x2\n"
        "  ldp x19, x20, [sp, #0]\n"
        "  ldp x21, x22, [sp, #16]\n"
        "  ldp x23, x24, [sp, #32]\n"
        "  ldp x25, x26, [sp, #48]\n"
        "  ldp x27, x28, [sp, #64]\n"
        "  ldp x29, x30, [sp, #80]\n"
        "  ldp d8, d9, [sp, #96]\n"
        "  ldp d10, d11, [sp, #112]\n"
        "  ldp d12, d13, [sp, #128]\n"
        "  ldp d14, d15, [sp, #144]\n"
        "  add sp, sp, #160\n"
        "  ret\n"
        ".globl " MO_SYM(mo_fiber_entry) "\n"
        MO_SYM(mo_fiber_entry) ":\n"
        "  mov x0, x19\n"
        "  mov x29, #0\n"
        "  b " MO_SYM(mo_fiber_start) "\n");
#elif defined(__x86_64__)
__asm__(".text\n.p2align 4\n"
        ".globl " MO_SYM(mo_fiber_swap) "\n"
        MO_SYM(mo_fiber_swap) ":\n"
        "  pushq %rbp\n"
        "  pushq %rbx\n"
        "  pushq %r12\n"
        "  pushq %r13\n"
        "  pushq %r14\n"
        "  pushq %r15\n"
        "  movq %rsp, (%rdi)\n"
        "  movq (%rsi), %rsp\n"
        "  popq %r15\n"
        "  popq %r14\n"
        "  popq %r13\n"
        "  popq %r12\n"
        "  popq %rbx\n"
        "  popq %rbp\n"
        "  retq\n"
        ".globl " MO_SYM(mo_fiber_entry) "\n"
        MO_SYM(mo_fiber_entry) ":\n"
        "  movq %rbx, %rdi\n"
        "  xorl %ebp, %ebp\n"
        "  jmp " MO_SYM(mo_fiber_start) "\n");
#else
#error "mo: fibers are implemented for aarch64 and x86_64"
#endif

/* A fiber whose first switch runs mo_fiber_start. The frame the switch pops holds zeroed
 * registers, the fiber where mo_fiber_entry looks for it, and mo_fiber_entry as the return. */
static Fiber *fiber_create(void) {
    size_t size = FIBER_STACK + FIBER_GUARD;
    void *memory = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
    if (memory == MAP_FAILED) out_of_memory();
    mprotect(memory, FIBER_GUARD, PROT_NONE);
    Fiber *f = calloc(1, sizeof(Fiber));
    if (!f) out_of_memory();
    f->memory = memory;
    f->size = size;
    uintptr_t top = ((uintptr_t)memory + size) & ~(uintptr_t)15;
#if defined(__aarch64__)
    uintptr_t *frame = (uintptr_t *)(top - 160);
    memset(frame, 0, 160);
    frame[0] = (uintptr_t)f;
    frame[11] = (uintptr_t)&mo_fiber_entry;
#else
    uintptr_t *frame = (uintptr_t *)(top - 64);
    memset(frame, 0, 64);
    frame[4] = (uintptr_t)f;
    frame[6] = (uintptr_t)&mo_fiber_entry;
#endif
    f->context.sp = frame;
    return f;
}

static void fiber_destroy(Fiber *f) {
    munmap(f->memory, f->size);
    free(f);
}

/* ---- the poller: kqueue or epoll on main's thread (poller.zig). A waiter is armed once and
 * reported once. */

#define NO_PROCESS UINT32_MAX
#define POLL_BATCH 256

typedef struct {
    int fd;
    bool write;
    /* Reported ready (or broken) since it was last armed. */
    bool fired, armed;
    /* The process whose update waits on it, or NO_PROCESS; or the source that waits on it. */
    uint32_t process;
    struct Source *source;
    /* Linux: a write waiter watches a duplicate of the descriptor, since epoll keys a registration
     * by descriptor and a read waiter may be watching the original. */
    int dup;
} Waiter;

static int poller_fd = -1;

static bool poller_open(void) {
    if (poller_fd >= 0) return true;
#ifdef MO_KQUEUE
    poller_fd = kqueue();
#else
    poller_fd = epoll_create1(EPOLL_CLOEXEC);
#endif
    return poller_fd >= 0;
}

/* False when the system will not watch it: the waiter tries its call again at once. */
static bool poller_arm(Waiter *w) {
    w->fired = false;
    if (w->armed) return true;
#ifdef MO_KQUEUE
    struct kevent change;
    EV_SET(&change, (uintptr_t)w->fd, w->write ? EVFILT_WRITE : EVFILT_READ, EV_ADD | EV_ONESHOT, 0, 0, w);
    if (kevent(poller_fd, &change, 1, NULL, 0, NULL) < 0) return false;
#else
    int fd = w->fd;
    if (w->write) {
        w->dup = dup(w->fd);
        if (w->dup < 0) return false;
        fd = w->dup;
    }
    struct epoll_event ev;
    memset(&ev, 0, sizeof ev);
    ev.events = (w->write ? EPOLLOUT : EPOLLIN | EPOLLRDHUP) | EPOLLONESHOT;
    ev.data.ptr = w;
    if (epoll_ctl(poller_fd, EPOLL_CTL_ADD, fd, &ev) != 0) {
        if (w->dup >= 0) close(w->dup);
        w->dup = -1;
        return false;
    }
#endif
    w->armed = true;
    return true;
}

#ifndef MO_KQUEUE
static void epoll_forget(Waiter *w) {
    epoll_ctl(poller_fd, EPOLL_CTL_DEL, w->dup >= 0 ? w->dup : w->fd, NULL);
    if (w->dup >= 0) close(w->dup);
    w->dup = -1;
}
#endif

static void poller_disarm(Waiter *w) {
    if (!w->armed) return;
    w->armed = false;
#ifdef MO_KQUEUE
    struct kevent change;
    EV_SET(&change, (uintptr_t)w->fd, w->write ? EVFILT_WRITE : EVFILT_READ, EV_DELETE, 0, 0, NULL);
    kevent(poller_fd, &change, 1, NULL, 0, NULL);
#else
    epoll_forget(w);
#endif
}

/* Waits at most `ms` and gives every waiter reported, each now fired and no longer armed. */
static size_t poller_wait(int64_t ms, Waiter **out) {
    size_t k = 0;
#ifdef MO_KQUEUE
    struct kevent events[POLL_BATCH];
    struct timespec ts = {(time_t)(ms / 1000), (long)(ms % 1000) * 1000000};
    int n = kevent(poller_fd, NULL, 0, events, POLL_BATCH, &ts);
    for (int i = 0; i < n; i++) {
        Waiter *w = events[i].udata;
        if (!w) continue;
        w->armed = false;
        w->fired = true;
        out[k++] = w;
    }
#else
    struct epoll_event events[POLL_BATCH];
    int n = epoll_wait(poller_fd, events, POLL_BATCH, (int)ms);
    for (int i = 0; i < n; i++) {
        Waiter *w = events[i].data.ptr;
        /* A one-shot registration stays behind, disabled, until it is deleted. */
        epoll_forget(w);
        w->armed = false;
        w->fired = true;
        out[k++] = w;
    }
#endif
    return k;
}

/* What a vm keeps that is not a value: saved by whoever gives up the thread and loaded by whoever
 * takes it. */
typedef struct {
    MoRegion heap;
    PtrTable growth;
    Growth text_growth[16];
    unsigned text_growth_next;
    PtrTable owned;
    Remembered *remembered;
    size_t nremembered, capremembered;
    Undo *undos;
    size_t nundos, capundos;
    uintptr_t undo_mark, frozen_below;
    size_t full_kept;
    jmp_buf *crash_jump;
    MoHandleFrame *handle_frames;
} VmState;

static void save_vm(VmState *s) {
    s->heap = mo_heap;
    s->growth = growth;
    memcpy(s->text_growth, text_growth, sizeof text_growth);
    s->text_growth_next = text_growth_next;
    s->owned = owned;
    s->remembered = remembered;
    s->nremembered = nremembered;
    s->capremembered = capremembered;
    s->undos = undos;
    s->nundos = nundos;
    s->capundos = capundos;
    s->undo_mark = undo_mark;
    s->frozen_below = frozen_below;
    s->full_kept = full_kept;
    s->crash_jump = crash_jump;
    s->handle_frames = mo_handle_frames;
}

static void load_vm(const VmState *s) {
    mo_heap = s->heap;
    growth = s->growth;
    memcpy(text_growth, s->text_growth, sizeof text_growth);
    text_growth_next = s->text_growth_next;
    owned = s->owned;
    remembered = s->remembered;
    nremembered = s->nremembered;
    capremembered = s->capremembered;
    undos = s->undos;
    nundos = s->nundos;
    capundos = s->capundos;
    undo_mark = s->undo_mark;
    frozen_below = s->frozen_below;
    full_kept = s->full_kept;
    crash_jump = s->crash_jump;
    mo_handle_frames = s->handle_frames;
}

/* A vm handed to a process whose id an ended process had: what it kept is cleared, its lists keep
 * their room, and its region is the caller's to set. */
static void reuse_vm(VmState *s) {
    Remembered *rem = s->remembered;
    size_t caprem = s->capremembered;
    Undo *u = s->undos;
    size_t capu = s->capundos;
    PtrTable g = s->growth, o = s->owned;
    memset(s, 0, sizeof *s);
    s->remembered = rem;
    s->capremembered = caprem;
    s->undos = u;
    s->capundos = capu;
    ptab_clear(&g);
    ptab_clear(&o);
    s->growth = g;
    s->owned = o;
}

enum { JOB_DELIVER, JOB_GO_ON };
enum { PHASE_IDLE, PHASE_RUNNING, PHASE_WAITING };

typedef struct {
    uint32_t id;
    VmState vm;
    /* The fiber its update runs on, from the delivery to the update's end; NULL at rest. */
    Fiber *fiber;
    /* Who handed it the thread, and gets it back. */
    uint32_t caller;
    /* PHASE_RUNNING: its update holds the thread, or waits for a process it handed it to. */
    int phase;
    /* In `ready`. */
    bool queued;
    /* How its update ended when a crash left it, for whoever gets the thread back. */
    int failed;
    Report report;
    /* Its region is released, after a sweep ended its process and more than KEPT_WORKERS had
     * ended since; the next process given its id reserves one again. */
    bool ended;
} Worker;

typedef struct { uint32_t id; int64_t deadline; } Parked;
typedef struct { uint64_t seq; uint32_t who; } Awaiting;
typedef struct { uint64_t seq; bool has; MoValue value; Parcel *parcel; } Answer;

static uint32_t holder = MAIN_TURN;
/* main's thread's own context, while a fiber runs. */
static FiberContext main_context;
/* Processes whose wait ended, oldest first from ready_head; each at most once. */
static uint32_t *ready;
static size_t ready_head, nready, capready;
/* One per process, made at its first delivery; indexed by process id. */
static Worker **workers;
static size_t nworkers, capworkers;
/* Fibers no update is on, and the updates on a fiber, running or waiting. */
static Fiber **fibers;
static size_t nfibers, capfibers;
static uint32_t in_flight;
/* Asks waiting for their reply, the replies that came, and processes parked in an ask or a Net
 * call. */
static Awaiting *awaiting;
static size_t nawaiting, capawaiting;
static Answer *answers;
static size_t nanswers, capanswers;
static Parked *parked;
static size_t nparked, capparked;
/* Where the next round of deliveries starts, and the ids that may have a message waiting: set
 * when one goes into a mailbox, cleared when a round finds the mailbox empty. */
static uint32_t cursor;
static uint64_t *runnable;
static size_t runnable_words;
static VmState main_vm;
/* The vm state of whoever holds the thread. */
static VmState *my_vm;

static FiberContext *context_of(uint32_t id) { return id == MAIN_TURN ? &main_context : &workers[id]->fiber->context; }

/* Switches to `to`, main or a process with a fiber; returns when something switches back. */
static void switch_to(uint32_t to) {
    uint32_t from = holder;
    uint32_t depth = mo_depth;
    holder = to;
    mo_fiber_swap(context_of(from), context_of(to));
    mo_depth = depth;
}

static void mark_runnable(uint32_t id) {
    size_t word = id / 64;
    if (word >= runnable_words) {
        size_t words = 2 * runnable_words > word + 1 ? 2 * runnable_words : word + 1;
        runnable = xrealloc(runnable, words * sizeof(uint64_t));
        memset(runnable + runnable_words, 0, (words - runnable_words) * sizeof(uint64_t));
        runnable_words = words;
    }
    runnable[word] |= (uint64_t)1 << (id % 64);
}

/* The first process in [from, to) that is up, not on a stack, and has a message waiting. A marked
 * process whose mailbox is empty, or that is down, is unmarked on the way. */
static bool next_runnable(uint32_t from, uint32_t to, uint32_t *out) {
    size_t end = to < runnable_words * 64 ? to : runnable_words * 64;
    size_t i = from;
    while (i < end) {
        uint64_t word = runnable[i / 64] >> (i % 64);
        if (word == 0) {
            i = (i / 64 + 1) * 64;
            continue;
        }
        i += (size_t)__builtin_ctzll(word);
        if (i >= end) break;
        const Proc *p = procs[i];
        if (!p->up || queued(p) == 0) {
            runnable[i / 64] &= ~((uint64_t)1 << (i % 64));
        } else if (!p->busy && !p->paused) {
            *out = (uint32_t)i;
            return true;
        }
        i++;
    }
    return false;
}

static Worker *worker_of(uint32_t id) {
    while (nworkers <= id) {
        GROW_ARRAY(workers, nworkers, capworkers);
        workers[nworkers++] = NULL;
    }
    if (workers[id] && !workers[id]->ended) return workers[id];
    Worker *w = workers[id];
    if (w) {
        /* The worker of an ended process: its lists keep their room. */
        reuse_vm(&w->vm);
        w->failed = 0;
        w->phase = PHASE_IDLE;
        w->queued = false;
        w->fiber = NULL;
        w->ended = false;
    } else {
        w = calloc(1, sizeof(Worker));
        if (!w) out_of_memory();
    }
    w->id = id;
    w->caller = MAIN_TURN;
    if (packs && !reserve_up_to(&w->vm.heap, PROCESS_REGION)) w->vm.heap = (MoRegion){0, 0, 0};
    workers[id] = w;
    return w;
}

/* The holder hands the thread to process `id`, to deliver its next message or to go on after a
 * wait, and has it back when the update ends or waits again. */
static void hand_to(uint32_t id, int job) {
    Worker *w = worker_of(id);
    uint32_t was_running = running;
    VmState *mine = my_vm;
    w->caller = holder;
    w->phase = PHASE_RUNNING;
    if (job == JOB_DELIVER) {
        Fiber *f = nfibers > 0 ? fibers[--nfibers] : fiber_create();
        f->id = id;
        w->fiber = f;
        in_flight++;
    }
    save_vm(mine);
    switch_to(id);
    my_vm = mine;
    load_vm(mine);
    running = was_running;
    if (w->failed) {
        int jumped = w->failed;
        w->failed = 0;
        raise_report(w->report, jumped);
    }
}

/* A fiber's life: each time it is switched to after a job ended, it delivers one message to the
 * process it was given, then gives the thread back and goes back to the pool. */
void mo_fiber_start(Fiber *f) {
    for (;;) {
        Worker *w = workers[f->id];
        my_vm = &w->vm;
        load_vm(&w->vm);
        mo_depth = 0;
        jmp_buf here;
        crash_jump = &here;
        int jumped = setjmp(here);
        if (jumped == 0) {
            deliver(w->id);
        } else {
            mo_depth = 0;
            mo_handle_frames = NULL;
            w->failed = jumped;
            w->report = last_report;
        }
        crash_jump = NULL;
        const Proc *p = procs[w->id];
        if (p->supervisor == NOBODY && queued(p) == 0) quiet++;
        w->phase = PHASE_IDLE;
        save_vm(&w->vm);
        w->fiber = NULL;
        in_flight--;
        GROW_ARRAY(fibers, nfibers, capfibers);
        fibers[nfibers++] = f;
        holder = w->caller;
        mo_fiber_swap(&f->context, context_of(w->caller));
    }
}

static void push_ready(uint32_t id) {
    Worker *w = workers[id];
    if (w->queued) return;
    w->queued = true;
    if (ready_head > 0 && nready == capready) {
        memmove(ready, ready + ready_head, (nready - ready_head) * sizeof(uint32_t));
        nready -= ready_head;
        ready_head = 0;
    }
    GROW_ARRAY(ready, nready, capready);
    ready[nready++] = id;
}

static bool pop_ready(uint32_t *id) {
    if (ready_head == nready) return false;
    *id = ready[ready_head++];
    if (ready_head == nready) ready_head = nready = 0;
    workers[*id]->queued = false;
    return true;
}

/* Process `id`'s wait ended: it leaves the parked list and is switched to next. */
static void wake(uint32_t id) {
    for (size_t k = 0; k < nparked; k++) {
        if (parked[k].id != id) continue;
        parked[k] = parked[--nparked];
        break;
    }
    push_ready(id);
}

/* A process parks in an ask until the reply comes, the target goes down, or `deadline`. */
static void park(int64_t deadline) {
    uint32_t id = holder;
    Worker *w = workers[id];
    uint32_t was_running = running;
    VmState *mine = my_vm;
    GROW_ARRAY(parked, nparked, capparked);
    parked[nparked++] = (Parked){id, deadline};
    w->phase = PHASE_WAITING;
    save_vm(mine);
    switch_to(w->caller);
    my_vm = mine;
    load_vm(mine);
    running = was_running;
}

/* main's thread, with no turn to hand out: waits in the poller until a socket something waits on
 * is ready, `also` is reported, or the earliest deadline passes, and at least once a second. */
static void idle(Waiter *also, bool bounded, int64_t deadline) {
    if (ready_head < nready) return;
    if (also && also->fired) return;
    if (sources_has_work()) return;
    int64_t until = deadline;
    for (size_t i = 0; i < nparked; i++) {
        if (!bounded || parked[i].deadline < until) until = parked[i].deadline;
        bounded = true;
    }
    int64_t due;
    if (sources_next_deadline(&due) && (!bounded || due < until)) {
        until = due;
        bounded = true;
    }
    if (nlater > 0 && (!bounded || later[0].at < until)) {
        until = later[0].at;
        bounded = true;
    }
    int64_t left = bounded ? until - now_ms() : 1000;
    if (left < 0) left = 0;
    if (left > 1000) left = 1000;
    if (!poller_open()) return;
    Waiter *out[POLL_BATCH];
    size_t n = poller_wait(left, out);
    for (size_t i = 0; i < n; i++) {
        if (out[i]->process != NO_PROCESS) wake(out[i]->process);
        else if (out[i]->source) sources_fired(out[i]->source);
    }
}

/* ---- ending finished processes (turns.zig, sweep) */

static bool *marks;
static size_t capmarks;
static uint32_t *worklist;
static size_t nworklist, capworklist;

static void mark_id(uint32_t id) {
    if (id >= nprocs || marks[id]) return;
    marks[id] = true;
    GROW_ARRAY(worklist, nworklist, capworklist);
    worklist[nworklist++] = id;
}

static bool may_hold_handle(MoValue v) {
    switch (v.tag) {
    case MO_HANDLE: case MO_TUPLE: case MO_VARIANT: case MO_LIST: case MO_SET: case MO_MAP: return true;
    default: return false;
    }
}

static void mark_value(MoValue v);

static void mark_values(const MoValue *xs, size_t n) {
    for (size_t i = 0; i < n; i++) mark_value(xs[i]);
}

/* Every handle inside `v`. A list, a set, or a map's keys or values whose first element cannot
 * hold a handle hold none, since their elements share a type. */
static void mark_value(MoValue v) {
    switch (v.tag) {
    case MO_HANDLE: mark_id((uint32_t)v.as.i); return;
    case MO_TUPLE: mark_values(v.as.xs, v.aux); return;
    case MO_VARIANT: mark_values(v.as.xs, mo_vcount(v)); return;
    /* A state (step 24): no struct holds a handle, so only a state's fields are read. */
    case MO_RECORD: mark_values(v.as.xs, mo_decls[v.aux].nfields); return;
    case MO_LIST:
        if (v.aux > 0 && may_hold_handle(v.as.xs[0])) mark_values(v.as.xs, v.aux);
        return;
    case MO_SET:
        if (v.as.m && v.as.m->len > 0 && may_hold_handle(v.as.m->entries[0])) mark_values(v.as.m->entries, v.as.m->len);
        return;
    case MO_MAP:
        if (v.as.m && v.as.m->len > 1) {
            bool keys = may_hold_handle(v.as.m->entries[0]), values = may_hold_handle(v.as.m->entries[1]);
            for (size_t k = 0; k + 1 < v.as.m->len; k += 2) {
                if (keys) mark_value(v.as.m->entries[k]);
                if (values) mark_value(v.as.m->entries[k + 1]);
            }
        }
        return;
    default: return;
    }
}

static void mark_frames(const MoHandleFrame *f) {
    for (; f; f = f->next) {
        for (uint32_t i = 0; i < f->n; i++) mark_value(*f->slots[i]);
    }
}

/* Began by a start call, nothing waiting for it, and no update of it on a stack. */
static bool finished(const Proc *p) { return p->supervisor == NOBODY && !p->busy && queued(p) == 0; }

/* Everything allocated goes back to the system, the reservation kept (region.zig, decommit). */
static void decommit(MoRegion *r) {
    size_t page = (size_t)sysconf(_SC_PAGESIZE);
    size_t used = ((r->top - r->base) + page - 1) & ~(page - 1);
    if (used > 0) mmap((void *)r->base, used, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON | MAP_FIXED, -1, 0);
    r->top = r->base;
}

/* Process `id` has finished: what it held is freed, and its emptied region waits for the next
 * process given its id. */
static void end_process(uint32_t id) {
    int64_t t0 = awake_ns();
    record_event(event_of(EV_ENDED, id));
    Proc *p = procs[id];
    if (id < nworkers && workers[id] && !workers[id]->ended) {
        Worker *w = workers[id];
        MoRegion heap = w->vm.heap;
        if (heap.end != 0) decommit(&heap);
        reuse_vm(&w->vm);
        w->vm.heap = heap;
    }
    parcel_free(p->start);
    for (size_t i = 0; i < p->nlog_parcels; i++) parcel_free(p->log_parcels[i]);
    free(p->mailbox);
    free(p->log);
    free(p->restarts);
    free(p->outbox);
    memset(p, 0, sizeof *p);
    p->supervisor = NOBODY;
    p->ended = true;
    GROW_ARRAY(free_ids, nfree_ids, capfree_ids);
    free_ids[nfree_ids++] = id;
    stat_freed++;
    stat_freed_ns += (uint64_t)(awake_ns() - t0);
}

/* The region kept for ended process `id` is released. */
static void release_worker(uint32_t id) {
    if (id >= nworkers || !workers[id] || workers[id]->ended) return;
    Worker *w = workers[id];
    if (w->vm.heap.end != 0) munmap((void *)w->vm.heap.base, w->vm.heap.end - w->vm.heap.base);
    w->vm.heap = (MoRegion){0, 0, 0};
    w->ended = true;
}

/* From main's thread, holding the turn: ends every process that has finished. One has when a start
 * call began it (a child line's never ends), its mailbox is empty, no update of it is on a stack,
 * and no handle to it is where anything could use it: in a frame of main or of an update on a
 * stack, in the start arguments of a process that has not finished, in the state of a process that
 * is up (step 24), in a send an update holds, or in a reply not yet taken. */
static void sweep(void) {
    if (capmarks < nprocs) {
        marks = xrealloc(marks, nprocs * sizeof(bool));
        capmarks = nprocs;
    }
    memset(marks, 0, nprocs * sizeof(bool));
    nworklist = 0;
    /* main's frames: only main's thread sweeps. */
    mark_frames(mo_handle_frames);
    for (uint32_t id = 0; id < nprocs; id++) {
        const Proc *p = procs[id];
        if (p->ended || finished(p)) continue;
        mark_values(p->args, p->nargs);
        /* A state may keep handles (step 24); a process that is down keeps none. */
        if (p->up) mark_value(p->state);
        /* A message may carry a handle (step 20): one waiting in a mailbox or held in an outbox
         * reaches its process. */
        for (size_t i = p->head; i < p->mailbox_len; i++) mark_value(p->mailbox[i].message);
        if (!p->busy) continue;
        mark_frames(workers[id]->vm.handle_frames);
        for (size_t i = 0; i < p->noutbox; i++) {
            mark_id(p->outbox[i].to);
            mark_value(p->outbox[i].message);
        }
    }
    for (size_t i = 0; i < nanswers; i++) {
        if (answers[i].has) mark_value(answers[i].value);
    }
    /* A source's target is where the runtime keeps sending. */
    sources_mark();
    /* A delayed send's target is where the runtime will send (step 24). */
    for (size_t i = 0; i < nlater; i++) {
        mark_id(later[i].to);
        mark_value(later[i].message);
    }
    while (nworklist > 0) {
        const Proc *p = procs[worklist[--nworklist]];
        mark_values(p->args, p->nargs);
        if (p->up) mark_value(p->state);
    }
    uint32_t still = 0;
    for (uint32_t id = 0; id < nprocs; id++) {
        const Proc *p = procs[id];
        if (p->ended || p->supervisor != NOBODY) continue;
        if (finished(p) && !marks[id]) end_process(id);
        else still++;
    }
    if (nfree_ids > KEPT_WORKERS) {
        for (size_t i = 0; i < nfree_ids - KEPT_WORKERS; i++) release_worker(free_ids[i]);
    }
    quiet = 0;
    sweep_at = 2 * still > SWEEP_MIN ? 2 * still : SWEEP_MIN;
}

/* In a test binary, a test's processes that have finished and that nothing can reach end when the
 * surface reads the processes, by sweep's rule (sim.zig, sweepEnded; step 24); an ended id is not
 * given to a later process. */
static void sweep_test(void) {
    if (turns_on) return;
    if (capmarks < nprocs) {
        marks = xrealloc(marks, nprocs * sizeof(bool));
        capmarks = nprocs;
    }
    memset(marks, 0, nprocs * sizeof(bool));
    nworklist = 0;
    /* One stack runs the test and every update on it. */
    mark_frames(mo_handle_frames);
    for (uint32_t id = 0; id < nprocs; id++) {
        const Proc *p = procs[id];
        if (p->ended || finished(p)) continue;
        mark_values(p->args, p->nargs);
        if (p->up) mark_value(p->state);
        for (size_t i = p->head; i < p->mailbox_len; i++) mark_value(p->mailbox[i].message);
        for (size_t i = 0; i < p->noutbox; i++) {
            mark_id(p->outbox[i].to);
            mark_value(p->outbox[i].message);
        }
    }
    sources_mark();
    /* A delayed send's target is where the runtime will send (step 24). */
    for (size_t i = 0; i < nlater; i++) {
        mark_id(later[i].to);
        mark_value(later[i].message);
    }
    while (nworklist > 0) {
        const Proc *p = procs[worklist[--nworklist]];
        mark_values(p->args, p->nargs);
        if (p->up) mark_value(p->state);
    }
    for (uint32_t id = 0; id < nprocs; id++) {
        Proc *p = procs[id];
        if (p->ended || !finished(p) || marks[id]) continue;
        record_event(event_of(EV_ENDED, id));
        p->nlog = 0;
        p->mailbox_len = p->head = 0;
        p->nargs = 0;
        p->state = MO_NONE_V;
        p->up = false;
        p->ended = true;
    }
}

/* One turn handed out, from main's thread: to a process whose wait ended, else to the next
 * process with a message waiting. False when there is none. */
static bool step(void) {
    if (quiet >= sweep_at) sweep();
    while (nfibers > KEPT_FIBERS) fiber_destroy(fibers[--nfibers]);
    /* What the runtime's loops took becomes messages first (sources.zig), and delayed sends whose
     * time has come (step 24). */
    sources_pump_server();
    due_later();
    int64_t now = now_ms();
    size_t k = 0;
    while (k < nparked) {
        if (parked[k].deadline <= now) {
            uint32_t id = parked[k].id;
            parked[k] = parked[--nparked];
            push_ready(id);
        } else {
            k++;
        }
    }
    uint32_t id;
    while (pop_ready(&id)) {
        const Worker *w = workers[id];
        if (w->phase != PHASE_WAITING || !w->fiber) continue;
        hand_to(id, JOB_GO_ON);
        return true;
    }
    if (nprocs == 0) return false;
    uint32_t from = cursor % nprocs;
    if (next_runnable(from, nprocs, &id) || next_runnable(0, from, &id)) {
        cursor = id + 1;
        hand_to(id, JOB_DELIVER);
        return true;
    }
    return false;
}

static void forget_awaiting(uint64_t seq) {
    for (size_t i = 0; i < nawaiting; i++) {
        if (awaiting[i].seq != seq) continue;
        awaiting[i] = awaiting[--nawaiting];
        return;
    }
}

/* `h.ask(message, within: d)` under main, with d in wall-clock time. The target's waiting
 * messages are delivered first; while it cannot answer, main hands out turns and a process
 * parks. Timeout at the deadline, or at once when the target's update is itself waiting on
 * this call; Down when the target is down, crashed on the message, or dropped it restarting. */
static MoValue turns_ask(uint32_t to, MoValue message, int64_t within) {
    if (!procs[to]->up) return ask_error(MO_N_DOWN);
    room_for(to, message);
    Parcel *parcel = packs ? pack(message) : NULL;
    uint64_t seq = enqueue(to, parcel ? parcel->value : message, parcel);
    GROW_ARRAY(awaiting, nawaiting, capawaiting);
    awaiting[nawaiting++] = (Awaiting){seq, holder};
    int64_t deadline = now_ms() + (within > 0 ? within : 0);
    procs[to]->mailbox[procs[to]->mailbox_len - 1].has_deadline = true;
    procs[to]->mailbox[procs[to]->mailbox_len - 1].deadline = deadline;
    for (;;) {
        /* A wait elsewhere doomed this ask (held sends): mo_ask crashes the update. */
        if (running != NOBODY && procs[running]->doomed) {
            forget_awaiting(seq);
            return ask_error(MO_N_DOWN);
        }
        for (size_t i = 0; i < nanswers; i++) {
            if (answers[i].seq != seq) continue;
            Answer got = answers[i];
            answers[i] = answers[--nanswers];
            if (!got.has) return ask_error(MO_N_DOWN);
            MoValue reply = got.value;
            if (got.parcel) {
                reply = unpack(got.parcel);
                parcel_free(got.parcel);
            }
            return ok_of(reply);
        }
        const Proc *p = procs[to];
        bool updating = p->busy && to < nworkers && workers[to] && workers[to]->phase == PHASE_RUNNING;
        if (!p->up || updating || now_ms() >= deadline) {
            forget_awaiting(seq);
            return ask_error(p->up ? MO_N_TIMEOUT : MO_N_DOWN);
        }
        if (!p->busy && !p->paused && queued(p) > 0) {
            hand_to(to, JOB_DELIVER);
        } else if (holder != MAIN_TURN) {
            park(deadline);
        } else if (!step()) {
            idle(NULL, true, deadline);
        }
    }
}

/* Between two of main's statements: every turn there is to hand out, without waiting. */
static void turns_settle(void) {
    while (step()) {}
}

/* main is about to start a process: past sweep_at quiet events, it settles first. */
static void turns_spawning(void) {
    if (holder == MAIN_TURN && quiet >= sweep_at) turns_settle();
}

/* main returned: turns go on being handed out until no message waits, no update is in progress, no
 * runtime loop can deliver, and no delayed send is still to come (step 24). */
static void turns_finish(void) {
    for (;;) {
        if (step()) continue;
        if (in_flight == 0 && !sources_active() && nlater == 0) return;
        idle(NULL, false, 0);
    }
}

static bool turns_awaits(uint64_t seq) {
    for (size_t i = 0; i < nawaiting; i++) {
        if (awaiting[i].seq == seq) return true;
    }
    return false;
}

/* An update that took message `seq` ended: with its reply, packed under main, or none when it
 * crashed. The asker takes the parcel; a parked asker is woken, and main looks each time round. */
static void turns_answer(uint64_t seq, bool has, MoValue reply, Parcel *parcel) {
    size_t i = 0;
    while (i < nawaiting && awaiting[i].seq != seq) i++;
    if (i == nawaiting) {
        parcel_free(parcel);
        return;
    }
    uint32_t who = awaiting[i].who;
    awaiting[i] = awaiting[--nawaiting];
    GROW_ARRAY(answers, nanswers, capanswers);
    answers[nanswers++] = (Answer){seq, has, reply, parcel};
    if (who == MAIN_TURN) return;
    for (size_t k = 0; k < nparked; k++) {
        if (parked[k].id == who) return wake(who);
    }
}

/* A process crashed: every parked process looks at what it waits for again. */
static void turns_wake_all(void) {
    while (nparked > 0) push_ready(parked[--nparked].id);
}


/* ==== Net: TCP under a program's main, and Net.fixture() in its tests (net.zig) ============ */

/* The longest line read_line gives: 64 KiB before its newline. */
#define LINE_LIMIT ((size_t)64 << 10)
/* A connection's read buffer at its first read; it grows to what the reader allows. */
#define BUFFER_INITIAL ((size_t)16 << 10)
/* Connections the kernel queues for a listener before accept takes them. */
#define BACKLOG 128

/* NetError's variants. */
enum { NET_TIMEOUT, NET_REFUSED, NET_CLOSED, NET_LINE_TOO_LONG, NET_BUSY };

static MoValue net_fail(int f) {
    static const uint32_t names[] = {MO_N_TIMEOUT, MO_N_REFUSED, MO_N_CLOSED, MO_N_LINE_TOO_LONG, MO_N_BUSY};
    return error_of(mo_variant(names[f], 0, NULL));
}

enum { SCAN_LINE, SCAN_TOO_LONG, SCAN_END, SCAN_MORE };
typedef struct { int what; size_t taken; const char *line; size_t len; } Scan;

static size_t without_cr(const char *line, size_t len) { return len > 0 && line[len - 1] == '\r' ? len - 1 : len; }

/* The next line in `pending`, the bytes of the stream so far not given out: how many bytes it
 * takes, and the line, what stands in its way, or more to read first. `eof`: nothing follows. A
 * line of more than 64 KiB is too long, and the bytes up to its newline are taken, at once or as
 * they arrive (`skipping`). */
static Scan scan_line(const char *pending, size_t n, bool eof, bool *skipping) {
    size_t off = 0;
    for (;;) {
        const char *rest = pending + off;
        size_t left = n - off;
        const char *nl = left ? memchr(rest, '\n', left) : NULL;
        if (nl) {
            size_t k = (size_t)(nl - rest);
            off += k + 1;
            if (*skipping) {
                *skipping = false;
                continue;
            }
            if (k > LINE_LIMIT) return (Scan){SCAN_TOO_LONG, off, NULL, 0};
            return (Scan){SCAN_LINE, off, rest, without_cr(rest, k)};
        }
        if (*skipping || left > LINE_LIMIT) {
            bool first = !*skipping;
            *skipping = !eof;
            if (first) return (Scan){SCAN_TOO_LONG, n, NULL, 0};
            return (Scan){eof ? SCAN_END : SCAN_MORE, n, NULL, 0};
        }
        if (!eof) return (Scan){SCAN_MORE, off, NULL, 0};
        if (left == 0) return (Scan){SCAN_END, off, NULL, 0};
        return (Scan){SCAN_LINE, n, rest, without_cr(rest, left)};
    }
}

/* Ok(Some(line)), LineTooLong, or Ok(None); false for more. The line is copied out first. */
static bool line_result(Scan s, MoValue *out) {
    switch (s.what) {
    case SCAN_LINE: *out = ok_of(mo_some(heap_string(s.line, s.len))); return true;
    case SCAN_TOO_LONG: *out = net_fail(NET_LINE_TOO_LONG); return true;
    case SCAN_END: *out = ok_of(mo_nothing()); return true;
    default: return false;
    }
}

/* ---- real sockets: a Listener's or a Conn's handle is its index here */

/* `served`: serve gave it to the runtime (sources), and an accept on it is Busy. */
typedef struct { int fd; uint16_t port; bool accepting; bool served; } Listener;
typedef struct {
    int fd;
    /* Bytes read and not yet given out are buf[start..end] of cap; allocated at the first read. */
    char *buf;
    size_t start, end, cap;
    /* The other side closed its end: what is buffered is the rest of the stream. */
    bool eof;
    /* close ran, a write timed out, the stream broke, or the process holding it stopped. */
    bool closed;
    /* The descriptor is closed: at once, or when the call waiting on it returns. */
    bool released;
    /* After LineTooLong, the rest of that line is dropped. */
    bool skipping;
    bool reading, writing;
    /* The listener that accepted it, or UINT32_MAX (held sends). */
    uint32_t listener;
    /* lines gave its reading to the runtime (sources): a read_line on it is Busy. */
    bool lining;
} Conn;

static Listener **listeners;
static size_t nlisteners, caplisteners;
static Conn **conns;
static size_t nconns, capconns;

/* An Exchange (Http): the connection it answers on, and until it is answered the request's bytes,
 * which exchange.request reads. Its handle is its index here, or in fix_exchanges in a test. */
typedef struct { uint32_t conn; char *request; size_t len; bool answered; } HttpExchange;
static HttpExchange *exchanges;
static size_t nexchanges, capexchanges;
static HttpExchange *fix_exchanges;
static size_t nfix_exchanges, capfix_exchanges;

/* Answered: the request's bytes are no longer kept. */
static void exchange_forget(HttpExchange *e) {
    if (!e->answered) free(e->request);
    e->answered = true;
    e->request = NULL;
}

static int64_t max0(int64_t ms) { return ms > 0 ? ms : 0; }

/* Waits for `fd` until `deadline` (awake ms); true when it is ready, or broke. */
static bool poll_until(int fd, short events, int64_t deadline) {
    for (;;) {
        int64_t left = max0(deadline - now_ms());
        struct pollfd p = {fd, events, 0};
        int r = poll(&p, 1, left > INT_MAX ? INT_MAX : (int)left);
        if (r > 0) return true;
        if (r < 0 && errno != EINTR) return true;
        if (r == 0 && now_ms() >= deadline) return false;
    }
}

/* A Net call's wait, at most `ms` (net.zig, wait; turns.zig, block). Under main with processes
 * the poller watches the socket: main's thread hands out turns until it is ready, and a process's
 * update switches back to whoever handed it the thread and is switched to again when the socket is
 * ready or the deadline passes. True when the socket was ready in time. */
static bool net_wait(int fd, short events, int64_t ms) {
    int64_t deadline = now_ms() + max0(ms);
    if (!turns_on || !poller_open()) return poll_until(fd, events, deadline);
    Waiter w = {fd, events == POLLOUT, false, false, NO_PROCESS, NULL, -1};
    if (!poller_arm(&w)) return true;
    if (holder == MAIN_TURN) {
        for (;;) {
            if (w.fired || now_ms() >= deadline) break;
            if (step()) continue;
            idle(&w, true, deadline);
        }
        poller_disarm(&w);
        return w.fired;
    }
    uint32_t id = holder;
    Worker *wk = workers[id];
    uint32_t was_running = running;
    VmState *mine = my_vm;
    w.process = id;
    /* Woken early (a crash elsewhere wakes every parked process), it parks again. */
    while (!w.fired && now_ms() < deadline) {
        GROW_ARRAY(parked, nparked, capparked);
        parked[nparked++] = (Parked){id, deadline};
        wk->phase = PHASE_WAITING;
        save_vm(mine);
        switch_to(wk->caller);
        my_vm = mine;
        load_vm(mine);
    }
    running = was_running;
    poller_disarm(&w);
    return w.fired;
}

static void nonblocking(int fd) {
    fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK);
    fcntl(fd, F_SETFD, FD_CLOEXEC);
}

static uint32_t adopt(int fd) {
    nonblocking(fd);
    Conn *c = calloc(1, sizeof(Conn));
    if (!c) out_of_memory();
    c->fd = fd;
    c->listener = UINT32_MAX;
    GROW_ARRAY(conns, nconns, capconns);
    conns[nconns] = c;
    return (uint32_t)nconns++;
}

/* A call that gives a connection gives its handle, or -1 - why not. */
static int64_t failed_conn(int f) { return -1 - (int64_t)f; }

static MoValue conn_result(int64_t h) {
    return h >= 0 ? ok_of(mo_cap(MO_CAP_CONN, (uint32_t)h, 0)) : net_fail((int)(-1 - h));
}

/* Closes the descriptor once no call is waiting on it. */
static void net_release(Conn *c) {
    if (c->released || c->reading || c->writing) return;
    c->released = true;
    close(c->fd);
    free(c->buf);
    c->buf = NULL;
    c->start = c->end = c->cap = 0;
}

/* `conn.close`: a call waiting on the connection ends, and every later call is Closed. */
static void net_close(Conn *c) {
    if (!c->closed) {
        c->closed = true;
        shutdown(c->fd, SHUT_RDWR);
    }
    net_release(c);
}

/* `net.listen(port)`: TCP on 127.0.0.1, at `port` or, given 0, at a free port. Binding does not
 * wait. SO_REUSEADDR alone: a port another listener holds is Busy, and a server that restarts at
 * once binds again. */
static MoValue net_listen(uint16_t port) {
    int fd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if (fd < 0) return net_fail(NET_REFUSED);
    int one = 1;
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof addr);
    addr.sin_family = AF_INET;
    addr.sin_port = htons(port);
    addr.sin_addr.s_addr = htonl(0x7f000001);
    socklen_t len = sizeof addr;
    int failed = -1;
    if (setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one) != 0) failed = NET_REFUSED;
    else if (bind(fd, (struct sockaddr *)&addr, sizeof addr) != 0) failed = errno == EADDRINUSE ? NET_BUSY : NET_REFUSED;
    else if (listen(fd, BACKLOG) != 0 || getsockname(fd, (struct sockaddr *)&addr, &len) != 0) failed = NET_REFUSED;
    if (failed >= 0) {
        close(fd);
        return net_fail(failed);
    }
    nonblocking(fd);
    Listener *l = calloc(1, sizeof(Listener));
    if (!l) out_of_memory();
    l->fd = fd;
    l->port = ntohs(addr.sin_port);
    GROW_ARRAY(listeners, nlisteners, caplisteners);
    listeners[nlisteners] = l;
    return ok_of(mo_cap(MO_CAP_LISTENER, (uint32_t)nlisteners++, 0));
}

static int64_t net_connect_conn(MoValue host, uint16_t port, int64_t ms) {
    int64_t deadline = now_ms() + max0(ms);
    char *name = xmalloc(host.aux + 1);
    memcpy(name, host.as.s, host.aux);
    name[host.aux] = 0;
    char service[8];
    snprintf(service, sizeof service, "%u", (unsigned)port);
    struct addrinfo hints;
    memset(&hints, 0, sizeof hints);
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    struct addrinfo *found = NULL;
    int gai = strlen(name) == host.aux ? getaddrinfo(name, service, &hints, &found) : EAI_NONAME;
    free(name);
    if (gai != 0) return failed_conn(gai == EAI_MEMORY ? NET_BUSY : NET_REFUSED);
    int why = NET_REFUSED;
    for (struct addrinfo *ai = found; ai; ai = ai->ai_next) {
        int fd = socket(ai->ai_family, SOCK_STREAM, 0);
        if (fd < 0) {
            why = errno == EMFILE || errno == ENFILE || errno == ENOBUFS || errno == ENOMEM ? NET_BUSY : NET_REFUSED;
            continue;
        }
        nonblocking(fd);
        int r = connect(fd, ai->ai_addr, ai->ai_addrlen);
        if (r != 0 && errno == EINPROGRESS) {
            if (!net_wait(fd, POLLOUT, deadline - now_ms())) {
                close(fd);
                why = NET_TIMEOUT;
                break;
            }
            int err = 0;
            socklen_t len = sizeof err;
            getsockopt(fd, SOL_SOCKET, SO_ERROR, &err, &len);
            r = err == 0 ? 0 : -1;
        }
        if (r == 0) {
            freeaddrinfo(found);
            return adopt(fd);
        }
        close(fd);
    }
    freeaddrinfo(found);
    return failed_conn(why);
}

static MoValue net_connect(MoValue host, uint16_t port, int64_t ms) { return conn_result(net_connect_conn(host, port, ms)); }

/* A call past its deadline leaves the listener listening. */
static int64_t net_accept_conn(Listener *l, int64_t ms) {
    if (l->accepting || l->served) return failed_conn(NET_BUSY);
    l->accepting = true;
    int64_t deadline = now_ms() + max0(ms);
    int64_t out;
    for (;;) {
        int fd = accept(l->fd, NULL, NULL);
        if (fd >= 0) {
            out = adopt(fd);
            for (size_t i = 0; i < nlisteners; i++) {
                if (listeners[i] == l) conns[out]->listener = (uint32_t)i;
            }
            break;
        }
        if (errno == EINTR || errno == ECONNABORTED) continue;
        if (errno != EAGAIN && errno != EWOULDBLOCK) {
            out = failed_conn(errno == EINVAL ? NET_CLOSED : NET_BUSY);
            break;
        }
        int64_t left = deadline - now_ms();
        if (left <= 0 || !net_wait(l->fd, POLLIN, left)) {
            out = failed_conn(NET_TIMEOUT);
            break;
        }
    }
    l->accepting = false;
    return out;
}

static MoValue net_accept(Listener *l, int64_t ms) { return conn_result(net_accept_conn(l, ms)); }

/* `conn.read_line`: the next line, None at the end of the stream, or why not. A call past its
 * deadline keeps the bytes of an unfinished line for the next call. */
enum { FILL_GOT, FILL_EOF, FILL_TIMEOUT, FILL_CLOSED, FILL_FULL };

/* Reads what arrives next on `c` into its buffer, waiting at most `ms`. The buffer is `initial`
 * bytes at the first read and grows to at most `cap`; FILL_FULL when it holds `cap` bytes not
 * given out. A read past its deadline keeps what was buffered; a stream that broke closes the
 * connection. */
static int net_fill(Conn *c, int64_t ms, size_t initial, size_t cap) {
    if (c->start > 0) {
        memmove(c->buf, c->buf + c->start, c->end - c->start);
        c->end -= c->start;
        c->start = 0;
    }
    if (c->end == c->cap) {
        if (c->cap >= cap) return FILL_FULL;
        size_t size = c->cap == 0 ? initial : 2 * c->cap < cap ? 2 * c->cap : cap;
        c->buf = xrealloc(c->buf, size);
        c->cap = size;
    }
    int64_t deadline = now_ms() + max0(ms);
    c->reading = true;
    ssize_t got;
    bool in_time = true;
    for (;;) {
        got = read(c->fd, c->buf + c->end, c->cap - c->end);
        if (got >= 0) break;
        if (errno == EINTR) continue;
        if (errno != EAGAIN && errno != EWOULDBLOCK) break;
        in_time = net_wait(c->fd, POLLIN, deadline - now_ms());
        if (!in_time || c->closed) break;
    }
    c->reading = false;
    if (c->closed) {
        net_release(c);
        return FILL_CLOSED;
    }
    if (!in_time) return FILL_TIMEOUT;
    if (got < 0) {
        net_close(c);
        return FILL_CLOSED;
    }
    if (got == 0) {
        c->eof = true;
        return FILL_EOF;
    }
    c->end += (size_t)got;
    return FILL_GOT;
}

static MoValue net_read_line(Conn *c, int64_t ms) {
    if (c->closed) return net_fail(NET_CLOSED);
    if (c->reading || c->lining) return net_fail(NET_BUSY);
    int64_t t0 = now_ms();
    for (;;) {
        Scan s = scan_line(c->buf ? c->buf + c->start : "", c->end - c->start, c->eof, &c->skipping);
        c->start += s.taken;
        MoValue out;
        bool given = line_result(s, &out);
        if (c->start == c->end) c->start = c->end = 0;
        if (given) return out;
        int64_t left = ms - (now_ms() - t0);
        if (left <= 0) return net_fail(NET_TIMEOUT);
        /* A line too long is taken before the buffer fills. */
        switch (net_fill(c, left, BUFFER_INITIAL, 2 * LINE_LIMIT)) {
        case FILL_TIMEOUT: return net_fail(NET_TIMEOUT);
        case FILL_CLOSED: return net_fail(NET_CLOSED);
        default: break;
        }
    }
}

/* All of `text` on `c`: -1, or why not. A call past its deadline closes the connection, since part
 * of the text may have gone. */
static int net_write_all(Conn *c, const char *text, size_t n, int64_t ms) {
    if (c->closed) return NET_CLOSED;
    if (c->writing) return NET_BUSY;
    c->writing = true;
    int64_t deadline = now_ms() + max0(ms);
    size_t done = 0;
    int failed = -1;
    while (done < n) {
        ssize_t w = write(c->fd, text + done, n - done);
        if (w > 0) {
            done += (size_t)w;
            continue;
        }
        if (w < 0 && errno == EINTR) continue;
        if (w < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
            int64_t left = deadline - now_ms();
            if (left <= 0 || !net_wait(c->fd, POLLOUT, left)) {
                failed = NET_TIMEOUT;
                break;
            }
            if (c->closed) break;
            continue;
        }
        failed = NET_CLOSED;
        break;
    }
    c->writing = false;
    if (c->closed) {
        net_release(c);
        return NET_CLOSED;
    }
    if (failed >= 0) {
        net_close(c);
        return failed;
    }
    return -1;
}

/* `conn.write(text)`: all of the text, or why not. */
static MoValue net_write(Conn *c, MoValue text, int64_t ms) {
    int f = net_write_all(c, text.as.s, text.aux, ms);
    return f >= 0 ? net_fail(f) : ok_none();
}

/* ---- Net.fixture(): one network in memory per test (net.zig, Fixture). What one end writes
 * waits for the other end to read it, and a closed end is the end of the stream for the other.
 * Nothing happens while a simulated call waits, so a call with nothing to take waits its whole
 * deadline and is Timeout, as a real one would be. */

typedef struct { uint16_t port; uint32_t *backlog; size_t nbacklog, capbacklog, head; bool served; } FixListener;
typedef struct {
    /* The other end of the connection. */
    uint32_t peer;
    /* What the peer wrote that this end has not read: inbound[start..len]. */
    char *inbound;
    size_t len, cap, start;
    bool closed, skipping;
    /* The listener whose backlog it went into, or UINT32_MAX for a client's end. */
    uint32_t listener;
    /* lines gave its reading to the runtime (sources): a read_line on it is Busy. */
    bool lining;
} FixConn;

static FixListener *fix_listeners;
static size_t nfix_listeners, capfix_listeners;
static FixConn *fix_conns;
static size_t nfix_conns, capfix_conns;
/* The port listen(0) tries next. */
static uint16_t fix_next_port = 49152;

static void reset_net_fixture(void) {
    for (size_t i = 0; i < nfix_listeners; i++) free(fix_listeners[i].backlog);
    for (size_t i = 0; i < nfix_conns; i++) free(fix_conns[i].inbound);
    for (size_t i = 0; i < nfix_exchanges; i++) exchange_forget(&fix_exchanges[i]);
    nfix_listeners = nfix_conns = nfix_exchanges = 0;
    fix_next_port = 49152;
}

static bool fix_port_taken(uint16_t port) {
    for (size_t i = 0; i < nfix_listeners; i++) {
        if (fix_listeners[i].port == port) return true;
    }
    return false;
}

static MoValue fix_listen(uint16_t port) {
    if (port == 0) {
        while (fix_port_taken(fix_next_port)) fix_next_port++;
        port = fix_next_port;
    }
    if (fix_port_taken(port)) return net_fail(NET_BUSY);
    GROW_ARRAY(fix_listeners, nfix_listeners, capfix_listeners);
    fix_listeners[nfix_listeners] = (FixListener){port, NULL, 0, 0, 0};
    return ok_of(mo_cap(MO_CAP_LISTENER, (uint32_t)nfix_listeners++, 0));
}

static MoValue fix_connect(uint16_t port) {
    FixListener *l = NULL;
    for (size_t i = 0; i < nfix_listeners && !l; i++) {
        if (fix_listeners[i].port == port) l = &fix_listeners[i];
    }
    if (!l) return net_fail(NET_REFUSED);
    uint32_t client = (uint32_t)nfix_conns;
    GROW_ARRAY(fix_conns, nfix_conns, capfix_conns);
    fix_conns[nfix_conns++] = (FixConn){client + 1, NULL, 0, 0, 0, false, false, UINT32_MAX};
    GROW_ARRAY(fix_conns, nfix_conns, capfix_conns);
    fix_conns[nfix_conns++] = (FixConn){client, NULL, 0, 0, 0, false, false, (uint32_t)(l - fix_listeners)};
    GROW_ARRAY(l->backlog, l->nbacklog, l->capbacklog);
    l->backlog[l->nbacklog++] = client + 1;
    return ok_of(mo_cap(MO_CAP_CONN, client, 0));
}

static MoValue fix_accept(uint32_t h, int64_t within) {
    FixListener *l = &fix_listeners[h];
    if (l->served) return net_fail(NET_BUSY);
    if (l->head == l->nbacklog) {
        sim_waited += within;
        return net_fail(NET_TIMEOUT);
    }
    l->head++;
    return ok_of(mo_cap(MO_CAP_CONN, l->backlog[l->head - 1], 0));
}

static MoValue fix_read_line(uint32_t h, int64_t within) {
    FixConn *c = &fix_conns[h];
    if (c->closed) return net_fail(NET_CLOSED);
    if (c->lining) return net_fail(NET_BUSY);
    Scan s = scan_line(c->inbound + c->start, c->len - c->start, fix_conns[c->peer].closed, &c->skipping);
    c->start += s.taken;
    MoValue out;
    if (!line_result(s, &out)) {
        sim_waited += within;
        return net_fail(NET_TIMEOUT);
    }
    if (c->start == c->len) c->start = c->len = 0;
    return out;
}

/* What one end writes, waiting for connection `to` to read it. */
static void fix_append(uint32_t to, const char *text, size_t n) {
    FixConn *c = &fix_conns[to];
    while (c->len + n > c->cap) {
        c->cap = c->cap ? 2 * c->cap : 256;
        c->inbound = xrealloc(c->inbound, c->cap);
    }
    if (n) memcpy(c->inbound + c->len, text, n);
    c->len += n;
}

static MoValue fix_write(uint32_t h, MoValue text) {
    FixConn *c = &fix_conns[h];
    FixConn *peer = &fix_conns[c->peer];
    if (c->closed) return net_fail(NET_CLOSED);
    if (peer->closed) {
        c->closed = true;
        return net_fail(NET_CLOSED);
    }
    fix_append(c->peer, text.as.s, text.aux);
    return ok_none();
}

/* ---- the rows: real sockets under main, the fixture's in a test */

MO_ROW(mo_r_Net_listen) {
    (void)kind;
    return server_mode ? net_listen((uint16_t)a[1].as.u) : fix_listen((uint16_t)a[1].as.u);
}

MO_ROW(mo_r_Net_connect) {
    (void)kind;
    return server_mode ? net_connect(a[1], (uint16_t)a[2].as.u, a[3].as.i) : fix_connect((uint16_t)a[2].as.u);
}

MO_ROW(mo_r_Listener_accept) {
    (void)kind;
    wait_on((Wait){true, mo_cap_handle(a[0]), "Listener.accept"});
    MoValue out = server_mode ? net_accept(listeners[mo_cap_handle(a[0])], a[1].as.i) : fix_accept(mo_cap_handle(a[0]), a[1].as.i);
    end_wait();
    return out;
}

MO_ROW(mo_r_Listener_port) {
    (void)kind;
    return mo_u64(server_mode ? listeners[mo_cap_handle(a[0])]->port : fix_listeners[mo_cap_handle(a[0])].port);
}

MO_ROW(mo_r_Conn_read_line) {
    (void)kind;
    wait_on((Wait){false, mo_cap_handle(a[0]), "Conn.read_line"});
    MoValue out = server_mode ? net_read_line(conns[mo_cap_handle(a[0])], a[1].as.i) : fix_read_line(mo_cap_handle(a[0]), a[1].as.i);
    end_wait();
    return out;
}

MO_ROW(mo_r_Conn_write) {
    (void)kind;
    return server_mode ? net_write(conns[mo_cap_handle(a[0])], a[1], a[2].as.i) : fix_write(mo_cap_handle(a[0]), a[1]);
}

MO_ROW(mo_r_Conn_close) {
    (void)kind;
    if (server_mode) net_close(conns[mo_cap_handle(a[0])]);
    else fix_conns[mo_cap_handle(a[0])].closed = true;
    return MO_NONE_V;
}

MO_ROW(mo_r_Net_fixture) { (void)a; (void)kind; return mo_cap(MO_CAP_NET, 0, 0); }

/* ==== Http: HTTP/1.1 over Net, real sockets under main and Net.fixture()'s network in a test (http.zig)
 * An HttpListener is a Listener, its handle the same index. One request per connection: accept reads
 * one whole request, reply writes the one response and closes the connection, and send connects,
 * writes one request, and reads the response to the end. */

/* The most a request line, the header lines together, or a body may be. */
#define HTTP_LIMIT ((size_t)1 << 20)
/* A connection's buffer at its first read, and at most: a message at every limit. */
#define HTTP_BUFFER_INITIAL ((size_t)16 << 10)
#define HTTP_BUFFER_CAP (3 * HTTP_LIMIT + 8)

/* HttpError's variants. */
enum { HTTP_TIMEOUT, HTTP_REFUSED, HTTP_CLOSED, HTTP_BUSY, HTTP_MALFORMED, HTTP_TOO_LARGE, HTTP_UNSUPPORTED };

static MoValue http_fail(int f) {
    static const uint32_t names[] = {MO_N_TIMEOUT, MO_N_REFUSED, MO_N_CLOSED, MO_N_BUSY, MO_N_MALFORMED, MO_N_TOO_LARGE, MO_N_UNSUPPORTED};
    return error_of(mo_variant(names[f], 0, NULL));
}

static int http_from_net(int f) {
    switch (f) {
    case NET_TIMEOUT: return HTTP_TIMEOUT;
    case NET_REFUSED: return HTTP_REFUSED;
    case NET_BUSY: return HTTP_BUSY;
    default: return HTTP_CLOSED;
    }
}

static bool http_digit(char c) { return c >= '0' && c <= '9'; }

static unsigned char http_lower(unsigned char c) { return c >= 'A' && c <= 'Z' ? (unsigned char)(c + 32) : c; }

static bool http_same(const char *a, size_t n, const char *name) {
    if (strlen(name) != n) return false;
    for (size_t i = 0; i < n; i++) {
        if (http_lower((unsigned char)a[i]) != (unsigned char)name[i]) return false;
    }
    return true;
}

/* A token (RFC 9110): a method, or a header name. */
static bool http_token(const char *s, size_t n) {
    if (n == 0) return false;
    for (size_t i = 0; i < n; i++) {
        unsigned char ch = (unsigned char)s[i];
        bool alnum = (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9');
        if (!alnum && (ch == 0 || !strchr("!#$%&'*+-.^_`|~", ch))) return false;
    }
    return true;
}

/* A header value: no control character but a tab. */
static bool http_value_ok(const char *s, size_t n) {
    for (size_t i = 0; i < n; i++) {
        unsigned char ch = (unsigned char)s[i];
        if ((ch < 0x20 && ch != '\t') || ch == 0x7f) return false;
    }
    return true;
}

/* HTTP/1.0 or HTTP/1.1: -1; another HTTP/d.d is Unsupported, anything else Malformed. */
static int http_version(const char *s, size_t n) {
    if (n != 8 || memcmp(s, "HTTP/", 5) != 0 || !http_digit(s[5]) || s[6] != '.' || !http_digit(s[7])) return HTTP_MALFORMED;
    if (memcmp(s, "HTTP/1.1", 8) == 0 || memcmp(s, "HTTP/1.0", 8) == 0) return -1;
    return HTTP_UNSUPPORTED;
}

/* A target in origin form: a /, then no space or control character. */
static bool http_target(const char *s, size_t n) {
    if (n == 0 || s[0] != '/') return false;
    for (size_t i = 0; i < n; i++) {
        if ((unsigned char)s[i] <= 0x20 || s[i] == 0x7f) return false;
    }
    return true;
}

static int http_hex(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

/* Whether every % in s begins two hex digits. */
static bool http_decodable(const char *s, size_t n) {
    for (size_t i = 0; i < n; i++) {
        if (s[i] != '%') continue;
        if (i + 2 >= n || http_hex(s[i + 1]) < 0 || http_hex(s[i + 2]) < 0) return false;
        i += 2;
    }
    return true;
}

typedef struct { const char *method; size_t method_len; const char *target; size_t target_len; } HttpRequestLine;

/* -1, or why the line is not a request line. */
static int http_request_line(const char *line, size_t n, HttpRequestLine *out) {
    const char *sp1 = memchr(line, ' ', n);
    if (!sp1) return HTTP_MALFORMED;
    const char *rest = sp1 + 1;
    size_t rest_len = n - (size_t)(rest - line);
    const char *sp2 = memchr(rest, ' ', rest_len);
    if (!sp2) return HTTP_MALFORMED;
    out->method = line;
    out->method_len = (size_t)(sp1 - line);
    out->target = rest;
    out->target_len = (size_t)(sp2 - rest);
    if (!http_token(out->method, out->method_len) || !http_target(out->target, out->target_len)) return HTTP_MALFORMED;
    int v = http_version(sp2 + 1, rest_len - out->target_len - 1);
    if (v >= 0) return v;
    const char *q = memchr(out->target, '?', out->target_len);
    if (q) {
        const char *p = q + 1, *end = out->target + out->target_len;
        for (;;) {
            const char *amp = memchr(p, '&', (size_t)(end - p));
            const char *stop = amp ? amp : end;
            if (!http_decodable(p, (size_t)(stop - p))) return HTTP_MALFORMED;
            if (!amp) break;
            p = amp + 1;
        }
    }
    return -1;
}

/* -1 and the status, 100 to 599, or why the line is not a status line. */
static int http_status_line(const char *line, size_t n, uint16_t *status) {
    const char *sp = memchr(line, ' ', n);
    if (!sp) return HTTP_MALFORMED;
    int v = http_version(line, (size_t)(sp - line));
    if (v >= 0) return v;
    const char *rest = sp + 1;
    size_t rest_len = n - (size_t)(rest - line);
    if (rest_len < 3 || (rest_len > 3 && rest[3] != ' ')) return HTTP_MALFORMED;
    if (!http_digit(rest[0]) || !http_digit(rest[1]) || !http_digit(rest[2])) return HTTP_MALFORMED;
    unsigned s = (unsigned)((rest[0] - '0') * 100 + (rest[1] - '0') * 10 + (rest[2] - '0'));
    if (s < 100 || s > 599) return HTTP_MALFORMED;
    *status = (uint16_t)s;
    return -1;
}

typedef struct { const char *name; size_t name_len; const char *value; size_t value_len; } HttpField;

static bool http_field(const char *line, size_t n, HttpField *f) {
    const char *colon = memchr(line, ':', n);
    if (!colon) return false;
    const char *v = colon + 1, *end = line + n;
    while (v < end && (*v == ' ' || *v == '\t')) v++;
    while (end > v && (end[-1] == ' ' || end[-1] == '\t')) end--;
    f->name = line;
    f->name_len = (size_t)(colon - line);
    f->value = v;
    f->value_len = (size_t)(end - v);
    return http_token(f->name, f->name_len) && http_value_ok(f->value, f->value_len);
}

enum { PARSE_MORE, PARSE_FAILED, PARSE_WHOLE };

/* A whole message in the bytes of a stream: its start line, its header lines (each with its line
 * end), its body, and the bytes it takes; or not yet, or why not. */
typedef struct {
    int what, failed;
    const char *start;
    size_t start_len;
    const char *headers;
    size_t headers_len;
    const char *body;
    size_t body_len, len;
} HttpParsed;

static HttpParsed parse_failed(int f) { return (HttpParsed){PARSE_FAILED, f, NULL, 0, NULL, 0, NULL, 0, 0}; }
static HttpParsed parse_more(bool eof) { return eof ? parse_failed(HTTP_CLOSED) : (HttpParsed){PARSE_MORE, 0, NULL, 0, NULL, 0, NULL, 0, 0}; }

/* What the bytes of a stream so far hold (http.zig, parse). `eof`: nothing follows. A response with
 * no content-length runs to the end of the stream; a request with none has no body. */
static HttpParsed http_parse(const char *bytes, size_t n, bool eof, bool response) {
    const char *nl = n ? memchr(bytes, '\n', n) : NULL;
    if (!nl) {
        if (n > HTTP_LIMIT + 1) return parse_failed(HTTP_TOO_LARGE);
        return parse_more(eof);
    }
    size_t start_end = (size_t)(nl - bytes);
    size_t start_len = without_cr(bytes, start_end);
    if (start_len > HTTP_LIMIT) return parse_failed(HTTP_TOO_LARGE);
    int f;
    if (response) {
        uint16_t status;
        f = http_status_line(bytes, start_len, &status);
    } else {
        HttpRequestLine line;
        f = http_request_line(bytes, start_len, &line);
    }
    if (f >= 0) return parse_failed(f);
    size_t headers_start = start_end + 1, at = headers_start, headers_end;
    bool has_length = false;
    uint64_t length = 0;
    for (;;) {
        const char *rest = bytes + at;
        size_t rest_len = n - at;
        const char *k = rest_len ? memchr(rest, '\n', rest_len) : NULL;
        if (!k) {
            if (at - headers_start + rest_len > HTTP_LIMIT) return parse_failed(HTTP_TOO_LARGE);
            return parse_more(eof);
        }
        size_t line_len = without_cr(rest, (size_t)(k - rest));
        size_t line_start = at;
        at += (size_t)(k - rest) + 1;
        if (line_len == 0) {
            headers_end = line_start;
            break;
        }
        if (at - headers_start > HTTP_LIMIT) return parse_failed(HTTP_TOO_LARGE);
        HttpField fl;
        if (!http_field(rest, line_len, &fl)) return parse_failed(HTTP_MALFORMED);
        if (http_same(fl.name, fl.name_len, "transfer-encoding")) return parse_failed(HTTP_UNSUPPORTED);
        if (http_same(fl.name, fl.name_len, "content-length")) {
            if (fl.value_len == 0 || fl.value_len > 19) return parse_failed(fl.value_len == 0 ? HTTP_MALFORMED : HTTP_TOO_LARGE);
            uint64_t v = 0;
            for (size_t i = 0; i < fl.value_len; i++) {
                if (!http_digit(fl.value[i])) return parse_failed(HTTP_MALFORMED);
                v = v * 10 + (uint64_t)(fl.value[i] - '0');
            }
            if (has_length && v != length) return parse_failed(HTTP_MALFORMED);
            has_length = true;
            length = v;
        }
    }
    HttpParsed p = {PARSE_WHOLE, 0, bytes, start_len, bytes + headers_start, headers_end - headers_start, bytes + at, 0, at};
    if (has_length) {
        if (length > HTTP_LIMIT) return parse_failed(HTTP_TOO_LARGE);
        if (n - at < length) return parse_more(eof);
        p.body_len = (size_t)length;
        p.len = at + (size_t)length;
        return p;
    }
    if (!response) return p;
    if (n - at > HTTP_LIMIT) return parse_failed(HTTP_TOO_LARGE);
    if (!eof) return parse_more(false);
    p.body_len = n - at;
    p.len = n;
    return p;
}

/* Sets `key` in `entries` (a map's, key then value), or when it is there already joins `value` to
 * its value with ", " (a repeated header) or replaces it (a repeated query key). */
static void http_set_entry(Values *entries, MoValue key, MoValue value, bool join) {
    for (size_t i = 0; i < entries->n; i += 2) {
        MoValue k = entries->xs[i];
        if (k.aux != key.aux || (key.aux && memcmp(k.as.s, key.as.s, key.aux) != 0)) continue;
        if (join) {
            MoValue old = entries->xs[i + 1];
            size_t len = (size_t)old.aux + 2 + value.aux;
            char *p = mo_alloc_bytes(len);
            if (old.aux) memcpy(p, old.as.s, old.aux);
            memcpy(p + old.aux, ", ", 2);
            if (value.aux) memcpy(p + old.aux + 2, value.as.s, value.aux);
            entries->xs[i + 1] = mo_str(p, (uint32_t)len);
        } else {
            entries->xs[i + 1] = value;
        }
        return;
    }
    values_push(entries, key);
    values_push(entries, value);
}

static MoValue http_map(Values *entries) {
    MoValue m = map_value(MO_MAP, entries->n ? map_of(dupe_values(entries->xs, entries->n), entries->n, 2) : NULL);
    free(entries->xs);
    return m;
}

/* The header lines as a map, names lower-cased. */
static MoValue http_headers_value(const char *headers, size_t n) {
    Values entries = {0};
    size_t at = 0;
    while (at < n) {
        const char *nl = memchr(headers + at, '\n', n - at);
        HttpField f;
        http_field(headers + at, without_cr(headers + at, (size_t)(nl - (headers + at))), &f);
        char *name = mo_alloc_bytes(f.name_len);
        for (size_t i = 0; i < f.name_len; i++) name[i] = (char)http_lower((unsigned char)f.name[i]);
        http_set_entry(&entries, mo_str(name, (uint32_t)f.name_len), heap_string(f.value, f.value_len), true);
        at = (size_t)(nl - headers) + 1;
    }
    return http_map(&entries);
}

/* A query key or value as it was before it was sent: + is a space, %XX its byte. */
static MoValue http_decode(const char *s, size_t n) {
    char *out = mo_alloc_bytes(n);
    size_t k = 0;
    for (size_t i = 0; i < n; i++) {
        if (s[i] == '+') {
            out[k++] = ' ';
        } else if (s[i] == '%') {
            out[k++] = (char)(http_hex(s[i + 1]) * 16 + http_hex(s[i + 2]));
            i += 2;
        } else {
            out[k++] = s[i];
        }
    }
    return mo_str(out, (uint32_t)k);
}

/* The Request a whole request's bytes spell. */
static MoValue http_request_value(const char *bytes, size_t n) {
    HttpParsed m = http_parse(bytes, n, true, false);
    HttpRequestLine line;
    http_request_line(m.start, m.start_len, &line);
    const char *q = memchr(line.target, '?', line.target_len);
    Values query = {0};
    if (q) {
        const char *p = q + 1, *end = line.target + line.target_len;
        for (;;) {
            const char *amp = memchr(p, '&', (size_t)(end - p));
            const char *stop = amp ? amp : end;
            if (stop > p) {
                const char *eq = memchr(p, '=', (size_t)(stop - p));
                MoValue key = http_decode(p, (size_t)((eq ? eq : stop) - p));
                MoValue value = eq ? http_decode(eq + 1, (size_t)(stop - eq - 1)) : mo_str("", 0);
                http_set_entry(&query, key, value, false);
            }
            if (!amp) break;
            p = amp + 1;
        }
    }
    MoValue fields[5];
    fields[0] = heap_string(line.method, line.method_len);
    fields[1] = heap_string(line.target, q ? (size_t)(q - line.target) : line.target_len);
    fields[2] = http_map(&query);
    fields[3] = http_headers_value(m.headers, m.headers_len);
    fields[4] = heap_string(m.body, m.body_len);
    return mo_record(mo_request_decl, 5, fields);
}

/* The Response a whole response's bytes spell. */
static MoValue http_response_value(const char *bytes, size_t n) {
    HttpParsed m = http_parse(bytes, n, true, true);
    uint16_t status = 0;
    http_status_line(m.start, m.start_len, &status);
    MoValue fields[3];
    fields[0] = mo_i64(status);
    fields[1] = http_headers_value(m.headers, m.headers_len);
    fields[2] = heap_string(m.body, m.body_len);
    return mo_record(mo_response_decl, 3, fields);
}

/* The reason phrase a status line gives a status; empty for one not listed. */
static const char *http_reason(int64_t status) {
    switch (status) {
    case 100: return "Continue";
    case 101: return "Switching Protocols";
    case 200: return "OK";
    case 201: return "Created";
    case 202: return "Accepted";
    case 204: return "No Content";
    case 301: return "Moved Permanently";
    case 302: return "Found";
    case 303: return "See Other";
    case 304: return "Not Modified";
    case 307: return "Temporary Redirect";
    case 308: return "Permanent Redirect";
    case 400: return "Bad Request";
    case 401: return "Unauthorized";
    case 403: return "Forbidden";
    case 404: return "Not Found";
    case 405: return "Method Not Allowed";
    case 409: return "Conflict";
    case 411: return "Length Required";
    case 413: return "Content Too Large";
    case 415: return "Unsupported Media Type";
    case 422: return "Unprocessable Content";
    case 429: return "Too Many Requests";
    case 500: return "Internal Server Error";
    case 501: return "Not Implemented";
    case 502: return "Bad Gateway";
    case 503: return "Service Unavailable";
    case 504: return "Gateway Timeout";
    default: return "";
    }
}

/* The program's headers as `name: value`, but content-length and connection, which the runtime
 * writes; false when a name is not a token or a value holds a control character. */
static bool http_write_headers(Buf *b, MoValue headers) {
    MoMap *m = headers.as.m;
    for (uint32_t i = 0; m && i + 1 < m->len; i += 2) {
        MoValue name = m->entries[i], value = m->entries[i + 1];
        if (!http_token(name.as.s, name.aux) || !http_value_ok(value.as.s, value.aux)) return false;
        if (http_same(name.as.s, name.aux, "content-length") || http_same(name.as.s, name.aux, "connection")) continue;
        buf_put(b, name.as.s, name.aux);
        buf_str(b, ": ");
        buf_put(b, value.as.s, value.aux);
        buf_str(b, "\r\n");
    }
    return true;
}

static bool http_has_header(MoValue headers, const char *name) {
    MoMap *m = headers.as.m;
    for (uint32_t i = 0; m && i + 1 < m->len; i += 2) {
        if (http_same(m->entries[i].as.s, m->entries[i].aux, name)) return true;
    }
    return false;
}

/* A Response as it goes on the wire; false when it is Malformed. */
static bool http_response_bytes(Buf *b, MoValue response) {
    const MoValue *f = response.as.xs;
    int64_t status = f[0].as.i;
    if (status < 100 || status > 599) return false;
    buf_printf(b, "HTTP/1.1 %lld %s\r\n", (long long)status, http_reason(status));
    if (!http_write_headers(b, f[1])) return false;
    buf_printf(b, "content-length: %u\r\nconnection: close\r\n\r\n", (unsigned)f[2].aux);
    buf_put(b, f[2].as.s, f[2].aux);
    return true;
}

/* `s` as a query key or value is sent: every byte but a letter, a digit, and -._~ as %XX. */
static void http_encode(Buf *b, MoValue s) {
    for (uint32_t i = 0; i < s.aux; i++) {
        unsigned char ch = (unsigned char)s.as.s[i];
        bool plain = (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9') || ch == '-' || ch == '.' || ch == '_' || ch == '~';
        if (plain) buf_byte(b, (char)ch);
        else buf_printf(b, "%%%02X", ch);
    }
}

/* A Request to `host` at `port` as it goes on the wire; false when it is Malformed. */
static bool http_request_bytes(Buf *b, MoValue request, MoValue host, int64_t port) {
    const MoValue *f = request.as.xs;
    MoValue method = f[0], path = f[1];
    if (!http_token(method.as.s, method.aux) || !http_target(path.as.s, path.aux)) return false;
    buf_put(b, method.as.s, method.aux);
    buf_byte(b, ' ');
    buf_put(b, path.as.s, path.aux);
    MoMap *q = f[2].as.m;
    bool has_q = memchr(path.as.s, '?', path.aux) != NULL;
    for (uint32_t i = 0; q && i + 1 < q->len; i += 2) {
        buf_byte(b, i > 0 || has_q ? '&' : '?');
        http_encode(b, q->entries[i]);
        buf_byte(b, '=');
        http_encode(b, q->entries[i + 1]);
    }
    buf_str(b, " HTTP/1.1\r\n");
    if (!http_has_header(f[3], "host")) {
        buf_str(b, "host: ");
        buf_put(b, host.as.s, host.aux);
        buf_printf(b, ":%lld\r\n", (long long)port);
    }
    if (!http_write_headers(b, f[3])) return false;
    buf_printf(b, "content-length: %u\r\nconnection: close\r\n\r\n", (unsigned)f[4].aux);
    buf_put(b, f[4].as.s, f[4].aux);
    return true;
}

/* The response a request that is not HTTP gets before its connection closes. */
static const char *http_refusal(int f) {
    switch (f) {
    case HTTP_MALFORMED: return "HTTP/1.1 400 Bad Request\r\ncontent-length: 0\r\nconnection: close\r\n\r\n";
    case HTTP_TOO_LARGE: return "HTTP/1.1 413 Content Too Large\r\ncontent-length: 0\r\nconnection: close\r\n\r\n";
    case HTTP_UNSUPPORTED: return "HTTP/1.1 501 Not Implemented\r\ncontent-length: 0\r\nconnection: close\r\n\r\n";
    default: return NULL;
    }
}

static MoValue exchange_cap(HttpExchange **table, size_t *n, size_t *cap, uint32_t conn, const char *bytes, size_t len) {
    char *copy = xmalloc(len ? len : 1);
    memcpy(copy, bytes, len);
    GROW_ARRAY(*table, *n, *cap);
    (*table)[*n] = (HttpExchange){conn, copy, len, false};
    return ok_of(mo_cap(MO_CAP_EXCHANGE, (uint32_t)(*n)++, 0));
}

/* ---- real sockets */

/* One whole message from `c`, at most `ms`: -1 and the bytes it takes at the front of the buffer,
 * or why not. */
static int http_read_message(Conn *c, bool response, int64_t ms, size_t *len) {
    if (c->closed) return HTTP_CLOSED;
    if (c->reading) return HTTP_BUSY;
    int64_t t0 = now_ms();
    for (;;) {
        HttpParsed p = http_parse(c->buf ? c->buf + c->start : "", c->end - c->start, c->eof, response);
        if (p.what == PARSE_WHOLE) {
            *len = p.len;
            return -1;
        }
        if (p.what == PARSE_FAILED) return p.failed;
        int64_t left = ms - (now_ms() - t0);
        if (left <= 0) return HTTP_TIMEOUT;
        switch (net_fill(c, left, HTTP_BUFFER_INITIAL, HTTP_BUFFER_CAP)) {
        case FILL_TIMEOUT: return HTTP_TIMEOUT;
        case FILL_CLOSED: return HTTP_CLOSED;
        case FILL_FULL: return HTTP_TOO_LARGE;
        default: break;
        }
    }
}

/* `listener.accept`: the next client's whole request, as an Exchange. A client whose request does
 * not arrive in time, or is not HTTP, is closed, and the listener goes on listening. */
static MoValue http_accept(Listener *l, int64_t ms) {
    int64_t t0 = now_ms();
    int64_t h = net_accept_conn(l, ms);
    if (h < 0) return http_fail(http_from_net((int)(-1 - h)));
    Conn *c = conns[h];
    size_t len = 0;
    int f = http_read_message(c, false, ms - (now_ms() - t0), &len);
    if (f < 0) {
        MoValue out = exchange_cap(&exchanges, &nexchanges, &capexchanges, (uint32_t)h, c->buf + c->start, len);
        c->start += len;
        return out;
    }
    const char *text = http_refusal(f);
    if (text) {
        int64_t left = ms - (now_ms() - t0);
        net_write_all(c, text, strlen(text), left > 100 ? left : 100);
    }
    net_close(c);
    return http_fail(f);
}

/* `exchange.reply(response)`: the response, then the connection closes. A second reply is Closed;
 * a Malformed response leaves the exchange unanswered. */
static MoValue http_reply(uint32_t handle, MoValue response, int64_t ms) {
    if (exchanges[handle].answered) return http_fail(HTTP_CLOSED);
    Buf b = {0};
    if (!http_response_bytes(&b, response)) {
        free(b.p);
        return http_fail(HTTP_MALFORMED);
    }
    Conn *c = conns[exchanges[handle].conn];
    int f = net_write_all(c, b.p, b.len, ms);
    free(b.p);
    if (f == NET_BUSY) return http_fail(HTTP_BUSY);
    exchange_forget(&exchanges[handle]);
    net_close(c);
    return f >= 0 ? http_fail(http_from_net(f)) : ok_none();
}

/* `http.send(request, host:, port:)`: connects, writes the request, and reads the whole response;
 * the connection closes either way. */
static MoValue http_send(MoValue request, MoValue host, int64_t port, int64_t ms) {
    Buf b = {0};
    if (!http_request_bytes(&b, request, host, port)) {
        free(b.p);
        return http_fail(HTTP_MALFORMED);
    }
    int64_t t0 = now_ms();
    int64_t h = net_connect_conn(host, (uint16_t)port, ms);
    if (h < 0) {
        free(b.p);
        return http_fail(http_from_net((int)(-1 - h)));
    }
    Conn *c = conns[h];
    MoValue out;
    int64_t left = ms - (now_ms() - t0);
    int f;
    size_t len = 0;
    if (left <= 0) {
        out = http_fail(HTTP_TIMEOUT);
    } else if ((f = net_write_all(c, b.p, b.len, left)) >= 0) {
        out = http_fail(http_from_net(f));
    } else if ((f = http_read_message(c, true, ms - (now_ms() - t0), &len)) >= 0) {
        out = http_fail(f);
    } else {
        out = ok_of(http_response_value(c->buf + c->start, len));
    }
    free(b.p);
    net_close(c);
    return out;
}

/* ---- Http.fixture(), on Net.fixture()'s network. As a Net fixture call, one with nothing to take
 * waits its whole deadline and is Timeout; a send delivers the processes' waiting messages a round
 * at a time while its response is not whole, and is Timeout when none is waiting. */

static MoValue fix_http_accept(uint32_t lh, int64_t within) {
    FixListener *l = &fix_listeners[lh];
    if (l->served) return http_fail(HTTP_BUSY);
    if (l->head == l->nbacklog) {
        sim_waited += within;
        return http_fail(HTTP_TIMEOUT);
    }
    uint32_t h = l->backlog[l->head++];
    FixConn *c = &fix_conns[h];
    bool peer_closed = fix_conns[c->peer].closed;
    HttpParsed p = http_parse(c->inbound ? c->inbound + c->start : "", c->len - c->start, peer_closed, false);
    if (p.what == PARSE_WHOLE) {
        MoValue out = exchange_cap(&fix_exchanges, &nfix_exchanges, &capfix_exchanges, h, c->inbound + c->start, p.len);
        fix_conns[h].start += p.len;
        return out;
    }
    if (p.what == PARSE_MORE) {
        sim_waited += within;
        c->closed = true;
        return http_fail(HTTP_TIMEOUT);
    }
    const char *text = http_refusal(p.failed);
    if (text && !peer_closed) fix_append(c->peer, text, strlen(text));
    fix_conns[h].closed = true;
    return http_fail(p.failed);
}

static MoValue fix_http_reply(uint32_t handle, MoValue response) {
    if (fix_exchanges[handle].answered) return http_fail(HTTP_CLOSED);
    Buf b = {0};
    if (!http_response_bytes(&b, response)) {
        free(b.p);
        return http_fail(HTTP_MALFORMED);
    }
    uint32_t h = fix_exchanges[handle].conn;
    exchange_forget(&fix_exchanges[handle]);
    uint32_t peer = fix_conns[h].peer;
    bool was_closed = fix_conns[h].closed || fix_conns[peer].closed;
    fix_conns[h].closed = true;
    if (!was_closed) fix_append(peer, b.p, b.len);
    free(b.p);
    return was_closed ? http_fail(HTTP_CLOSED) : ok_none();
}

static MoValue fix_http_send(MoValue request, MoValue host, int64_t port, int64_t within) {
    Buf b = {0};
    if (!http_request_bytes(&b, request, host, port)) {
        free(b.p);
        return http_fail(HTTP_MALFORMED);
    }
    FixListener *l = NULL;
    for (size_t i = 0; i < nfix_listeners && !l; i++) {
        if (fix_listeners[i].port == (uint16_t)port) l = &fix_listeners[i];
    }
    if (!l) {
        free(b.p);
        return http_fail(HTTP_REFUSED);
    }
    uint32_t client = (uint32_t)nfix_conns;
    GROW_ARRAY(fix_conns, nfix_conns, capfix_conns);
    fix_conns[nfix_conns++] = (FixConn){client + 1, NULL, 0, 0, 0, false, false, UINT32_MAX};
    GROW_ARRAY(fix_conns, nfix_conns, capfix_conns);
    fix_conns[nfix_conns++] = (FixConn){client, NULL, 0, 0, 0, false, false, (uint32_t)(l - fix_listeners)};
    GROW_ARRAY(l->backlog, l->nbacklog, l->capbacklog);
    l->backlog[l->nbacklog++] = client + 1;
    fix_append(client + 1, b.p, b.len);
    free(b.p);
    uint32_t delivered = 0;
    int64_t since = sim_waited;
    for (;;) {
        FixConn *c = &fix_conns[client];
        HttpParsed p = http_parse(c->inbound ? c->inbound + c->start : "", c->len - c->start, fix_conns[c->peer].closed, true);
        if (p.what == PARSE_WHOLE) {
            c->closed = true;
            return ok_of(http_response_value(c->inbound + c->start, p.len));
        }
        if (p.what == PARSE_FAILED) {
            c->closed = true;
            return http_fail(p.failed);
        }
        if (!deliver_round(&delivered)) {
            /* Nothing waits: simulated time passes to a delayed send due within the deadline, and the
             * rounds go on (step 24). */
            if (nlater > 0 && later[0].at <= since + within) {
                if (later[0].at > sim_waited) sim_waited = later[0].at;
                continue;
            }
            if (since + within > sim_waited) sim_waited = since + within;
            fix_conns[client].closed = true;
            return http_fail(HTTP_TIMEOUT);
        }
    }
}

/* ---- the rows: real sockets under main, the fixture's in a test */

static MoValue as_http_listener(MoValue listened) {
    if (!mo_is(listened, MO_N_OK)) return listened;
    return ok_of(mo_cap(MO_CAP_HTTP_LISTENER, mo_cap_handle(listened.as.xs[0]), 0));
}

MO_ROW(mo_r_Http_listen) { return as_http_listener(mo_r_Net_listen(a, kind)); }

MO_ROW(mo_r_HttpListener_port) { return mo_r_Listener_port(a, kind); }

MO_ROW(mo_r_HttpListener_accept) {
    (void)kind;
    uint32_t h = mo_cap_handle(a[0]);
    wait_on((Wait){true, h, "HttpListener.accept"});
    MoValue out = server_mode ? http_accept(listeners[h], a[1].as.i) : fix_http_accept(h, a[1].as.i);
    end_wait();
    return out;
}

MO_ROW(mo_r_Exchange_request) {
    (void)kind;
    const HttpExchange *e = server_mode ? &exchanges[mo_cap_handle(a[0])] : &fix_exchanges[mo_cap_handle(a[0])];
    if (e->answered) mo_fail(MO_R_OTHER, "request", "exchange.request after the exchange was answered: read the request before replying");
    return http_request_value(e->request, e->len);
}

MO_ROW(mo_r_Exchange_reply) {
    (void)kind;
    uint32_t h = mo_cap_handle(a[0]);
    return server_mode ? http_reply(h, a[1], a[2].as.i) : fix_http_reply(h, a[1]);
}

MO_ROW(mo_r_Http_send) {
    (void)kind;
    return server_mode ? http_send(a[1], a[2], a[3].as.i, a[4].as.i) : fix_http_send(a[1], a[2], a[3].as.i, a[4].as.i);
}

MO_ROW(mo_r_Http_fixture) { (void)a; (void)kind; return mo_cap(MO_CAP_HTTP, 0, 0); }

/* Whether connection `h` is open, and the listener that accepted it (sim.zig, connection). */
static bool connection_of(uint32_t h, uint32_t *listener) {
    if (server_mode) {
        *listener = conns[h]->listener;
        return !conns[h]->closed;
    }
    *listener = fix_conns[h].listener;
    return !fix_conns[h].closed;
}

static bool unanswered_conn(uint32_t exchange, uint32_t *conn) {
    const HttpExchange *e = server_mode ? &exchanges[exchange] : &fix_exchanges[exchange];
    if (e->answered) return false;
    *conn = e->conn;
    return true;
}

/* A process holding these arguments stopped: every Conn and Exchange among them closes. */
static void close_held(const MoValue *args, uint32_t n) {
    for (uint32_t i = 0; i < n; i++) {
        if (args[i].tag != MO_CAP) continue;
        uint32_t kind = mo_cap_kind(args[i]), h = mo_cap_handle(args[i]);
        if (kind == MO_CAP_EXCHANGE) h = server_mode ? exchanges[h].conn : fix_exchanges[h].conn;
        else if (kind != MO_CAP_CONN) continue;
        if (server_mode) net_close(conns[h]);
        else fix_conns[h].closed = true;
    }
}


/* ==== the loops the runtime owns (sources.zig) ============================================
 * listener.serve(into:, idle:), conn.lines(into:, idle:), and http_listener.serve(into:, idle:)
 * make the runtime accept or read from that call on and send each result to a process as a
 * message it declares. A source delivers while its target's mailbox holds fewer than its bound
 * less its headroom, and after stopping there starts again once the mailbox has drained to half
 * its bound. In a test every source is pumped at the start of each delivery round, in start
 * order; under main main's thread pumps only the sources that can do something (step 21): one just
 * added, one whose socket the poller reported ready, one paused at its target's bound, and one
 * whose idle time ran out, which a heap of deadlines finds. */

enum { SRC_SERVE, SRC_LINES, SRC_HTTP_SERVE, SRC_REQUEST };

typedef struct Source {
    int kind;
    /* The listener's handle (serve, http serve) or the connection's (lines, request). */
    uint32_t handle;
    uint32_t to;
    int64_t idle_ms;
    /* When the idle time last started: simulated in a test, the wall clock under main. */
    int64_t since;
    /* A serve source's last Idle in a test, so simulated time must pass before the next. */
    int64_t idled_at;
    bool done, paused;
    /* It serves the runtime surface (step 23), so it does not keep a program running. */
    bool background;
    /* A request source's http serve source, whose requests in flight it counts. */
    struct Source *parent;
    uint32_t inflight;
    /* Under main: what the poller reports when its socket is ready; its place in `sources`; in the
     * dirty list, in the paused list; its place in the deadline heap, or -1; a listener the system
     * refused a connection waits until retry_at. */
    Waiter waiter;
    size_t index;
    bool dirty, in_paused;
    ptrdiff_t timer;
    int64_t retry_at;
} Source;

static Source **sources;
static size_t nsources, capsources;
/* The sources in `sources` that serve the runtime surface. */
static size_t nbackground;
/* Under main: the sources to pump next, the ones paused at their target's bound, and a heap of
 * deadlines, earliest first, one entry per source at most. An entry may come before its source's
 * deadline, since `since` moves on; it is put back when it comes. */
typedef struct { int64_t at; Source *source; } Timer;
static Source **dirty;
static size_t ndirty, capdirty;
static Source **paused_sources;
static size_t npaused, cappaused;
static Timer *timers;
static size_t ntimers, captimers;
/* Under main, how long a listener waits before accepting again after the system refused a
 * connection for want of descriptors or memory. */
#define REFUSED_RETRY_MS 100

static uint32_t source_headroom(uint32_t bound) { return bound / 2 < 4 ? bound / 2 : 4; }

static void reset_sources(void) {
    for (size_t i = 0; i < nsources; i++) free(sources[i]);
    nsources = ndirty = npaused = ntimers = 0;
}

static void mark_dirty(Source *s) {
    if (s->dirty || s->done) return;
    s->dirty = true;
    GROW_ARRAY(dirty, ndirty, capdirty);
    dirty[ndirty++] = s;
}

static Source *source_add(int kind, uint32_t handle, uint32_t to, int64_t idle_ms, int64_t since, Source *parent) {
    Source *s = calloc(1, sizeof(Source));
    if (!s) out_of_memory();
    s->kind = kind;
    s->handle = handle;
    s->to = to;
    s->idle_ms = idle_ms;
    s->since = since;
    s->idled_at = INT64_MIN;
    s->parent = parent;
    s->background = is_hidden(to);
    s->waiter = (Waiter){-1, false, false, false, NO_PROCESS, NULL, -1};
    s->timer = -1;
    s->index = nsources;
    GROW_ARRAY(sources, nsources, capsources);
    sources[nsources++] = s;
    if (s->background) nbackground++;
    if (server_mode) mark_dirty(s);
    return s;
}

/* The row a source serves, as the events and the surface name it (sources.zig, rowLabel). */
static const char *source_label(int kind) {
    return kind == SRC_SERVE ? "Listener.serve" : kind == SRC_LINES ? "Conn.lines" : "HttpListener.serve";
}

/* A source stopped or started again at its target's bound (step 23). */
static void record_pause(const Source *s, uint8_t kind) {
    Event e = event_of(kind, s->to);
    e.name = source_label(s->kind);
    e.count = s->parent ? s->parent->inflight : s->inflight;
    record_event(e);
}

/* Whether `s` may deliver one more message to its target, counting `extra` more waiting. */
static bool source_room(Source *s, uint32_t extra) {
    const Proc *p = procs[s->to];
    uint32_t bound = mo_processes[p->process].mailbox;
    size_t waiting = queued(p) + extra;
    if (s->paused) {
        if (waiting > bound / 2) return false;
        s->paused = false;
        record_pause(s, EV_SOURCE_RESUMED);
    }
    if (waiting + source_headroom(bound) >= bound) {
        s->paused = true;
        record_pause(s, EV_SOURCE_PAUSED);
        return false;
    }
    return true;
}

/* A message from the runtime, packed under main. */
static void source_send(uint32_t to, uint32_t name, uint32_t n, const MoValue *fields) {
    MoValue message = mo_variant(name, n, fields);
    Parcel *parcel = packs ? pack(message) : NULL;
    enqueue(to, parcel ? parcel->value : message, parcel);
}

static uint32_t into_of(MoValue h) { return (uint32_t)h.as.i; }

MO_ROW(mo_r_Listener_serve) {
    (void)kind;
    uint32_t h = mo_cap_handle(a[0]);
    bool *served = server_mode ? &listeners[h]->served : &fix_listeners[h].served;
    if (*served) mo_fail(MO_R_OTHER, "Listener.serve", "this listener is already served: a listener is served into one process");
    *served = true;
    source_add(SRC_SERVE, h, into_of(a[1]), max0(a[2].as.i), server_mode ? now_ms() : sim_waited, NULL);
    return MO_NONE_V;
}

MO_ROW(mo_r_HttpListener_serve) {
    (void)kind;
    uint32_t h = mo_cap_handle(a[0]);
    bool *served = server_mode ? &listeners[h]->served : &fix_listeners[h].served;
    if (*served) mo_fail(MO_R_OTHER, "HttpListener.serve", "this listener is already served: a listener is served into one process");
    *served = true;
    source_add(SRC_HTTP_SERVE, h, into_of(a[1]), max0(a[2].as.i), server_mode ? now_ms() : sim_waited, NULL);
    return MO_NONE_V;
}

MO_ROW(mo_r_Conn_lines) {
    (void)kind;
    uint32_t h = mo_cap_handle(a[0]);
    bool *lining = server_mode ? &conns[h]->lining : &fix_conns[h].lining;
    if (*lining) mo_fail(MO_R_OTHER, "Conn.lines", "this connection's lines already go to a process: a connection is read into one process");
    *lining = true;
    source_add(SRC_LINES, h, into_of(a[1]), max0(a[2].as.i), server_mode ? now_ms() : sim_waited, NULL);
    return MO_NONE_V;
}

/* ---- in a test */

static bool serve_fixture(Source *s) {
    FixListener *l = &fix_listeners[s->handle];
    if (l->head == l->nbacklog) {
        if (sim_waited - s->since < s->idle_ms || sim_waited <= s->idled_at || !source_room(s, 0)) return false;
        source_send(s->to, MO_N_IDLE, 0, NULL);
        s->since = s->idled_at = sim_waited;
        return true;
    }
    if (!procs[s->to]->up || !source_room(s, 0)) return false;
    uint32_t h = l->backlog[l->head];
    if (s->kind == SRC_SERVE) {
        l->head++;
        s->since = sim_waited;
        MoValue conn = mo_cap(MO_CAP_CONN, h, 0);
        source_send(s->to, MO_N_ACCEPTED, 1, &conn);
        return true;
    }
    FixConn *c = &fix_conns[h];
    bool peer_closed = fix_conns[c->peer].closed;
    HttpParsed p = http_parse(c->inbound ? c->inbound + c->start : "", c->len - c->start, peer_closed, false);
    if (p.what == PARSE_WHOLE) {
        l->head++;
        s->since = sim_waited;
        MoValue ok = exchange_cap(&fix_exchanges, &nfix_exchanges, &capfix_exchanges, h, c->inbound + c->start, p.len);
        fix_conns[h].start += p.len;
        source_send(s->to, MO_N_ACCEPTED, 1, &ok.as.xs[0]);
        return true;
    }
    if (p.what == PARSE_MORE) {
        if (sim_waited - s->since < s->idle_ms) return false;
        l->head++;
        c->closed = true;
        return true;
    }
    l->head++;
    const char *text = http_refusal(p.failed);
    if (text && !peer_closed) fix_append(c->peer, text, strlen(text));
    fix_conns[h].closed = true;
    return true;
}

static bool lines_fixture(Source *s) {
    FixConn *c = &fix_conns[s->handle];
    if (c->closed) {
        s->done = true;
        return false;
    }
    if (!procs[s->to]->up) {
        c->closed = true;
        s->done = true;
        return false;
    }
    bool skipping = c->skipping;
    Scan sc = scan_line(c->inbound ? c->inbound + c->start : "", c->len - c->start, fix_conns[c->peer].closed, &skipping);
    if (sc.what == SCAN_MORE) {
        c->start += sc.taken;
        c->skipping = skipping;
        if (c->start == c->len) c->start = c->len = 0;
        if (sim_waited - s->since < s->idle_ms || !source_room(s, 0)) return false;
        source_send(s->to, MO_N_IDLE, 0, NULL);
        c->closed = true;
        s->done = true;
        return true;
    }
    if (!source_room(s, 0)) return false;
    if (sc.what == SCAN_LINE) {
        MoValue text = heap_string(sc.line, sc.len);
        source_send(s->to, MO_N_LINE, 1, &text);
    } else if (sc.what == SCAN_TOO_LONG) {
        source_send(s->to, MO_N_LINE_TOO_LONG, 0, NULL);
    } else {
        source_send(s->to, MO_N_CLOSED, 0, NULL);
        s->done = true;
    }
    c = &fix_conns[s->handle];
    c->start += sc.taken;
    c->skipping = skipping;
    if (c->start == c->len) c->start = c->len = 0;
    s->since = sim_waited;
    return true;
}

static bool sources_pump_fixture(void) {
    bool progressed = false;
    size_t n = nsources;
    for (size_t k = 0; k < n; k++) {
        Source *s = sources[k];
        if (s->done) continue;
        bool went = s->kind == SRC_LINES ? lines_fixture(s) : serve_fixture(s);
        progressed = progressed || went;
    }
    return progressed;
}

/* ---- under main */

/* ---- the deadline heap */

static void timer_swap(size_t a, size_t b) {
    Timer t = timers[a];
    timers[a] = timers[b];
    timers[b] = t;
    timers[a].source->timer = (ptrdiff_t)a;
    timers[b].source->timer = (ptrdiff_t)b;
}

static void timer_up(size_t i) {
    while (i > 0) {
        size_t parent = (i - 1) / 2;
        if (timers[parent].at <= timers[i].at) return;
        timer_swap(i, parent);
        i = parent;
    }
}

static void timer_down(size_t i) {
    for (;;) {
        size_t least = i, l = 2 * i + 1, r = l + 1;
        if (l < ntimers && timers[l].at < timers[least].at) least = l;
        if (r < ntimers && timers[r].at < timers[least].at) least = r;
        if (least == i) return;
        timer_swap(i, least);
        i = least;
    }
}

static void timer_push(Source *s, int64_t at) {
    GROW_ARRAY(timers, ntimers, captimers);
    timers[ntimers] = (Timer){at, s};
    s->timer = (ptrdiff_t)ntimers++;
    timer_up((size_t)s->timer);
}

static void timer_remove(Source *s) {
    if (s->timer < 0) return;
    size_t i = (size_t)s->timer;
    s->timer = -1;
    ntimers--;
    if (i == ntimers) return;
    timers[i] = timers[ntimers];
    timers[i].source->timer = (ptrdiff_t)i;
    timer_down(i);
    timer_up(i);
}

/* When `s` must be looked at again with nothing reported: its idle time, or a retry. */
static int64_t due_at(const Source *s) {
    return s->retry_at > s->since + s->idle_ms || s->paused ? s->retry_at : s->since + s->idle_ms;
}

static void leave_paused(Source *s) {
    s->in_paused = false;
    for (size_t i = 0; i < npaused; i++) {
        if (paused_sources[i] != s) continue;
        paused_sources[i] = paused_sources[--npaused];
        return;
    }
}

/* After a pump: a paused source is in the paused list; any other has a deadline. */
static void settle_source(Source *s) {
    if (s->paused) {
        if (!s->in_paused) {
            s->in_paused = true;
            GROW_ARRAY(paused_sources, npaused, cappaused);
            paused_sources[npaused++] = s;
        }
        if (s->timer >= 0 && s->retry_at == 0) timer_remove(s);
        return;
    }
    if (s->in_paused) leave_paused(s);
    if (s->timer < 0) timer_push(s, due_at(s));
}

/* `s` is done: it stops being watched, leaves every list, and is freed at the end of the pump (it
 * is in the dirty list then). */
static void source_retire(Source *s) {
    s->done = true;
    if (s->background) nbackground--;
    poller_disarm(&s->waiter);
    if (s->in_paused) leave_paused(s);
    if (s->timer >= 0) timer_remove(s);
    Source *last = sources[--nsources];
    if (last != s) {
        sources[s->index] = last;
        last->index = s->index;
    }
}

static void source_watch(Source *s, int fd) {
    if (s->waiter.armed && s->waiter.fd == fd) return;
    poller_disarm(&s->waiter);
    s->waiter = (Waiter){fd, false, false, false, NO_PROCESS, s, -1};
    if (poller_open()) poller_arm(&s->waiter);
}

static void serve_server(Source *s, int64_t now) {
    Listener *l = listeners[s->handle];
    while (now >= s->retry_at && procs[s->to]->up && source_room(s, s->inflight)) {
        int fd = accept(l->fd, NULL, NULL);
        if (fd < 0) {
            if (errno == EINTR || errno == ECONNABORTED) continue;
            if (errno == EAGAIN || errno == EWOULDBLOCK) {
                source_watch(s, l->fd);
            } else if (errno == EMFILE || errno == ENFILE || errno == ENOBUFS || errno == ENOMEM) {
                /* Out of descriptors or memory: the connection waits in the kernel's queue. */
                s->retry_at = now + REFUSED_RETRY_MS;
                timer_remove(s);
            }
            break;
        }
        uint32_t h = adopt(fd);
        conns[h]->listener = s->handle;
        s->since = now;
        if (s->kind == SRC_SERVE) {
            MoValue conn = mo_cap(MO_CAP_CONN, h, 0);
            source_send(s->to, MO_N_ACCEPTED, 1, &conn);
        } else {
            conns[h]->lining = true;
            s->inflight++;
            source_add(SRC_REQUEST, h, s->to, s->idle_ms, now, s);
        }
    }
    if (s->paused) {
        s->since = now;
    } else if (now - s->since >= s->idle_ms && source_room(s, s->inflight)) {
        source_send(s->to, MO_N_IDLE, 0, NULL);
        s->since = now;
    }
}

/* Reads what has arrived on `c` without waiting: FILL_GOT, FILL_EOF, FILL_TIMEOUT when nothing
 * has, FILL_CLOSED when the stream broke, FILL_FULL when the buffer holds `cap` bytes. */
static int source_read(Conn *c, size_t initial, size_t cap) {
    if (c->start > 0) {
        memmove(c->buf, c->buf + c->start, c->end - c->start);
        c->end -= c->start;
        c->start = 0;
    }
    if (c->end == c->cap) {
        if (c->cap >= cap) return FILL_FULL;
        size_t size = c->cap == 0 ? initial : 2 * c->cap < cap ? 2 * c->cap : cap;
        c->buf = xrealloc(c->buf, size);
        c->cap = size;
    }
    for (;;) {
        ssize_t got = read(c->fd, c->buf + c->end, c->cap - c->end);
        if (got > 0) {
            c->end += (size_t)got;
            return FILL_GOT;
        }
        if (got == 0) {
            c->eof = true;
            return FILL_EOF;
        }
        if (errno == EINTR) continue;
        return errno == EAGAIN || errno == EWOULDBLOCK ? FILL_TIMEOUT : FILL_CLOSED;
    }
}

/* With nothing buffered, the buffer goes back: a connection at rest holds none. */
static void conn_give_back(Conn *c) {
    if (c->start != c->end || !c->buf) return;
    free(c->buf);
    c->buf = NULL;
    c->start = c->end = c->cap = 0;
}

static void lines_server(Source *s, int64_t now) {
    Conn *c = conns[s->handle];
    if (c->closed) {
        net_release(c);
        return source_retire(s);
    }
    if (!procs[s->to]->up) {
        net_close(c);
        return source_retire(s);
    }
    for (;;) {
        while (source_room(s, 0)) {
            Scan sc = scan_line(c->buf ? c->buf + c->start : "", c->end - c->start, c->eof, &c->skipping);
            if (sc.what == SCAN_MORE) {
                c->start += sc.taken;
                break;
            }
            if (sc.what == SCAN_LINE) {
                MoValue text = heap_string(sc.line, sc.len);
                c->start += sc.taken;
                source_send(s->to, MO_N_LINE, 1, &text);
            } else if (sc.what == SCAN_TOO_LONG) {
                c->start += sc.taken;
                source_send(s->to, MO_N_LINE_TOO_LONG, 0, NULL);
            } else {
                source_send(s->to, MO_N_CLOSED, 0, NULL);
                return source_retire(s);
            }
            if (c->start == c->end) c->start = c->end = 0;
            s->since = now;
        }
        if (s->paused) {
            s->since = now;
            return;
        }
        /* A line too long is taken before the buffer fills, so there is always room to read. */
        int r = source_read(c, BUFFER_INITIAL, 2 * LINE_LIMIT);
        if (r == FILL_TIMEOUT) break;
        if (r == FILL_CLOSED) {
            net_close(c);
            source_send(s->to, MO_N_CLOSED, 0, NULL);
            return source_retire(s);
        }
    }
    if (now - s->since >= s->idle_ms) {
        source_send(s->to, MO_N_IDLE, 0, NULL);
        net_close(c);
        return source_retire(s);
    }
    conn_give_back(c);
    source_watch(s, c->fd);
}

static void request_refused(Conn *c, int failed) {
    const char *text = http_refusal(failed);
    if (text) {
        ssize_t r = write(c->fd, text, strlen(text));
        (void)r;
    }
    net_close(c);
}

static void request_finish(Source *s) {
    s->parent->inflight--;
    source_retire(s);
}

static void request_server(Source *s, int64_t now) {
    Conn *c = conns[s->handle];
    for (;;) {
        HttpParsed p = http_parse(c->buf ? c->buf + c->start : "", c->end - c->start, c->eof, false);
        if (p.what == PARSE_WHOLE) {
            MoValue ok = exchange_cap(&exchanges, &nexchanges, &capexchanges, s->handle, c->buf + c->start, p.len);
            c->start += p.len;
            c->lining = false;
            request_finish(s);
            if (!procs[s->to]->up) {
                exchange_forget(&exchanges[nexchanges - 1]);
                net_close(c);
                return;
            }
            return source_send(s->to, MO_N_ACCEPTED, 1, &ok.as.xs[0]);
        }
        if (p.what == PARSE_FAILED) {
            request_refused(c, p.failed);
            return request_finish(s);
        }
        if (c->closed || c->eof) {
            if (c->closed) net_release(c);
            else net_close(c);
            return request_finish(s);
        }
        int r = source_read(c, HTTP_BUFFER_INITIAL, HTTP_BUFFER_CAP);
        if (r == FILL_TIMEOUT) break;
        if (r == FILL_FULL) {
            request_refused(c, HTTP_TOO_LARGE);
            return request_finish(s);
        }
        if (r == FILL_CLOSED) {
            net_close(c);
            return request_finish(s);
        }
    }
    if (now - s->since >= s->idle_ms) {
        net_close(c);
        return request_finish(s);
    }
    source_watch(s, c->fd);
}

/* From main's thread, holding the turn: every source that can do something turns what it took into
 * messages, and arms the poller when it has taken all there is. */
static void sources_pump_server(void) {
    if (!server_mode || nsources == 0) return;
    int64_t now = now_ms();
    while (ntimers > 0 && timers[0].at <= now) {
        Source *s = timers[0].source;
        timer_remove(s);
        if (due_at(s) <= now) mark_dirty(s);
        else timer_push(s, due_at(s));
    }
    /* A paused source looks at its target's mailbox again. */
    for (size_t i = 0; i < npaused; i++) mark_dirty(paused_sources[i]);
    /* A request source an http serve source adds is pumped in this same pass. */
    for (size_t k = 0; k < ndirty; k++) {
        Source *s = dirty[k];
        s->dirty = false;
        if (s->done) continue;
        if (s->kind == SRC_LINES) lines_server(s, now);
        else if (s->kind == SRC_REQUEST) request_server(s, now);
        else serve_server(s, now);
        if (!s->done) settle_source(s);
    }
    /* Sources that ended give back their memory. */
    for (size_t k = 0; k < ndirty; k++) {
        if (dirty[k]->done) free(dirty[k]);
    }
    ndirty = 0;
}

static bool sources_active(void) {
    if (server_mode) return nsources > nbackground;
    for (size_t i = 0; i < nsources; i++) {
        if (!sources[i]->done && !sources[i]->background) return true;
    }
    return false;
}

static bool sources_has_work(void) { return ndirty > 0; }

static bool sources_next_deadline(int64_t *at) {
    if (ntimers == 0) return false;
    *at = timers[0].at;
    return true;
}

static void sources_fired(struct Source *s) { mark_dirty(s); }

static void sources_mark(void) {
    for (size_t i = 0; i < nsources; i++) {
        if (!sources[i]->done) mark_id(sources[i]->to);
    }
}

/* main called exit and returned: every source stops. */
static void sources_stop(void) {
    for (size_t i = 0; i < nsources; i++) {
        Source *s = sources[i];
        poller_disarm(&s->waiter);
        s->done = true;
        if (!s->dirty) free(s);
    }
    nsources = npaused = ntimers = 0;
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
    reset_processes();
    reset_net_fixture();
    reset_sources();
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
    return kind == MO_R_REQUIRES || kind == MO_R_REFINEMENT || kind == MO_R_INVARIANT || kind == MO_R_NEVER || kind == MO_R_HELD;
}

/* A crash is the verdict: a test rejects passes when it tripped what rejects expects. */
static void verdict(Result *r, const MoTest *t, Report report) {
    r->has_report = true;
    r->report = report;
    r->outcome = t->kind == MO_TEST_REJECTS && trips_rejects(report.kind) ? TRIPPED_AS_EXPECTED : FAILED;
}

/* What stopped a run: a supervisor that gave up, else the first crash in a process, else the
 * body's own. */
static Report crash_of(void) { return gave_up ? last_report : crashed_once ? first_crash : last_report; }

/* The body, then every message still waiting, then every never; the first crash, in a process
 * or in the body, is the verdict. */
static Result run_test(const MoTest *t) {
    Result r = {PASSED, false, {0}, 0, NULL, NULL};
    reset_memory();
    fresh_run();
    rng_seed(BASE_SEED);
    sim_seed = BASE_SEED;
    test_name = t->name;
    jmp_buf here;
    crash_jump = &here;
    mo_depth = 0;
    int jumped = setjmp(here);
    if (jumped != 0) {
        mo_depth = 0;
        mo_handle_frames = NULL;
    }
    if (jumped == 0) {
        t->fn();
        drain();
        check_nevers();
        if (crashed_once) {
            verdict(&r, t, first_crash);
        } else if (t->kind == MO_TEST_REJECTS) {
            r.outcome = DID_NOT_TRIP;
            r.note = "the body ran to its end without tripping a requires, a refinement, an invariant, or a never";
        }
    } else if (jumped == JUMP_SKIP) {
        r.outcome = SKIPPED;
        r.has_report = true;
        r.report = last_report;
    } else {
        verdict(&r, t, crash_of());
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
            sim_seed = seed;
            test_name = t->name;
            jmp_buf here;
            crash_jump = &here;
            mo_depth = 0;
            int jumped = setjmp(here);
            if (jumped != 0) {
                mo_depth = 0;
                mo_handle_frames = NULL;
            }
            if (jumped == 0) {
                t->fn();
                check_nevers();
                crash_jump = NULL;
                if (!crashed_once) {
                    held++;
                    break;
                }
                jumped = JUMP_CRASH;
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
            r.report = crash_of();
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

/* ---- the runtime surface (surface.zig, step 23): the rows of a Runtime. A read is a snapshot taken
 * between updates, and a process whose update waits on a stack is read once that update ends, within
 * the row's deadline; send, pause, and resume act, each an event, and a Runtime narrowed by read_only
 * refuses them. platform.runtime is Some in a binary built with --surface, and None otherwise. */

#define RUNTIME_READ_ONLY 1
#define LARGEST_LISTED 5

static MoValue runtime_failure(uint32_t name) { return error_of(mo_variant(name, 0, NULL)); }
static MoValue text_value(const char *s) { return mo_str(s, (uint32_t)strlen(s)); }

static MoValue text_copy(const char *s, size_t len) {
    char *out = mo_alloc_bytes(len);
    if (len) memcpy(out, s, len);
    return mo_str(out, (uint32_t)len);
}

/* A process id a row was given, when a process that has not ended has it. */
static bool live_id(MoValue v, uint32_t *out) {
    __int128 n = mo_wide(v);
    if (n < 0 || n >= (__int128)nprocs) return false;
    uint32_t id = (uint32_t)n;
    if (procs[id]->ended || is_hidden(id)) return false;
    *out = id;
    return true;
}

/* `n` of a row, no more than there are. */
static size_t row_count(MoValue v, size_t there) {
    __int128 n = mo_wide(v);
    return n < 0 ? 0 : n > (__int128)there ? there : (size_t)n;
}

static uint64_t region_bytes_of(uint32_t id) {
    if (!turns_on || id >= nworkers || !workers[id] || workers[id]->ended) return 0;
    const MoRegion *r = my_vm == &workers[id]->vm ? &mo_heap : &workers[id]->vm.heap;
    return r->end ? r->top - r->base : 0;
}

static Event ring_get(size_t i) { return ring[(ring_head + i) % ring_len]; }

static MoValue maybe_id(uint32_t id) { return id == NOBODY ? mo_nothing() : mo_some(mo_u64(id)); }

/* A process's name, or who acts from outside one. */
static const char *who_name(uint32_t id, const char *name) { return id != NOBODY ? name : server_mode ? "main" : "the test"; }

/* One event as the prelude's Event enum spells it. */
static MoValue event_value(const Event *e) {
    MoValue f[7];
    f[0] = mo_time(ring_wall_ms + (e->at - ring_mono_us) / 1000);
    MoValue id = mo_u64(e->process), name = text_value(e->process_name);
    switch (e->kind) {
    case EV_UPDATED:
        f[1] = id, f[2] = name, f[3] = text_value(e->name), f[4] = mo_u64(e->took_us), f[5] = mo_u64(e->waited_us), f[6] = text_value(e->call);
        return mo_variant(MO_N_UPDATED, 7, f);
    case EV_STARTED: f[1] = id, f[2] = name; return mo_variant(MO_N_STARTED, 3, f);
    case EV_ENDED: f[1] = id, f[2] = name; return mo_variant(MO_N_ENDED, 3, f);
    case EV_RESTARTED: f[1] = id, f[2] = name, f[3] = mo_u64(e->count); return mo_variant(MO_N_RESTARTED, 4, f);
    case EV_CRASHED:
        f[1] = id, f[2] = name, f[3] = mo_u64(e->seed), f[4] = text_value(e->clause), f[5] = text_value(e->message), f[6] = text_value(e->state);
        return mo_variant(MO_N_CRASHED, 7, f);
    case EV_OVERFLOWED:
        f[1] = maybe_id(e->other), f[2] = text_value(who_name(e->other, e->other_name)), f[3] = id, f[4] = name;
        return mo_variant(MO_N_OVERFLOWED, 5, f);
    case EV_TIMED_OUT:
        f[1] = maybe_id(e->process), f[2] = text_value(who_name(e->process, e->process_name)), f[3] = text_value(e->call);
        return mo_variant(MO_N_TIMED_OUT, 4, f);
    case EV_SOURCE_PAUSED:
    case EV_SOURCE_RESUMED:
        f[1] = text_value(e->name), f[2] = id, f[3] = name, f[4] = mo_u64(e->count);
        return mo_variant(e->kind == EV_SOURCE_PAUSED ? MO_N_SOURCE_PAUSED : MO_N_SOURCE_RESUMED, 5, f);
    case EV_SENT: f[1] = id, f[2] = name, f[3] = text_value(e->message); return mo_variant(MO_N_SENT, 4, f);
    case EV_PAUSED: f[1] = id, f[2] = name; return mo_variant(MO_N_PAUSED, 3, f);
    default: f[1] = id, f[2] = name; return mo_variant(MO_N_RESUMED, 3, f);
    }
}

static MoValue process_info(uint32_t id) {
    const Proc *p = procs[id];
    MoValue f[9];
    f[0] = mo_u64(id);
    f[1] = text_value(name_of(id));
    f[2] = mo_bool(p->up);
    f[3] = mo_u64(queued(p));
    f[4] = mo_u64(mo_processes[p->process].mailbox);
    f[5] = p->busy && p->waiting && p->waiting[0] ? mo_some(text_value(p->waiting)) : mo_nothing();
    f[6] = mo_u64(p->restarted);
    f[7] = mo_u64(region_bytes_of(id));
    f[8] = mo_bool(p->paused);
    return mo_record(mo_process_info_decl, 9, f);
}

/* Under main, while an update of process `id` is on a stack, main hands out turns and a process parks,
 * a millisecond at a time, at most `within` (turns.zig, waitIdle). True once none is. */
static bool turns_wait_idle(uint32_t id, int64_t within) {
    int64_t deadline = now_ms() + (within > 0 ? within : 0);
    while (procs[id]->busy) {
        int64_t now = now_ms();
        if (now >= deadline) return false;
        int64_t until = deadline < now + 1 ? deadline : now + 1;
        if (holder != MAIN_TURN) park(until);
        else if (!step()) idle(NULL, true, until);
    }
    return true;
}

MO_ROW(mo_r_Platform_runtime) {
    (void)a;
    (void)kind;
    platform_only("Platform", "runtime");
    return mo_surface_built ? mo_some(mo_cap(MO_CAP_RUNTIME, 0, 0)) : mo_nothing();
}

MO_ROW(mo_r_Runtime_fixture) { (void)a; (void)kind; return mo_cap(MO_CAP_RUNTIME, 0, 0); }
MO_ROW(mo_r_Runtime_read_only) { (void)a; (void)kind; return mo_cap(MO_CAP_RUNTIME, RUNTIME_READ_ONLY, 0); }

MO_ROW(mo_r_Runtime_processes) {
    (void)a;
    (void)kind;
    sweep_test();
    MoValue *out = mo_alloc_values(nprocs);
    uint32_t n = 0;
    for (uint32_t id = 0; id < nprocs; id++) {
        if (!procs[id]->ended && !is_hidden(id)) out[n++] = process_info(id);
    }
    return mo_list(out, n);
}

MO_ROW(mo_r_Runtime_state) {
    (void)kind;
    sweep_test();
    uint32_t id;
    if (!live_id(a[1], &id)) return runtime_failure(MO_N_NO_PROCESS);
    if (procs[id]->busy && (!turns_on || running == id || !turns_wait_idle(id, a[2].as.i))) return runtime_failure(MO_N_TIMEOUT);
    char *s = render(procs[id]->state);
    MoValue text = text_copy(s, strlen(s));
    free(s);
    return ok_of(text);
}

/* The last `n` events that `keep` keeps, oldest first. */
static MoValue last_events(size_t n, bool (*keep)(const Event *, __int128), __int128 arg) {
    MoValue *out = mo_alloc_values(n);
    size_t got = 0;
    for (size_t i = ring_len; i > 0 && got < n; i--) {
        Event e = ring_get(i - 1);
        if (keep(&e, arg)) out[got++] = event_value(&e);
    }
    for (size_t i = 0; i < got / 2; i++) {
        MoValue x = out[i];
        out[i] = out[got - 1 - i];
        out[got - 1 - i] = x;
    }
    return mo_list(out, (uint32_t)got);
}

static bool of_process(const Event *e, __int128 id) { return (__int128)e->process == id; }
static bool is_crash(const Event *e, __int128 unused) { (void)unused; return e->kind == EV_CRASHED; }

MO_ROW(mo_r_Runtime_recent) { (void)kind; return last_events(row_count(a[2], ring_len), of_process, mo_wide(a[1])); }
MO_ROW(mo_r_Runtime_crashes) { (void)kind; return last_events(row_count(a[1], ring_len), is_crash, 0); }

MO_ROW(mo_r_Runtime_events) {
    (void)kind;
    int64_t at = ring_mono_us + (a[1].as.i - ring_wall_ms) * 1000;
    size_t lo = 0, hi = ring_len;
    while (lo < hi) {
        size_t mid = (lo + hi) / 2;
        if (ring_get(mid).at < at) lo = mid + 1;
        else hi = mid;
    }
    size_t n = row_count(a[2], ring_len - lo);
    MoValue *out = mo_alloc_values(n);
    for (size_t i = 0; i < n; i++) {
        Event e = ring_get(lo + i);
        out[i] = event_value(&e);
    }
    return mo_list(out, (uint32_t)n);
}

typedef struct { uint64_t took; size_t index; } Timed;

static int longer_first(const void *x, const void *y) {
    const Timed *a = x, *b = y;
    if (a->took != b->took) return a->took > b->took ? -1 : 1;
    return a->index < b->index ? -1 : a->index > b->index;
}

/* The n longest updates the ring holds, longest first; of two as long, the earlier first. */
MO_ROW(mo_r_Runtime_slowest) {
    (void)kind;
    Timed *updates = xmalloc((ring_len ? ring_len : 1) * sizeof(Timed));
    size_t m = 0;
    for (size_t i = 0; i < ring_len; i++) {
        Event e = ring_get(i);
        if (e.kind == EV_UPDATED) updates[m++] = (Timed){e.took_us, i};
    }
    qsort(updates, m, sizeof(Timed), longer_first);
    size_t n = row_count(a[1], m);
    MoValue *out = mo_alloc_values(n);
    for (size_t i = 0; i < n; i++) {
        Event e = ring_get(updates[i].index);
        out[i] = event_value(&e);
    }
    free(updates);
    return mo_list(out, (uint32_t)n);
}

MO_ROW(mo_r_Runtime_sources) {
    (void)a;
    (void)kind;
    MoValue *out = mo_alloc_values(nsources);
    uint32_t n = 0;
    for (size_t i = 0; i < nsources; i++) {
        const Source *s = sources[i];
        /* A request being read counts in its listener's in flight. */
        if (s->done || s->kind == SRC_REQUEST || is_hidden(s->to)) continue;
        MoValue f[5] = {text_value(source_label(s->kind)), mo_u64(s->to), text_value(name_of(s->to)), mo_u64(s->inflight), mo_bool(s->paused)};
        out[n++] = mo_record(mo_source_info_decl, 5, f);
    }
    return mo_list(out, n);
}

/* The program's resident memory now, in bytes. */
static uint64_t resident_bytes(void) {
#if defined(__APPLE__)
    struct mach_task_basic_info info;
    mach_msg_type_number_t count = MACH_TASK_BASIC_INFO_COUNT;
    if (task_info(mach_task_self(), MACH_TASK_BASIC_INFO, (task_info_t)&info, &count) != KERN_SUCCESS) return 0;
    return info.resident_size;
#elif defined(__linux__)
    FILE *f = fopen("/proc/self/statm", "r");
    unsigned long size = 0, pages = 0;
    if (f) {
        if (fscanf(f, "%lu %lu", &size, &pages) != 2) pages = 0;
        fclose(f);
    }
    return (uint64_t)pages * (uint64_t)sysconf(_SC_PAGESIZE);
#else
    return 0;
#endif
}

MO_ROW(mo_r_Runtime_memory) {
    sweep_test();
    (void)a;
    (void)kind;
    uint64_t regions = 0;
    if (server_mode && mo_compacts) {
        const MoRegion *m = my_vm == &main_vm ? &mo_heap : &main_vm.heap;
        if (m->end) regions += m->top - m->base;
    }
    uint32_t top[LARGEST_LISTED];
    uint64_t top_bytes[LARGEST_LISTED];
    uint32_t ntop = 0;
    for (uint32_t id = 0; id < nprocs; id++) {
        if (procs[id]->ended || is_hidden(id)) continue;
        uint64_t b = region_bytes_of(id);
        regions += b;
        uint32_t k = ntop;
        if (ntop < LARGEST_LISTED) {
            ntop++;
        } else {
            if (b <= top_bytes[LARGEST_LISTED - 1]) continue;
            k = LARGEST_LISTED - 1;
        }
        while (k > 0 && top_bytes[k - 1] < b) {
            top[k] = top[k - 1];
            top_bytes[k] = top_bytes[k - 1];
            k--;
        }
        top[k] = id;
        top_bytes[k] = b;
    }
    MoValue *largest = mo_alloc_values(ntop);
    for (uint32_t i = 0; i < ntop; i++) largest[i] = process_info(top[i]);
    MoValue f[5] = {mo_u64(resident_bytes()), mo_u64(regions), mo_u64(stat_packed_bytes), mo_u64(ring ? ring_cap * sizeof(Event) : 0), mo_list(largest, ntop)};
    return mo_record(mo_memory_info_decl, 5, f);
}

/* ---- a message from the text a report prints it as (surface.zig, Parser) */

typedef struct { const char *s; size_t n, at; char *why; } TextIn;

static bool in_fail(TextIn *in, const char *format, ...) __attribute__((format(printf, 2, 3)));
static bool in_fail(TextIn *in, const char *format, ...) {
    char what[512];
    va_list ap;
    va_start(ap, format);
    vsnprintf(what, sizeof what, format, ap);
    va_end(ap);
    if (!in->why) in->why = text_of("%s, at byte %zu", what, in->at);
    return false;
}

static void in_space(TextIn *in) {
    while (in->at < in->n && isspace((unsigned char)in->s[in->at])) in->at++;
}

static bool in_eat(TextIn *in, const char *lit) {
    in_space(in);
    size_t len = strlen(lit);
    if (in->n - in->at < len || memcmp(in->s + in->at, lit, len) != 0) return false;
    in->at += len;
    return true;
}

static bool in_expect(TextIn *in, const char *lit) { return in_eat(in, lit) || in_fail(in, "expected %s", lit); }

static size_t in_name(TextIn *in, const char **start) {
    in_space(in);
    *start = in->s + in->at;
    size_t from = in->at;
    while (in->at < in->n && (isalnum((unsigned char)in->s[in->at]) || in->s[in->at] == '_' || in->s[in->at] == '?')) in->at++;
    return in->at - from;
}

static bool same_name(const char *name, const char *s, size_t len) { return strlen(name) == len && memcmp(name, s, len) == 0; }

static bool in_integer(TextIn *in, __int128 *out) {
    in_space(in);
    size_t start = in->at;
    bool negative = in->at < in->n && in->s[in->at] == '-';
    if (negative) in->at++;
    __int128 n = 0;
    size_t digits = 0;
    for (; in->at < in->n && (isdigit((unsigned char)in->s[in->at]) || in->s[in->at] == '_'); in->at++) {
        if (in->s[in->at] == '_') continue;
        if (n > ((((__int128)1) << 125) - 1) / 5) return in_fail(in, "that number is too large");
        n = n * 10 + (in->s[in->at] - '0');
        digits++;
    }
    if (digits == 0) {
        in->at = start;
        return in_fail(in, "expected a number");
    }
    *out = negative ? -n : n;
    return true;
}

static bool parse_value(TextIn *in, uint32_t t, MoValue *out);

static bool parse_fields(TextIn *in, const MoField *fields, uint32_t n, const char *owner, MoValue **out) {
    MoValue *xs = mo_alloc_values(n);
    *out = xs;
    if (n == 0) return true;
    if (!in_expect(in, "(")) return false;
    for (uint32_t i = 0; i < n; i++) {
        if (i > 0 && !in_expect(in, ",")) return false;
        size_t save = in->at;
        const char *label;
        size_t len = in_name(in, &label);
        if (len > 0 && in_eat(in, ":")) {
            if (!same_name(fields[i].name, label, len)) return in_fail(in, "%s takes %s here, not %.*s", owner, fields[i].name, (int)len, label);
        } else {
            in->at = save;
        }
        if (!parse_value(in, fields[i].type, &xs[i])) return false;
    }
    return in_expect(in, ")");
}

static bool parse_variant(TextIn *in, const MoDecl *d, const char *what, MoValue *out) {
    const char *name;
    size_t len = in_name(in, &name);
    for (uint32_t k = 0; k < d->nvariants; k++) {
        const MoVariantDef *def = &mo_variants[d->variants + k];
        if (!same_name(mo_names[def->name], name, len)) continue;
        MoValue *xs;
        if (!parse_fields(in, def->fields, def->nfields, mo_names[def->name], &xs)) return false;
        *out = mo_variant(def->name, def->nfields, xs);
        return true;
    }
    if (len == 0) return in_fail(in, "nothing is not %s", what);
    return in_fail(in, "%.*s is not %s", (int)len, name, what);
}

static const char *const int_kind_names[] = {"i8", "i16", "i32", "i64", "u8", "u16", "u32", "u64"};

static bool parse_value(TextIn *in, uint32_t t, MoValue *out) {
    const MoType *ty = &mo_types[t];
    in_space(in);
    switch (ty->tag) {
    case MO_T_ALIAS: return parse_value(in, ty->b, out);
    case MO_T_BOOL:
        if (in_eat(in, "true")) return *out = mo_bool(true), true;
        if (in_eat(in, "false")) return *out = mo_bool(false), true;
        return in_fail(in, "expected true or false");
    case MO_T_INT: {
        __int128 n;
        if (!in_integer(in, &n)) return false;
        if (n < kind_min(ty->a) || n > kind_max(ty->a)) {
            char digits[48];
            size_t len = 0;
            unsigned __int128 u = n < 0 ? (unsigned __int128)(-n) : (unsigned __int128)n;
            do digits[len++] = (char)('0' + (int)(u % 10)); while ((u /= 10) > 0);
            if (n < 0) digits[len++] = '-';
            char spelled[48];
            for (size_t i = 0; i < len; i++) spelled[i] = digits[len - 1 - i];
            spelled[len] = 0;
            return in_fail(in, "%s does not fit a %s", spelled, int_kind_names[ty->a]);
        }
        *out = mo_i128(n);
        return true;
    }
    case MO_T_FLOAT: {
        size_t start = in->at;
        while (in->at < in->n && strchr("+-.0123456789eE", in->s[in->at]) && in->s[in->at]) in->at++;
        char number[64];
        size_t len = in->at - start;
        if (len == 0 || len >= sizeof number) return in_fail(in, "expected a number");
        memcpy(number, in->s + start, len);
        number[len] = 0;
        char *end;
        double f = strtod(number, &end);
        if (*end) return in_fail(in, "expected a number");
        *out = mo_f64(f);
        return true;
    }
    case MO_T_STRING: {
        if (!in_expect(in, "\"")) return false;
        Buf b = {0};
        for (;;) {
            if (in->at == in->n) {
                free(b.p);
                return in_fail(in, "the string does not end");
            }
            char ch = in->s[in->at++];
            if (ch == '"') break;
            if (ch == '\\' && in->at < in->n && (in->s[in->at] == '"' || in->s[in->at] == '\\')) buf_byte(&b, in->s[in->at++]);
            else buf_byte(&b, ch);
        }
        *out = text_copy(b.p, b.len);
        free(b.p);
        return true;
    }
    case MO_T_DURATION: {
        __int128 n;
        if (!in_integer(in, &n) || !in_expect(in, ".ms")) return false;
        if (n < INT64_MIN || n > INT64_MAX) return in_fail(in, "that duration is too long");
        *out = mo_duration((int64_t)n);
        return true;
    }
    case MO_T_TIME: {
        if (!in_expect(in, "Time.fixture()")) return false;
        __int128 at = FIXTURE_TIME, n;
        if (in_eat(in, "+")) {
            if (!in_integer(in, &n) || !in_expect(in, ".ms")) return false;
            at += n;
        } else if (in_eat(in, "-")) {
            if (!in_integer(in, &n) || !in_expect(in, ".ms")) return false;
            at -= n;
        }
        if (at < INT64_MIN || at > INT64_MAX) return in_fail(in, "that time is out of range");
        *out = mo_time((int64_t)at);
        return true;
    }
    case MO_T_LIST: {
        if (!in_expect(in, "[")) return false;
        Values items = {NULL, 0, 0};
        if (!in_eat(in, "]")) {
            for (;;) {
                MoValue x;
                if (!parse_value(in, ty->a, &x)) {
                    free(items.xs);
                    return false;
                }
                values_push(&items, x);
                if (!in_eat(in, ",")) break;
            }
            if (!in_expect(in, "]")) {
                free(items.xs);
                return false;
            }
        }
        MoValue *xs = mo_alloc_values(items.n);
        if (items.n) memcpy(xs, items.xs, items.n * sizeof(MoValue));
        free(items.xs);
        *out = mo_list(xs, (uint32_t)items.n);
        return true;
    }
    case MO_T_TUPLE: {
        if (!in_expect(in, "(")) return false;
        MoValue *xs = mo_alloc_values(ty->b);
        for (uint32_t i = 0; i < ty->b; i++) {
            if (i > 0 && !in_expect(in, ",")) return false;
            if (!parse_value(in, ty->items[i], &xs[i])) return false;
        }
        if (!in_expect(in, ")")) return false;
        *out = mo_tuple_of(xs, ty->b);
        return true;
    }
    case MO_T_OPTION: {
        if (in_eat(in, "None")) return *out = mo_nothing(), true;
        MoValue x;
        if (!in_expect(in, "Some(") || !parse_value(in, ty->a, &x) || !in_expect(in, ")")) return false;
        *out = mo_some(x);
        return true;
    }
    case MO_T_RESULT: {
        MoValue x;
        if (in_eat(in, "Ok(")) {
            if (!parse_value(in, ty->a, &x) || !in_expect(in, ")")) return false;
            *out = ok_of(x);
            return true;
        }
        if (!in_expect(in, "Error(") || !parse_value(in, ty->b, &x) || !in_expect(in, ")")) return false;
        *out = error_of(x);
        return true;
    }
    case MO_T_DECL: {
        const MoDecl *d = &mo_decls[ty->a];
        if (d->kind == MO_D_STRUCT) {
            const char *name;
            size_t len = in_name(in, &name);
            if (!same_name(d->name, name, len)) return in_fail(in, "expected a %s", d->name);
            MoValue *xs;
            if (!parse_fields(in, d->fields, d->nfields, d->name, &xs)) return false;
            MoValue v = {MO_RECORD, ty->a, {0}};
            v.as.xs = xs;
            *out = v;
            return true;
        }
        if (d->kind == MO_D_ENUM || d->kind == MO_D_PRELUDE_ENUM) return parse_variant(in, d, "one of its variants", out);
        break;
    }
    default: break;
    }
    return in_fail(in, "a %s is not made from text by the surface", ty->name);
}

MO_ROW(mo_r_Runtime_send) {
    (void)kind;
    if (mo_cap_handle(a[0]) == RUNTIME_READ_ONLY) return runtime_failure(MO_N_READ_ONLY);
    uint32_t id;
    if (!live_id(a[1], &id) || !procs[id]->up) return runtime_failure(MO_N_NO_PROCESS);
    const MoProcess *process = &mo_processes[procs[id]->process];
    TextIn in = {a[2].as.s, a[2].aux, 0, NULL};
    MoValue message;
    bool parsed = parse_variant(&in, &mo_decls[process->decl], "a message this process declares", &message);
    if (parsed) {
        in_space(&in);
        if (in.at != in.n) parsed = in_fail(&in, "%s is followed by more text", mo_names[mo_vname(message)]);
    }
    if (!parsed) {
        MoValue why = text_copy(in.why, strlen(in.why));
        free(in.why);
        return error_of(mo_variant(MO_N_UNPARSED, 1, &why));
    }
    if (queued(procs[id]) >= process->mailbox) return runtime_failure(MO_N_MAILBOX_FULL);
    Parcel *parcel = packs ? pack(message) : NULL;
    enqueue(id, parcel ? parcel->value : message, parcel);
    Event e = event_of(EV_SENT, id);
    e.name = mo_names[mo_vname(message)];
    char *copy = xmalloc(a[2].aux + 1);
    memcpy(copy, a[2].as.s, a[2].aux);
    copy[a[2].aux] = 0;
    e.message = copy;
    record_event(e);
    return ok_none();
}

static MoValue runtime_hold(const MoValue *a, bool pause) {
    if (mo_cap_handle(a[0]) == RUNTIME_READ_ONLY) return runtime_failure(MO_N_READ_ONLY);
    uint32_t id;
    if (!live_id(a[1], &id)) return runtime_failure(MO_N_NO_PROCESS);
    Proc *p = procs[id];
    p->paused = pause;
    record_event(event_of(pause ? EV_PAUSED : EV_RESUMED, id));
    if (!pause && queued(p) > 0 && turns_on) mark_runnable(id);
    return ok_none();
}

/* MO_SURFACE=PORT in a binary built with --surface (step 23): the port main's surface serves on, or
 * -1 when it is not set or not a port. */
int mo_surface_port(void) {
    const char *said = getenv("MO_SURFACE");
    if (!said || !*said) return -1;
    char *end;
    long port = strtol(said, &end, 10);
    return *end || port < 0 || port > 65535 ? -1 : (int)port;
}

/* The surface is listening on the port it gives, or could not have the port when it gives 0. */
void mo_surface_listening(MoValue got) {
    long long port = (long long)mo_wide(got);
    if (port == 0) fprintf(stderr, "runtime surface: 127.0.0.1:%d could not be had\n", mo_surface_port());
    else fprintf(stderr, "runtime surface: http://127.0.0.1:%lld\n", port);
    fflush(stderr);
}

MO_ROW(mo_r_Runtime_pause) { (void)kind; return runtime_hold(a, true); }
MO_ROW(mo_r_Runtime_resume) { (void)kind; return runtime_hold(a, false); }

void mo_program_start(int argc, char **argv) {
    server_mode = true;
    signal(SIGPIPE, SIG_IGN);
    if (getenv("MO_STATS")) signal(SIGTERM, stats_on_term);
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
    /* Each process runs its updates on a fiber of its own on main's thread; a value that goes from
     * one to another goes packed when values live in regions. */
    my_vm = &main_vm;
    sim_seed = 0;
    /* MO_EVENTS=N: the events the run keeps, as mo run --events N (step 23). */
    const char *events = getenv("MO_EVENTS");
    if (events) ring_cap = (size_t)strtoull(events, NULL, 10);
    ring_wall_ms = wall_ms();
    ring_mono_us = awake_ns() / 1000;
    hidden_process = mo_surface_process;
    turns_on = mo_nprocesses > 0;
    packs = turns_on && mo_compacts;
    /* MO_CLOCK fixes where main's clock starts, as mo run --clock does. */
    const char *clock = getenv("MO_CLOCK");
    if (clock) {
        int64_t start;
        if (!parse_time(clock, strlen(clock), &start)) {
            fprintf(stderr, "%s: %s is not an ISO-8601 time such as 2026-01-01T00:00:00Z\n", argc > 0 ? argv[0] : "mo", clock);
            exit(2);
        }
        clock_offset = start - wall_ms();
    }
    program_argc = argc > 0 ? argc - 1 : 0;
    program_argv = argv + 1;
    char *cwd = getcwd(NULL, 0);
    add_scope((Scope){cwd ? cwd : strdup("/"), "/", false, false});
}

int mo_program_end(void) {
    /* main returned: the run goes on until no message is waiting and no source can deliver; a
     * main that called exit stops the sources first. */
    if (turns_on) {
        if (exited) sources_stop();
        turns_finish();
    }
    stream_flush(&out_stream);
    stream_flush(&err_stream);
    if (getenv("MO_STATS")) print_stats();
    return exit_code;
}
