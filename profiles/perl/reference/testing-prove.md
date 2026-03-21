# Perl Testing Reference

> Deep reference for Perl testing patterns. Covers Test2::V0 and
> Test::More frameworks, prove configuration, fixture isolation,
> assertion discipline, and coverage tooling. Companion to the Perl
> governance template.

---

## Evidence Discipline

Tests are evidence, not ceremony. Every test must:
- Assert a specific, falsifiable claim about code behavior
- Fail meaningfully when the claim is violated (not just "exit 1")
- Be reproducible in isolation (no shared state, no test ordering)
- Name what it proves (test name = specification)

Before trusting a passing test suite as evidence:
- Verify tests actually execute the code path in question
- Check for tautological assertions (always-true conditions)
- Confirm mocks match real interface contracts
- Review coverage for the specific change, not just total coverage %

---

## Framework Patterns

### Test2::V0 vs Test::More

Test2::V0 is the modern framework with better diagnostics, built-in
subtesting, and structured comparison builders. Use it for new code.
Use Test::More only for legacy suites or when Test2 is unavailable.

```perl
# Test2::V0 -- modern, preferred
use Test2::V0;

is($result, 42, "computation returns 42");
like($output, qr/success/, "output contains success marker");
is_deeply(\@got, \@expected, "arrays match element-by-element");

done_testing;
```

Key advantages of Test2::V0 over Test::More:
- `hash`, `array`, `bag`, `object` check builders for structure matching
- Inline diagnostic output showing both got and expected values
- Built-in mock and intercept support via Test2::Tools
- Test::More is core Perl (no dependency), but lacks structured checks

### `prove` Configuration

Configure default flags in `.proverc` at the project root.

```
# .proverc
--recurse
--verbose
--lib
--color
--state=save
```

Common usage patterns:
```bash
prove -r t/              # full suite
prove -j4 -r t/          # parallel with 4 workers
prove --state=failed      # rerun only failures from last run
prove --shuffle t/        # randomize order to detect hidden deps
```

### TAP Output

TAP (Test Anything Protocol) format: `ok N` for pass, `not ok N`
for fail, `#` lines for diagnostics, `1..N` for the plan.

```
ok 1 - database connection succeeds
not ok 2 - query returns expected value
#   Failed test 'query returns expected value'
#          got: 'pending'
#     expected: 'complete'
1..2
```

### Plan Strategies

Use `plan N` when the count is fixed (catches premature exit), or
`done_testing` when the count depends on data.

```perl
use Test2::V0;
plan 3;           # exactly 3 tests expected
ok(1, "first");
ok(1, "second");
ok(1, "third");
```

```perl
use Test2::V0;
for my $case (@test_cases) {
    is(process($case->{input}), $case->{expected}, $case->{name});
}
done_testing;     # count determined at runtime
```

---

## Fixture & Setup Patterns

### Test File Isolation

Each `.t` file runs as a separate Perl process with no shared state.
This is a fundamental property -- use it. Do not rely on execution
order or write to package globals that other files read.

```perl
# t/lib/TestHelper.pm -- shared setup extracted to a module
package TestHelper;
use Exporter 'import';
our @EXPORT_OK = qw(make_test_config);

sub make_test_config {
    return { database => 'test_db', timeout => 5 };
}
1;
```

```perl
# t/feature.t
use Test2::V0;
use lib 't/lib';
use TestHelper qw(make_test_config);

my $config = make_test_config();
is($config->{database}, 'test_db', "config has test database");
done_testing;
```

### Temporary Files with `File::Temp`

Never use `$$` or manual naming. `File::Temp` provides race-free
creation and automatic cleanup.

```perl
use Test2::V0;
use File::Temp qw(tempdir tempfile);

my $dir = tempdir(CLEANUP => 1);
my ($fh, $filename) = tempfile(DIR => $dir, SUFFIX => '.txt');
print {$fh} "test data\n";
close $fh or die "Cannot close: $!";

is(count_lines($filename), 1, "file has one line");
done_testing;
```

### Mocking with `Test2::Mock`

Mock at system boundaries (network, I/O, database), not internal
business logic.

```perl
use Test2::V0;
use Test2::Tools::Mock;

my $mock = mock 'MyApp::HTTPClient' => (
    override => [
        get => sub { return { status => 200, body => '{"ok":true}' } },
    ],
);

my $svc = MyApp::Service->new(client => MyApp::HTTPClient->new());
is($svc->fetch_data("https://api.example.com")->{ok}, 1, "processes response");
done_testing;
```

For module-level mocking without dependency injection:

