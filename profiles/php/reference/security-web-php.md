# PHP Web Security Reference

> Deep reference for PHP web security patterns. Covers SQL injection,
> XSS prevention, authentication, file upload safety, and
> deserialization risks. Companion to the PHP governance template.

---

## SQL Injection

### PDO Prepared Statements

Prepared statements separate query structure from data. The database
parses the template once, then binds parameters separately -- user
input never becomes part of SQL syntax.

```php
// UNSAFE -- string interpolation
$pdo->query("SELECT * FROM users WHERE email = '$email'");

// SAFE -- positional placeholder
$stmt = $pdo->prepare('SELECT * FROM users WHERE email = ?');
$stmt->execute([$email]);

// SAFE -- named placeholder
$stmt = $pdo->prepare('SELECT * FROM users WHERE email = :email');
$stmt->execute(['email' => $email]);
```

### Emulated Prepares

PDO's default `ATTR_EMULATE_PREPARES` interpolates parameters
client-side and sends the query as a single string, defeating
prepared statement security.

```php
// SAFE -- native server-side prepares
$pdo = new PDO($dsn, $user, $pass, [
    PDO::ATTR_EMULATE_PREPARES => false,
    PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
    PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
]);
```

### Eloquent Raw Methods

Eloquent parameterizes automatically, but raw methods bypass this.
Every raw method accepts a bindings array as its second argument.

```php
// UNSAFE -- raw without bindings
Order::whereRaw("status = '$status'")->get();

// SAFE -- bindings parameter
Order::whereRaw('status = ?', [$status])->get();
DB::select('SELECT * FROM users WHERE role = ?', [$role]);
```

Affected methods: `DB::raw()`, `DB::select()`, `DB::statement()`,
`whereRaw()`, `orWhereRaw()`, `havingRaw()`, `selectRaw()`,
`orderByRaw()`, `groupByRaw()`. Every one accepts bindings.

### Doctrine DQL

```php
// UNSAFE -- concatenation
$em->createQuery("SELECT u FROM User u WHERE u.email = '$email'");

// SAFE -- parameter binding
$query = $em->createQuery('SELECT u FROM User u WHERE u.email = :email');
$query->setParameter('email', $email);
```

---

## XSS Prevention

### Template Engine Escaping

Blade and Twig auto-escape by default. The danger is the explicit
raw output syntax.

```php
{{-- Blade --}}
{{ $user->name }}       {{-- SAFE -- htmlspecialchars applied --}}
{!! $user->bio !!}      {{-- UNSAFE -- raw HTML output --}}

{# Twig #}
{{ user.name }}         {# SAFE -- auto-escaped #}
{{ user.bio|raw }}      {# UNSAFE -- raw output #}
```

Never use raw output for user-controlled data. Reserve `{!! !!}`
for server-generated HTML sanitized through HTML Purifier or
league/commonmark with safe mode.

### Manual Escaping

When not using a template engine, escape with correct flags.

```php
// UNSAFE -- default flags miss single quotes
echo htmlspecialchars($input);

// SAFE -- ENT_QUOTES prevents attribute injection
echo htmlspecialchars($input, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
```

`ENT_QUOTES` escapes both single and double quotes. Without it,
`' onmouseover='alert(1)` inside a single-quoted attribute executes
JavaScript. `ENT_SUBSTITUTE` replaces invalid encoding sequences.

### Content Security Policy

CSP headers are defense-in-depth. Even with an escaping gap, CSP
prevents inline script execution.

```php
// Middleware
$response->headers->set('Content-Security-Policy',
    "default-src 'self'; "
    . "script-src 'self' 'nonce-{$nonce}'; "
    . "style-src 'self' 'unsafe-inline'; "
    . "frame-ancestors 'none';"
);
```

Use nonce-based CSP for inline scripts. Generate a fresh nonce per
request. Block `frame-ancestors` to prevent clickjacking.

### Cookie Security Flags

```php
// config/session.php (Laravel)
'secure' => true,       // HTTPS only
'http_only' => true,    // not accessible via JavaScript
'same_site' => 'strict' // prevents cross-site request attachment

// Manual cookie
setcookie('session_id', $value, [
    'secure' => true, 'httponly' => true, 'samesite' => 'Strict',
]);
```

`HttpOnly` prevents JS cookie access (mitigates XSS theft).
`Secure` restricts to HTTPS. `SameSite=Strict` prevents cross-origin
cookie attachment (mitigates CSRF).

---

## Authentication

### Framework-Provided Auth

Use framework auth packages. Authentication is a solved problem.

```php
// Laravel Sanctum -- API token auth
$token = $user->createToken('api-access', ['read', 'write']);

// Protecting routes
Route::middleware('auth:sanctum')->group(function () {
    Route::get('/user', fn (Request $request) => $request->user());
});
```

For SPAs, use Sanctum cookie-based auth. For mobile/third-party, use
tokens. For server-to-server, use short-lived tokens with scopes.

### Password Hashing

