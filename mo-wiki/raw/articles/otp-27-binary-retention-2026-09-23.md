---
source_url: https://www.erlang.org/docs/27/apps/stdlib/binary.html
ingested: 2026-09-23
version: "OTP 27.3.4.16 / stdlib 6.2.2.4; publication date unstated"
read_status: complete-extracted-text-read
extraction: Exa cached text
sha256: 0e8d0c799784510fe915da081d59adcd0f116850a7a1e97ac41268a4017a29ca
---
binary — OTP 27.3.4.16 (stdlib 6.2.2.4)

# binary (stdlib v6.2.2.4) 

Library for handling binary data.

This module contains functions for manipulating byte-oriented binaries. Although the majority of functions could be provided using bit-syntax, the functions in this library are highly optimized and are expected to either execute faster or consume less memory, or both, than a counterpart written in pure Erlang.

The module is provided according to Erlang Enhancement Proposal (EEP) 31.

#### Note

The library handles byte-oriented data. For bitstrings that are not binaries (does not contain whole octets of bits) a `badarg` exception is thrown from any of the functions in this module.

## Types 

 cp() 

Opaque data type representing a compiled search pattern.

 part() 

A representation of a part (or range) in a binary. `Start` is a zero-based offset into a `binary/0` and `Length` is the length of that part.

## Functions 

 at(Subject, Pos) 

Returns the byte at position `Pos` (zero-based) in binary `Subject` as an integer.

 bin_to_list(Subject) 

Converts `Subject` to a list of `byte/0` s, each representing the value of one byte.

 bin_to_list(Subject, PosLen) 

Equivalent to `bin_to_list(Subject, Pos, Len)`.

 bin_to_list(Subject, Pos, Len) 

Converts `Subject` to a list of `byte/0` s, each representing the value of one byte. `PosLen` or alternatively `Pos` and `Len` denote which part of the `Subject` binary to convert. By default, the entire `Subject` binary is converted.

 compile_pattern(Pattern) 

Builds an internal structure representing a compilation of a search pattern, later to be used in functions `match/3`, `matches/3`, `split/3`, or `replace/4`.

 copy(Subject) 

Equivalent to `copy(Subject, 1)`.

 copy(Subject, N) 

Creates a binary with the content of `Subject` duplicated `N` times.

 decode_hex(Bin) 

Decodes a hex encoded binary into a binary.

 decode_unsigned(Subject) 

Equivalent to `decode_unsigned(Subject, big)`.

 decode_unsigned(Subject, Endianness) 

Converts the binary digit representation, in big endian or little endian, of a positive integer in `Subject` to an Erlang `integer/0`.

 encode_hex(Bin) 

Equivalent to `encode_hex(Bin, uppercase)`.

 encode_hex(Bin, Case) 

Encodes a binary into a hex encoded binary using the specified case for the hexadecimal digits "a" to "f".

 encode_unsigned(Unsigned) 

Equivalent to `encode_unsigned(Unsigned, big)`.

 encode_unsigned(Unsigned, Endianness) 

Converts a positive integer to the smallest possible representation in a binary digit representation, either big endian or little endian.

 first(Subject) 

Returns the first byte of binary `Subject` as an integer. If the size of `Subject` is zero, a `badarg` exception is raised.

 last(Subject) 

Returns the last byte of binary `Subject` as an integer. If the size of `Subject` is zero, a `badarg` exception is raised.

 list_to_bin(ByteList) 

Works exactly as `erlang:list_to_binary/1`, added for completeness.

 longest_common_prefix(Binaries) 

Returns the length of the longest common prefix of the binaries in list `Binaries`.

 longest_common_suffix(Binaries) 

Returns the length of the longest common suffix of the binaries in list `Binaries`.

 match(Subject, Pattern) 

Equivalent to `match(Subject, Pattern, [])`.

 match(Subject, Pattern, Options) 

Searches for the first occurrence of `Pattern` in `Subject` and returns the position and length.

 matches(Subject, Pattern) 

Equivalent to `matches(Subject, Pattern, [])`.

 matches(Subject, Pattern, Options) 

As `match/2`, but `Subject` is searched until exhausted and a list of all non-overlapping parts matching `Pattern` is returned (in order).

 part(Subject, PosLen) 

