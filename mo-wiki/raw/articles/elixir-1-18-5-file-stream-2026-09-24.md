---
source_url: https://hexdocs.pm/elixir/1.18.5/File.html
ingested: 2026-09-24
version: "Elixir 1.18.5; undated versioned API docs"
read_status: "sections-read: introduction and stream!/3; rest not fully read"
sha256: 42985ed9dcbae1024d5c2911028025797c054bbc7ddaa3d5aefb68de85610260
---
File — Elixir v1.18.5

# File (Elixir v1.18.5) 

This module contains functions to manipulate files.

Some of those functions are low-level, allowing the user to interact with files or IO devices, like `open/2`, `copy/3` and others. This module also provides higher level functions that work with filenames and have their naming based on Unix variants. For example, one can copy a file via `cp/3` and remove files and directories recursively via `rm_rf/1`.

Paths given to functions in this module can be either relative to the current working directory (as returned by `File.cwd/0`), or absolute paths. Shell conventions like `~` are not expanded automatically. To use paths like `~/Downloads`, you can use `Path.expand/1` or `Path.expand/2` to expand your path to an absolute path.

## Encoding

In order to write and read files, one must use the functions in the `IO` module. By default, a file is opened in binary mode, which requires the functions `IO.binread/2` and `IO.binwrite/2` to interact with the file. A developer may pass `:utf8` as an option when opening the file, then the slower `IO.read/2` and `IO.write/2` functions must be used as they are responsible for doing the proper conversions and providing the proper data guarantees.

Note that filenames when given as charlists in Elixir are always treated as UTF-8. In particular, we expect that the shell and the operating system are configured to use UTF-8 encoding. Binary filenames are considered raw and passed to the operating system as is.

## API

Most of the functions in this module return `:ok` or `{:ok, result}` in case of success, `{:error, reason}` otherwise. Those functions also have a variant that ends with `!` which returns the result (instead of the `{:ok, result}` tuple) in case of success or raises an exception in case it fails. For example:

```
File.read("hello.txt")
#=> {:ok, "World"}

File.read("invalid.txt")
#=> {:error, :enoent}

File.read!("hello.txt")
#=> "World"

File.read!("invalid.txt")
#=> raises File.Error
```

In general, a developer should use the former in case they want to react if the file does not exist. The latter should be used when the developer expects their software to fail in case the file cannot be read (i.e. it is literally an exception).

## Processes and raw files

Every time a file is opened, Elixir spawns a new process. Writing to a file is equivalent to sending messages to the process that writes to the file descriptor.

This means files can be passed between nodes and message passing guarantees they can write to the same file in a network.

However, you may not always want to pay the price for this abstraction. In such cases, a file can be opened in `:raw` mode. The options `:read_ahead` and `:delayed_write` are also useful when operating on large files or working with files in tight loops.

Check `:file.open/2` for more information about such options and other performance considerations.

## Seeking within a file

You may also use any of the functions from the `:file` module to interact with files returned by Elixir. For example, to read from a specific position in a file, use `:file.pread/3`:

```
File.write!("example.txt", "Eats, Shoots & Leaves")
file = File.open!("example.txt")
:file.pread(file, 15, 6)
#=> {:ok, "Leaves"}
```

Alternatively, if you need to keep track of the current position, use `:file.position/2` and `:file.read/2`:

```
:file.position(file, 6)
#=> {:ok, 6}
:file.read(file, 6)
#=> {:ok, "Shoots"}
:file.position(file, {:cur, -12})
#=> {:ok, 0}
:file.read(file, 4)
#=> {:ok, "Eats"}
```

### Types 

 encoding_mode() 

 erlang_time() 

 file_descriptor() 

 io_device() 

 mode() 

 on_conflict_callback() 

 posix() 

 posix_time() 

 read_offset_mode() 

 stat_options() 

 stream_mode() 

### Functions 

 cd(path) 

Sets the current working directory.

 cd!(path) 

The same as `cd/1`, but raises a `File.Error` exception if it fails.

 cd!(path, function) 

Changes the current directory to the given `path`, executes the given function and then reverts back to the previous path regardless of whether there is an exception.

 chgrp(path, gid) 

Changes the group given by the group ID `gid` for a given `file`. Returns `:ok` on success, or `{:error, reason}` on failure.

 chgrp!(path, gid) 

Same as `chgrp/2`, but raises a `File.Error` exception in case of failure. Otherwise `:ok`.

 chmod(path, mode) 

Changes the `mode` for a given `file`.

 chmod!(path, mode) 

Same as `chmod/2`, but raises a `File.Error` exception in case of failure. Otherwise `:ok`.

 chown(path, uid) 

Changes the owner given by the user ID `uid` for a given `file`. Returns `:ok` on success, or `{:error, reason}` on failure.

 chown!(path, uid) 

Same as `chown/2`, but raises a `File.Error` exception in case of failure. Otherwise `:ok`.

 close(io_device) 

Closes the file referenced by `io_device`. It mostly returns `:ok`, except for some severe errors such as out of memory.

 copy(source, destination, bytes_count \\ :infinity) 

Copies the contents of `source` to `destination`.

 copy!(source, destination, bytes_count \\ :infinity) 

The same as `copy/3` but raises a `File.CopyError` exception if it fails. Returns the `bytes_copied` otherwise.

 cp(source_file, destination_file, options \\ []) 

Copies the contents of `source_file` to `destination_file` preserving its modes.

 cp!(source_file, destination_file, options \\ []) 

