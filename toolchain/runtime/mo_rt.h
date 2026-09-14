/* mo_rt.h: the runtime a compiled Mo program links (design-v0/07, build order item 2).
 * C11, no dependency past libc. emit_c.zig writes one translation unit per program that
 * includes this header and defines the tables it declares `extern`; mo_rt.c is the rest.
 *
 * The interpreter (toolchain/src/vm.zig) is the reference semantics, and this runtime
 * reproduces it: the same values, the same overflow traps, the same crash reports, the same
 * stdlib rows, and the same memory discipline, regions freed at the safe points the vm uses.
 *
 * A value is 16 bytes: a tag, a 32-bit aux, and a 64-bit payload.
 *   MO_INT      aux 0, i: an integer that fits int64
 *   MO_UINT     aux 0, u: an integer above INT64_MAX (a UInt64); so each integer has one form
 *   MO_BIG      p: an __int128 a contract's unbounded arithmetic left outside both
 *   MO_FLOAT    f
 *   MO_STRING   aux: bytes, s: UTF-8 (not NUL-terminated)
 *   MO_TIME, MO_DURATION  i: milliseconds
 *   MO_LIST, MO_TUPLE     aux: elements, xs
 *   MO_MAP, MO_SET        m: entries and hash index (NULL: empty)
 *   MO_RECORD   aux: its decl (mo_decls), xs: the fields
 *   MO_VARIANT  aux: name id (mo_names) | fields << 16, xs: the fields
 *   MO_FUNC     fn: code, id, and captures
 *   MO_CAP      aux: kind | handle << 8, i: an Fs fixture's delay
 */
#ifndef MO_RT_H
#define MO_RT_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define MO_U __attribute__((unused))
#define MO_LIKELY(x) __builtin_expect(!!(x), 1)
#define MO_UNLIKELY(x) __builtin_expect(!!(x), 0)

enum {
    MO_NONE, MO_BOOL, MO_INT, MO_UINT, MO_BIG, MO_FLOAT, MO_STRING, MO_TIME, MO_DURATION,
    MO_LIST, MO_TUPLE, MO_MAP, MO_SET, MO_RECORD, MO_VARIANT, MO_FUNC, MO_CAP, MO_HANDLE
};

typedef struct MoValue MoValue;
typedef struct MoMap MoMap;
typedef struct MoFunc MoFunc;
typedef MoValue (*MoCode)(const MoValue *cap, const MoValue *args);

struct MoValue {
    uint32_t tag;
    uint32_t aux;
    union {
        int64_t i;
        uint64_t u;
        double f;
        bool b;
        const char *s;
        MoValue *xs;
        MoMap *m;
        MoFunc *fn;
        __int128 *big;
    } as;
};

/* A map's or a set's entries (`stride` values each: 2 or 1) in the order the keys were
 * first added, and once there are enough of them an open-addressing table over them:
 * index[0] counts the slots in use, index[1..index_len) holds ordinal + 1, 0 when empty. */
struct MoMap {
    MoValue *entries;
    uint32_t len;
    uint32_t index_len;
    uint32_t *index;
};

struct MoFunc {
    MoCode code;
    uint32_t id;
    uint32_t ncap;
    MoValue cap[];
};

/* ---- the program's tables (emit_c.zig defines them) */

/* Every name a variant has, the runtime's own first (MO_N_*). */
extern const char *const mo_names[];
extern const uint32_t mo_nnames;
enum {
    MO_N_SOME, MO_N_NONE, MO_N_OK, MO_N_ERROR, MO_N_MISSING, MO_N_TIMEOUT, MO_N_SYNTAX,
    MO_N_OBJECT, MO_N_ARRAY, MO_N_STRING, MO_N_NUMBER, MO_N_BOOL, MO_N_NULL, MO_N_DOWN,
    MO_N_REFUSED, MO_N_CLOSED, MO_N_LINE_TOO_LONG, MO_N_BUSY, MO_N_MALFORMED, MO_N_TOO_LARGE,
    MO_N_UNSUPPORTED, MO_N_NOT_TEXT, MO_N_ACCEPTED, MO_N_LINE, MO_N_IDLE, MO_N_NO_PROCESS, MO_N_UNPARSED,
    MO_N_READ_ONLY, MO_N_MAILBOX_FULL, MO_N_UPDATED, MO_N_STARTED, MO_N_ENDED, MO_N_RESTARTED, MO_N_CRASHED,
    MO_N_OVERFLOWED, MO_N_TIMED_OUT, MO_N_SOURCE_PAUSED, MO_N_SOURCE_RESUMED, MO_N_SENT, MO_N_PAUSED,
    MO_N_RESUMED, MO_N_FIXED
};