Equivalent to `part(Subject, Pos, Len)`.

 part(Subject, Pos, Len) 

Extracts the part of binary `Subject` described by `PosLen`.

 referenced_byte_size(Binary) 

Get the size of the underlying binary referenced by `Binary`.

 replace(Subject, Pattern, Replacement) 

Equivalent to `replace(Subject, Pattern, Replacement, [])`.

 replace(Subject, Pattern, Replacement, Options) 

Constructs a new binary by replacing the parts in `Subject` matching `Pattern` with `Replacement` if given as a literal `binary/0` or with the result of applying `Replacement` to a matching subpart if given as a `fun`.

 split(Subject, Pattern) 

Equivalent to `split(Subject, Pattern, [])`.

 split(Subject, Pattern, Options) 

Splits `Subject` into a list of binaries based on `Pattern`.

```
-opaque cp()
```

Opaque data type representing a compiled search pattern.

Guaranteed to be a `tuple/0` to allow programs to distinguish it from non-precompiled search patterns.

# part()

```
-type part() :: {Start :: non_neg_integer(), Length :: integer()}.
```

A representation of a part (or range) in a binary. `Start` is a zero-based offset into a `binary/0` and `Length` is the length of that part.

As input to functions in this module, a reverse part specification is allowed, constructed with a negative `Length`, so that the part of the binary begins at `Start` + `Length` and is -`Length` long. This is useful for referencing the last `N` bytes of a binary as `{size(Binary), -N}`. The functions in this module always return `part/0` s with positive `Length`.

# at(Subject, Pos)

```
-spec at(Subject, Pos) -> byte() when Subject :: binary(), Pos :: non_neg_integer().
```

Returns the byte at position `Pos` (zero-based) in binary `Subject` as an integer.

If `Pos` >= `byte_size(Subject)`, a `badarg` exception is raised.

# bin_to_list(Subject)

```
-spec bin_to_list(Subject) -> [byte()] when Subject :: binary().
```

Converts `Subject` to a list of `byte/0` s, each representing the value of one byte.

```
1> binary:bin_to_list(<<"erlang">>).
"erlang"
%% or [101,114,108,97,110,103] in list notation.
```

# bin_to_list(Subject, PosLen)

```
-spec bin_to_list(Subject, PosLen) -> [byte()] when Subject :: binary(), PosLen :: part().
```

Equivalent to `bin_to_list(Subject, Pos, Len)`.

# bin_to_list(Subject, Pos, Len)

```
-spec bin_to_list(Subject, Pos, Len) -> [byte()]
                     when Subject :: binary(), Pos :: non_neg_integer(), Len :: integer().
```

Converts `Subject` to a list of `byte/0` s, each representing the value of one byte. `PosLen` or alternatively `Pos` and `Len` denote which part of the `Subject` binary to convert. By default, the entire `Subject` binary is converted.

```
1> binary:bin_to_list(<<"erlang">>, {1,3}).
"rla"
%% or [114,108,97] in list notation.
```

If `PosLen` or alternatively `Pos` and `Len` in any way reference outside the binary, a `badarg` exception is raised.

# compile_pattern(Pattern)

```
-spec compile_pattern(Pattern) -> cp()
                         when
                             Pattern :: PatternBinary | [PatternBinary, ...],
                             PatternBinary :: nonempty_binary().
```

Builds an internal structure representing a compilation of a search pattern, later to be used in functions `match/3`, `matches/3`, `split/3`, or `replace/4`.

The `cp/0` returned is guaranteed to be a `tuple/0` to allow programs to distinguish it from non-precompiled search patterns.

When a list of binaries is specified, it denotes a set of alternative binaries to search for. For example, if `[<<"functional">>,<<"programming">>]` is specified as `Pattern`, this means either `<<"functional">>` or `<<"programming">>`". The pattern is a set of alternatives; when only a single binary is specified, the set has only one element. The order of alternatives in a pattern is not significant.

The list of binaries used for search alternatives must be flat, proper and non-empty.

If `Pattern` is not a binary or a flat proper non-empty list of binaries with length > 0, a `badarg` exception is raised.

```
-spec copy(Subject) -> binary() when Subject :: binary().
```

Equivalent to `copy(Subject, 1)`.

