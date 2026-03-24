# PHP Governance Template

> Seed template for /r-init. Merged with codebase scan results during
> governance generation. Not copied verbatim -- scan data overrides
> where conflicts exist.

## Strict Types

- `declare(strict_types=1);` as the first statement in every PHP file --
  prevents silent type coercion (string "1" accepted as int without it)
- Without strict types, `function add(int $a, int $b)` silently accepts
  `add("3", "4")` and returns 7 -- this masks type errors at boundaries
- PSR-12 coding style enforced via `php-cs-fixer` or `PHP_CodeSniffer`

## SQL Safety

- Parameterized queries always -- never string-concatenated SQL
- PDO prepared statements: `$stmt = $pdo->prepare('SELECT * FROM users WHERE id = ?')`
- Eloquent/Doctrine query builders use parameter binding internally --
  but `DB::raw()` and `whereRaw()` bypass it; parameterize manually
- Never `$pdo->query("SELECT * FROM users WHERE name = '$name'")` --
  SQL injection even with `addslashes()` (multibyte bypass)
- Set `PDO::ATTR_EMULATE_PREPARES` to `false` -- emulated prepares
  send the query as a single string, defeating the purpose

## Mass Assignment

- Explicit `$fillable` on all Eloquent models -- whitelist approach
- Never `$guarded = []` -- enables mass assignment attacks on sensitive
  fields (is_admin, role, pricing, email_verified)
- `$fillable` must not include: `id`, `is_admin`, `role`, `password`,
  `email_verified_at`, `api_token`, or any authorization field
- For non-Laravel ORMs: equivalent protection (Doctrine uses explicit
  setter methods; Symfony forms use `allow_extra_fields: false`)

## Query Performance

- Eager loading with `with()` to prevent N+1 queries --
  `User::with('posts', 'comments')->get()` not `User::all()` followed
  by `$user->posts` in a loop
- `Model::preventLazyLoading()` in development/staging -- throws
  exception on N+1, forces eager loading discipline
- `DB::enableQueryLog()` in development to audit query counts
- Index frequently filtered/sorted columns -- verify with `EXPLAIN`
- Pagination (`->paginate()`) not `->get()` for user-facing lists

## Template Safety

- `{{ $variable }}` (escaped output) not `{!! $variable !!}` (raw) --
  Blade escapes HTML entities by default
- Raw output `{!! !!}` only for pre-sanitized trusted HTML (e.g.,
  markdown rendered server-side through a sanitizer)
- Twig: `{{ variable }}` (auto-escaped) not `{{ variable|raw }}`
- Never `echo $userInput` without `htmlspecialchars($userInput, ENT_QUOTES, 'UTF-8')`
- Content Security Policy headers as defense-in-depth against XSS

## Type Declarations

- All function parameters, return types, and class properties typed
- Use union types (`string|int`) over mixed when possible
- Use PHP 8.1+ enums instead of string/integer constants --
  `enum Status: string { case Active = 'active'; }` not
  `const STATUS_ACTIVE = 'active';`
- Constructor promotion for DTOs: `public function __construct(
  public readonly string $name, public readonly int $age)`
- `readonly` on immutable properties (PHP 8.1+)
- Never `/** @var Type */` as substitute for actual type declaration --
  annotations are not enforced at runtime

## Dependencies

- `composer.lock` committed to version control -- ensures reproducible
  installs across environments
- `composer install --no-dev` in production -- dev dependencies include
  debug tools, test frameworks, profilers
- `composer audit` in CI pipeline -- checks for known vulnerabilities
  in installed packages
- Pin major versions in `composer.json` (`"^8.0"` not `"*"`) --
  prevent breaking changes from auto-updating
- Autoloading via PSR-4 -- never manual `require`/`include` chains
- `composer dump-autoload --optimize` for production deployments

## Testing

- PHPUnit (standard) or Pest (expressive syntax) for test framework
- `phpstan analyse --level=max` in CI -- catches type errors, dead code,
  impossible conditions statically
- `php-cs-fixer fix --dry-run --diff` in CI -- enforces coding standards
- Feature tests for HTTP endpoints; unit tests for domain logic
- Database tests use transactions with rollback (`RefreshDatabase` trait)
  or in-memory SQLite -- never a shared test database
- Factories for test data (`User::factory()->create()`) not raw SQL
  inserts -- factories respect model events and relationships

## Security

- CSRF tokens on all state-changing forms (`@csrf` in Blade) -- verify
  token on every POST/PUT/PATCH/DELETE
- File upload validation: extension allowlist, MIME type check, file
  size limit, store outside web root with randomized names
- XSS prevention: output escaping (see Template Safety), Content
  Security Policy headers, `HttpOnly` + `Secure` cookie flags
- Mass assignment protection via `$fillable` (see Mass Assignment)
- Authentication: use framework-provided auth (Laravel Sanctum/Fortify,
  Symfony Security) -- never roll custom password hashing
- Password hashing: `password_hash()` with `PASSWORD_ARGON2ID` or
  `PASSWORD_BCRYPT` -- never MD5/SHA1/SHA256 for passwords
- Rate limiting on authentication and API endpoints
- `APP_DEBUG=false` in production -- debug mode exposes env vars,
  SQL queries, stack traces to users