/* types.Tag, in its order. */
enum {
    MO_T_UNKNOWN, MO_T_NONE, MO_T_NEVER, MO_T_BOOL, MO_T_STRING, MO_T_TIME, MO_T_DURATION,
    MO_T_INT, MO_T_FLOAT, MO_T_LIST, MO_T_OPTION, MO_T_RESULT, MO_T_MAP, MO_T_SET, MO_T_TUPLE,
    MO_T_FUNC, MO_T_DECL, MO_T_ALIAS, MO_T_CAP, MO_T_HANDLE, MO_T_MESSAGE, MO_T_STATE,
    MO_T_PARAM, MO_T_SELF, MO_T_VARIABLE
};

/* types.IntKind, in its order; MO_K_NONE when a row has no integer receiver. */
enum { MO_I8, MO_I16, MO_I32, MO_I64, MO_U8, MO_U16, MO_U32, MO_U64 };
#define MO_KIND_NONE UINT32_MAX
/* A map or set row on a var that owns its buffer may write in place (bytecode.unique). */
#define MO_KIND_UNIQUE (UINT32_MAX - 1)

/* types.CapKind, in its order. */
enum {
    MO_CAP_CLOCK, MO_CAP_FS, MO_CAP_EVENTS, MO_CAP_LEDGER, MO_CAP_PLATFORM, MO_CAP_ENV, MO_CAP_OUT, MO_CAP_NET,
    MO_CAP_LISTENER, MO_CAP_CONN, MO_CAP_HTTP, MO_CAP_HTTP_LISTENER, MO_CAP_EXCHANGE, MO_CAP_RUNTIME
};

/* check.DeclKind, in its order. */
enum { MO_D_STRUCT, MO_D_ENUM, MO_D_ALIAS, MO_D_OPAQUE, MO_D_TRAIT, MO_D_PROCESS, MO_D_SUPERVISOR, MO_D_RECIPE, MO_D_PRELUDE_ENUM };

/* A checker type, resolved: its children are indices into mo_types too. */
typedef struct {
    uint8_t tag;
    /* Its Mo spelling, for a report. */
    const char *name;
    /* A never reads values of it with T.all: its index among those, or UINT32_MAX. */
    uint32_t recorded;
    /* A value of it can hold a value of a recorded type. */
    bool may_hold;
    uint32_t a, b;
    const uint32_t *items;
} MoType;
extern const MoType mo_types[];

typedef struct { const char *name; uint32_t type; } MoField;
typedef struct { uint32_t name; uint32_t nfields; const MoField *fields; } MoVariantDef;
typedef MoValue (*MoRefineFn)(MoValue value);
typedef struct {
    const char *name;
    uint8_t kind;
    uint32_t nfields;
    const MoField *fields;
    uint32_t variants, nvariants;
    /* An alias's refinements, which any(T) keeps to. */
    uint32_t nrefines;
    const MoRefineFn *refines;
    /* The integer bounds they state (bytecode.Bounds), clamped to the base type, when they
     * state any and lo <= hi; and the clause any(T) crashes with when none of its candidates
     * pass (MO0325). */
    bool bounded;
    __int128 lo, hi;
    uint32_t none_admitted;
} MoDecl;
extern const MoDecl mo_decls[];
/* Every variant the checker knows, in its order (vm.formatValue looks through them). */
extern const MoVariantDef mo_variants[];
extern const uint32_t mo_nvariants;

/* contracts.Kind, in its order. */
enum { MO_R_REQUIRES, MO_R_ENSURES, MO_R_REFINEMENT, MO_R_INVARIANT, MO_R_NEVER, MO_R_ASSERT, MO_R_OVERFLOW, MO_R_DIVIDE_BY_ZERO, MO_R_MAILBOX, MO_R_SUPERVISOR, MO_R_OTHER, MO_R_HELD };

typedef struct {
    uint8_t kind;
    bool skip;
    const char *text;
    const char *within;
    /* "path:line:column", or NULL for a clause with no place. */
    const char *where;
} MoClause;
extern const MoClause mo_clauses[];

enum { MO_TEST, MO_TEST_REJECTS, MO_PROPERTY };
typedef struct { uint8_t kind; const char *name; MoValue (*fn)(void); } MoTest;
extern const MoTest mo_tests[];
extern const uint32_t mo_ntests;

typedef struct { MoValue (*fn)(void); uint32_t clause; uint32_t nnames; const char *const *names; } MoNever;
extern const MoNever mo_nevers[];
extern const uint32_t mo_nnevers;
/* Types some never reads with T.all. */
extern const uint32_t mo_nrecorded;
/* The refund module's Charge stand-in (prelude.zig), or UINT32_MAX when no module has one. */
extern const uint32_t mo_charge_decl;
/* The prelude's Request and Response structs (Http). */
extern const uint32_t mo_request_decl;
extern const uint32_t mo_response_decl;
/* The runtime surface's structs (step 23), and whether the binary was built with --surface. */
extern const uint32_t mo_process_info_decl;
extern const uint32_t mo_source_info_decl;
extern const uint32_t mo_memory_info_decl;
extern const bool mo_surface_built;
/* The runtime surface's own process, in mo_processes, or UINT32_MAX; MO_SURFACE's port, or -1; and
 * the line that says where it listens. */