# copy(Subject, N)

```
-spec copy(Subject, N) -> binary() when Subject :: binary(), N :: non_neg_integer().
```

Creates a binary with the content of `Subject` duplicated `N` times.

This function always creates a new binary, even if `N = 1`. By using `copy/1` on a binary referencing a larger binary, one can free up the larger binary for garbage collection.

By deliberately copying a single binary to avoid referencing a larger binary, one can, instead of freeing up the larger binary for later garbage collection, create much more binary data than needed. Sharing binary data is usually good. Only in special cases, when small parts reference large binaries and the large binaries are no longer used in any process, deliberate copying can be a good idea.

# decode_hex(Bin)

```
-spec decode_hex(Bin) -> Bin2 when Bin :: <<_:_*16>>, Bin2 :: binary().
```

Decodes a hex encoded binary into a binary.

```
1> binary:decode_hex(<<"66">>).
<<"f">>
```

# decode_unsigned(Subject)

```
-spec decode_unsigned(Subject) -> Unsigned when Subject :: binary(), Unsigned :: non_neg_integer().
```

Equivalent to `decode_unsigned(Subject, big)`.

# decode_unsigned(Subject, Endianness)

```
-spec decode_unsigned(Subject, Endianness) -> Unsigned
                         when
                             Subject :: binary(),
                             Endianness :: big | little,
                             Unsigned :: non_neg_integer().
```

Converts the binary digit representation, in big endian or little endian, of a positive integer in `Subject` to an Erlang `integer/0`.

```
1> binary:decode_unsigned(<<169,138,199>>).
11111111
2> binary:decode_unsigned(<<169,138,199>>, big).
11111111
3> binary:decode_unsigned(<<169,138,199>>, little).
13077161
```

# encode_hex(Bin)

```
-spec encode_hex(Bin) -> Bin2 when Bin :: binary(), Bin2 :: <<_:_*16>>.
```

Equivalent to `encode_hex(Bin, uppercase)`.

# encode_hex(Bin, Case)

```
-spec encode_hex(Bin, Case) -> Bin2
                    when Bin :: binary(), Case :: lowercase | uppercase, Bin2 :: <<_:_*16>>.
```

Encodes a binary into a hex encoded binary using the specified case for the hexadecimal digits "a" to "f".

The default case is `uppercase`.

```
1> binary:encode_hex(<<"f">>).
<<"66">>
2> binary:encode_hex(<<"/">>).
<<"2F">>
3> binary:encode_hex(<<"/">>, lowercase).
<<"2f">>
4> binary:encode_hex(<<"/">>, uppercase).
<<"2F">>
```

# encode_unsigned(Unsigned)

```
-spec encode_unsigned(Unsigned) -> binary() when Unsigned :: non_neg_integer().
```

Equivalent to `encode_unsigned(Unsigned, big)`.

# encode_unsigned(Unsigned, Endianness)

```
-spec encode_unsigned(Unsigned, Endianness) -> binary()
                         when Unsigned :: non_neg_integer(), Endianness :: big | little.
```

Converts a positive integer to the smallest possible representation in a binary digit representation, either big endian or little endian.

```
1> binary:encode_unsigned(11111111).
<<169,138,199>>
2> binary:encode_unsigned(11111111, big).
<<169,138,199>>
2> binary:encode_unsigned(11111111, little).
<<199,138,169>>
```

```
-spec first(Subject) -> byte() when Subject :: binary().
```

Returns the first byte of binary `Subject` as an integer. If the size of `Subject` is zero, a `badarg` exception is raised.

# last(Subject)

```
-spec last(Subject) -> byte() when Subject :: binary().
```

Returns the last byte of binary `Subject` as an integer. If the size of `Subject` is zero, a `badarg` exception is raised.

# list_to_bin(ByteList)

```
-spec list_to_bin(ByteList) -> binary() when ByteList :: iolist().
```

Works exactly as `erlang:list_to_binary/1`, added for completeness.

# longest_common_prefix(Binaries)

```
-spec longest_common_prefix(Binaries) -> non_neg_integer() when Binaries :: [binary(), ...].
```

Returns the length of the longest common prefix of the binaries in list `Binaries`.

Example:

