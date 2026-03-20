# Perl Governance Template

> Seed template for /r:init. Merged with codebase scan results during
> governance generation. Not copied verbatim -- scan data overrides
> where conflicts exist.

## Pragmas

- `use strict; use warnings;` in every `.pl` and `.pm` file --
  non-negotiable, catches typos and unsafe constructs at compile time
- `use utf8;` when source contains non-ASCII literals
- `use Carp;` for library modules -- `croak`/`carp` report errors from
  the caller's perspective, not the library's
- Minimum version declaration (`use v5.16;`) when using version-gated
  features (say, unicode_strings, etc.)

## File I/O

- Three-argument `open` with lexical filehandles always:
  `open my $fh, '>', $file or die "Cannot open $file: $!"`
- Never two-argument `open` -- filenames containing `|`, `>`, or
  whitespace cause shell injection or silent data loss
- `close $fh or die "Cannot close $file: $!"` -- close failures mean
  data loss (buffered writes not flushed, NFS errors)
- `binmode $fh, ':encoding(UTF-8)'` for text files -- default encoding
  is platform-dependent
- `File::Temp` for temporary files -- never manual `$$`/`$RANDOM` naming

## OOP

- Moo (lightweight) or Moose (full-featured) for OOP -- never raw
  `bless {}` which lacks type constraints, accessors, and role composition
- `has` declarations with `isa` constraints for attribute typing
- Roles (`Moo::Role` / `Moose::Role`) over deep inheritance -- composition
  over inheritance is a first-class pattern in Perl OOP
- `namespace::autoclean` in Moose classes to remove imported functions
  from the public API
- `BUILDARGS` for constructor argument normalization, `BUILD` for
  post-construction validation

## Regex Safety

- `\Q...\E` for interpolated variables in regex -- never raw `$var` in
  patterns (regex injection: user input containing `.*` matches everything)
- Acceptable: `$str =~ /\Q$input\E/` or pre-compiled `qr/\Q$input\E/`
- Named captures `(?<name>...)` over positional `$1`, `$2` for clarity
- `/x` flag on complex patterns for readability with inline comments
- Avoid catastrophic backtracking -- no nested quantifiers like `(a+)+`

## Error Handling

- `Try::Tiny` or `Syntax::Keyword::Try` for exception handling --
  never bare `eval { }; if ($@)` because `$@` can be clobbered between
  the eval exit and the if check (object destructors, signal handlers)
- Check return values of system calls -- `open`, `close`, `rename`,
  `unlink` all return false on failure
- `die` with objects or structured messages -- bare `die "string"`
  loses stack context; use `Carp::croak` in libraries
- Propagate errors via return values or exceptions -- never silently
  continue on failure

## Variable Scope

- Avoid `$_` in large scopes -- use named lexical variables with `my`
- `$_` acceptable only in short `map`/`grep`/`for` expressions where
  the scope is a single line or expression
- `my` for all variables -- never `our` unless exporting module state
  (and prefer accessor methods over exported variables)
- Avoid package globals -- they create hidden coupling and test isolation
  problems

## Security

- Taint mode (`-T` in shebang) for any code processing external input
  (CGI, network daemons, file processors)
- `\Q\E` in regex with user data -- prevents regex injection
- Three-argument `open` -- prevents command injection via pipe in filenames
- Validate before `system()`, `exec()`, backticks, or `qx{}` -- never
  pass unsanitized user input to shell commands
- Use list form of `system(@args)` to bypass shell interpolation
- `DBI` with placeholders (`?`) for SQL -- never interpolate into queries
- Avoid `eval $string` with any user-influenced data -- code injection

## Testing

- `Test2::V0` (modern, preferred) or `Test::More` (legacy compatibility)
- `prove -r t/` for running the full test suite
- Test files in `t/` directory with `.t` extension
- `perlcritic` for style enforcement -- configure severity level per
  project in `.perlcriticrc`
- `Devel::Cover` for coverage measurement
- Test isolation: each `.t` file is an independent process -- no shared
  state between test files
- Mock external dependencies with `Test2::Mock` or `Test::MockModule`