extern const uint32_t mo_surface_process;
int mo_surface_port(void);
void mo_surface_listening(MoValue got);

/* Contracts (requires, ensures, refinements) are checked when this is set: in every binary
 * `mo build` makes unless it was built --no-contracts, and always in a test binary.
 * MO_CONTRACTS=0 or 1 overrides a program's build at run time. */
extern bool mo_contracts;
extern const bool mo_contracts_built;

/* ---- values */

#define MO_NONE_V ((MoValue){MO_NONE, 0, {0}})
static inline MoValue mo_bool(bool b) { MoValue v = {MO_BOOL, 0, {0}}; v.as.b = b; return v; }
static inline MoValue mo_i64(int64_t x) { MoValue v = {MO_INT, 0, {0}}; v.as.i = x; return v; }
static inline MoValue mo_u64(uint64_t x) {
    MoValue v = {x > (uint64_t)INT64_MAX ? MO_UINT : MO_INT, 0, {0}};
    v.as.u = x;
    return v;
}
MoValue mo_i128(__int128 x);
static inline MoValue mo_f64(double f) { MoValue v = {MO_FLOAT, 0, {0}}; v.as.f = f; return v; }
static inline MoValue mo_f64_bits(uint64_t bits) { MoValue v = {MO_FLOAT, 0, {0}}; v.as.u = bits; return v; }
static inline MoValue mo_time(int64_t ms) { MoValue v = {MO_TIME, 0, {0}}; v.as.i = ms; return v; }
static inline MoValue mo_duration(int64_t ms) { MoValue v = {MO_DURATION, 0, {0}}; v.as.i = ms; return v; }
static inline MoValue mo_str(const char *s, uint32_t len) { MoValue v = {MO_STRING, len, {0}}; v.as.s = s; return v; }
static inline MoValue mo_list(MoValue *xs, uint32_t n) { MoValue v = {MO_LIST, n, {0}}; v.as.xs = xs; return v; }
static inline MoValue mo_tuple_of(MoValue *xs, uint32_t n) { MoValue v = {MO_TUPLE, n, {0}}; v.as.xs = xs; return v; }
static inline MoValue mo_cap(uint32_t kind, uint32_t handle, int64_t delay) { MoValue v = {MO_CAP, kind | handle << 8, {0}}; v.as.i = delay; return v; }
static inline uint32_t mo_cap_kind(MoValue v) { return v.aux & 0xff; }
static inline uint32_t mo_cap_handle(MoValue v) { return v.aux >> 8; }
static inline uint32_t mo_vname(MoValue v) { return v.aux & 0xffff; }
static inline uint32_t mo_vcount(MoValue v) { return v.aux >> 16; }
/* Any integer as an __int128. */
static inline __int128 mo_wide(MoValue v) {
    return v.tag == MO_INT ? (__int128)v.as.i : v.tag == MO_UINT ? (__int128)v.as.u : *v.as.big;
}
/* The fields of a record, variant, or tuple, and how many. */
uint32_t mo_nfields(MoValue v);
static inline MoValue mo_field(MoValue v, uint32_t k) { return v.as.xs[k]; }

/* ---- memory: regions freed at safe points (vm.zig) */

typedef struct { uintptr_t base, end, top; } MoRegion;
extern MoRegion mo_heap;
/* Compaction runs: under a program's main, not in a test, whose memory goes whole. */
extern bool mo_compacts;
#define MO_FRAME_BUDGET ((size_t)1 << 20)
#define MO_LOOP_BUDGET ((size_t)256 << 10)

void *mo_alloc_bytes(size_t n);
MoValue *mo_alloc_values(size_t n);
static inline size_t mo_mark(void) { return mo_heap.top; }
/* A loop's safe point: `kept` is what its last compaction kept. */
static inline bool mo_loop_due(size_t mark, size_t kept) {
    return MO_UNLIKELY(mo_compacts && mo_heap.top - mark > 2 * kept + MO_LOOP_BUDGET);
}
static inline bool mo_frame_due(size_t frame) {
    return MO_UNLIKELY(mo_compacts && mo_heap.top - frame > MO_FRAME_BUDGET);
}
/* Keeps what `roots` reach past `from`, frees the rest; roots then hold the copies. */
void mo_compact(size_t from, MoValue *roots, size_t n);
/* The locals of a frame whose function can hold a process's handle, innermost first: what a
 * sweep reads under main to end the processes nothing can reach (mo_rt.c, processes). */
typedef struct MoHandleFrame { struct MoHandleFrame *next; MoValue *const *slots; uint32_t n; } MoHandleFrame;
extern MoHandleFrame *mo_handle_frames;
/* A read of a var other than by an update of it: a map or set it holds may be held twice. */
void mo_disown_in(MoValue v);