```php
// UNSAFE -- fast hashes not designed for passwords
$hash = md5($password);
$hash = sha1($password);

// SAFE -- bcrypt (widely supported)
$hash = password_hash($password, PASSWORD_BCRYPT, ['cost' => 12]);

// SAFE -- Argon2id (preferred, PHP 7.3+)
$hash = password_hash($password, PASSWORD_ARGON2ID, [
    'memory_cost' => 65536, 'time_cost' => 4, 'threads' => 3,
]);

// Verification
if (password_verify($plaintext, $storedHash)) { /* success */ }

// Rehash on login to upgrade algorithm/cost transparently
if (password_needs_rehash($storedHash, PASSWORD_ARGON2ID)) {
    $user->updatePasswordHash(password_hash($plaintext, PASSWORD_ARGON2ID));
}
```

Never use MD5/SHA-1/SHA-256 for passwords. Use `password_hash()`
which includes a unique salt. Check `password_needs_rehash()` on
every login.

### Session Fixation Prevention

```php
// After login -- regenerate session ID
if (Auth::attempt($credentials)) {
    $request->session()->regenerate();
    return redirect()->intended('/dashboard');
}

// On logout -- invalidate entirely
Auth::logout();
$request->session()->invalidate();
$request->session()->regenerateToken();  // new CSRF token
```

Regenerate the session ID after every authentication state change.

### Rate Limiting

```php
RateLimiter::for('login', function (Request $request) {
    $key = Str::lower($request->input('email')) . '|' . $request->ip();
    return Limit::perMinute(5)->by($key);
});

Route::post('/login', [AuthController::class, 'login'])
    ->middleware('throttle:login');
```

Rate limit by IP and account to prevent both credential stuffing and
targeted brute force. Return HTTP 429 with `Retry-After` header.

---

## File Upload Safety

### Extension Allowlist

Never blocklist. Blocklists miss `pht`, `phtml`, `php5`, and double
extensions like `file.php.jpg` on misconfigured servers.

```php
$allowed = ['jpg', 'jpeg', 'png', 'gif', 'webp'];
$ext = strtolower($file->getClientOriginalExtension());
if (!in_array($ext, $allowed, true)) {
    abort(422, 'File type not allowed');
}
```

### MIME Type Validation

Client Content-Type headers are spoofable. Validate server-side.

```php
// UNSAFE -- trusting client header
$mime = $file->getClientMimeType();

// SAFE -- content inspection
$mime = (new \finfo(FILEINFO_MIME_TYPE))->file($file->getRealPath());
if (!in_array($mime, ['image/jpeg', 'image/png', 'image/webp'], true)) {
    abort(422, 'Invalid file type');
}
```

### Storage and Naming

Store outside web root -- a `.php` file in `/public/uploads/`
executes when requested. Use randomized filenames to prevent path
traversal and enumeration.

```php
// UNSAFE -- web root, original filename
$file->move(public_path('uploads'), $file->getClientOriginalName());

// SAFE -- private disk, random name
$filename = bin2hex(random_bytes(16)) . '.' . $ext;
$path = $file->storeAs('uploads', $filename, 'private');

// Serve through controller with access control
Route::get('/files/{path}', function (string $path) {
    abort_unless(auth()->user()->canAccess($path), 403);
    return response()->file(Storage::disk('private')->path($path));
})->where('path', '.*');
```

Use `random_bytes()` -- `uniqid()` is predictable. Store original
filename in the database for display, never in the filesystem.

---

## Deserialization

### Object Injection via unserialize

`unserialize()` reconstructs objects, triggering `__wakeup` and
`__destruct`. An attacker controlling the serialized string can
instantiate arbitrary classes and execute code via magic methods.

```php
// UNSAFE -- unserialize user-controlled data
$data = unserialize($_COOKIE['preferences']);
$data = unserialize(base64_decode($_POST['state']));
```

### JSON as Safe Alternative

JSON produces data-only output with no object reconstruction.
```php
// SAFE -- no object injection vector
$data = json_decode($input, true, 512, JSON_THROW_ON_ERROR);

// Storing structured data
$serialized = json_encode($preferences, JSON_THROW_ON_ERROR);
```

Use `JSON_THROW_ON_ERROR` (PHP 7.3+) instead of checking
`json_last_error()`. The depth limit prevents stack overflow from
deeply nested payloads.

### allowed_classes Parameter

When `unserialize()` is unavoidable, restrict instantiable classes.

```php
// Only specific classes allowed (PHP 7.0+)
$data = unserialize($cached, [
    'allowed_classes' => [UserPreferences::class, ThemeSettings::class],
]);

// Safest -- no objects, only scalars and arrays
$data = unserialize($cached, ['allowed_classes' => false]);
```

Disallowed objects become `__PHP_Incomplete_Class` with no magic
methods and no code execution vector.

### Signed Payloads

When serialized data traverses untrusted channels, sign with HMAC
to prevent tampering. Use `hash_equals()` for MAC comparison --
`===` is vulnerable to timing attacks.

```php
$mac = hash_hmac('sha256', $data, $key);
$signed = base64_encode($data) . '.' . $mac;

// Verification -- constant-time comparison
$expected = hash_hmac('sha256', $data, $key);
if (!hash_equals($expected, $mac)) { /* tampered */ }
```

Prefer framework encryption (`Crypt::encryptString()` in Laravel)
over manual HMAC when available.
