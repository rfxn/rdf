# PHP Anti-Patterns Reference

> Deep reference for common PHP anti-patterns. Each section shows the
> broken pattern, explains why it fails, and provides the correct
> alternative. Companion to the PHP governance template.

---

## Verification Preamble

Before reporting any pattern from this document as a finding:
1. Verify the pattern exists in project code (not just dependencies)
2. Check whether framework or library protections already mitigate it
3. Confirm the code path is reachable from an entry point
4. Read the "When this is safe" annotation if present

A pattern match is a candidate. A verified pattern match is a finding.

---

## Type Safety

### Missing strict_types

Without `declare(strict_types=1)`, PHP silently coerces types at
function boundaries, masking type confusion bugs.

Bad:
```php
<?php
// No strict_types -- silently accepts strings, returns 150
function calculateTotal(int $price, int $quantity): int {
    return $price * $quantity;
}
echo calculateTotal("15", "10");
```

Good:
```php
<?php
declare(strict_types=1);
function calculateTotal(int $price, int $quantity): int {
    return $price * $quantity;
}
// TypeError: Argument #1 must be of type int, string given
```

The declaration applies to calls made from the declaring file. Every
file needs it -- a single missing file creates a type coercion hole.

### Mixed Type Parameters

Untyped parameters accept anything. Bugs propagate silently through
call chains until they surface far from the root cause.

Bad:
```php
function processOrder($data, $userId) {
    $order = new Order();
    $order->items = $data;  // could be array, object, string, null
    return $order->save();
}
```

Good:
```php
function processOrder(array $items, int $userId): OrderResult {
    $order = new Order();
    $order->items = $items;
    $order->user_id = $userId;
    return $order->save();
}
```

Type every parameter, return type, and class property. Use union types
(`string|int`) when multiple types are genuinely valid.

When this is safe: Legacy code where adding types would break callers.
Add types to all new code regardless.

### Annotation-Only Types

PHPDoc `@var` annotations are documentation, not enforcement. They
are invisible to the runtime.

Bad:
```php
class User {
    /** @var string */
    public $name;
    /** @var int */
    public $age;
}
$user = new User();
$user->name = 42;  // No error -- annotation is not enforced
```

Good:
```php
class User {
    public function __construct(
        public readonly string $name,
        public readonly int $age,
        /** @var list<string> */
        public readonly array $roles = [],
    ) {}
}
```

Use actual type declarations. Constructor promotion (PHP 8.0+) with
`readonly` (PHP 8.1+) provides real type safety. Reserve `@var` for
generic arrays and phpstan template types.

When this is safe: When targeting PHP < 7.4 where typed properties
do not exist.

### Loose Comparison

PHP's `==` applies type juggling: `"0" == false`, `"" == false`,
`"0" == null` are all true under loose comparison.

Bad:
```php
if ($status == false) { return false; }  // "0" matches
if (in_array($val, $arr)) { ... }       // loose by default
```

Good:
```php
if ($status === '') { return false; }
if (in_array($val, $arr, true)) { ... }  // strict flag
```

Use `===` everywhere. The third parameter in `in_array()` and
`array_search()` enables strict comparison and is `false` by
default -- a dangerous default that must be overridden.

When this is safe: Intentional type juggling with an explicit inline
comment explaining why.

---

## Query Safety

### Raw SQL Concatenation

String-concatenated SQL is the most exploited vulnerability class in
PHP. Even `addslashes()` fails against multibyte charset attacks.

Bad:
```php
$name = $_GET['name'];
$pdo->query("SELECT * FROM users WHERE name = '$name'");

$name = addslashes($_GET['name']);  // still vulnerable
$pdo->query("SELECT * FROM users WHERE name = '$name'");
```

Good:
```php
$stmt = $pdo->prepare('SELECT * FROM users WHERE name = :name');
$stmt->execute(['name' => $_GET['name']]);
$result = $stmt->fetchAll();
```