/* ---- building values */

MoValue mo_record(uint32_t decl, uint32_t n, const MoValue *fields);
MoValue mo_variant(uint32_t name, uint32_t n, const MoValue *fields);
MoValue mo_tuple(uint32_t n, const MoValue *elems);
MoValue mo_list_of(uint32_t n, const MoValue *elems);
MoValue mo_set_field(MoValue obj, uint32_t k, MoValue v);
MoValue mo_closure(MoCode code, uint32_t id, uint32_t n, const MoValue *caps);
MoValue mo_range(MoValue lo, MoValue hi);
MoValue mo_concat(uint32_t n, const MoValue *parts);
static inline MoValue mo_some(MoValue x) { return mo_variant(MO_N_SOME, 1, &x); }
static inline MoValue mo_nothing(void) { return mo_variant(MO_N_NONE, 0, NULL); }
static inline bool mo_is(MoValue v, uint32_t name) { return v.tag == MO_VARIANT && mo_vname(v) == name; }
static inline MoValue mo_invoke(MoValue f, const MoValue *args) { return f.as.fn->code(f.as.fn->cap, args); }

bool mo_equal(MoValue a, MoValue b);
/* The natural order: -1, 0, 1. */
int mo_order(MoValue a, MoValue b);
/* The comparison ops bytecode.Op names: eq ne lt le gt ge. */
enum { MO_EQ, MO_NE, MO_LT, MO_LE, MO_GT, MO_GE };
bool mo_compare(int op, MoValue l, MoValue r);

/* ---- crashes: a complete report, never a value */

_Noreturn void mo_crash(uint32_t clause);
_Noreturn void mo_crash_values(uint32_t clause, uint32_t n, const char *const *names, const MoValue *values);
/* An overflow or division by zero: `operands` named left and right, or value. */
_Noreturn void mo_crash_arith(uint8_t kind, uint32_t clause, uint32_t n, const MoValue *operands);
_Noreturn void mo_trip(uint32_t clause, uint32_t n, const MoValue *values);
/* A report made by the runtime: no clause, no place. */
_Noreturn void mo_fail(uint8_t kind, const char *within, const char *format, ...);
/* Calls nest at most this deep (contracts.depth_limit): every function counts itself in
 * mo_depth on entry and out on return, and the call past the limit crashes naming `name`. */
#define MO_DEPTH_LIMIT 10000
extern _Thread_local uint32_t mo_depth;
_Noreturn void mo_too_deep(const char *name);
/* A property attempt whose guard is false. */
_Noreturn void mo_discard(void);
/* No impl of a trait signature for this receiver. */
_Noreturn void mo_no_impl(const char *name, MoValue receiver);

/* ---- sized integer arithmetic: every operation traps on overflow (design-v0/02) */

#ifdef MO_WRAP
/* The bench's comparison build only (-fwrapv): wrapping arithmetic, never shipped. */
#define MO_ADD_OV(a, b, r) (*(r) = (a) + (b), 0)
#define MO_SUB_OV(a, b, r) (*(r) = (a) - (b), 0)
#define MO_MUL_OV(a, b, r) (*(r) = (a) * (b), 0)
#define MO_OUT(x, lo, hi) 0
#else
#define MO_ADD_OV(a, b, r) __builtin_add_overflow(a, b, r)
#define MO_SUB_OV(a, b, r) __builtin_sub_overflow(a, b, r)
#define MO_MUL_OV(a, b, r) __builtin_mul_overflow(a, b, r)
#define MO_OUT(x, lo, hi) ((x) < (lo) || (x) > (hi))
#endif

_Noreturn void mo_overflow2(uint32_t clause, MoValue l, MoValue r);
_Noreturn void mo_div_zero(uint32_t clause, MoValue l, MoValue r);

/* Int8 to Int32 work in int64 and check the range; Int64 checks the operation itself. */
#define MO_NARROW_SIGNED(K, LO, HI)                                                          \
    static inline MoValue mo_add_##K(MoValue l, MoValue r, uint32_t c) {                    \
        int64_t x = l.as.i + r.as.i;                                                         \
        if (MO_OUT(x, LO, HI)) mo_overflow2(c, l, r);                                        \
        return mo_i64(x);                                                                    \
    }                                                                                        \
    static inline MoValue mo_sub_##K(MoValue l, MoValue r, uint32_t c) {                    \
        int64_t x = l.as.i - r.as.i;                                                         \
        if (MO_OUT(x, LO, HI)) mo_overflow2(c, l, r);                                        \
        return mo_i64(x);                                                                    \
    }                                                                                        \
    static inline MoValue mo_mul_##K(MoValue l, MoValue r, uint32_t c) {                    \
        int64_t x = l.as.i * r.as.i;                                                         \
        if (MO_OUT(x, LO, HI)) mo_overflow2(c, l, r);                                        \
        return mo_i64(x);                                                                    \
    }                                                                                        \
    static inline MoValue mo_div_##K(MoValue l, MoValue r, uint32_t c) {                    \
        if (r.as.i == 0) mo_div_zero(c, l, r);                                               \
        int64_t x = l.as.i / r.as.i;                                                         \
        if (MO_OUT(x, LO, HI)) mo_overflow2(c, l, r);                                        \
        return mo_i64(x);                                                                    \
    }                                                                                        \
    static inline MoValue mo_rem_##K(MoValue l, MoValue r, uint32_t c) {                    \
        if (r.as.i == 0) mo_div_zero(c, l, r);                                               \
        return mo_i64(l.as.i % r.as.i);                                                      \
    }                                                                                        \
    static inline MoValue mo_neg_##K(MoValue v, uint32_t c) {                                \
        int64_t x = -v.as.i;                                                                 \
        if (MO_OUT(x, LO, HI)) mo_crash_arith(MO_R_OVERFLOW, c, 1, &v);                      \
        return mo_i64(x);                                                                    \
    }

