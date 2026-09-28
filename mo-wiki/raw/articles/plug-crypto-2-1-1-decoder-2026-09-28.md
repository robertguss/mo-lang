---
source_url: https://hexdocs.pm/plug_crypto/2.1.1/Plug.Crypto.html
ingested: 2026-09-28
version: "Plug.Crypto v2.1.1 versioned documentation; not source inspection"
read_status: complete-extracted-text-read
extraction: Exa cached text; PDF layout artifacts retained where applicable
sha256: adcb04304c557650da9b55c815a693a979732a3e2004531051e6329350c5c542
---
Plug.Crypto — Plug.Crypto v2.1.1

# Plug.Crypto (Plug.Crypto v2.1.1)

Namespace and module for crypto-related functionality.

For low-level functionality, see Plug.Crypto.KeyGenerator, Plug.Crypto.MessageEncryptor, and Plug.Crypto.MessageVerifier.

# Summary

## Functions

decrypt(key_base, secret, token, opts \\ [])

Decrypts the original data from the token and verifies its integrity.

encrypt(key_base, secret, data, opts \\ [])

Encodes, encrypts, and signs data into a token you can send to clients.

mask(left, right)

Masks the token on the left with the token on the right.

masked_compare(left, right, mask)

Compares the two binaries (one being masked) in constant-time to avoid timing attacks.

non_executable_binary_to_term(binary, opts \\ [])

A restricted version of:erlang.binary_to_term/2 that forbids executable terms, such as anonymous functions.

prune_args_from_stacktrace(stacktrace)

Prunes the stacktrace to remove any argument trace.

secure_compare(left, right)

Compares the two binaries in constant-time to avoid timing attacks.

sign(key_base, salt, data, opts \\ [])

Encodes and signs data into a token you can send to clients.

verify(key_base, salt, token, opts \\ [])

Decodes the original data from the token and verifies its integrity.

# Functions

# decrypt(key_base, secret, token, opts \\ [])

Decrypts the original data from the token and verifies its integrity.

## Options

- `:max_age`- verifies the token only if it has been generated "max age" ago in seconds. A reasonable value is 1 day (86400 seconds)
- `:key_iterations`- option passed to Plug.Crypto.KeyGenerator when generating the encryption and signing keys. Defaults to 1000
- `:key_length`- option passed to Plug.Crypto.KeyGenerator when generating the encryption and signing keys. Defaults to 32
- `:key_digest`- option passed to Plug.Crypto.KeyGenerator when generating the encryption and signing keys. Defaults to`:sha256`

# encrypt(key_base, secret, data, opts \\ [])

Encodes, encrypts, and signs data into a token you can send to clients.

```
Plug.Crypto.encrypt(conn.secret_key_base, "user-secret", {:elixir, :terms})
```

A key will be derived from the secret key base and the given user secret. The key will also be cached for performance reasons on future calls.

## Options

- `:key_iterations`- option passed to Plug.Crypto.KeyGenerator when generating the encryption and signing keys. Defaults to 1000
- `:key_length`- option passed to Plug.Crypto.KeyGenerator when generating the encryption and signing keys. Defaults to 32
- `:key_digest`- option passed to Plug.Crypto.KeyGenerator when generating the encryption and signing keys. Defaults to`:sha256`
- `:signed_at`- set the timestamp of the token in seconds. Defaults to`System.os_time(:millisecond)`
- `:max_age`- the default maximum age of the token. Defaults to`86400` seconds (1 day) and it may be overridden on`decrypt/4`.

# mask(left, right)

```
@spec mask(binary(), binary()) :: binary()
```

Masks the token on the left with the token on the right.

Both tokens are required to have the same size.

# masked_compare(left, right, mask)

```
@spec masked_compare(binary(), binary(), binary()) :: boolean()
```

Compares the two binaries (one being masked) in constant-time to avoid timing attacks.

It is assumed the right token is masked according to the given mask.