```
1> binary:longest_common_prefix([<<"erlang">>, <<"ergonomy">>]).
2
2> binary:longest_common_prefix([<<"erlang">>, <<"perl">>]).
0
```

If `Binaries` is not a flat non-empty list of binaries, a `badarg` exception is raised.

```
-spec longest_common_suffix(Binaries) -> non_neg_integer() when Binaries :: [binary(), ...].
```

Returns the length of the longest common suffix of the binaries in list `Binaries`.

```
1> binary:longest_common_suffix([<<"erlang">>, <<"fang">>]).
3
2> binary:longest_common_suffix([<<"erlang">>, <<"perl">>]).
0
```

If `Binaries` is not a flat non-empty list of binaries, a `badarg` exception is raised.

# match(Subject, Pattern)

```
-spec match(Subject, Pattern) -> Found | nomatch
               when
                   Subject :: binary(),
                   Pattern :: PatternBinary | [PatternBinary, ...] | cp(),
                   PatternBinary :: nonempty_binary(),
                   Found :: part().
```

Equivalent to `match(Subject, Pattern, [])`.

# match(Subject, Pattern, Options)

```
-spec match(Subject, Pattern, Options) -> Found | nomatch
               when
                   Subject :: binary(),
                   Pattern :: PatternBinary | [PatternBinary, ...] | cp(),
                   PatternBinary :: nonempty_binary(),
                   Found :: part(),
                   Options :: [Option],
                   Option :: {scope, part()}.
```

Searches for the first occurrence of `Pattern` in `Subject` and returns the position and length.

The function returns `{Pos, Length}` for the binary in `Pattern`, starting at the lowest position in `Subject`.

```
1> binary:match(<<"abcde">>, [<<"bcde">>, <<"cd">>],[]).
{1,4}
```

Even though `<<"cd">>` ends before `<<"bcde">>`, `<<"bcde">>` begins first and is therefore the first match. If two overlapping matches begin at the same position, the longest is returned.

Summary of the options:

- {scope, {Start, Length}} - Only the specified part is searched. Return values still have offsets from the beginning of `Subject`. A negative `Length` is allowed as described in section Data Types in this manual.

If none of the strings in `Pattern` is found, the atom `nomatch` is returned.

For a description of `Pattern`, see function `compile_pattern/1`.

If `{scope, {Start,Length}}` is specified in the options such that `Start` > size of `Subject`, `Start` + `Length` < 0 or `Start` + `Length` > size of `Subject`, a `badarg` exception is raised.

# matches(Subject, Pattern)

```
-spec matches(Subject, Pattern) -> Found
                 when
                     Subject :: binary(),
                     Pattern :: PatternBinary | [PatternBinary, ...] | cp(),
                     PatternBinary :: nonempty_binary(),
                     Found :: [part()].
```

Equivalent to `matches(Subject, Pattern, [])`.

# matches(Subject, Pattern, Options)

```
-spec matches(Subject, Pattern, Options) -> Found
                 when
                     Subject :: binary(),
                     Pattern :: PatternBinary | [PatternBinary, ...] | cp(),
                     PatternBinary :: nonempty_binary(),
                     Found :: [part()],
                     Options :: [Option],
                     Option :: {scope, part()}.
```

As `match/2`, but `Subject` is searched until exhausted and a list of all non-overlapping parts matching `Pattern` is returned (in order).

The first and longest match is preferred to a shorter, which is illustrated by the following example:

```
1> binary:matches(<<"abcde">>,
                  [<<"bcde">>,<<"bc">>,<<"de">>],[]).
[{1,4}]
```

The result shows that <<"bcde">> is selected instead of the shorter match <<"bc">> (which would have given raise to one more match, <<"de">>). This corresponds to the behavior of POSIX regular expressions (and programs like awk), but is not consistent with alternative matches in `re` (and Perl), where instead lexical ordering in the search pattern selects which string matches.

If none of the strings in a pattern is found, an empty list is returned.

For a description of `Pattern`, see `compile_pattern/1`. For a description of available options, see `match/3`.

If `{scope, {Start,Length}}` is specified in the options such that `Start` > size of `Subject`, `Start + Length` < 0 or `Start + Length` is > size of `Subject`, a `badarg` exception is raised.

