# Node.js Backend Guide

> Deep reference for Node.js backend patterns. Covers framework
> conventions, middleware, error handling, streaming, graceful shutdown,
> and structured logging. Companion to the TypeScript governance
> template.

---

## Framework Conventions

### Express

Express is the most widely used Node.js framework. Unopinionated,
middleware-based, requires manual async error handling in v4.

```typescript
import express from "express";

const app = express();

// Built-in middleware
app.use(express.json({ limit: "1mb" }));
app.use(express.urlencoded({ extended: true }));

// Route handlers
app.get("/api/users", async (req, res, next) => {
    try {
        const users = await userService.list();
        res.json(users);
    } catch (e) {
        next(e); // forward to error handler
    }
});

// Error handler (must have 4 parameters)
app.use((err: Error, req: express.Request, res: express.Response,
         next: express.NextFunction) => {
    logger.error(err);
    res.status(500).json({ error: "Internal server error" });
});
```

Key conventions:
- Route handlers with async must wrap in try/catch and call `next(e)`
  (Express 4.x does not catch rejected promises)
- Or use `express-async-errors` package to patch this behavior
- Error middleware must have exactly 4 parameters (Express uses arity
  to distinguish error handlers from regular middleware)
- Use `express.json()` built-in instead of `body-parser` (Express 4.16+)

### Fastify

Fastify is a performance-focused framework with built-in validation,
serialization, and async error handling.

```typescript
import Fastify from "fastify";

const app = Fastify({
    logger: true, // built-in pino logging
});

// Schema-based validation (compiled at startup for performance)
app.post("/api/users", {
    schema: {
        body: {
            type: "object",
            required: ["name", "email"],
            properties: {
                name: { type: "string" },
                email: { type: "string", format: "email" },
            },
        },
    },
    handler: async (request, reply) => {
        const user = await userService.create(request.body);
        reply.status(201).send(user);
        // No try/catch needed -- Fastify handles async errors natively
    },
});
```

Key conventions:
- Async errors are caught automatically -- no try/catch boilerplate
- Schema validation at the route level (uses Ajv internally)
- `reply.send()` instead of `res.json()` -- returns a promise
- Plugins for encapsulation: `app.register(plugin, options)`
- Built-in pino logging via `logger: true`

### Nest.js

Nest.js is an opinionated framework with decorators, dependency
injection, and a module system inspired by Angular.

```typescript
import { Controller, Get, Post, Body, HttpException } from "@nestjs/common";

@Controller("users")
export class UserController {
    constructor(private readonly userService: UserService) {}

    @Get()
    async findAll(): Promise<User[]> {
        return this.userService.findAll();
    }

    @Post()
    async create(@Body() dto: CreateUserDto): Promise<User> {
        return this.userService.create(dto);
    }
}
```

Key conventions:
- Dependency injection via constructor parameters
- Decorators for routing (`@Controller`, `@Get`, `@Post`)
- DTOs with `class-validator` decorators for validation
- Exception filters for centralized error handling
- Modules group related controllers and providers

---

## Middleware Patterns

### Authentication Middleware

```typescript
import type { Request, Response, NextFunction } from "express";

interface AuthenticatedRequest extends Request {
    userId: string;
}

function requireAuth(req: Request, res: Response, next: NextFunction): void {
    const token = req.headers.authorization?.replace("Bearer ", "");

    if (!token) {
        res.status(401).json({ error: "Missing authorization header" });
        return;
    }

    try {
        const payload = verifyToken(token);
        (req as AuthenticatedRequest).userId = payload.sub;
        next();
    } catch {
        res.status(401).json({ error: "Invalid token" });
    }
}
```

### Request Validation Middleware

```typescript
import { z, ZodSchema } from "zod";

function validate(schema: ZodSchema) {
    return (req: Request, res: Response, next: NextFunction): void => {
        const result = schema.safeParse(req.body);
        if (!result.success) {
            res.status(400).json({
                error: "Validation failed",
                details: result.error.issues,
            });
            return;
        }
        req.body = result.data; // replace with parsed, validated data
        next();
    };
}

const CreateUserSchema = z.object({
    name: z.string().min(1).max(100),
    email: z.string().email(),
});

app.post("/api/users", validate(CreateUserSchema), createUserHandler);
```

### Middleware Ordering

```typescript
// Order matters -- apply in this sequence
app.use(requestId());          // 1. Assign request ID for tracing
app.use(requestLogger());      // 2. Log incoming request
app.use(rateLimiter());        // 3. Rate limit before processing
app.use(authenticate());       // 4. Authenticate (optional -- some routes public)
app.use(express.json());       // 5. Parse body
// ... route handlers ...
app.use(notFoundHandler);      // 6. 404 for unmatched routes
app.use(errorHandler);         // 7. Error handler last
```

---

## Error Handling

### Error Class Hierarchy

```typescript
export class AppError extends Error {
    constructor(
        message: string,
        public readonly statusCode: number = 500,
        public readonly code: string = "INTERNAL_ERROR",
        public readonly isOperational: boolean = true,
    ) {
        super(message);
        this.name = this.constructor.name;
    }
}

export class NotFoundError extends AppError {
    constructor(resource: string, id: string) {
        super(`${resource} ${id} not found`, 404, "NOT_FOUND");
    }
}

export class ValidationError extends AppError {
    constructor(
        message: string,
        public readonly fields: Record<string, string>,
    ) {
        super(message, 400, "VALIDATION_ERROR");
    }
}
```

### Centralized Error Handler

