# Perl Regex Security Reference

> Deep reference for Perl regex security patterns. Covers regex
> injection prevention, catastrophic backtracking, safe interpolation,
> taint mode interaction, and Unicode safety. Companion to the Perl
> governance template.

---

## Regex Injection

User-controlled data interpolated into regex patterns is code
injection. Perl's regex engine interprets the interpolated string
as pattern syntax, not literal text.

### The `\Q\E` Discipline

Every variable interpolated into a regex must be wrapped in
`\Q...\E` unless the variable is trusted and intended as a pattern.

```perl
# UNSAFE -- user input is regex syntax
my $search = get_user_input();  # user sends: .*
$str =~ /$search/;              # matches everything

# SAFE -- user input is literal text
$str =~ /\Q$search\E/;          # .* treated as literal dot-star
```

### Precompilation with `qr//`

For patterns used multiple times, precompile to avoid repeated
compilation and make quoting explicit.

```perl
my $literal = qr/\Q$user_input\E/;
for my $line (@lines) {
    push @matches, $line if $line =~ $literal;
}
```

### Input Validation Anchoring

Anchor patterns with `\A` and `\z` (not `^`/`$`, which match
line boundaries under `/m`). Validate the entire string.

```perl
# WRONG -- partial match accepts "admin; DROP TABLE"
if ($username =~ /[a-zA-Z0-9_]+/) { accept($username) }

# CORRECT -- anchored full-string match
if ($username =~ /\A[a-zA-Z0-9_]{1,64}\z/) {
    accept($username);
} else {
    reject("Invalid username format");
}
```

---

## Catastrophic Backtracking

Perl's regex engine uses backtracking NFA. Certain patterns cause
exponential backtracking on non-matching input.

### Nested Quantifiers

The classic ReDoS shape: a quantifier applied to a group that
itself contains a quantifier.

```perl
# VULNERABLE -- exponential on "aaaaaaaaaaX"
my $bad = qr/(a+)+$/;

# Other dangerous shapes
qr/(a|a)+$/;           # overlapping alternatives
qr/([a-z]+[a-z]+)+$/;  # overlapping character classes
qr/(.*?,)+$/;           # quantified optional
```

### Timeout Guards

Wrap regex on untrusted input in a timeout.

```perl
sub safe_match {
    my ($string, $pattern, $timeout) = @_;
    $timeout //= 2;
    my $matched;
    eval {
        local $SIG{ALRM} = sub { die "regex timeout\n" };
        alarm($timeout);
        $matched = $string =~ $pattern;
        alarm(0);
    };
    alarm(0);  # clear even if eval dies for other reasons
    if ($@ && $@ =~ /regex timeout/) {
        warn "Regex timed out on input length " . length($string);
        return 0;
    }
    die $@ if $@;
    return $matched;
}
```

### Atomic Groups and Possessive Quantifiers

Atomic groups `(?>...)` prevent backtracking into the group.
Possessive quantifiers (`++`, `*+`, `?+`) are shorthand (Perl 5.10+).

```perl
# Backtracking -- tries all partitions of a's
"aaaaab" =~ /(a+)ab/;

# Atomic -- fails immediately after a+ consumes all a's
"aaaaab" =~ /(?>a+)ab/;

# Possessive -- same as atomic
"aaaaab" =~ /a++ab/;
```

---

## Safe Interpolation

### Match Side vs Replacement Side

The match side interpolates variables as regex. The replacement
side interpolates as a double-quoted string (safe).

```perl
my ($old, $new) = ("foo", "bar");

# Match side needs quoting
$str =~ s/\Q$old\E/$new/g;  # $old is literal, $new is plain string
```

### The `/e` Modifier

`/e` evaluates the replacement as Perl code. This is the most
dangerous regex feature.

```perl
# /e -- replacement is code
$str =~ s/(\d+)/$1 * 2/e;  # doubles numbers

# DANGEROUS with user content
$template =~ s/\{(\w+)\}/$data{$1}/e;
# if $1 comes from user, they control the expression
```

Safe template substitution without `/e`:

```perl
for my $key (keys %vars) {
    my $placeholder = quotemeta("{$key}");
    $template =~ s/$placeholder/$vars{$key}/g;
}
```

### Capturing vs Non-Capturing Groups

Use `(?:...)` when you do not need the match text. This avoids
populating `$1` with potentially sensitive data.