# part(Subject, PosLen)

```
-spec part(Subject, PosLen) -> binary() when Subject :: binary(), PosLen :: part().
```

Equivalent to `part(Subject, Pos, Len)`.

# part(Subject, Pos, Len)

```
-spec part(Subject, Pos, Len) -> binary()
              when Subject :: binary(), Pos :: non_neg_integer(), Len :: integer().
```

Extracts the part of binary `Subject` described by `PosLen`.

A negative length can be used to extract bytes at the end of a binary:

```
1> Bin = <<1,2,3,4,5,6,7,8,9,10>>.
2> binary:part(Bin, {byte_size(Bin), -5}).
<<6,7,8,9,10>>
```

`part/2` and `part/3` are also available in the `erlang` module under the names `binary_part/2` and `binary_part/3`. Those BIFs are allowed in guard tests.

If `PosLen` in any way references outside the binary, a `badarg` exception is raised.

# referenced_byte_size(Binary)

```
-spec referenced_byte_size(Binary) -> non_neg_integer() when Binary :: binary().
```

Get the size of the underlying binary referenced by `Binary`.

If a binary references a larger binary (often described as being a subbinary), it can be useful to get the size of the referenced binary. This function can be used in a program to trigger the use of `copy/1`. By copying a binary, one can dereference the original, possibly large, binary that a smaller binary is a reference to.

```
store(Binary, GBSet) ->
  NewBin =
      case binary:referenced_byte_size(Binary) of
          Large when Large > 2 * byte_size(Binary) ->
             binary:copy(Binary);
          _ ->
             Binary
      end,
  gb_sets:insert(NewBin,GBSet).
```

In this example, we chose to copy the binary content before inserting it in `gb_sets:set()` if it references a binary more than twice the data size we want to keep. Of course, different rules apply when copying to different programs.

Binary sharing occurs whenever binaries are taken apart. This is the fundamental reason why binaries are fast, decomposition can always be done with O(1) complexity. In rare circumstances this data sharing is however undesirable, why this function together with `copy/1` can be useful when optimizing for memory use.

Example of binary sharing:

```
1> A = binary:copy(<<1>>, 100).
<<1,1,1,1,1 ...
2> byte_size(A).
100
3> binary:referenced_byte_size(A).
100
4> <<B:10/binary, C:90/binary>> = A.
<<1,1,1,1,1 ...
5> {byte_size(B), binary:referenced_byte_size(B)}.
{10,10}
6> {byte_size(C), binary:referenced_byte_size(C)}.
{90,100}
```

In the above example, the small binary `B` was copied while the larger binary `C` references binary `A`.

Binary data is shared among processes. If another process still references the larger binary, copying the part this process uses only consumes more memory and does not free up the larger binary for garbage collection. Use this kind of intrusive functions with extreme care and only if a real problem is detected.

# replace(Subject, Pattern, Replacement)

```
-spec replace(Subject, Pattern, Replacement) -> Result
                 when
                     Subject :: binary(),
                     Pattern :: PatternBinary | [PatternBinary, ...] | cp(),
                     PatternBinary :: nonempty_binary(),
                     Replacement :: binary() | fun((binary()) -> binary()),
                     Result :: binary().
```

Equivalent to `replace(Subject, Pattern, Replacement, [])`.

# replace(Subject, Pattern, Replacement, Options)

```
-spec replace(Subject, Pattern, Replacement, Options) -> Result
                 when
                     Subject :: binary(),
                     Pattern :: PatternBinary | [PatternBinary, ...] | cp(),
                     PatternBinary :: nonempty_binary(),
                     Replacement :: binary() | fun((binary()) -> binary()),
                     Options :: [Option],
                     Option :: global | {scope, part()} | {insert_replaced, InsPos},
                     InsPos :: OnePos | [OnePos],
                     OnePos :: non_neg_integer(),
                     Result :: binary().
```

Constructs a new binary by replacing the parts in `Subject` matching `Pattern` with `Replacement` if given as a literal `binary/0` or with the result of applying `Replacement` to a matching subpart if given as a `fun`.

If `Replacement` is given as a `binary/0` and the matching subpart of `Subject` giving raise to the replacement is to be inserted in the result, option `{insert_replaced, InsPos}` inserts the matching part into `Replacement` at the specified position (or positions) before inserting `Replacement` into `Subject`. If `Replacement` is given as a `fun` instead, this option is ignored.