Use PDO prepared statements. Set `PDO::ATTR_EMULATE_PREPARES` to
`false` -- emulated prepares interpolate client-side, defeating the
purpose. Eloquent/Doctrine parameterize automatically, but raw methods
(`DB::raw()`, `whereRaw()`, `selectRaw()`) bypass protection -- always
pass bindings as the second argument.

### Mass Assignment

An empty `$guarded` array allows any field to be mass-assigned,
including `is_admin`, `role`, and `email_verified_at`.

Bad:
```php
class User extends Model {
    protected $guarded = [];  // everything is assignable
}
User::create($request->all());
```

Good:
```php
class User extends Model {
    protected $fillable = ['name', 'email', 'password'];
}
User::create($request->validated());
```

Use explicit `$fillable` whitelist. Never include `id`, `is_admin`,
`role`, `email_verified_at`, or authorization fields. For Doctrine:
use explicit setter methods. For Symfony: `allow_extra_fields: false`.

### Raw Template Output

Blade's `{!! !!}` outputs unescaped HTML. User-controlled data
rendered through raw output creates stored XSS vulnerabilities.

Bad:
```php
<div class="bio">{!! $user->bio !!}</div>
```

Good:
```php
<div class="bio">{{ $user->bio }}</div>
```

Use `{{ }}` (auto-escaped) for all user-controlled output.

When this is safe: Pre-sanitized trusted HTML from a server-side
markdown renderer where the sanitization pipeline is verified.

---

## Query Performance

### N+1 Queries

Accessing a relationship in a loop generates one query per item.
100 users with posts means 101 queries instead of 2.

Bad:
```php
$users = User::all();
foreach ($users as $user) {
    echo $user->posts->count();  // SELECT per iteration
}
```

Good:
```php
$users = User::with('posts')->get();  // 2 queries total
foreach ($users as $user) {
    echo $user->posts->count();  // no additional query
}
```

Use `with()` for eager loading. Enable `Model::preventLazyLoading()`
in development to throw on N+1 queries.

When this is safe: Single-record lookups where eager loading would
fetch unnecessary data.

### Missing Pagination

Loading unbounded result sets causes memory exhaustion as data grows.

Bad:
```php
$orders = Order::get();  // loads entire table into memory
return view('orders.index', compact('orders'));
```

Good:
```php
$orders = Order::orderBy('created_at', 'desc')->paginate(25);
return view('orders.index', compact('orders'));
```

Use `paginate()` or `cursorPaginate()` for user-facing lists. For
background jobs, use `chunk()` or `lazy()` to control memory.

When this is safe: Admin-only reports with known-small datasets and
an explicit `limit()` clause.

---

## Error Handling

### Bare catch

An empty catch block silently swallows exceptions, making failures
impossible to diagnose.

Bad:
```php
try {
    $order->process();
} catch (\Exception $e) {
    // silently swallowed
}
```

Good:
```php
try {
    $order->process();
} catch (PaymentFailedException $e) {
    Log::error('Payment failed', ['order_id' => $order->id]);
    throw $e;
} catch (InventoryException $e) {
    Log::warning('Inventory check failed', ['order_id' => $order->id]);
    $order->markAsPendingInventory();
}
```

Catch specific exceptions. Log with context. Either rethrow, handle
with a defined recovery path, or convert to a domain exception.

### error_reporting(0)

Suppressing errors hides type errors, undefined variables, deprecated
usage, and security-relevant warnings.

Bad:
```php
error_reporting(0);
ini_set('display_errors', '0');
$result = procss_data($input);  // typo -- no error shown
```

Good:
```php
// All environments: report everything
error_reporting(E_ALL);
// Production: log, never display
ini_set('display_errors', '0');
ini_set('log_errors', '1');
```

Set `error_reporting(E_ALL)` everywhere. In production, disable
display but enable logging. Use Sentry/Bugsnag/Flare for alerting.