#define MO_NARROW_UNSIGNED(K, HI)                                                            \
    static inline MoValue mo_add_##K(MoValue l, MoValue r, uint32_t c) {                    \
        uint64_t x = l.as.u + r.as.u;                                                        \
        if (MO_OUT(x, 0, HI)) mo_overflow2(c, l, r);                                         \
        return mo_i64((int64_t)x);                                                           \
    }                                                                                        \
    static inline MoValue mo_sub_##K(MoValue l, MoValue r, uint32_t c) {                    \
        if (MO_OUT(r.as.u, 0, l.as.u)) mo_overflow2(c, l, r);                                \
        return mo_i64((int64_t)(l.as.u - r.as.u));                                           \
    }                                                                                        \
    static inline MoValue mo_mul_##K(MoValue l, MoValue r, uint32_t c) {                    \
        uint64_t x = l.as.u * r.as.u;                                                        \
        if (MO_OUT(x, 0, HI)) mo_overflow2(c, l, r);                                         \
        return mo_i64((int64_t)x);                                                           \
    }                                                                                        \
    static inline MoValue mo_div_##K(MoValue l, MoValue r, uint32_t c) {                    \
        if (r.as.u == 0) mo_div_zero(c, l, r);                                               \
        return mo_i64((int64_t)(l.as.u / r.as.u));                                           \
    }                                                                                        \
    static inline MoValue mo_rem_##K(MoValue l, MoValue r, uint32_t c) {                    \
        if (r.as.u == 0) mo_div_zero(c, l, r);                                               \
        return mo_i64((int64_t)(l.as.u % r.as.u));                                           \
    }                                                                                        \
    static inline MoValue mo_neg_##K(MoValue v, uint32_t c) {                                \
        if (v.as.u != 0) mo_crash_arith(MO_R_OVERFLOW, c, 1, &v);                            \
        return v;                                                                            \
    }

MO_NARROW_SIGNED(i8, -128, 127)
MO_NARROW_SIGNED(i16, -32768, 32767)
MO_NARROW_SIGNED(i32, -2147483647 - 1, 2147483647)
MO_NARROW_UNSIGNED(u8, 255u)
MO_NARROW_UNSIGNED(u16, 65535u)
MO_NARROW_UNSIGNED(u32, 4294967295u)

static inline MoValue mo_add_i64(MoValue l, MoValue r, uint32_t c) {
    int64_t x;
    if (MO_ADD_OV(l.as.i, r.as.i, &x)) mo_overflow2(c, l, r);
    return mo_i64(x);
}
static inline MoValue mo_sub_i64(MoValue l, MoValue r, uint32_t c) {
    int64_t x;
    if (MO_SUB_OV(l.as.i, r.as.i, &x)) mo_overflow2(c, l, r);
    return mo_i64(x);
}
static inline MoValue mo_mul_i64(MoValue l, MoValue r, uint32_t c) {
    int64_t x;
    if (MO_MUL_OV(l.as.i, r.as.i, &x)) mo_overflow2(c, l, r);
    return mo_i64(x);
}
static inline MoValue mo_div_i64(MoValue l, MoValue r, uint32_t c) {
    if (r.as.i == 0) mo_div_zero(c, l, r);
    if (r.as.i == -1 && l.as.i == INT64_MIN) mo_overflow2(c, l, r);
    return mo_i64(l.as.i / r.as.i);
}
static inline MoValue mo_rem_i64(MoValue l, MoValue r, uint32_t c) {
    if (r.as.i == 0) mo_div_zero(c, l, r);
    if (r.as.i == -1) return mo_i64(0);
    return mo_i64(l.as.i % r.as.i);
}
static inline MoValue mo_neg_i64(MoValue v, uint32_t c) {
    int64_t x;
    if (MO_SUB_OV((int64_t)0, v.as.i, &x)) mo_crash_arith(MO_R_OVERFLOW, c, 1, &v);
    return mo_i64(x);
}
static inline MoValue mo_add_u64(MoValue l, MoValue r, uint32_t c) {
    uint64_t x;
    if (MO_ADD_OV(l.as.u, r.as.u, &x)) mo_overflow2(c, l, r);
    return mo_u64(x);
}
static inline MoValue mo_sub_u64(MoValue l, MoValue r, uint32_t c) {
    uint64_t x;
    if (MO_SUB_OV(l.as.u, r.as.u, &x)) mo_overflow2(c, l, r);
    return mo_u64(x);
}
static inline MoValue mo_mul_u64(MoValue l, MoValue r, uint32_t c) {
    uint64_t x;
    if (MO_MUL_OV(l.as.u, r.as.u, &x)) mo_overflow2(c, l, r);
    return mo_u64(x);
}
static inline MoValue mo_div_u64(MoValue l, MoValue r, uint32_t c) {
    if (r.as.u == 0) mo_div_zero(c, l, r);
    return mo_u64(l.as.u / r.as.u);
}
static inline MoValue mo_rem_u64(MoValue l, MoValue r, uint32_t c) {
    if (r.as.u == 0) mo_div_zero(c, l, r);
    return mo_u64(l.as.u % r.as.u);
}
static inline MoValue mo_neg_u64(MoValue v, uint32_t c) {
    if (v.as.u != 0) mo_crash_arith(MO_R_OVERFLOW, c, 1, &v);
    return v;
}