The same as `cp/3`, but raises a `File.CopyError` exception if it fails. Returns `:ok` otherwise.

 cp_r(source, destination, options \\ []) 

Copies the contents in `source` to `destination` recursively, maintaining the source directory structure and modes.

 cp_r!(source, destination, options \\ []) 

The same as `cp_r/3`, but raises a `File.CopyError` exception if it fails. Returns the list of copied files otherwise.

 cwd() 

Gets the current working directory.

 cwd!() 

The same as `cwd/0`, but raises a `File.Error` exception if it fails.

 dir?(path, opts \\ []) 

Returns `true` if the given path is a directory.

 exists?(path, opts \\ []) 

Returns `true` if the given path exists.

 ln(existing, new) 

Creates a hard link `new` to the file `existing`.

 ln!(existing, new) 

Same as `ln/2` but raises a `File.LinkError` exception if it fails. Returns `:ok` otherwise.

 ln_s(existing, new) 

Creates a symbolic link `new` to the file or directory `existing`.

 ln_s!(existing, new) 

Same as `ln_s/2` but raises a `File.LinkError` exception if it fails. Returns `:ok` otherwise.

 ls(path \\ ".") 

Returns the list of files in the given directory.

 ls!(path \\ ".") 

The same as `ls/1` but raises a `File.Error` exception in case of an error.

 lstat(path, opts \\ []) 

Returns information about the `path`. If the file is a symlink, sets the `type` to `:symlink` and returns a `File.Stat` struct for the link. For any other file, returns exactly the same values as `stat/2`.

 lstat!(path, opts \\ []) 

Same as `lstat/2` but returns the `File.Stat` struct directly, or raises a `File.Error` exception if an error is returned.

 mkdir(path) 

Tries to create the directory `path`.

 mkdir!(path) 

Same as `mkdir/1`, but raises a `File.Error` exception in case of failure. Otherwise `:ok`.

 mkdir_p(path) 

Tries to create the directory `path`.

 mkdir_p!(path) 

Same as `mkdir_p/1`, but raises a `File.Error` exception in case of failure. Otherwise `:ok`.

 open(path, modes_or_function \\ []) 

Opens the given `path`.

 open(path, modes, function) 

Similar to `open/2` but expects a function as its last argument.

 open!(path, modes_or_function \\ []) 

Similar to `open/2` but raises a `File.Error` exception if the file could not be opened. Returns the IO device otherwise.

 open!(path, modes, function) 

Similar to `open/3` but raises a `File.Error` exception if the file could not be opened.

 read(path) 

Returns `{:ok, binary}`, where `binary` is a binary data object that contains the contents of `path`, or `{:error, reason}` if an error occurs.

 read!(path) 

Returns a binary with the contents of the given filename, or raises a `File.Error` exception if an error occurs.

 read_link(path) 

Reads the symbolic link at `path`.

 read_link!(path) 

Same as `read_link/1` but returns the target directly, or raises a `File.Error` exception if an error is returned.

 regular?(path, opts \\ []) 

Returns `true` if the path is a regular file.

 rename(source, destination) 

Renames the `source` file to `destination` file. It can be used to move files (and directories) between directories. If moving a file, you must fully specify the `destination` filename, it is not sufficient to simply specify its directory.

 rename!(source, destination) 

The same as `rename/2` but raises a `File.RenameError` exception if it fails. Returns `:ok` otherwise.

Tries to delete the file `path`.

Same as `rm/1`, but raises a `File.Error` exception in case of failure. Otherwise `:ok`.

 rm_rf(path) 