### Swallowed Exceptions

Catching and returning a default without logging creates silent
failures that corrupt data over time.

Bad:
```php
function findUser(int $id): ?User {
    try {
        return $this->repository->find($id);
    } catch (\Exception $e) {
        return null;  // database down? timeout? permission error?
    }
}
```

Good:
```php
function findUser(int $id): ?User {
    try {
        return $this->repository->find($id);
    } catch (RecordNotFoundException $e) {
        return null;  // expected -- user does not exist
    } catch (\Exception $e) {
        Log::error('User lookup failed', ['user_id' => $id]);
        throw new UserLookupException("Failed to find user $id", previous: $e);
    }
}
```

Catch expected exceptions with specific recovery. Let unexpected
exceptions propagate or wrap in domain-specific exceptions with
the original as `previous`.

When this is safe: Specific expected exceptions where absence is a
valid state -- "record not found" when the caller handles null.

---

## Security

### CSRF Gaps

State-changing endpoints without CSRF verification allow cross-site
request forgery.

Bad:
```php
{{-- Missing @csrf --}}
<form method="POST" action="/account/delete">
    <button type="submit">Delete Account</button>
</form>
```

Good:
```php
<form method="POST" action="/account/delete">
    @csrf
    <button type="submit">Delete Account</button>
</form>
```

Include `@csrf` in every form. Ensure `VerifyCsrfToken` middleware
is active on all web routes. For SPAs, use Sanctum with
`SameSite=Strict` cookies.

### File Upload Without Validation

Unvalidated uploads enable remote code execution (`.php` upload),
DoS (oversized files), and content-type spoofing.

Bad:
```php
$path = $request->file('avatar')->store('uploads');
```

Good:
```php
$request->validate([
    'avatar' => ['required', 'file', 'mimes:jpg,png,webp', 'max:2048'],
]);
$file = $request->file('avatar');
$mime = (new \finfo(FILEINFO_MIME_TYPE))->file($file->getRealPath());
if (!in_array($mime, ['image/jpeg', 'image/png', 'image/webp'], true)) {
    abort(422, 'Invalid file type');
}
$path = $file->store('avatars', 'private');
```

Validate extension (allowlist), MIME via `finfo_file()` (not client
header), and size. Store outside web root with randomized filenames.

### APP_DEBUG=true in Production

Debug mode exposes env vars, SQL queries, stack traces, and framework
internals to any user who triggers an error.

Bad:
```php
# .env (production)
APP_DEBUG=true
```

Good:
```php
# .env (production)
APP_DEBUG=false

# app/Exceptions/Handler.php -- report to error tracker
$this->reportable(function (\Throwable $e) {
    if (app()->bound('sentry')) {
        app('sentry')->captureException($e);
    }
});
```

Set `APP_DEBUG=false` in production. Create custom error pages. Use
an error tracking service for exception capture.

### Static Facades as Service Locator

Static facades in domain logic hide dependencies and couple business
logic to the framework, requiring full bootstrap for unit tests.

Bad:
```php
class OrderProcessor {
    public function process(int $orderId): void {
        $order = DB::table('orders')->find($orderId);
        Cache::put("order:$orderId", $order, 3600);
        Mail::send(new OrderConfirmation($order));
    }
}
```

Good:
```php
class OrderProcessor {
    public function __construct(
        private readonly OrderRepository $orders,
        private readonly CacheInterface $cache,
        private readonly MailerInterface $mailer,
    ) {}

    public function process(int $orderId): void {
        $order = $this->orders->find($orderId);
        $this->cache->set("order:$orderId", $order, 3600);
        $this->mailer->send(new OrderConfirmation($order));
    }
}
```

Inject dependencies through the constructor. Domain logic should
depend on interfaces, not facades.

When this is safe: In controllers, commands, and service providers
where the framework provides the entry point and manages lifecycle.
