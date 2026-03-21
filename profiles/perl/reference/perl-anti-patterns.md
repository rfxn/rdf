# Perl Anti-Patterns Reference

> Deep reference for common Perl anti-patterns. Each entry shows the
> broken pattern, explains why it fails, and provides the correct
> alternative. Companion to the Perl governance template.

---

## Verification Preamble

Before reporting any pattern from this document as a finding:
1. Verify the pattern exists in project code (not just dependencies)
2. Check whether framework or library protections already mitigate it
3. Confirm the code path is reachable from an entry point
4. Read the "When this is safe" annotation if present

A pattern match is a candidate. A verified pattern match is a finding.

---

## Scope & Variables

### Two-Argument Open

Two-argument `open` treats the filename as a mode+path string,
enabling shell injection via pipe characters and redirects.

Bad:
```perl
open(FH, $file);
print FH "data\n";
close FH;
```

Good:
```perl
open my $fh, '<', $file or die "Cannot open $file: $!";
while (my $line = <$fh>) {
    chomp $line;
    process($line);
}
close $fh or die "Cannot close $file: $!";
```

Three-argument `open` separates mode from filename, preventing
shell interpretation.

### `$_` in Large Scopes

`$_` is a package global. Any function that uses `$_` internally
will clobber the caller's value in multi-line blocks.

Bad:
```perl
for (@records) {
    my $cleaned = clean($_);
    log("Processing: $cleaned");  # log() clobbers $_
    save($_);  # saves wrong record
}
```

Good:
```perl
for my $record (@records) {
    my $cleaned = clean($record);
    log("Processing: $cleaned");
    save($record);
}
```

Named lexical variables are immune to clobbering by called functions.

When this is safe: Single-expression `map`/`grep`/`for` blocks:
`my @upper = map { uc } @names;`

### `our` vs `my`

`our` declares a package global visible everywhere, creating
hidden coupling and breaking test isolation.

Bad:
```perl
package MyApp::Cache;
our %data;

sub store { my ($key, $val) = @_; $data{$key} = $val }
sub fetch { my ($key) = @_; return $data{$key} }
```

Good:
```perl
package MyApp::Cache;
use Moo;

has _data => (is => 'ro', default => sub { {} });

sub store { my ($self, $key, $val) = @_; $self->_data->{$key} = $val }
sub fetch { my ($self, $key) = @_; return $self->_data->{$key} }
```

Object attributes encapsulate state. Tests create fresh instances.

When this is safe: Read-only constants set once at compile time:
`use constant MAX_RETRIES => 3;`

### Missing `strict` and `warnings`

Without these pragmas, Perl silently creates globals on first use
and ignores variable name typos.

Bad:
```perl
#!/usr/bin/perl
$naem = "Alice";     # typo: $naem instead of $name
print "Hello $name"; # prints "Hello " -- $name is undef
```

Good:
```perl
#!/usr/bin/perl
use strict;
use warnings;

my $name = "Alice";
print "Hello $name\n";
```

`strict` requires variable declaration; `warnings` reports
suspicious constructs. Non-negotiable in every `.pl` and `.pm`.

---

## I/O & Files

### Unquoted Variable Interpolation in Print

Perl's parser can misinterpret the first argument after `print`
as a filehandle when the filehandle variable is not disambiguated.

Bad:
```perl
print $fh $data;
```

Good:
```perl
print {$fh} $data;
```

The block form `{$fh}` unambiguously marks the filehandle,
eliminating parsing ambiguity.

When this is safe: Printing to STDOUT or STDERR without a filehandle:
`print "output\n";` or `print STDERR "error\n";`

### Raw Regex Variable Interpolation

Interpolating a variable directly into a regex treats its content
as pattern syntax, enabling regex injection.

Bad:
```perl
my $search = get_user_input();
if ($str =~ /$search/) { print "Found\n" }
```

Good:
```perl
my $search = get_user_input();
if ($str =~ /\Q$search\E/) { print "Found\n" }
```