# non_executable_binary_to_term(binary, opts \\ [])

```
@spec non_executable_binary_to_term(binary(), [atom()]) :: term()
```

A restricted version of:erlang.binary_to_term/2 that forbids executable terms, such as anonymous functions.

The`opts` are given to the underlying:erlang.binary_to_term/2 call, with an empty list as a default.

By default this function does not restrict atoms, as an atom interned in one node may not yet have been interned on another (except for releases, which preload all code).

If you want to avoid atoms from being created, then you can pass`[:safe]` as options, as that will also enable the safety mechanisms from:erlang.binary_to_term/2 itself.

# prune_args_from_stacktrace(stacktrace)

```
@spec prune_args_from_stacktrace(Exception.stacktrace()) :: Exception.stacktrace()
```

Prunes the stacktrace to remove any argument trace.

This is useful when working with functions that receives secrets and we want to make sure those secrets do not leak on error messages.

# secure_compare(left, right)

```
@spec secure_compare(binary(), binary()) :: boolean()
```

Compares the two binaries in constant-time to avoid timing attacks.

See: http://codahale.com/a-lesson-in-timing-attacks/

# sign(key_base, salt, data, opts \\ [])

Encodes and signs data into a token you can send to clients.

```
Plug.Crypto.sign(conn.secret_key_base, "user-secret", {:elixir, :terms})
```

A key will be derived from the secret key base and the given user secret. The key will also be cached for performance reasons on future calls.

## Options

- `:key_iterations`- option passed to Plug.Crypto.KeyGenerator when generating the encryption and signing keys. Defaults to 1000
- `:key_length`- option passed to Plug.Crypto.KeyGenerator when generating the encryption and signing keys. Defaults to 32
- `:key_digest`- option passed to Plug.Crypto.KeyGenerator when generating the encryption and signing keys. Defaults to`:sha256`
- `:signed_at`- set the timestamp of the token in seconds. Defaults to`System.os_time(:millisecond)`
- `:max_age`- the default maximum age of the token. Defaults to`86400` seconds (1 day) and it may be overridden on`verify/4`.

# verify(key_base, salt, token, opts \\ [])

Decodes the original data from the token and verifies its integrity.

## Examples

In this scenario we will create a token, sign it, then provide it to a client application. The client will then use this token to authenticate requests for resources from the server. See Plug.Crypto summary for more info about creating tokens.

```
iex> user_id    = 99
iex> secret     = "kjoy3o1zeidquwy1398juxzldjlksahdk3"
iex> user_salt  = "user salt"
iex> token      = Plug.Crypto.sign(secret, user_salt, user_id)
```

The mechanism for passing the token to the client is typically through a cookie, a JSON response body, or HTTP header. For now, assume the client has received a token it can use to validate requests for protected resources.

When the server receives a request, it can use`verify/4` to determine if it should provide the requested resources to the client:

```
iex> Plug.Crypto.verify(secret, user_salt, token, max_age: 86400)
{:ok, 99}
```

In this example, we know the client sent a valid token because`verify/4` returned a tuple of type`{:ok, user_id}`. The server can now proceed with the request.

However, if the client had sent an expired or otherwise invalid token`verify/4` would have returned an error instead:

```
iex> Plug.Crypto.verify(secret, user_salt, expired, max_age: 86400)
{:error, :expired}

iex> Plug.Crypto.verify(secret, user_salt, invalid, max_age: 86400)
{:error, :invalid}
```

## Options

- `:max_age`- verifies the token only if it has been generated "max age" ago in seconds. Defaults to the max age signed in the token (86400)
- `:key_iterations`- option passed to Plug.Crypto.KeyGenerator when generating the encryption and signing keys. Defaults to 1000
- `:key_length`- option passed to Plug.Crypto.KeyGenerator when generating the encryption and signing keys. Defaults to 32
- `:key_digest`- option passed to Plug.Crypto.KeyGenerator when generating the encryption and signing keys. Defaults to`:sha256`