```perl
use Test2::V0;
use Test::MockModule;

my $mock = Test::MockModule->new('LWP::UserAgent');
$mock->mock('get', sub {
    return HTTP::Response->new(200, 'OK', [], '{"ok":true}');
});

my $result = MyApp::fetch_api_data();
is($result->{ok}, 1, "handles API response");
done_testing;
```

### Setup/Teardown with Subtests

`subtest` provides implicit scoping for setup and teardown.

```perl
use Test2::V0;

subtest 'user creation' => sub {
    my $db = setup_test_database();
    my $user = $db->create_user(name => "alice");
    ok($user->id, "user gets an ID");
    is($user->name, "alice", "name is stored");
    $db->cleanup();
};

subtest 'user deletion' => sub {
    my $db = setup_test_database();
    my $user = $db->create_user(name => "bob");
    $db->delete_user($user->id);
    ok(!$db->find_user($user->id), "user is removed");
    $db->cleanup();
};

done_testing;
```

### Database Test Isolation

Use in-memory SQLite with transaction rollback between subtests.

```perl
use Test2::V0;
use DBI;

my $dbh = DBI->connect('dbi:SQLite:dbname=:memory:', '', '',
    { RaiseError => 1 });
$dbh->do('CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT)');

subtest 'insert' => sub {
    $dbh->begin_work;
    $dbh->do("INSERT INTO users (name) VALUES (?)", undef, "alice");
    my ($count) = $dbh->selectrow_array("SELECT COUNT(*) FROM users");
    is($count, 1, "one user after insert");
    $dbh->rollback;
};

done_testing;
```

---

## Assertion Patterns

### Core Assertions

```perl
use Test2::V0;

is($got, $expected, "values are equal");
ok($condition, "condition is true");
like($string, qr/pattern/, "string matches");
unlike($string, qr/forbidden/, "string excludes pattern");
is_deeply(\%got, \%expected, "structures match deeply");
ref_ok($obj, 'MyApp::User', "correct object type");

done_testing;
```

### Exception Testing

```perl
use Test2::V0;

my $exception = dies { parse_invalid_input("garbage") };
ok($exception, "invalid input causes death");
like($exception, qr/parse error/, "descriptive error message");

ok(lives { parse_valid_input("good data") }, "valid input succeeds");

done_testing;
```

### Subtest Grouping

Group related assertions. Each subtest is one pass/fail in parent
output with details in verbose mode.

```perl
use Test2::V0;

subtest 'config loading' => sub {
    my $config = load_config("t/fixtures/valid.conf");
    is($config->{host}, "localhost", "host");
    is($config->{port}, 8080, "port");
    is_deeply($config->{ips}, ["127.0.0.1"], "allowed IPs");
};

subtest 'missing config' => sub {
    my $e = dies { load_config("nonexistent.conf") };
    like($e, qr/Cannot open/, "reports missing file");
};

done_testing;
```

### Custom Comparators (Test2)

```perl
use Test2::V0;

is(
    $user,
    hash {
        field name  => 'alice';
        field email => match qr/\@example\.com$/;
        field role  => in_set('viewer', 'editor', 'admin');
        end();  # no extra fields
    },
    "user has expected structure",
);

done_testing;
```

---

## Coverage & CI

### Devel::Cover

```bash
cover -test -ignore_re '^t/' -ignore_re 'vendor/'
cover -report html
cover -report text | grep 'Total'
```

Check the `branch` column, not just `statement` -- statement
coverage misses untested branches in conditionals.

### Parallel Testing

```bash
prove -j4 -r t/       # 4 workers
prove -j$(nproc) -r t/ # auto-detect CPU count
```

Prerequisites: no shared temp files with hardcoded paths, no
shared databases without isolation, no test-order dependencies.

### `perlcritic` Integration

```
# .perlcriticrc
severity = 3
[TestingAndDebugging::RequireUseStrict]
severity = 5
[InputOutput::RequireCheckedOpen]
severity = 5
```

```bash
perlcritic --severity 4 --quiet lib/ bin/
```

### CI Pipeline Structure

Run checks in order of cost -- fast failures first:

1. `perl -c lib/MyApp/*.pm` -- syntax (fast)
2. `perlcritic --severity 4 lib/` -- static analysis (fast)
3. `prove -j4 -r t/unit/` -- unit tests (medium)
4. `prove -r t/integration/` -- integration tests (slow)
5. `cover -test` -- coverage (slowest)

### Test Ordering Independence

```bash
prove --shuffle t/     # random order
prove t/specific.t     # single file isolation
```

If a test fails in isolation but passes in the full suite, it has
a hidden dependency on another test's side effects. Fix the
dependency -- do not rely on execution order.
