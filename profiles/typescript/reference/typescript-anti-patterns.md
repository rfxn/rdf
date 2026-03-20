# TypeScript Anti-Patterns Reference

> Deep reference for common TypeScript anti-patterns, with focus on
> mistakes that AI code generators make frequently. Each section shows
> the broken pattern, explains why it fails, and provides the correct
> alternative. Companion to the TypeScript governance template.

---

## Floating Promises

### Async Call Without await

Calling an async function without `await` returns a Promise that
executes in the background. Errors are silently swallowed and
execution order becomes unpredictable.

Bad:
```typescript
async function saveUser(user: User): Promise<void> {
    await db.insert(user);
}

app.post("/users", async (req, res) => {
    const user = parseUser(req.body);
    saveUser(user); // floating promise -- error silently lost
    res.status(201).send({ id: user.id });
});
```

The response is sent before `saveUser` completes. If the insert fails,
no error is reported -- the client receives 201 but the data is lost.

Good:
```typescript
app.post("/users", async (req, res) => {
    const user = parseUser(req.body);
    await saveUser(user); // awaited -- errors propagate
    res.status(201).send({ id: user.id });
});
```

### Floating Promise in forEach

`Array.forEach` does not await async callbacks. The loop completes
immediately and all promises run concurrently with no error handling.

Bad:
```typescript
async function processItems(items: Item[]): Promise<void> {
    items.forEach(async (item) => {
        await processItem(item); // each iteration is a floating promise
    });
    // returns here immediately -- none of the items are processed yet
}
```

Good:
```typescript
async function processItems(items: Item[]): Promise<void> {
    // Sequential processing
    for (const item of items) {
        await processItem(item);
    }

    // Or concurrent processing with error collection
    await Promise.all(items.map((item) => processItem(item)));
}
```

Use `for...of` for sequential processing or `Promise.all` with `.map`
for concurrent processing. Never use `forEach` with async callbacks.

### Missing Return in Promise Chain

Forgetting to return a promise inside `.then()` creates a floating
promise that the chain does not wait for.

Bad:
```typescript
function deploy(): Promise<void> {
    return build()
        .then(() => {
            upload(); // missing return -- floating promise
        })
        .then(() => {
            console.log("Done"); // runs before upload finishes
        });
}
```

Good:
```typescript
function deploy(): Promise<void> {
    return build()
        .then(() => {
            return upload(); // returned -- chain waits for upload
        })
        .then(() => {
            console.log("Done"); // runs after upload completes
        });
}
```

Better: use async/await instead of `.then()` chains entirely.

---

## any Type Abuse

### Using any to Suppress Errors

`any` disables all type checking. It spreads silently -- a single
`any` infects every expression it touches.

Bad:
```typescript
function parseConfig(raw: any): Config {
    return {
        host: raw.host,           // no validation
        port: raw.port,           // no type check
        features: raw.feautres,   // typo compiles successfully
    };
}
```

The typo `raw.feautres` compiles because `any` allows any property
access. This bug is invisible until runtime.

Good:
```typescript
function parseConfig(raw: unknown): Config {
    if (typeof raw !== "object" || raw === null) {
        throw new ConfigError("Expected object");
    }
    const obj = raw as Record<string, unknown>;

    const host = typeof obj.host === "string" ? obj.host : "localhost";
    const port = typeof obj.port === "number" ? obj.port : 3000;

    return { host, port, features: [] };
}
```

Use `unknown` and narrow with type guards. Better: use Zod for
runtime validation.

### any in Generic Constraints

Using `any` as a generic constraint defeats the purpose of generics.

Bad:
```typescript
function merge<T extends any>(a: T, b: T): T {
    return { ...a, ...b };
}
```

Good:
```typescript
function merge<T extends Record<string, unknown>>(a: T, b: Partial<T>): T {
    return { ...a, ...b };
}
```

Constrain generics to the minimum type that describes the actual
requirements.

---

## Hallucinated npm Packages

### Packages That Don't Exist

AI code generators frequently suggest npm packages that look plausible
but do not exist on the npm registry.

Common hallucinations:
```typescript
// These packages do not exist
import { validate } from "express-validator-middleware";
import { rateLimit } from "express-rate-limiter";
import { createLogger } from "node-structured-logger";
import { parseCSV } from "csv-parser-async";
```

Actual packages:
```typescript
import { body, validationResult } from "express-validator";
import rateLimit from "express-rate-limit";
import pino from "pino";
import { parse } from "csv-parse";
```

**Verification process:** Before adding any dependency, verify it
exists on npmjs.com. Check download counts, last publish date, and
maintainer. If a package has zero downloads or was published in the
last week, it may be a typosquat.

### Wrong Package for the Framework Version

AI models trained on older code suggest packages that have been
superseded or are incompatible with the current framework version.

Bad:
```typescript
// Express 4.x -- does not work with Express 5.x
import bodyParser from "body-parser";
app.use(bodyParser.json());
```

Good:
```typescript
// Express 4.18+ has built-in JSON parsing
app.use(express.json());
```

Check the current version of your framework and verify that imported
packages are compatible with it.

---

## Wrong Framework Version Patterns

### Mixing API Versions

Generating code for v2 of a framework when v3 is installed causes
runtime errors that TypeScript cannot catch at compile time.

Bad (Next.js 12 pattern in a Next.js 14 project):
```typescript
// pages/api/users.ts -- Pages Router API route
import type { NextApiRequest, NextApiResponse } from "next";

export default function handler(req: NextApiRequest, res: NextApiResponse) {
    res.status(200).json({ users: [] });
}
```

