# PHPUnit Testing Reference

> Deep reference for PHP testing patterns. Covers PHPUnit and Pest
> conventions, fixture management, assertion discipline, and coverage
> strategy. Companion to the PHP governance template.

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

### PHPUnit vs Pest

PHPUnit is the standard testing framework. Pest provides an
expressive wrapper with syntax closer to Jest or RSpec.

```php
// PHPUnit -- class-based, explicit assertions
class OrderTotalTest extends TestCase {
    public function test_calculates_total_with_tax(): void {
        $order = new Order(items: [new LineItem(price: 1000, quantity: 2)]);
        $this->assertSame(2200, $order->totalWithTax(taxRate: 0.10));
    }
}

// Pest -- functional, expressive
it('calculates total with tax', function () {
    $order = new Order(items: [new LineItem(price: 1000, quantity: 2)]);
    expect($order->totalWithTax(taxRate: 0.10))->toBe(2200);
});
```

Choose one per project -- do not mix styles in the same suite.

### Static Analysis Integration

`phpstan` catches type errors, dead code, and impossible conditions
statically. It complements tests -- analysis finds what tests miss,
tests verify what analysis cannot reason about.

```yaml
# phpstan.neon
parameters:
    level: max
    paths: [app, src]
    checkMissingIterableValueType: true
```

Run `phpstan --level=max` in CI. Use a baseline for legacy projects:
`phpstan analyse --generate-baseline`. Increase level incrementally.

### Test Directory Structure

```
tests/
    Unit/           # No framework bootstrap, pure logic
    Feature/        # Full framework stack, HTTP tests
    Integration/    # External service interactions
    TestCase.php    # Base test class with shared setup
```

Unit tests have no framework dependency. Feature tests bootstrap the
framework for HTTP and console testing. If a test needs the service
container, it is a feature test.

---

## Fixture & Setup Patterns

### Database Isolation

The `RefreshDatabase` trait wraps each test in a transaction and
rolls back after completion -- faster than fresh migrations per test.

```php
class UserRegistrationTest extends TestCase {
    use RefreshDatabase;

    public function test_registers_new_user(): void {
        $response = $this->postJson('/api/register', [
            'name' => 'Alice',
            'email' => 'alice@example.com',
            'password' => 'secure-password-123',
        ]);
        $response->assertStatus(201);
        $this->assertDatabaseHas('users', ['email' => 'alice@example.com']);
    }
}
```

### Model Factories

Factories create test data with sensible defaults. Override only
the fields relevant to each test.

```php
// Factory definition
class UserFactory extends Factory {
    public function definition(): array {
        return [
            'name' => fake()->name(),
            'email' => fake()->unique()->safeEmail(),
            'password' => bcrypt('password'),
        ];
    }

    public function admin(): static {
        return $this->state(fn (array $attrs) => ['role' => 'admin']);
    }
}

// In tests -- override only what matters
public function test_admin_can_access_dashboard(): void {
    $admin = User::factory()->admin()->create();
    $this->actingAs($admin)->get('/admin/dashboard')->assertStatus(200);
}
```

Never use raw SQL inserts. Factories respect model events, mutators,
and relationships. Use factory states for common variations.

### setUp and tearDown

`setUp()` runs before each test. `tearDown()` runs after, even if
the test fails. Always call `parent::setUp()`.

```php
class ExternalApiTest extends TestCase {
    private string $tempDir;

    protected function setUp(): void {
        parent::setUp();
        $this->tempDir = sys_get_temp_dir() . '/' . uniqid('test_', true);
        mkdir($this->tempDir, 0755, true);
    }

    protected function tearDown(): void {
        if (is_dir($this->tempDir)) {
            array_map('unlink', glob($this->tempDir . '/*'));
            rmdir($this->tempDir);
        }
        parent::tearDown();
    }
}
```

### Test Doubles

Mocks verify interactions. Stubs provide canned responses. Fakes are
lightweight in-memory implementations of external services.

```php
// Laravel fake -- verifies mail was sent
public function test_sends_welcome_email(): void {
    Mail::fake();
    $this->postJson('/api/register', [
        'name' => 'Alice', 'email' => 'alice@example.com',
        'password' => 'secure-password-123',
    ]);
    Mail::assertSent(WelcomeEmail::class, fn ($mail) =>
        $mail->hasTo('alice@example.com'));
}

// PHPUnit mock -- verifies interaction contract
public function test_processor_calls_gateway(): void {
    $gateway = $this->createMock(PaymentGateway::class);
    $gateway->expects($this->once())
        ->method('charge')
        ->with('tok_test', 5000)
        ->willReturn(new PaymentResult(success: true));
    $processor = new OrderProcessor($gateway);
    $this->assertTrue($processor->processPayment('tok_test', 5000)->success);
}
```