If any position specified in `InsPos` > size of the replacement binary, a `badarg` exception is raised.

Options `global` and `{scope, part()}` work as for `split/3`. The return type is always a `binary/0`.

For a description of `Pattern`, see `compile_pattern/1`.

```
1> binary:replace(<<"abcde">>, [<<"b">>, <<"d">>], <<"X">>, []).
<<"aXcde">>

2> binary:replace(<<"abcde">>, [<<"b">>, <<"d">>], <<"X">>, [global]).
<<"aXcXe">>

3> binary:replace(<<"abcde">>, <<"b">>, <<"[]">>, [{insert_replaced, 1}]).
<<"a[b]cde">>

4> binary:replace(<<"abcde">>, [<<"b">>, <<"d">>], <<"[]">>, [global, {insert_replaced, 1}]).
<<"a[b]c[d]e">>

5> binary:replace(<<"abcde">>, [<<"b">>, <<"d">>], <<"[]">>, [global, {insert_replaced, [1, 1]}]).
<<"a[bb]c[dd]e">>

6> binary:replace(<<"abcde">>, [<<"b">>, <<"d">>], <<"[-]">>, [global, {insert_replaced, [1, 2]}]).
<<"a[b-b]c[d-d]e">>

7> binary:replace(<<"abcde">>, [<<"b">>, <<"d">>], fun(M) -> <<$[, M/binary, $]>> end, []).
<<"a[b]cde">>

8> binary:replace(<<"abcde">>, [<<"b">>, <<"d">>], fun(M) -> <<$[, M/binary, $]>> end, [global]).
<<"a[b]c[d]e">>
```

# split(Subject, Pattern)

```
-spec split(Subject, Pattern) -> Parts
               when
                   Subject :: binary(),
                   Pattern :: PatternBinary | [PatternBinary, ...] | cp(),
                   PatternBinary :: nonempty_binary(),
                   Parts :: [binary()].
```

Equivalent to `split(Subject, Pattern, [])`.

# split(Subject, Pattern, Options)

```
-spec split(Subject, Pattern, Options) -> Parts
               when
                   Subject :: binary(),
                   Pattern :: PatternBinary | [PatternBinary, ...] | cp(),
                   PatternBinary :: nonempty_binary(),
                   Options :: [Option],
                   Option :: {scope, part()} | trim | global | trim_all,
                   Parts :: [binary()].
```

Splits `Subject` into a list of binaries based on `Pattern`.

If option `global` is not specified, only the first occurrence of `Pattern` in `Subject` gives rise to a split.

The parts of `Pattern` found in `Subject` are not included in the result.

```
1> binary:split(<<1,255,4,0,0,0,2,3>>, [<<0,0,0>>,<<2>>],[]).
[<<1,255,4>>, <<2,3>>]
2> binary:split(<<0,1,0,0,4,255,255,9>>, [<<0,0>>, <<255,255>>],[global]).
[<<0,1>>,<<4>>,<<9>>]
```

Summary of options:

- {scope, part()} - Works as in `match/3` and `matches/3`. Notice that this only defines the scope of the search for matching strings, it does not cut the binary before splitting. The bytes before and after the scope are kept in the result. See the example below.
- trim - Removes trailing empty parts of the result (as does `trim` in `re:split/3`.
- trim_all - Removes all empty parts of the result.
- global - Repeats the split until `Subject` is exhausted. Conceptually option `global` makes split work on the positions returned by `matches/3`, while it normally works on the position returned by `match/3`.

Example of the difference between a scope and taking the binary apart before splitting:

```
1> binary:split(<<"banana">>, [<<"a">>],[{scope,{2,3}}]).
[<<"ban">>,<<"na">>]
2> binary:split(binary:part(<<"banana">>,{2,3}), [<<"a">>],[]).
[<<"n">>,<<"n">>]
```

The return type is always a list of binaries that are all referencing `Subject`. This means that the data in `Subject` is not copied to new binaries, and that `Subject` cannot be garbage collected until the results of the split are no longer referenced.

For a description of `Pattern`, see `compile_pattern/1`.