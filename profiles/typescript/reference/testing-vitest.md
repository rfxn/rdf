# Vitest Testing Reference

> Deep reference for TypeScript testing with Vitest. Covers setup,
> test conventions, HTTP endpoint testing with Supertest, mocking
> strategies, coverage configuration, and CI pipeline setup.
> Companion to the TypeScript governance template.

---

## Vitest Setup and Configuration

### Installation

```bash
pnpm add -D vitest @vitest/coverage-v8
```

### Configuration

```typescript
// vitest.config.ts
import { defineConfig } from "vitest/config";

export default defineConfig({
    test: {
        globals: true,           // describe, it, expect without imports
        environment: "node",     // or "jsdom" for browser-like environment
        include: ["src/**/*.test.ts", "tests/**/*.test.ts"],
        exclude: ["node_modules", "dist"],
        coverage: {
            provider: "v8",
            reporter: ["text", "lcov"],
            include: ["src/**/*.ts"],
            exclude: ["src/**/*.test.ts", "src/**/*.d.ts"],
            thresholds: {
                statements: 80,
                branches: 75,
                functions: 80,
                lines: 80,
            },
        },
        testTimeout: 10_000,     // 10s default timeout
        hookTimeout: 15_000,     // 15s for setup/teardown
    },
});
```

### TypeScript Integration

```json
// tsconfig.json
{
    "compilerOptions": {
        "types": ["vitest/globals"]
    }
}
```

With `globals: true`, test functions (`describe`, `it`, `expect`,
`vi`) are available without imports. This matches Jest conventions
and reduces boilerplate.

---

## describe/it Block Conventions

### Test Structure

```typescript
describe("UserService", () => {
    let service: UserService;
    let mockRepo: MockUserRepository;

    beforeEach(() => {
        mockRepo = new MockUserRepository();
        service = new UserService(mockRepo);
    });

    describe("findById", () => {
        it("returns the user when found", async () => {
            mockRepo.addUser({ id: "1", name: "Alice" });

            const user = await service.findById("1");

            expect(user).toEqual({ id: "1", name: "Alice" });
        });

        it("throws NotFoundError when user does not exist", async () => {
            await expect(service.findById("999"))
                .rejects.toThrow(NotFoundError);
        });

        it("throws on empty id", async () => {
            await expect(service.findById(""))
                .rejects.toThrow("id must not be empty");
        });
    });

    describe("create", () => {
        it("saves the user and returns it with an id", async () => {
            const user = await service.create({ name: "Bob", email: "bob@test.com" });

            expect(user.id).toBeDefined();
            expect(user.name).toBe("Bob");
            expect(mockRepo.savedUsers).toHaveLength(1);
        });
    });
});
```

### Naming Conventions

- `describe` blocks name the unit under test (class, function, module)
- Nested `describe` blocks name the method or scenario
- `it` blocks describe the expected behavior in plain English
- Start `it` descriptions with a verb: "returns", "throws", "creates",
  "rejects", "emits"
- Do not prefix with "should" -- it adds noise without clarity
  ("returns the user" is clearer than "should return the user")

### Assertion Patterns

```typescript
// Equality
expect(result).toBe(42);              // strict equality (===)
expect(result).toEqual({ a: 1 });     // deep equality
expect(result).toStrictEqual(obj);    // deep equality + prototype check

// Truthiness
expect(value).toBeTruthy();
expect(value).toBeFalsy();
expect(value).toBeNull();
expect(value).toBeUndefined();
expect(value).toBeDefined();

// Numbers
expect(value).toBeGreaterThan(3);
expect(value).toBeCloseTo(0.3, 5);    // floating point

// Strings
expect(str).toMatch(/pattern/);
expect(str).toContain("substring");

// Arrays
expect(arr).toContain("item");
expect(arr).toHaveLength(3);
expect(arr).toEqual(expect.arrayContaining(["a", "b"]));

// Errors
expect(() => riskyCall()).toThrow(TypeError);
await expect(asyncCall()).rejects.toThrow("message");

// Snapshots
expect(output).toMatchSnapshot();
expect(output).toMatchInlineSnapshot(`"expected"`);
```

---

## Supertest for HTTP Endpoint Testing

### Setup

```bash
pnpm add -D supertest @types/supertest
```

### Testing Express Endpoints

```typescript
import request from "supertest";
import { createApp } from "../src/app";

describe("POST /api/users", () => {
    const app = createApp();

    it("creates a user and returns 201", async () => {
        const response = await request(app)
            .post("/api/users")
            .send({ name: "Alice", email: "alice@test.com" })
            .expect(201);

        expect(response.body).toMatchObject({
            id: expect.any(String),
            name: "Alice",
            email: "alice@test.com",
        });
    });

    it("returns 400 for missing required fields", async () => {
        const response = await request(app)
            .post("/api/users")
            .send({ name: "Alice" }) // missing email
            .expect(400);

        expect(response.body.error.code).toBe("VALIDATION_ERROR");
    });

    it("returns 401 for unauthenticated requests", async () => {
        await request(app)
            .get("/api/users/me")
            .expect(401);
    });

    it("returns 200 with valid auth token", async () => {
        const token = generateTestToken({ userId: "1" });

        const response = await request(app)
            .get("/api/users/me")
            .set("Authorization", `Bearer ${token}`)
            .expect(200);

        expect(response.body.id).toBe("1");
    });
});
```