Good (Next.js 14 App Router):
```typescript
// app/api/users/route.ts -- App Router route handler
import { NextResponse } from "next/server";

export async function GET() {
    return NextResponse.json({ users: [] });
}
```

### Deprecated API Usage

Bad (React class components in a hooks-era project):
```typescript
class UserProfile extends React.Component<Props, State> {
    componentDidMount() {
        this.fetchUser();
    }
    // ...
}
```

Good:
```typescript
function UserProfile({ userId }: Props) {
    const [user, setUser] = useState<User | null>(null);

    useEffect(() => {
        fetchUser(userId).then(setUser);
    }, [userId]);

    // ...
}
```

---

## export default

### Breaking Tree-Shaking

Default exports give the imported binding an arbitrary name, making
it harder to search for usages and breaking consistent imports across
the codebase.

Bad:
```typescript
// utils.ts
export default function formatDate(date: Date): string {
    return date.toISOString();
}

// consumer1.ts
import formatDate from "./utils";

// consumer2.ts
import dateFormatter from "./utils"; // different name, same function
```

Good:
```typescript
// utils.ts
export function formatDate(date: Date): string {
    return date.toISOString();
}

// consumer1.ts
import { formatDate } from "./utils";

// consumer2.ts
import { formatDate } from "./utils"; // same name everywhere
```

Named exports enforce consistent naming, enable IDE "find all
references", and allow tree-shaking of unused exports from barrel files.

---

## Bare String Throws

### Throwing Strings Instead of Error Instances

Throwing a string loses the stack trace. The `catch` block receives
a value with no `.stack`, `.message`, or `.name` properties.

Bad:
```typescript
function validateAge(age: number): void {
    if (age < 0) {
        throw "Age cannot be negative"; // no stack trace
    }
}

try {
    validateAge(-1);
} catch (e) {
    console.error(e.stack); // undefined -- e is a string
}
```

Good:
```typescript
class ValidationError extends Error {
    constructor(
        public readonly field: string,
        message: string,
    ) {
        super(message);
        this.name = "ValidationError";
    }
}

function validateAge(age: number): void {
    if (age < 0) {
        throw new ValidationError("age", "Age cannot be negative");
    }
}

try {
    validateAge(-1);
} catch (e) {
    if (e instanceof ValidationError) {
        console.error(`${e.field}: ${e.message}`);
        console.error(e.stack); // full stack trace available
    }
}
```

Always throw `Error` instances or subclasses. Use `instanceof` for
type-safe error handling in catch blocks.

---

## process.exit() in Library Code

### Forcing Process Termination from Libraries

`process.exit()` in library code prevents the application from running
cleanup handlers, closing connections, or logging the error.

Bad:
```typescript
// lib/database.ts
export function connect(url: string): Connection {
    try {
        return new Connection(url);
    } catch (e) {
        console.error("Failed to connect to database");
        process.exit(1); // kills the entire process
    }
}
```

Good:
```typescript
// lib/database.ts
export function connect(url: string): Connection {
    // Throws on failure -- let the application decide what to do
    return new Connection(url);
}

// app.ts
async function main(): Promise<void> {
    try {
        const db = connect(config.databaseUrl);
        await startServer(db);
    } catch (e) {
        logger.fatal(e, "Startup failed");
        await cleanup();
        process.exit(1); // only in the application entry point
    }
}
```

Libraries throw errors. Applications catch them, run cleanup, and
decide whether to exit. `process.exit()` belongs only in `main()`.

---

## Missing Type Narrowing

### Trusting as Casts

`as` assertions tell TypeScript "trust me, this is type X" without
any runtime verification. If the assertion is wrong, the error appears
at runtime, not compile time.

Bad:
```typescript
interface User {
    id: number;
    name: string;
    email: string;
}

function getUser(data: unknown): User {
    return data as User; // no validation -- could be anything at runtime
}

const user = getUser(JSON.parse(untrustedInput));
console.log(user.email.toLowerCase()); // runtime crash if email is missing
```

Good:
```typescript
import { z } from "zod";

const UserSchema = z.object({
    id: z.number(),
    name: z.string(),
    email: z.string().email(),
});

type User = z.infer<typeof UserSchema>;

function getUser(data: unknown): User {
    return UserSchema.parse(data); // throws ZodError if invalid
}
```

Use runtime validation (Zod, Joi, io-ts) at trust boundaries. Use
type guards (`if ("email" in data)`) for lightweight narrowing.
Reserve `as` for cases where you have external proof that the type
is correct (e.g., DOM element types after `querySelector`).

### Ignoring null/undefined

TypeScript's strict mode makes `null` and `undefined` explicit, but
non-null assertions (`!`) bypass the check.

Bad:
```typescript
function getFirstItem<T>(items: T[]): T {
    return items[0]!; // non-null assertion -- crashes on empty array
}
```

Good:
```typescript
function getFirstItem<T>(items: T[]): T | undefined {
    return items[0]; // with noUncheckedIndexedAccess, this is T | undefined
}

// or throw explicitly
function getFirstItemOrThrow<T>(items: T[]): T {
    if (items.length === 0) {
        throw new Error("Expected non-empty array");
    }
    return items[0]!; // assertion is safe -- we checked length
}
```

Non-null assertions (`!`) are acceptable only after an explicit guard
that proves the value is not null/undefined.