`\Q` quotes all metacharacters until `\E`. For repeated use,
precompile: `my $pat = qr/\Q$search\E/;`

### Missing `binmode`

Perl's default I/O encoding is platform-dependent. Without explicit
encoding, UTF-8 data is silently corrupted.

Bad:
```perl
open my $fh, '<', $file or die "Cannot open $file: $!";
my $content = do { local $/; <$fh> };
close $fh or die "Cannot close $file: $!";
```

Good:
```perl
open my $fh, '<', $file or die "Cannot open $file: $!";
binmode $fh, ':encoding(UTF-8)';
my $content = do { local $/; <$fh> };
close $fh or die "Cannot close $file: $!";
```

Alternatively: `use open qw(:std :encoding(UTF-8));`

When this is safe: Binary files where raw bytes are intended.
Use `binmode $fh, ':raw';` explicitly.

---

## OOP

### Raw `bless`

Using `bless` directly bypasses type constraints, accessor
generation, and role composition.

Bad:
```perl
package MyApp::User;
sub new {
    my ($class, %args) = @_;
    return bless { name => $args{name}, email => $args{email} }, $class;
}
sub name  { return $_[0]->{name} }
```

Good:
```perl
package MyApp::User;
use Moo;
use Types::Standard qw(Str);

has name  => (is => 'ro', isa => Str, required => 1);
has email => (is => 'ro', isa => Str, required => 1);
```

Moo provides type constraints, required attributes, defaults,
and role composition with proper accessor semantics.

When this is safe: Trivial internal-only data containers where
adding a Moo dependency is disproportionate to the scope.

### Deep Inheritance

Deep `@ISA` chains create fragile hierarchies where base class
changes ripple unpredictably through descendants.

Bad:
```perl
package Animal;
sub new { bless {}, shift }

package Mammal;
our @ISA = ('Animal');

package Dog;
our @ISA = ('Mammal');

package GuideDog;
our @ISA = ('Dog');
# 4 levels -- which method comes from where?
```

Good:
```perl
package Speakable;
use Moo::Role;
requires 'speak';

package Dog;
use Moo;
with 'Speakable', 'Breathable';
sub speak { "woof" }
```

Roles provide flat composition. Conflicts are detected at compile
time. No inheritance hierarchy to maintain.

### Package Globals for Shared State

Package-level `our` variables for runtime state create invisible
coupling and break test isolation.

Bad:
```perl
package MyApp::Config;
our %settings;
sub load { my ($file) = @_; %settings = parse_config($file) }
sub get  { my ($key) = @_;  return $settings{$key} }
```

Good:
```perl
package MyApp::Config;
use Moo;
has _settings => (is => 'ro', default => sub { {} });
sub load { my ($self, $file) = @_; %{$self->_settings} = parse_config($file) }
sub get  { my ($self, $key) = @_;  return $self->_settings->{$key} }
```

Each instance carries its own state. Tests create fresh instances.

When this is safe: Read-only configuration loaded once at startup
and never modified (e.g., `%ENV` wrappers).

---

## Error Handling

### Bare `eval`/`$@`

`$@` can be clobbered between `eval` exit and the `if` check by
object destructors or nested `eval` blocks, silently losing the
exception.

Bad:
```perl
eval {
    my $obj = SomeClass->new();
    risky_operation();
};
if ($@) { warn "Error: $@" }
```

Good:
```perl
use Try::Tiny;
try { risky_operation() }
catch { warn "Error: $_" };
```

`Try::Tiny` localizes `$@` and passes the exception safely. For
Perl 5.24+, `Syntax::Keyword::Try` provides native try/catch.

### Unchecked System Calls

`open`, `close`, `rename`, and `unlink` return false on failure
but do not die. Without checks, failures are silently ignored.

Bad:
```perl
open my $fh, '>', $output_file;
print {$fh} generate_report();
close $fh;
rename $output_file, $final_path;
```