```perl
# Capturing -- $1 contains password-like data
$line =~ /(secret:\s*\S+)/;

# Non-capturing -- no sensitive data in $1
$line =~ /(?:secret:\s*\S+)/;
```

Named captures `(?<name>...)` improve readability but still store
data in `$+{name}` -- same sensitivity considerations apply.

---

## Taint Mode Interaction

Perl's taint mode (`-T`) marks external data as tainted and
prevents it from reaching dangerous operations. Regex captures
are the primary untainting mechanism.

### How Regex Untaints

Captured substrings from a regex match on tainted data are
untainted. The regex is the validation gate.

```perl
#!/usr/bin/perl -T
my $input = $ENV{QUERY_STRING};  # tainted
if ($input =~ /\A([a-z]{1,32})\z/) {
    my $clean = $1;  # untainted
    process($clean);
} else {
    die "Invalid input format";
}
```

### Unsafe Untaint Patterns

Catch-all patterns defeat taint mode entirely:

```perl
# NEVER -- accepts everything, validates nothing
my ($clean) = ($tainted =~ /(.*)/s);
my ($clean) = ($tainted =~ /(.+)/s);
my ($clean) = ($tainted =~ /([\s\S]*)/);
```

### Safe Untaint by Domain

```perl
# Username
my ($user) = ($input =~ /\A([a-zA-Z0-9_]{1,64})\z/)
    or die "Invalid username";

# Filename (no path traversal)
my ($file) = ($input =~ /\A([a-zA-Z0-9_.-]{1,255})\z/)
    or die "Invalid filename";

# IPv4
my ($ip) = ($input =~ /\A(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})\z/)
    or die "Invalid IP";

# Integer
my ($num) = ($input =~ /\A(-?\d{1,10})\z/)
    or die "Invalid integer";
```

### Taint Propagation

`s///` does not untaint -- only parenthesized captures in `m//` do.

```perl
#!/usr/bin/perl -T
my $tainted = $ENV{PATH};
(my $modified = $tainted) =~ s/:/ /g;
# $modified is still tainted

if ($tainted =~ m{\A(/[a-z/]+)\z}i) {
    my $clean = $1;  # untainted via capture
}
```

### Taint Checking

```perl
use Scalar::Util qw(tainted);

sub assert_untainted {
    my ($value, $label) = @_;
    die "$label is still tainted" if tainted($value);
}
```

---

## Unicode Safety

### `.` vs `\X` for Grapheme Clusters

`.` matches a single code point. Characters with combining marks
are multiple code points but one visible grapheme.

```perl
use utf8;
my $str = "\x{0065}\x{0301}";  # e + combining acute = one grapheme

$str =~ /^.$/;   # FAILS -- two code points
$str =~ /^\X$/;  # matches -- one grapheme cluster
```

### `/u` Flag for Unicode Semantics

```perl
use utf8;
my $str = "cafe\x{0301}";

$str =~ /\w+/;   # ASCII semantics (platform-dependent)
$str =~ /\w+/u;  # Unicode semantics -- matches accented chars
```

In Perl 5.14+, `use feature 'unicode_strings'` (included in
`use v5.16;`) enables Unicode semantics by default.

### Unicode Property Classes

`\p{}` and `\P{}` match Unicode properties -- more precise than
POSIX classes for international text.

```perl
$str =~ /\p{Letter}+/;      # any letter, any script
$str =~ /\p{Number}+/;      # any numeric character
$str =~ /\p{Greek}/;         # Greek script
$str =~ /\P{Letter}/;        # non-letter
```

### UTF-8 Boundary Safety

Always decode byte strings before applying regex. Byte-level
matching can split multi-byte sequences.

```perl
use Encode qw(decode);

my $bytes = do { local $/; <$fh> };
my $text = decode('UTF-8', $bytes, Encode::FB_CROAK);

# Now regex operates on characters, not bytes
if ($text =~ /\p{Cyrillic}/) {
    warn "Contains Cyrillic characters";
}
```

### Homoglyph Detection

Unicode contains visually identical characters from different
scripts. Detect mixed scripts to prevent spoofing.

```perl
use Unicode::UCD qw(charscript);

sub has_mixed_scripts {
    my ($str) = @_;
    my %scripts;
    for my $char (split //, $str) {
        my $script = charscript(ord $char) // 'Unknown';
        next if $script eq 'Common' || $script eq 'Inherited';
        $scripts{$script} = 1;
    }
    return scalar keys %scripts > 1;
}
```