/* A contract's integers are unbounded; __int128 stands in (contracts.zig), and passing it
 * is an overflow crash, never a wrap. Floats, times, and durations go through mo_arith. */
enum { MO_OP_ADD, MO_OP_SUB, MO_OP_MUL, MO_OP_DIV, MO_OP_REM };
MoValue mo_arith_wide(int op, MoValue l, MoValue r, uint32_t clause);
MoValue mo_neg_wide(MoValue v, uint32_t clause);
MoValue mo_arith(int op, MoValue l, MoValue r, uint32_t clause);
MoValue mo_neg(MoValue v, uint32_t clause);

/* ---- what a test run records for a never's T.all (sim.zig) */

extern bool mo_records;
void mo_observe(MoValue v, uint32_t type);
MoValue mo_all(uint32_t index);

/* ---- the prelude's rows: each takes its receiver, positional arguments, named ones in
 * row order, and within: last, in `a`; `kind` is the receiver's integer kind, a checked
 * type for Json.encode, or MO_KIND_UNIQUE (prelude.zig, stdlib.zig, vm.zig). */
#define MO_ROW(name) MoValue name(const MoValue *a, uint32_t kind)
MO_ROW(mo_r_List_size); MO_ROW(mo_r_List_push); MO_ROW(mo_r_List_map); MO_ROW(mo_r_List_filter);
MO_ROW(mo_r_List_reduce); MO_ROW(mo_r_List_contains_q); MO_ROW(mo_r_List_first); MO_ROW(mo_r_List_last);
MO_ROW(mo_r_List_get); MO_ROW(mo_r_List_slice); MO_ROW(mo_r_List_take); MO_ROW(mo_r_List_drop);
MO_ROW(mo_r_List_concat); MO_ROW(mo_r_List_reverse); MO_ROW(mo_r_List_flat_map); MO_ROW(mo_r_List_any_q);
MO_ROW(mo_r_List_all_q); MO_ROW(mo_r_List_find); MO_ROW(mo_r_List_count); MO_ROW(mo_r_List_sort);
MO_ROW(mo_r_List_sort_by); MO_ROW(mo_r_List_sort_by_desc); MO_ROW(mo_r_List_min); MO_ROW(mo_r_List_max);
MO_ROW(mo_r_List_sum); MO_ROW(mo_r_min_of); MO_ROW(mo_r_max_of);
MO_ROW(mo_r_List_zip); MO_ROW(mo_r_List_enumerate); MO_ROW(mo_r_List_unique); MO_ROW(mo_r_List_group_by);
MO_ROW(mo_r_Map_new); MO_ROW(mo_r_Map_size); MO_ROW(mo_r_Map_get); MO_ROW(mo_r_Map_has_q);
MO_ROW(mo_r_Map_set); MO_ROW(mo_r_Map_update); MO_ROW(mo_r_Map_remove); MO_ROW(mo_r_Map_keys);
MO_ROW(mo_r_Map_values); MO_ROW(mo_r_Map_entries); MO_ROW(mo_r_Set_new); MO_ROW(mo_r_Set_size);
MO_ROW(mo_r_Set_add); MO_ROW(mo_r_Set_remove); MO_ROW(mo_r_Set_has_q); MO_ROW(mo_r_Set_to_list);
MO_ROW(mo_r_String_size); MO_ROW(mo_r_String_bytes); MO_ROW(mo_r_String_byte_size); MO_ROW(mo_r_String_starts_with_q);
MO_ROW(mo_r_String_from_bytes); MO_ROW(mo_r_String_chars); MO_ROW(mo_r_String_split); MO_ROW(mo_r_String_lines);
MO_ROW(mo_r_String_trim); MO_ROW(mo_r_String_ends_with_q); MO_ROW(mo_r_String_contains_q); MO_ROW(mo_r_String_index_of);
MO_ROW(mo_r_String_slice); MO_ROW(mo_r_String_replace); MO_ROW(mo_r_String_to_upper); MO_ROW(mo_r_String_to_lower);
MO_ROW(mo_r_String_pad_left); MO_ROW(mo_r_String_pad_right); MO_ROW(mo_r_String_repeat); MO_ROW(mo_r_String_join);
MO_ROW(mo_r_String_to_u64); MO_ROW(mo_r_String_to_i64); MO_ROW(mo_r_String_to_f64);
MO_ROW(mo_r_Int_to_u8); MO_ROW(mo_r_Int_to_u16); MO_ROW(mo_r_Int_to_u32); MO_ROW(mo_r_Int_to_u64); MO_ROW(mo_r_Int_to_i64);
MO_ROW(mo_r_Int_checked_to_u8); MO_ROW(mo_r_Int_checked_to_u16); MO_ROW(mo_r_Int_checked_to_u32);
MO_ROW(mo_r_Int_checked_to_u64); MO_ROW(mo_r_Int_checked_to_i64); MO_ROW(mo_r_Int_to_f64);
MO_ROW(mo_r_Float64_round); MO_ROW(mo_r_Float64_to_string);
MO_ROW(mo_r_Int_checked_add); MO_ROW(mo_r_Int_checked_sub); MO_ROW(mo_r_Int_checked_mul);
MO_ROW(mo_r_Int_saturating_add); MO_ROW(mo_r_Int_saturating_sub); MO_ROW(mo_r_Int_saturating_mul);
MO_ROW(mo_r_Int_wrapping_add); MO_ROW(mo_r_Int_wrapping_sub); MO_ROW(mo_r_Int_wrapping_mul);
MO_ROW(mo_r_Int_ms); MO_ROW(mo_r_Int_minute); MO_ROW(mo_r_Int_days);
MO_ROW(mo_r_Time_fixture); MO_ROW(mo_r_Time_parse); MO_ROW(mo_r_Time_from_parts); MO_ROW(mo_r_Time_to_iso8601);
MO_ROW(mo_r_Time_since); MO_ROW(mo_r_Duration_ms); MO_ROW(mo_r_Duration_seconds); MO_ROW(mo_r_Duration_minutes);
MO_ROW(mo_r_Clock_now); MO_ROW(mo_r_Clock_fixture);
MO_ROW(mo_r_Fs_read); MO_ROW(mo_r_Fs_read_lines); MO_ROW(mo_r_Fs_read_bytes); MO_ROW(mo_r_Fs_fold_lines); MO_ROW(mo_r_Fs_size); MO_ROW(mo_r_Fs_list);
MO_ROW(mo_r_Fs_scoped); MO_ROW(mo_r_Fs_read_only); MO_ROW(mo_r_Fs_write); MO_ROW(mo_r_Fs_append);
MO_ROW(mo_r_Fs_remove); MO_ROW(mo_r_Fs_rename); MO_ROW(mo_r_Fs_mkdir); MO_ROW(mo_r_Fs_fixture); MO_ROW(mo_r_Fs_fixture_delay);
MO_ROW(mo_r_Events_emit); MO_ROW(mo_r_Events_fixture); MO_ROW(mo_r_Ledger_fixture);
MO_ROW(mo_r_Ledger_find_charge); MO_ROW(mo_r_Ledger_save_charge);
MO_ROW(mo_r_Platform_args); MO_ROW(mo_r_Platform_env); MO_ROW(mo_r_Platform_stdout); MO_ROW(mo_r_Platform_stderr);
MO_ROW(mo_r_Platform_fs); MO_ROW(mo_r_Platform_clock); MO_ROW(mo_r_Platform_net); MO_ROW(mo_r_Platform_exit);
MO_ROW(mo_r_Net_listen); MO_ROW(mo_r_Net_connect); MO_ROW(mo_r_Net_fixture); MO_ROW(mo_r_Listener_accept);
MO_ROW(mo_r_Listener_port); MO_ROW(mo_r_Conn_read_line); MO_ROW(mo_r_Conn_write); MO_ROW(mo_r_Conn_close);
MO_ROW(mo_r_Listener_serve); MO_ROW(mo_r_Conn_lines); MO_ROW(mo_r_HttpListener_serve);
MO_ROW(mo_r_Platform_http); MO_ROW(mo_r_Http_listen); MO_ROW(mo_r_Http_send); MO_ROW(mo_r_Http_fixture);
MO_ROW(mo_r_HttpListener_accept); MO_ROW(mo_r_HttpListener_port); MO_ROW(mo_r_Exchange_request); MO_ROW(mo_r_Exchange_reply);
MO_ROW(mo_r_Platform_runtime); MO_ROW(mo_r_Runtime_processes); MO_ROW(mo_r_Runtime_state); MO_ROW(mo_r_Runtime_recent);
MO_ROW(mo_r_Runtime_events); MO_ROW(mo_r_Runtime_crashes); MO_ROW(mo_r_Runtime_sources); MO_ROW(mo_r_Runtime_memory);
MO_ROW(mo_r_Runtime_slowest); MO_ROW(mo_r_Runtime_send); MO_ROW(mo_r_Runtime_pause); MO_ROW(mo_r_Runtime_resume);
MO_ROW(mo_r_Runtime_read_only); MO_ROW(mo_r_Runtime_fixture);
MO_ROW(mo_r_Env_get); MO_ROW(mo_r_Out_write); MO_ROW(mo_r_Out_write_line); MO_ROW(mo_r_Out_flush);
MO_ROW(mo_r_Out_fixture); MO_ROW(mo_r_Out_written);
MO_ROW(mo_r_Json_encode); MO_ROW(mo_r_Json_decode); MO_ROW(mo_r_Json_to_i64); MO_ROW(mo_r_Deadline_at_most); MO_ROW(mo_r_Deadline_fixture);
MO_ROW(mo_r_Charge_fixture); MO_ROW(mo_r_Charge_fixture_at); MO_ROW(mo_r_Charge_refunded_q);
MO_ROW(mo_r_Money_cents); MO_ROW(mo_r_Money_zero);