Mock at system boundaries (payment, email, filesystem). Never mock
the class under test or value objects -- use real instances.

---

## Assertion Patterns

### assertEquals vs assertSame

`assertEquals` uses loose `==`. `assertSame` uses strict `===`.

```php
$this->assertEquals(0, '');    // PASSES: 0 == '' is true
$this->assertSame(0, '');     // FAILS:  0 !== ''
$this->assertEquals('1', 1);  // PASSES: '1' == 1 is true
$this->assertSame('1', 1);   // FAILS:  '1' !== 1
```

Default to `assertSame` for scalars. Use `assertEquals` only when
loose comparison is explicitly intended.

### Exception Testing

```php
public function test_rejects_negative_quantity(): void {
    $this->expectException(\InvalidArgumentException::class);
    $this->expectExceptionMessage('Quantity must be positive');
    new LineItem(price: 1000, quantity: -1);
}

// When you need to assert state after the exception
public function test_failed_payment_creates_no_order(): void {
    try {
        $this->processor->processPayment('bad_token');
        $this->fail('Expected PaymentFailedException');
    } catch (PaymentFailedException $e) {
        $this->assertDatabaseMissing('orders', ['payment_token' => 'bad_token']);
    }
}
```

### Data Providers

Data providers run a test with multiple input sets, generating a
separate case per entry.

```php
/** @dataProvider slugProvider */
public function test_generates_slug(string $input, string $expected): void {
    $this->assertSame($expected, Slug::generate($input));
}

public static function slugProvider(): array {
    return [
        'simple text'    => ['Hello World', 'hello-world'],
        'special chars'  => ['Foo & Bar!', 'foo-bar'],
        'already slug'   => ['hello-world', 'hello-world'],
        'empty string'   => ['', ''],
    ];
}
```

Name each data set with array keys. Data providers must be `static`
in PHPUnit 10+.

### HTTP Response Assertions

```php
public function test_api_returns_user_list(): void {
    User::factory()->count(3)->create();
    $response = $this->getJson('/api/users');
    $response->assertStatus(200)
        ->assertJsonCount(3, 'data')
        ->assertJsonStructure([
            'data' => [['id', 'name', 'email']],
            'meta' => ['current_page', 'total'],
        ]);
}

public function test_validation_returns_errors(): void {
    $this->postJson('/api/users', ['name' => '', 'email' => 'bad'])
        ->assertStatus(422)
        ->assertJsonValidationErrors(['name', 'email']);
}
```

Test both success and error paths. Assert structure, not just status.

---

## Coverage & CI

### PHPUnit Coverage Configuration

```xml
<phpunit>
    <coverage>
        <include>
            <directory suffix=".php">app</directory>
        </include>
        <report>
            <clover outputFile="coverage.xml"/>
        </report>
    </coverage>
</phpunit>
```

Include application code, exclude framework boilerplate. Review
coverage for the specific change, not just total percentage.

### Mutation Testing with Infection

Coverage measures which lines execute. Mutation testing measures
whether tests detect changes. A mutant (flipping `>` to `>=`,
removing a call) that does not break tests means insufficient tests.

```bash
composer require --dev infection/infection
infection --min-msi=80 --min-covered-msi=90 --threads=4 --only-covered
```

MSI (Mutation Score Indicator) is the percentage of mutants killed.
Start with `--only-covered` to focus on existing test quality.

### CI Pipeline

```yaml
# .github/workflows/ci.yml
jobs:
  test:
    strategy:
      matrix:
        php: ['8.1', '8.2', '8.3']
    steps:
      - uses: shivammathur/setup-php@v2
        with: { php-version: '${{ matrix.php }}', coverage: xdebug }
      - run: composer install --no-progress
      - run: php-cs-fixer fix --dry-run --diff
      - run: phpstan analyse --level=max --no-progress
      - run: php artisan test --coverage-clover=coverage.xml
      - run: infection --min-msi=80 --threads=4 --no-progress
        if: matrix.php == '8.3'
```

Run fast checks first (coding standards, static analysis). Run
mutation testing on one PHP version to save CI time. Use matrix
builds for version compatibility verification.

### Pre-Commit Hooks

```bash
php-cs-fixer fix --dry-run --diff
phpstan analyse --level=max --no-progress --memory-limit=512M
php artisan test --stop-on-failure
```

Use `--stop-on-failure` for fast feedback on the first broken test.