### Testing with Database

```typescript
describe("User API (integration)", () => {
    let app: Express;
    let db: Database;

    beforeAll(async () => {
        db = await createTestDatabase();
        app = createApp({ db });
    });

    afterAll(async () => {
        await db.close();
    });

    beforeEach(async () => {
        await db.query("DELETE FROM users");
    });

    it("persists user to database", async () => {
        await request(app)
            .post("/api/users")
            .send({ name: "Alice", email: "alice@test.com" })
            .expect(201);

        const rows = await db.query("SELECT * FROM users WHERE email = $1",
            ["alice@test.com"]);
        expect(rows).toHaveLength(1);
        expect(rows[0].name).toBe("Alice");
    });
});
```

---

## Mock Boundaries

### Mock at the Edge, Not Internals

Mock external dependencies (database, HTTP clients, file system,
message queues). Do not mock internal business logic.

```
Good:
  [Handler] -> [Service] -> [Repository (mocked)]
                                    ^
                                    mock the I/O boundary

Bad:
  [Handler] -> [Service (mocked)] -> [Repository]
                    ^
                    mocking business logic hides bugs
```

### Vitest Mocking

```typescript
import { vi } from "vitest";

// Mock a module
vi.mock("../src/database", () => ({
    query: vi.fn(),
}));

// Import the mocked module
import { query } from "../src/database";

it("returns cached result on second call", async () => {
    vi.mocked(query).mockResolvedValueOnce([{ id: 1, name: "Alice" }]);

    const result1 = await service.getUser(1);
    const result2 = await service.getUser(1); // should hit cache

    expect(query).toHaveBeenCalledTimes(1); // only one DB call
    expect(result1).toEqual(result2);
});
```

### Spy vs Mock vs Stub

```typescript
// Spy: observe calls without changing behavior
const spy = vi.spyOn(logger, "info");
service.doWork();
expect(spy).toHaveBeenCalledWith("Work completed");

// Mock: replace implementation entirely
vi.mocked(fetch).mockResolvedValue(new Response('{"ok": true}'));

// Stub: replace with specific return value
vi.mocked(config.get).mockReturnValue("test-value");
```

### Timer Mocking

```typescript
it("retries after delay", async () => {
    vi.useFakeTimers();

    const fetchMock = vi.mocked(fetch)
        .mockRejectedValueOnce(new Error("timeout"))
        .mockResolvedValueOnce(new Response("ok"));

    const promise = fetchWithRetry("/api/data");

    await vi.advanceTimersByTimeAsync(1000); // advance past retry delay

    const result = await promise;
    expect(result).toBe("ok");
    expect(fetchMock).toHaveBeenCalledTimes(2);

    vi.useRealTimers();
});
```

### Cleanup

Always restore mocks between tests to prevent test pollution.

```typescript
afterEach(() => {
    vi.restoreAllMocks();  // restore spied/mocked functions
    vi.clearAllMocks();    // clear call history and implementations
});
```

---

## Coverage Configuration

### Coverage Thresholds

```typescript
// vitest.config.ts
coverage: {
    thresholds: {
        statements: 80,
        branches: 75,
        functions: 80,
        lines: 80,
    },
}
```

### Running Coverage

```bash
# Generate coverage report
pnpm vitest run --coverage

# Watch mode with coverage (development)
pnpm vitest --coverage
```

### Coverage Guidelines

- Do not chase 100% coverage -- it incentivizes testing implementation
  details rather than behavior
- Focus coverage on business logic and error handling paths
- Exclude generated code, type definitions, and configuration files
- Coverage thresholds prevent regression -- they should only go up
- `/* v8 ignore next */` for lines that cannot be reached in tests
  (defensive code, platform-specific branches)

---

## CI Pipeline

### Complete CI Configuration

```yaml
# .github/workflows/ci.yml
name: CI
on: [push, pull_request]

jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: pnpm/action-setup@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 22
          cache: pnpm

      - name: Install dependencies
        run: pnpm install --frozen-lockfile

      - name: Type check
        run: pnpm tsc --noEmit

      - name: Lint
        run: pnpm eslint .

      - name: Test
        run: pnpm vitest run --coverage

      - name: Security audit
        run: pnpm audit --audit-level=high
```

### Pipeline Order

1. `tsc --noEmit` -- type checking catches type errors before running
   tests (faster feedback than waiting for runtime failures)
2. `eslint .` -- lint rules catch style issues and common mistakes
3. `vitest run --coverage` -- full test suite with coverage
4. `pnpm audit` -- check for known vulnerabilities

### Running Tests Locally

```bash
# Run all tests once
pnpm vitest run

# Watch mode (re-runs on file change)
pnpm vitest

# Run specific test file
pnpm vitest run src/services/user.test.ts

# Run tests matching a pattern
pnpm vitest run --reporter=verbose -t "UserService"

# Run with coverage
pnpm vitest run --coverage

# Update snapshots
pnpm vitest run --update
```