Good:
```perl
open my $fh, '>', $output_file
    or die "Cannot open $output_file: $!";
print {$fh} generate_report();
close $fh
    or die "Cannot close $output_file: $!";
rename $output_file, $final_path
    or die "Cannot rename to $final_path: $!";
```

Every fallible system call needs `or die` with `$!`. Or use
`use autodie;` to make built-ins throw automatically.

### Silent `close`

`close` can fail when buffered data cannot be flushed (NFS errors,
disk full, broken pipe). Ignoring this means undetected data loss.

Bad:
```perl
open my $fh, '>', $file or die "Cannot open: $!";
print {$fh} $data;
close $fh;
```

Good:
```perl
open my $fh, '>', $file or die "Cannot open: $!";
print {$fh} $data;
close $fh or die "Cannot close $file: $!";
```

When this is safe: Closing STDIN/STDOUT/STDERR at program exit
where failure is unrecoverable.

### `die` with Bare String

Bare string `die` loses call stack context. Library callers
cannot determine where the error originated.

Bad:
```perl
package MyApp::Parser;
sub parse {
    my ($self, $input) = @_;
    die "input is undefined" unless defined $input;
}
```

Good:
```perl
package MyApp::Parser;
use Carp;
sub parse {
    my ($self, $input) = @_;
    croak "parse() requires defined input" unless defined $input;
}
```

`Carp::croak` reports the error from the caller's perspective.
Use `Carp::confess` for full stack traces.

When this is safe: Top-level scripts where error context is obvious:
`die "Usage: $0 <filename>\n" unless @ARGV;`

---

## Security

### Shell Injection via `system()`

The single-string form of `system()` passes arguments through
`/bin/sh`, enabling metacharacter injection.

Bad:
```perl
my $filename = get_user_input();
system("wc -l $filename");
```

Good:
```perl
my $filename = get_user_input();
system("wc", "-l", $filename);
```

List form bypasses the shell entirely via `execvp()`. Use
`Capture::Tiny` or `IPC::Run3` for safe output capture.

### `eval $string`

`eval` with a string argument compiles and executes arbitrary Perl
code. With user-influenced data, this is remote code execution.

Bad:
```perl
my $expr = get_user_input();
my $result = eval $expr;
```

Good:
```perl
# Safe math: use a purpose-built evaluator
use Math::Expression::Evaluator;
my $result = Math::Expression::Evaluator->new->parse($expr)->val();

# Safe dispatch: use a lookup table
my %handlers = (add => \&handle_add, remove => \&handle_remove);
my $handler = $handlers{$action} or die "Unknown action";
$handler->($args);
```

### Taint Bypass

The catch-all untaint pattern `/(.*)/s` accepts everything,
defeating taint mode entirely.

Bad:
```perl
#!/usr/bin/perl -T
my $input = $ENV{QUERY_STRING};
my ($clean) = ($input =~ /(.*)/s);  # validates nothing
system("grep $clean /var/log/app.log");
```

Good:
```perl
#!/usr/bin/perl -T
my $input = $ENV{QUERY_STRING};
my ($clean) = ($input =~ /^([a-zA-Z0-9_.-]{1,64})$/)
    or die "Invalid input";
system("grep", "--", $clean, "/var/log/app.log");
```

Untaint patterns must match only the specific expected format.
Combine with list-form `system()` for defense in depth.

### Two-Arg `open` Pipe Injection

Two-argument `open` interprets leading/trailing pipe characters
as commands, turning file opens into arbitrary code execution.

Bad:
```perl
my $logfile = get_config_value("logfile");
open(FH, $logfile);
# "| malicious_command" executes the command
```

Good:
```perl
my $logfile = get_config_value("logfile");
open my $fh, '<', $logfile
    or die "Cannot open $logfile: $!";
```

Three-argument `open` treats the filename as a literal path. In a
security context, two-argument `open` with external input is a
command injection vector.