Removes files and directories recursively at the given `path`. Symlinks are not followed but simply removed, non-existing files are simply ignored (i.e. doesn't make this function fail).

Same as `rm_rf/1` but raises a `File.Error` exception in case of failures, otherwise the list of files or directories removed.

 rmdir(path) 

Tries to delete the dir at `path`.

 rmdir!(path) 

Same as `rmdir/1`, but raises a `File.Error` exception in case of failure. Otherwise `:ok`.

 stat(path, opts \\ []) 

Returns information about the `path`. If it exists, it returns a `{:ok, info}` tuple, where info is a `File.Stat` struct. Returns `{:error, reason}` with the same reasons as `read/1` if a failure occurs.

 stat!(path, opts \\ []) 

Same as `stat/2` but returns the `File.Stat` directly, or raises a `File.Error` exception if an error is returned.

 stream!(path, line_or_bytes_modes \\ []) 

Shortcut for `File.stream!/3`.

 stream!(path, line_or_bytes, modes) 

Returns a `File.Stream` for the given `path` with the given `modes`.

 touch(path, time \\ System.os_time(:second)) 

Updates modification time (mtime) and access time (atime) of the given file.

 touch!(path, time \\ System.os_time(:second)) 

Same as `touch/2` but raises a `File.Error` exception if it fails. Returns `:ok` otherwise.

 write(path, content, modes \\ []) 

Writes `content` to the file `path`.

 write!(path, content, modes \\ []) 

Same as `write/3` but raises a `File.Error` exception if it fails. Returns `:ok` otherwise.

 write_stat(path, stat, opts \\ []) 

Writes the given `File.Stat` back to the file system at the given path. Returns `:ok` or `{:error, reason}`.

 write_stat!(path, stat, opts \\ []) 

Same as `write_stat/3` but raises a `File.Error` exception if it fails. Returns `:ok` otherwise.

# encoding_mode()

```
@type encoding_mode() ::
  :utf8
  | {:encoding,
     :latin1
     | :unicode
     | :utf8
     | :utf16
     | :utf32
     | {:utf16, :big | :little}
     | {:utf32, :big | :little}}
```

# erlang_time()

```
@type erlang_time() ::
  {{year :: non_neg_integer(), month :: 1..12, day :: 1..31},
   {hour :: 0..23, minute :: 0..59, second :: 0..59}}
```

# file_descriptor()

```
@type file_descriptor() :: :file.fd()
```

# io_device()

```
@type io_device() :: :file.io_device()
```

# mode()

```
@type mode() ::
  :append
  | :binary
  | :charlist
  | :compressed
  | :delayed_write
  | :exclusive
  | :raw
  | :read
  | :read_ahead
  | :sync
  | :write
  | {:read_ahead, pos_integer()}
  | {:delayed_write, non_neg_integer(), non_neg_integer()}
  | encoding_mode()
```

# on_conflict_callback()

```
@type on_conflict_callback() :: (Path.t(), Path.t() -> boolean())
```

# posix()

```
@type posix() :: :file.posix()
```

# posix_time()

```
@type posix_time() :: integer()
```

# read_offset_mode()

```
@type read_offset_mode() :: {:read_offset, non_neg_integer()}
```

# stat_options()

```
@type stat_options() :: [{:time, :local | :universal | :posix}]
```

# stream_mode()

```
@type stream_mode() ::
  encoding_mode()
  | read_offset_mode()
  | :append
  | :compressed
  | :delayed_write
  | :trim_bom
  | {:read_ahead, pos_integer() | false}
  | {:delayed_write, non_neg_integer(), non_neg_integer()}
```

# cd(path)

```
@spec cd(Path.t()) :: :ok | {:error, posix()}
```

Sets the current working directory.

The current working directory is set for the BEAM globally. This can lead to race conditions if multiple processes are changing the current working directory concurrently. To run an external command in a given directory without changing the global current working directory, use the `:cd` option of `System.cmd/3` and `Port.open/2`.

Returns `:ok` if successful, `{:error, reason}` otherwise.

# cd!(path)

```
@spec cd!(Path.t()) :: :ok
```

The same as `cd/1`, but raises a `File.Error` exception if it fails.

# cd!(path, function)

```
@spec cd!(Path.t(), (-> res)) :: res when res: var
```

Changes the current directory to the given `path`, executes the given function and then reverts back to the previous path regardless of whether there is an exception.

The current working directory is temporarily set for the BEAM globally. This can lead to race conditions if multiple processes are changing the current working directory concurrently. To run an external command in a given directory without changing the global current working directory, use the `:cd` option of `System.cmd/3` and `Port.open/2`.

Raises an error if retrieving or changing the current directory fails.

# chgrp(path, gid)

```
@spec chgrp(Path.t(), non_neg_integer()) :: :ok | {:error, posix()}
```

Changes the group given by the group ID `gid` for a given `file`. Returns `:ok` on success, or `{:error, reason}` on failure.

# chgrp!(path, gid)

```
@spec chgrp!(Path.t(), non_neg_integer()) :: :ok
```

Same as `chgrp/2`, but raises a `File.Error` exception in case of failure. Otherwise `:ok`.

# chmod(path, mode)

```
@spec chmod(Path.t(), non_neg_integer()) :: :ok | {:error, posix()}
```

Changes the `mode` for a given `file`.

Returns `:ok` on success, or `{:error, reason}` on failure.

## Permissions

File permissions are specified by adding together the following octal modes:

- `0o400` - read permission: owner
- `0o200` - write permission: owner
- `0o100` - execute permission: owner
- `0o040` - read permission: group
- `0o020` - write permission: group
- `0o010` - execute permission: group
- `0o004` - read permission: other
- `0o002` - write permission: other
- `0o001` - execute permission: other

For example, setting the mode `0o755` gives it write, read and execute permission to the owner and both read and execute permission to group and others.

# chmod!(path, mode)

```
@spec chmod!(Path.t(), non_neg_integer()) :: :ok
```

Same as `chmod/2`, but raises a `File.Error` exception in case of failure. Otherwise `:ok`.

# chown(path, uid)

```
@spec chown(Path.t(), non_neg_integer()) :: :ok | {:error, posix()}
```

Changes the owner given by the user ID `uid` for a given `file`. Returns `:ok` on success, or `{:error, reason}` on failure.

# chown!(path, uid)

```
@spec chown!(Path.t(), non_neg_integer()) :: :ok
```

Same as `chown/2`, but raises a `File.Error` exception in case of failure. Otherwise `:ok`.

# close(io_device)

```
@spec close(io_device()) :: :ok | {:error, posix() | :badarg | :terminated}
```

Closes the file referenced by `io_device`. It mostly returns `:ok`, except for some severe errors such as out of memory.

Note that if the option `:delayed_write` was used when opening the file, `close/1` might return an old write error and not even try to close the file. See `open/2` for more information.

# copy(source, destination, bytes_count \\ :infinity)

```
@spec copy(Path.t() | io_device(), Path.t() | io_device(), pos_integer() | :infinity) ::
  {:ok, non_neg_integer()} | {:error, posix()}
```

Copies the contents of `source` to `destination`.

Both parameters can be a filename or an IO device opened with `open/2`. `bytes_count` specifies the number of bytes to copy, the default being `:infinity`.

If file `destination` already exists, it is overwritten by the contents in `source`.

Returns `{:ok, bytes_copied}` if successful, `{:error, reason}` otherwise.

Compared to the `cp/3`, this function is more low-level, allowing a copy from device to device limited by a number of bytes. On the other hand, `cp/3` performs more extensive checks on both source and destination and it also preserves the file mode after copy.

Typical error reasons are the same as in `open/2`, `read/1` and `write/3`.

# copy!(source, destination, bytes_count \\ :infinity)

```
@spec copy!(Path.t() | io_device(), Path.t() | io_device(), pos_integer() | :infinity) ::
  non_neg_integer()
```

The same as `copy/3` but raises a `File.CopyError` exception if it fails. Returns the `bytes_copied` otherwise.

# cp(source_file, destination_file, options \\ [])

```
@spec cp(Path.t(), Path.t(), [{:on_conflict, on_conflict_callback()}]) ::
  :ok | {:error, posix()}
```

Copies the contents of `source_file` to `destination_file` preserving its modes.

`source_file` must be a file or a symbolic link to one. `destination_file` must be a path to a non-existent file. If either is a directory, `{:error, :eisdir}` will be returned.

The function returns `:ok` in case of success. Otherwise, it returns `{:error, reason}`.

If you want to copy contents from an IO device to another device or do a straight copy from a source to a destination without preserving modes, check `copy/3` instead.

Note: The command `cp` in Unix-like systems behaves differently depending on whether the destination is an existing directory or not. We have chosen to explicitly disallow copying to a destination which is a directory, and an error will be returned if tried.

## Options

- `:on_conflict` - (since v1.14.0) Invoked when a file already exists in the destination. The function receives arguments for `source_file` and `destination_file`. It should return `true` if the existing file should be overwritten, `false` if otherwise. The default callback returns `true`. On earlier versions, this callback could be given as third argument, but such behavior is now deprecated.

# cp!(source_file, destination_file, options \\ [])

```
@spec cp!(Path.t(), Path.t(), [{:on_conflict, on_conflict_callback()}]) :: :ok
```

The same as `cp/3`, but raises a `File.CopyError` exception if it fails. Returns `:ok` otherwise.

# cp_r(source, destination, options \\ [])

```
@spec cp_r(Path.t(), Path.t(),
  on_conflict: on_conflict_callback(),
  dereference_symlinks: boolean()
) ::
  {:ok, [binary()]} | {:error, posix(), binary()}
```

Copies the contents in `source` to `destination` recursively, maintaining the source directory structure and modes.

If `source` is a file or a symbolic link to it, `destination` must be a path to an existent file, a symbolic link to one, or a path to a non-existent file.

If `source` is a directory, or a symbolic link to it, then `destination` must be an existent `directory` or a symbolic link to one, or a path to a non-existent directory.

If the source is a file, it copies `source` to `destination`. If the `source` is a directory, it copies the contents inside source into the `destination` directory.

If a file already exists in the destination, it invokes the optional `on_conflict` callback given as an option. See "Options" for more information.

This function may fail while copying files, in such cases, it will leave the destination directory in a dirty state, where file which have already been copied won't be removed.

The function returns `{:ok, files_and_directories}` in case of success, `files_and_directories` lists all files and directories copied in no specific order. It returns `{:error, reason, file}` otherwise.

Note: The command `cp` in Unix-like systems behaves differently depending on whether `destination` is an existing directory or not. We have chosen to explicitly disallow this behavior. If `source` is a `file` and `destination` is a directory, `{:error, :eisdir}` will be returned.

## Options

- `:on_conflict` - (since v1.14.0) Invoked when a file already exists in the destination. The function receives arguments for `source` and `destination`. It should return `true` if the existing file should be overwritten, `false` if otherwise. The default callback returns `true`. On earlier versions, this callback could be given as third argument, but such behavior is now deprecated.
- `:dereference_symlinks` - (since v1.14.0) By default, this function will copy symlinks by creating symlinks that point to the same location. This option forces symlinks to be dereferenced and have their contents copied instead when set to `true`. If the dereferenced files do not exist, than the operation fails. The default is `false`.

## Examples

```
# Copies file "a.txt" to "b.txt"
File.cp_r("a.txt", "b.txt")

# Copies all files in "samples" to "tmp"
File.cp_r("samples", "tmp")

# Same as before, but asks the user how to proceed in case of conflicts
File.cp_r("samples", "tmp", on_conflict: fn source, destination ->
  IO.gets("Overwriting #{destination} by #{source}. Type y to confirm. ") == "y\n"
end)
```

# cp_r!(source, destination, options \\ [])

```
@spec cp_r!(Path.t(), Path.t(),
  on_conflict: on_conflict_callback(),
  dereference_symlinks: boolean()
) ::
  [binary()]
```

The same as `cp_r/3`, but raises a `File.CopyError` exception if it fails. Returns the list of copied files otherwise.

# cwd()

```
@spec cwd() :: {:ok, binary()} | {:error, posix()}
```

Gets the current working directory.

In rare circumstances, this function can fail on Unix-like systems. It may happen if read permissions do not exist for the parent directories of the current directory. For this reason, returns `{:ok, cwd}` in case of success, `{:error, reason}` otherwise.

# cwd!()

```
@spec cwd!() :: binary()
```

The same as `cwd/0`, but raises a `File.Error` exception if it fails.

# dir?(path, opts \\ [])

```
@spec dir?(Path.t(), [dir_option]) :: boolean() when dir_option: :raw
```

Returns `true` if the given path is a directory.

This function follows symbolic links, so if a symbolic link points to a directory, `true` is returned.

## Options

The supported options are:

- `:raw` - a single atom to bypass the file server and only check for the file locally

## Examples

```
File.dir?("./test")
#=> true

File.dir?("test")
#=> true

File.dir?("/usr/bin")
#=> true

File.dir?("~/Downloads")
#=> false

"~/Downloads" |> Path.expand() |> File.dir?()
#=> true
```

# exists?(path, opts \\ [])

```
@spec exists?(Path.t(), [exists_option]) :: boolean() when exists_option: :raw
```

Returns `true` if the given path exists.

It can be a regular file, directory, socket, symbolic link, named pipe, or device file. Returns `false` for symbolic links pointing to non-existing targets.

## Options

The supported options are:

- `:raw` - a single atom to bypass the file server and only check for the file locally

## Examples

```
File.exists?("test/")
#=> true

File.exists?("missing.txt")
#=> false

File.exists?("/dev/null")
#=> true
```

# ln(existing, new)

```
@spec ln(Path.t(), Path.t()) :: :ok | {:error, posix()}
```

Creates a hard link `new` to the file `existing`.

Returns `:ok` if successful, `{:error, reason}` otherwise. If the operating system does not support hard links, returns `{:error, :enotsup}`.

# ln!(existing, new)

```
@spec ln!(Path.t(), Path.t()) :: :ok
```

Same as `ln/2` but raises a `File.LinkError` exception if it fails. Returns `:ok` otherwise.

# ln_s(existing, new)

```
@spec ln_s(Path.t(), Path.t()) :: :ok | {:error, posix()}
```

Creates a symbolic link `new` to the file or directory `existing`.

Returns `:ok` if successful, `{:error, reason}` otherwise. If the operating system does not support symlinks, returns `{:error, :enotsup}`.

# ln_s!(existing, new)

```
@spec ln_s!(Path.t(), Path.t()) :: :ok
```

Same as `ln_s/2` but raises a `File.LinkError` exception if it fails. Returns `:ok` otherwise.

# ls(path \\ ".")

```
@spec ls(Path.t()) :: {:ok, [binary()]} | {:error, posix()}
```

Returns the list of files in the given directory.

Hidden files are not ignored and the results are not sorted.

Since directories are considered files by the file system, they are also included in the returned value.

Returns `{:ok, files}` in case of success, `{:error, reason}` otherwise.

# ls!(path \\ ".")

```
@spec ls!(Path.t()) :: [binary()]
```

The same as `ls/1` but raises a `File.Error` exception in case of an error.

# lstat(path, opts \\ [])

```
@spec lstat(Path.t(), stat_options()) :: {:ok, File.Stat.t()} | {:error, posix()}
```

Returns information about the `path`. If the file is a symlink, sets the `type` to `:symlink` and returns a `File.Stat` struct for the link. For any other file, returns exactly the same values as `stat/2`.

For more details, see `:file.read_link_info/2`.

## Options

The accepted options are:

- `:time` - configures how the file timestamps are returned

The values for `:time` can be:

- `:universal` - returns a `{date, time}` tuple in UTC (default)
- `:local` - returns a `{date, time}` tuple using the machine time
- `:posix` - returns the time as integer seconds since epoch

Note: Since file times are stored in POSIX time format on most operating systems, it is faster to retrieve file information with the `time: :posix` option.

# lstat!(path, opts \\ [])

```
@spec lstat!(Path.t(), stat_options()) :: File.Stat.t()
```

Same as `lstat/2` but returns the `File.Stat` struct directly, or raises a `File.Error` exception if an error is returned.

# mkdir(path)

```
@spec mkdir(Path.t()) :: :ok | {:error, posix()}
```

Tries to create the directory `path`.

Missing parent directories are not created. Returns `:ok` if successful, or `{:error, reason}` if an error occurs.

Typical error reasons are:

- `:eacces` - missing search or write permissions for the parent directories of `path`
- `:eexist` - there is already a file or directory named `path`
- `:enoent` - a component of `path` does not exist
- `:enospc` - there is no space left on the device
- `:enotdir` - a component of `path` is not a directory; on some platforms, `:enoent` is returned instead

# mkdir!(path)

```
@spec mkdir!(Path.t()) :: :ok
```

Same as `mkdir/1`, but raises a `File.Error` exception in case of failure. Otherwise `:ok`.

# mkdir_p(path)

```
@spec mkdir_p(Path.t()) :: :ok | {:error, posix()}
```

Tries to create the directory `path`.

Missing parent directories are created. Returns `:ok` if successful, or `{:error, reason}` if an error occurs.

Typical error reasons are:

- `:eacces` - missing search or write permissions for the parent directories of `path`
- `:enospc` - there is no space left on the device
- `:enotdir` - a component of `path` is not a directory

# mkdir_p!(path)

```
@spec mkdir_p!(Path.t()) :: :ok
```

Same as `mkdir_p/1`, but raises a `File.Error` exception in case of failure. Otherwise `:ok`.

# open(path, modes_or_function \\ [])

```
@spec open(Path.t(), [mode() | :ram]) ::
  {:ok, io_device() | file_descriptor()} | {:error, posix()}
```

```
@spec open(Path.t(), (io_device() | file_descriptor() -> res)) ::
  {:ok, res} | {:error, posix()}
when res: var
```

Opens the given `path`.

`modes_or_function` can either be a list of modes or a function. If it's a list, it's considered to be a list of modes (that are documented below). If it's a function, then it's equivalent to calling `open(path, [], modes_or_function)`. See the documentation for `open/3` for more information on this function.

The allowed modes:

- `:binary` - opens the file in binary mode, disabling special handling of Unicode sequences (default mode).
- `:read` - the file, which must exist, is opened for reading.
- `:write` - the file is opened for writing. It is created if it does not exist.

If the file does exist, and if write is not combined with read, the file will be truncated.
- `:append` - the file will be opened for writing, and it will be created if it does not exist. Every write operation to a file opened with append will take place at the end of the file.
- `:exclusive` - the file, when opened for writing, is created if it does not exist. If the file exists, open will return `{:error, :eexist}`.
- `:charlist` - when this term is given, read operations on the file will return charlists rather than binaries.
- `:compressed` - makes it possible to read or write gzip compressed files.

The compressed option must be combined with either read or write, but not both. Note that the file size obtained with `stat/1` will most probably not match the number of bytes that can be read from a compressed file.
- `:utf8` - this option denotes how data is actually stored in the disk file and makes the file perform automatic translation of characters to and from UTF-8.

If data is sent to a file in a format that cannot be converted to the UTF-8 or if data is read by a function that returns data in a format that cannot cope with the character range of the data, an error occurs and the file will be closed.
- `:delayed_write`, `:raw`, `:ram`, `:read_ahead`, `:sync`, `{:encoding, ...}`, `{:read_ahead, pos_integer}`, `{:delayed_write, non_neg_integer, non_neg_integer}` - for more information about these options see `:file.open/2`.

This function returns:

- `{:ok, io_device | file_descriptor}` - the file has been opened in the requested mode. We explore the differences between these two results in the following section
- `{:error, reason}` - the file could not be opened due to `reason`.

## IO devices

By default, this function returns an IO device. An `io_device` is a process which handles the file and you can interact with it using the functions in the `IO` module. By default, a file is opened in `:binary` mode, which requires the functions `IO.binread/2` and `IO.binwrite/2` to interact with the file. A developer may pass `:utf8` as a mode when opening the file and then all other functions from `IO` are available, since they work directly with Unicode data.

Given the IO device is a file, if the owner process terminates, the file is closed and the process itself terminates too. If any process to which the `io_device` is linked terminates, the file will be closed and the process itself will be terminated.

## File descriptors

When the `:raw` or `:ram` modes are given, this function returns a low-level file descriptors. This avoids creating a process but requires using the functions in the `:file` module to interact with it.

## Examples

```
{:ok, file} = File.open("foo.tar.gz", [:read, :compressed])
IO.read(file, :line)
File.close(file)
```

# open(path, modes, function)

```
@spec open(Path.t(), [mode() | :ram], (io_device() | file_descriptor() -> res)) ::
  {:ok, res} | {:error, posix()}
when res: var
```

Similar to `open/2` but expects a function as its last argument.

The file is opened, given to the function as an argument and automatically closed after the function returns, regardless if there was an error when executing the function.

Returns `{:ok, function_result}` in case of success, `{:error, reason}` otherwise.

This function expects the file to be closed with success, which is usually the case unless the `:delayed_write` option is given. For this reason, we do not recommend passing `:delayed_write` to this function.

## Examples

```
File.open("file.txt", [:read, :write], fn file ->
  IO.read(file, :line)
end)
```

See `open/2` for the list of available `modes`.

# open!(path, modes_or_function \\ [])

```
@spec open!(Path.t(), [mode() | :ram]) :: io_device() | file_descriptor()
```

```
@spec open!(Path.t(), (io_device() | file_descriptor() -> res)) :: res when res: var
```

Similar to `open/2` but raises a `File.Error` exception if the file could not be opened. Returns the IO device otherwise.

See `open/2` for the list of available modes.

# open!(path, modes, function)

```
@spec open!(Path.t(), [mode() | :ram], (io_device() | file_descriptor() -> res)) ::
  res
when res: var
```

Similar to `open/3` but raises a `File.Error` exception if the file could not be opened.

If it succeeds opening the file, it returns the `function` result on the IO device.

See `open/2` for the list of available `modes`.

# read(path)

```
@spec read(Path.t()) :: {:ok, binary()} | {:error, posix()}
```

Returns `{:ok, binary}`, where `binary` is a binary data object that contains the contents of `path`, or `{:error, reason}` if an error occurs.

Typical error reasons:

- `:enoent` - the file does not exist
- `:eacces` - missing permission for reading the file, or for searching one of the parent directories
- `:eisdir` - the named file is a directory
- `:enotdir` - a component of the file name is not a directory; on some platforms, `:enoent` is returned instead
- `:enomem` - there is not enough memory for the contents of the file

You can use `:file.format_error/1` to get a descriptive string of the error.

# read!(path)

```
@spec read!(Path.t()) :: binary()
```

Returns a binary with the contents of the given filename, or raises a `File.Error` exception if an error occurs.

# read_link(path)

```
@spec read_link(Path.t()) :: {:ok, binary()} | {:error, posix()}
```

Reads the symbolic link at `path`.

If `path` exists and is a symlink, returns `{:ok, target}`, otherwise returns `{:error, reason}`.

For more details, see `:file.read_link/1`.

Typical error reasons are:

- `:einval` - path is not a symbolic link
- `:enoent` - path does not exist
- `:enotsup` - symbolic links are not supported on the current platform

# read_link!(path)

```
@spec read_link!(Path.t()) :: binary()
```

Same as `read_link/1` but returns the target directly, or raises a `File.Error` exception if an error is returned.

# regular?(path, opts \\ [])

```
@spec regular?(Path.t(), [regular_option]) :: boolean() when regular_option: :raw
```

Returns `true` if the path is a regular file.

This function follows symbolic links, so if a symbolic link points to a regular file, `true` is returned.

## Options

The supported options are:

- `:raw` - a single atom to bypass the file server and only check for the file locally

## Examples

```
File.regular?(__ENV__.file)
#=> true
```

# rename(source, destination)

```
@spec rename(Path.t(), Path.t()) :: :ok | {:error, posix()}
```

Renames the `source` file to `destination` file. It can be used to move files (and directories) between directories. If moving a file, you must fully specify the `destination` filename, it is not sufficient to simply specify its directory.

Returns `:ok` in case of success, `{:error, reason}` otherwise.

Note: The command `mv` in Unix-like systems behaves differently depending on whether `source` is a file and the `destination` is an existing directory. We have chosen to explicitly disallow this behavior.

## Examples

```
# Rename file "a.txt" to "b.txt"
File.rename("a.txt", "b.txt")

# Rename directory "samples" to "tmp"
File.rename("samples", "tmp")
```

# rename!(source, destination)

```
@spec rename!(Path.t(), Path.t()) :: :ok
```

The same as `rename/2` but raises a `File.RenameError` exception if it fails. Returns `:ok` otherwise.

# rm(path)

```
@spec rm(Path.t()) :: :ok | {:error, posix()}
```

Tries to delete the file `path`.

Returns `:ok` if successful, or `{:error, reason}` if an error occurs.

Note the file is deleted even if in read-only mode.

Typical error reasons are:

- `:enoent` - the file does not exist
- `:eacces` - missing permission for the file or one of its parents
- `:eperm` - the file is a directory and user is not super-user
- `:enotdir` - a component of the file name is not a directory; on some platforms, `:enoent` is returned instead
- `:einval` - filename had an improper type, such as tuple

## Examples

```
File.rm("file.txt")
#=> :ok

File.rm("tmp_dir/")
#=> {:error, :eperm}
```

# rm!(path)

```
@spec rm!(Path.t()) :: :ok
```

Same as `rm/1`, but raises a `File.Error` exception in case of failure. Otherwise `:ok`.

# rm_rf(path)

```
@spec rm_rf(Path.t()) :: {:ok, [binary()]} | {:error, posix(), binary()}
```

Removes files and directories recursively at the given `path`. Symlinks are not followed but simply removed, non-existing files are simply ignored (i.e. doesn't make this function fail).

Returns `{:ok, files_and_directories}` with all files and directories removed in no specific order, `{:error, reason, file}` otherwise.

## Examples

```
File.rm_rf("samples")
#=> {:ok, ["samples", "samples/1.txt"]}

File.rm_rf("unknown")
#=> {:ok, []}
```

# rm_rf!(path)

```
@spec rm_rf!(Path.t()) :: [binary()]
```

Same as `rm_rf/1` but raises a `File.Error` exception in case of failures, otherwise the list of files or directories removed.

# rmdir(path)

```
@spec rmdir(Path.t()) :: :ok | {:error, posix()}
```

Tries to delete the dir at `path`.

Returns `:ok` if successful, or `{:error, reason}` if an error occurs. It returns `{:error, :eexist}` if the directory is not empty.

## Examples

```
File.rmdir("tmp_dir")
#=> :ok

File.rmdir("non_empty_dir")
#=> {:error, :eexist}

File.rmdir("file.txt")
#=> {:error, :enotdir}
```

# rmdir!(path)

```
@spec rmdir!(Path.t()) :: :ok | {:error, posix()}
```

Same as `rmdir/1`, but raises a `File.Error` exception in case of failure. Otherwise `:ok`.

# stat(path, opts \\ [])

```
@spec stat(Path.t(), stat_options()) :: {:ok, File.Stat.t()} | {:error, posix()}
```

Returns information about the `path`. If it exists, it returns a `{:ok, info}` tuple, where info is a `File.Stat` struct. Returns `{:error, reason}` with the same reasons as `read/1` if a failure occurs.

## Options

The accepted options are:

- `:time` - configures how the file timestamps are returned

The values for `:time` can be:

- `:universal` - returns a `{date, time}` tuple in UTC (default)
- `:local` - returns a `{date, time}` tuple using the same time zone as the machine
- `:posix` - returns the time as integer seconds since epoch

Note: Since file times are stored in POSIX time format on most operating systems, it is faster to retrieve file information with the `time: :posix` option.

# stat!(path, opts \\ [])

```
@spec stat!(Path.t(), stat_options()) :: File.Stat.t()
```

Same as `stat/2` but returns the `File.Stat` directly, or raises a `File.Error` exception if an error is returned.

# stream!(path, line_or_bytes_modes \\ [])

```
@spec stream!(Path.t(), :line | pos_integer() | [stream_mode()]) :: File.Stream.t()
```

Shortcut for `File.stream!/3`.

# stream!(path, line_or_bytes, modes)

```
@spec stream!(Path.t(), :line | pos_integer(), [stream_mode()]) :: File.Stream.t()
```

Returns a `File.Stream` for the given `path` with the given `modes`.

The stream implements both `Enumerable` and `Collectable` protocols, which means it can be used both for read and write.

The `line_or_bytes` argument configures how the file is read when streaming, by `:line` (default) or by a given number of bytes. When using the `:line` option, CRLF line breaks (`"\r\n"`) are normalized to LF (`"\n"`).

Similar to other file operations, a stream can be created in one node and forwarded to another node. Once the stream is opened in another node, a request will be sent to the creator node to spawn a process for file streaming.

Operating the stream can fail on open for the same reasons as `File.open!/2`. Note that the file is automatically opened each time streaming begins. There is no need to pass `:read` and `:write` modes, as those are automatically set by Elixir.

## Raw files

Since Elixir controls when the streamed file is opened, the underlying device cannot be shared and as such it is convenient to open the file in raw mode for performance reasons. Therefore, Elixir will open streams in `:raw` mode with the `:read_ahead` option if the stream is open in the same node as it is created and no encoding has been specified. This means any data streamed into the file must be converted to `iodata/0` type. If you pass, for example, `[encoding: :utf8]` or `[encoding: {:utf16, :little}]` in the modes parameter, the underlying stream will use `IO.write/2` and the `String.Chars` protocol to convert the data. See `IO.binwrite/2` and `IO.write/2` .

One may also consider passing the `:delayed_write` option if the stream is meant to be written to under a tight loop.

## Byte order marks and read offset

If you pass `:trim_bom` in the modes parameter, the stream will trim UTF-8, UTF-16 and UTF-32 byte order marks when reading from file.

Note that this function does not try to discover the file encoding based on BOM. From Elixir v1.16.0, you may also pass a `:read_offset` that is skipped whenever enumerating the stream (if both `:read_offset` and `:trim_bom` are given, the offset is skipped after the BOM).

## Examples

```
# Read a utf8 text file which may include BOM
File.stream!("./test/test.txt", [:trim_bom, encoding: :utf8])

# Read in 2048 byte chunks rather than lines
File.stream!("./test/test.data", 2048)
```

See `Stream.run/1` for an example of streaming into a file.

# touch(path, time \\ System.os_time(:second))

```
@spec touch(Path.t(), erlang_time() | posix_time()) :: :ok | {:error, posix()}
```

Updates modification time (mtime) and access time (atime) of the given file.

The file is created if it doesn't exist. Requires datetime in UTC (as returned by `:erlang.universaltime()`) or an integer representing the POSIX timestamp (as returned by `System.os_time(:second)`).

In Unix-like systems, changing the modification time may require you to be either `root` or the owner of the file. Having write access may not be enough. In those cases, touching the file the first time (to create it) will succeed, but touching an existing file with fail with `{:error, :eperm}`.

## Examples

```
File.touch("/tmp/a.txt", {{2018, 1, 30}, {13, 59, 59}})
#=> :ok
File.touch("/fakedir/b.txt", {{2018, 1, 30}, {13, 59, 59}})
{:error, :enoent}

File.touch("/tmp/a.txt", 1544519753)
#=> :ok
```

# touch!(path, time \\ System.os_time(:second))

```
@spec touch!(Path.t(), erlang_time() | posix_time()) :: :ok
```

Same as `touch/2` but raises a `File.Error` exception if it fails. Returns `:ok` otherwise.

The file is created if it doesn't exist. Requires datetime in UTC (as returned by `:erlang.universaltime()`) or an integer representing the POSIX timestamp (as returned by `System.os_time(:second)`).

## Examples

```
File.touch!("/tmp/a.txt", {{2018, 1, 30}, {13, 59, 59}})
#=> :ok
File.touch!("/fakedir/b.txt", {{2018, 1, 30}, {13, 59, 59}})
** (File.Error) could not touch "/fakedir/b.txt": no such file or directory

File.touch!("/tmp/a.txt", 1544519753)
```

# write(path, content, modes \\ [])

```
@spec write(Path.t(), iodata(), [mode()]) :: :ok | {:error, posix()}
```

Writes `content` to the file `path`.

The file is created if it does not exist. If it exists, the previous contents are overwritten. Returns `:ok` if successful, or `{:error, reason}` if an error occurs.

`content` must be `iodata` (a list of bytes or a binary). Setting the encoding for this function has no effect.

Warning: Every time this function is invoked, a file descriptor is opened and a new process is spawned to write to the file. For this reason, if you are doing multiple writes in a loop, opening the file via `File.open/2` and using the functions in `IO` to write to the file will yield much better performance than calling this function multiple times.

Typical error reasons are:

- `:enoent` - a component of the file name does not exist
- `:enotdir` - a component of the file name is not a directory; on some platforms, `:enoent` is returned instead
- `:enospc` - there is no space left on the device
- `:eacces` - missing permission for writing the file or searching one of the parent directories
- `:eisdir` - the named file is a directory

Check `File.open/2` for other available options.

# write!(path, content, modes \\ [])

```
@spec write!(Path.t(), iodata(), [mode()]) :: :ok
```

Same as `write/3` but raises a `File.Error` exception if it fails. Returns `:ok` otherwise.

# write_stat(path, stat, opts \\ [])

```
@spec write_stat(Path.t(), File.Stat.t(), stat_options()) :: :ok | {:error, posix()}
```

Writes the given `File.Stat` back to the file system at the given path. Returns `:ok` or `{:error, reason}`.

# write_stat!(path, stat, opts \\ [])

```
@spec write_stat!(Path.t(), File.Stat.t(), stat_options()) :: :ok
```

Same as `write_stat/3` but raises a `File.Error` exception if it fails. Returns `:ok` otherwise.