/* A row compiled programs do not run: a clear crash. */
_Noreturn void mo_not_compiled(const char *what);

/* ---- processes (sim.zig, turns.zig): the program's tables, and the rows start, send, and ask */

/* bytecode.Restart, in its order. */
enum { MO_RESTART_ALWAYS, MO_RESTART_ON_CRASH, MO_RESTART_NEVER };

/* Each takes its parameters in `args`, then the state after and the state before; true when broken. */
typedef struct { MoCode fn; uint32_t clause; } MoInvariant;
typedef struct {
    const char *name;
    uint32_t decl;
    uint32_t mailbox;
    /* The parameters in `args` give the first state. */
    MoCode init;
    /* The parameters, the state, and a message in `args` give (reply, state). */
    MoCode update;
    uint32_t ninvariants;
    const MoInvariant *invariants;
    /* An invariant reads old(state), so an update never writes the state before it in place. */
    bool reads_old;
} MoProcess;
/* A child line: `args` takes the supervisor's parameters and gives the child's as a tuple; `per`
 * gives the window, or is NULL; max_restarts is UINT32_MAX when the line names none. */
typedef struct { uint32_t process; MoCode args; uint8_t restart; uint32_t max_restarts; MoCode per; } MoChild;
typedef struct { const char *name; uint32_t nchildren; const MoChild *children; } MoSupervisor;
extern const MoProcess mo_processes[];
extern const uint32_t mo_nprocesses;
extern const MoSupervisor mo_supervisors[];
extern const uint32_t mo_nsupervisors;