```typescript
function errorHandler(
    err: Error,
    req: Request,
    res: Response,
    _next: NextFunction,
): void {
    if (err instanceof AppError) {
        // Operational error -- expected, safe to return details
        logger.warn({ err, requestId: req.id }, err.message);
        res.status(err.statusCode).json({
            error: { code: err.code, message: err.message },
        });
        return;
    }

    // Programmer error -- unexpected, log fully, return generic message
    logger.error({ err, requestId: req.id }, "Unhandled error");
    res.status(500).json({
        error: { code: "INTERNAL_ERROR", message: "Internal server error" },
    });
}
```

### Async Error Propagation

```typescript
// Option 1: express-async-errors (patches Express automatically)
import "express-async-errors";

app.get("/api/users/:id", async (req, res) => {
    const user = await userService.findById(req.params.id);
    if (!user) throw new NotFoundError("User", req.params.id);
    res.json(user);
    // rejected promise is automatically forwarded to error handler
});

// Option 2: wrapper function
function asyncHandler(
    fn: (req: Request, res: Response, next: NextFunction) => Promise<void>,
) {
    return (req: Request, res: Response, next: NextFunction): void => {
        fn(req, res, next).catch(next);
    };
}

app.get("/api/users/:id", asyncHandler(async (req, res) => {
    const user = await userService.findById(req.params.id);
    if (!user) throw new NotFoundError("User", req.params.id);
    res.json(user);
}));
```

---

## Request Streaming and Backpressure

### Streaming Large Responses

```typescript
import { pipeline } from "node:stream/promises";

app.get("/api/export", async (req, res) => {
    const cursor = db.query("SELECT * FROM large_table").stream();

    res.setHeader("Content-Type", "application/jsonl");

    await pipeline(
        cursor,
        new Transform({
            objectMode: true,
            transform(row, _encoding, callback) {
                callback(null, JSON.stringify(row) + "\n");
            },
        }),
        res,
    );
    // pipeline handles backpressure and error propagation
});
```

### Streaming File Uploads

```typescript
import { createWriteStream } from "node:fs";
import { pipeline } from "node:stream/promises";

app.post("/api/upload", async (req, res) => {
    const dest = createWriteStream(`/uploads/${req.headers["x-filename"]}`);

    await pipeline(req, dest);
    // backpressure is automatic -- if disk is slow, TCP receive slows down

    res.status(201).json({ status: "uploaded" });
});
```

Key rules:
- Use `pipeline()` (not `.pipe()`) -- it handles error propagation
  and cleanup on both readable and writable streams
- Never buffer entire request/response bodies for large payloads --
  stream them
- Set `highWaterMark` to control chunk size and memory usage
- Check `Content-Length` before streaming to reject oversized payloads

---

## Graceful Shutdown

### Complete Shutdown Handler

```typescript
async function startServer(): Promise<void> {
    const app = createApp();
    const server = app.listen(config.port);
    const db = await connectDatabase();

    logger.info({ port: config.port }, "Server started");

    async function shutdown(signal: string): Promise<void> {
        logger.info({ signal }, "Shutdown signal received");

        // 1. Stop accepting new connections
        server.close();

        // 2. Wait for in-flight requests to complete (with timeout)
        const forceTimeout = setTimeout(() => {
            logger.error("Forced shutdown -- timeout exceeded");
            process.exit(1);
        }, 30_000);

        // 3. Close database connections
        await db.end();

        // 4. Clear timeout and exit cleanly
        clearTimeout(forceTimeout);
        logger.info("Graceful shutdown complete");
        process.exit(0);
    }

    process.on("SIGTERM", () => shutdown("SIGTERM"));
    process.on("SIGINT", () => shutdown("SIGINT"));
}
```

### Shutdown Ordering

1. Stop accepting new connections (`server.close()`)
2. Wait for in-flight requests to drain (with a timeout)
3. Close database connection pools
4. Close message queue connections
5. Flush log buffers
6. Exit with code 0

Never call `process.exit()` without closing connections first --
in-flight queries may corrupt data.

---

## Health Check Endpoints

### Liveness vs Readiness

```typescript
// Liveness: "Is the process alive?"
// Returns 200 as long as the event loop is responsive
app.get("/healthz", (_req, res) => {
    res.status(200).json({ status: "alive" });
});

// Readiness: "Can the service handle traffic?"
// Checks all dependencies
app.get("/readyz", async (_req, res) => {
    const checks: Record<string, string> = {};

    try {
        await db.query("SELECT 1");
        checks.database = "ok";
    } catch {
        checks.database = "failed";
    }

    try {
        await redis.ping();
        checks.cache = "ok";
    } catch {
        checks.cache = "failed";
    }

    const healthy = Object.values(checks).every((v) => v === "ok");
    res.status(healthy ? 200 : 503).json({ status: healthy ? "ready" : "degraded", checks });
});
```

---

## Structured Logging

### Pino Setup

```typescript
import pino from "pino";

const logger = pino({
    level: process.env.LOG_LEVEL ?? "info",
    formatters: {
        level(label) {
            return { level: label }; // "info" not 30
        },
    },
    serializers: {
        err: pino.stdSerializers.err, // stack traces in error logs
    },
});

// Usage
logger.info({ userId: 42, action: "login" }, "User logged in");
logger.error({ err, requestId }, "Request failed");
```

### Log Conventions

- First argument: structured data object (searchable fields)
- Second argument: human-readable message
- Never log sensitive data (passwords, tokens, PII)
- Include request IDs for distributed tracing
- Use `logger.child({ requestId })` for per-request logger instances
- Never use `console.log` in production code -- it writes unstructured
  text with no levels, timestamps, or correlation IDs