/* `Name.start(args)`: its Handle. */
MoValue mo_spawn(uint32_t process, uint32_t n, const MoValue *args);
/* `Sup.start(args)`: its one child's Handle, a tuple of them in child order, or no value. */
MoValue mo_start_supervisor(uint32_t supervisor, uint32_t n, const MoValue *args);
MoValue mo_send(MoValue handle, MoValue message);
/* Ok(reply), Error(Timeout), or Error(Down). */
MoValue mo_ask(MoValue handle, MoValue message, MoValue within);
/* Deadlines (step 22): reply_by in the running update, what remains of a Deadline as a Duration
 * (-1 ms when nothing does), and the Timeout a call with nothing left gives at once. */
MoValue mo_reply_by(void);
MoValue mo_deadline_left(MoValue deadline);
MoValue mo_timed_out_now(void);
/* A row that waits, timed for the events (step 23): the events' clock before it, and its result,
 * given back, after it. */
MoValue mo_wait_begin(const char *call);
MoValue mo_waited(const char *call, MoValue since, MoValue result);
/* Between two statements of a test, or of main in a program with processes. */
void mo_settle(void);

/* ---- any(T), a zero value, and the platform */

MoValue mo_generate(uint32_t type, const char *name);
/* The zero value of a type, or crashes with `clause` when it has none. */
MoValue mo_zero(uint32_t type, uint32_t clause);
MoValue mo_platform(void);

/* ---- entry points */

/* main on Mo.Server: args, env, the working directory, and the exit code. */
void mo_program_start(int argc, char **argv);
int mo_program_end(void);
/* Every test of the module, printed as `mo test` prints them; 1 when one fails. */
int mo_run_tests(void);

#endif
