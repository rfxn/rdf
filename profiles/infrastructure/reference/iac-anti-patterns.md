# IaC Anti-Patterns Reference

> Deep reference for common Infrastructure-as-Code anti-patterns. Each
> section shows the broken pattern, explains why it fails, and provides
> the correct alternative across Terraform, Kubernetes, Ansible, Docker,
> and CI/CD. Companion to the Infrastructure governance template.

---

## Verification Preamble

Before reporting any pattern from this document as a finding:
1. Verify the pattern exists in project code (not just dependencies)
2. Check whether framework or library protections already mitigate it
3. Confirm the code path is reachable from an entry point
4. Read the "When this is safe" annotation if present

A pattern match is a candidate. A verified pattern match is a finding.

---

## Terraform

### count vs for_each for Collections

`count` uses integer indices. Removing an item from the middle
renumbers subsequent resources, triggering destroy/recreate.

Bad:
```hcl
resource "aws_s3_bucket" "buckets" {
  count  = length(var.bucket_names)
  bucket = var.bucket_names[count.index]
}
```

Good:
```hcl
resource "aws_s3_bucket" "buckets" {
  for_each = toset(var.bucket_names)
  bucket   = each.value
}
```

`for_each` uses stable string keys -- removing one item only affects
that resource. `count` renumbers everything after the removed index.

When this is safe: `count` for numeric replication with no distinct
identity, such as `count = 3` for identical replicas.

### Unversioned Providers

Without version constraints, `terraform init` downloads the latest
provider. A major version bump can silently break plans.

Bad:
```hcl
terraform {
  required_providers {
    aws = { source = "hashicorp/aws" }
  }
}
```

Good:
```hcl
terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}
```

`~>` allows 5.x upgrades while blocking 6.x breaking changes.

### Missing moved Blocks

Renaming a resource without `moved` causes destroy + create -- data
loss for stateful resources.

Bad:
```hcl
# Renamed from aws_db_instance.main without moved block
resource "aws_db_instance" "primary" { }
# Plan: destroy main + create primary = database recreated
```

Good:
```hcl
moved {
  from = aws_db_instance.main
  to   = aws_db_instance.primary
}
resource "aws_db_instance" "primary" { }
# Plan: state updated, no infrastructure changes
```

After one successful apply, the `moved` block can be removed.

### terraform apply Without Plan File

Running `terraform apply` without a saved plan re-computes changes.
Drift between review and apply introduces unreviewed modifications.

Bad:
```hcl
# terraform plan          (reviewed)
# terraform apply         (re-computes -- may differ)
```

Good:
```hcl
# terraform plan -out=tfplan && terraform apply tfplan
```

A saved plan locks the exact changes. No re-computation, no races.

When this is safe: Development-only environments with no shared state.

### Auto-Approve in Production

`-auto-approve` bypasses confirmation, removing the last human gate.

Bad:
```hcl
# terraform apply -auto-approve  # in production CI
```

Good:
```hcl
# terraform plan -out=tfplan
# (human reviews plan in PR comment or approval gate)
# terraform apply tfplan
```

When this is safe: Never for production. Acceptable for ephemeral
development environments where the blast radius is zero.

---

## Kubernetes

### latest Image Tags

`latest` is mutable -- two nodes pulling at different times may run
different versions, causing silent drift.

Bad:
```yaml
containers:
  - name: myapp
    image: myapp:latest
```

Good:
```yaml
containers:
  - name: myapp
    image: myapp@sha256:a1b2c3d4e5f6...
```

Digest-pinned images are immutable. Semver tags are acceptable when
the registry enforces tag immutability.

When this is safe: Local development with `imagePullPolicy: Always`.

### Missing Resource Limits

Containers without limits consume unbounded CPU and memory. A single
runaway pod starves all other workloads on the node.

Bad:
```yaml
containers:
  - name: worker
    image: worker:1.2.0
    # No resources block
```

Good:
```yaml
containers:
  - name: worker
    image: worker:1.2.0
    resources:
      requests: { cpu: "250m", memory: "256Mi" }
      limits:   { cpu: "1000m", memory: "512Mi" }
```

Requests affect scheduling. Limits enforce at runtime (CPU throttled,
memory OOM-killed).

### Privileged Containers

`privileged: true` grants full host kernel access. A container escape
becomes a full node compromise.

Bad:
```yaml
securityContext:
  runAsUser: 0
  privileged: true
```

Good:
```yaml
securityContext:
  runAsNonRoot: true
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  capabilities:
    drop: ["ALL"]
```

`runAsNonRoot` + `readOnlyRootFilesystem` + dropped capabilities is
the minimum viable security posture.

When this is safe: System-level DaemonSets that genuinely require host
access (CNI plugins, storage drivers) -- document the justification.

### Default Namespace

The `default` namespace has no resource quotas, no network policies,
and no isolation from other tenants.

Bad:
```yaml
metadata:
  name: payment-service
  # namespace omitted -- deploys to default
```

Good:
```yaml
metadata:
  name: payment-service
  namespace: payments
```

Dedicated namespaces enable resource quotas, network policies, and
RBAC scoping. Never deploy application workloads to `default` or
`kube-system`.

When this is safe: Single-use ephemeral clusters like CI runners.

---

## Ansible

### Inline Shell Over Modules

`shell` tasks re-execute every run unless guarded. Modules are
idempotent by design.

Bad:
```yaml
- name: Install nginx
  shell: apt-get install -y nginx
```

Good:
```yaml
- name: Install nginx
  apt:
    name: nginx
    state: present
```

Modules check current state and report `changed: false` accurately.
`shell` always reports `changed: true` unless guarded.

When this is safe: When no module exists. Guard with `creates:` or
`removes:` for idempotency.

### Missing no_log on Secrets

Ansible prints task parameters to stdout. Tasks handling passwords
expose them in logs and CI output.

Bad:
```yaml
- name: Set database password
  mysql_user:
    name: appuser
    password: "{{ db_password }}"
```

Good:
```yaml
- name: Set database password
  mysql_user:
    name: appuser
    password: "{{ db_password }}"
  no_log: true
```

Apply `no_log: true` to every task handling sensitive data.

### Missing Handlers

Inline service restarts execute every run, even when nothing changed.
Handlers run once at play end, only when notified.

Bad:
```yaml
- name: Update nginx config
  template:
    src: nginx.conf.j2
    dest: /etc/nginx/nginx.conf
- name: Restart nginx
  service:
    name: nginx
    state: restarted
```

Good:
```yaml
- name: Update nginx config
  template:
    src: nginx.conf.j2
    dest: /etc/nginx/nginx.conf
  notify: restart nginx

handlers:
  - name: restart nginx
    service:
      name: nginx
      state: restarted
```

The handler only runs when the template task reports `changed: true`.
This prevents unnecessary service disruptions.

When this is safe: One-shot scripts that will never be re-run.

---

## Docker

### Running as Root

Containers run as root by default. An exploited vulnerability gives
root access inside the container and potentially on the host.

Bad:
```dockerfile
FROM python:3.12-slim
COPY . /app/
CMD ["python", "app.py"]
# Runs as root -- PID 1 is root
```

Good:
```dockerfile
FROM python:3.12-slim
RUN groupadd -r app && useradd -r -g app app
COPY --chown=app:app . /app/
USER app:app
CMD ["python", "app.py"]
```

Switch to non-root with `USER` before `CMD`. Install packages before
the `USER` directive since package managers require root.

When this is safe: Build stages run as root -- the final stage must
switch to a non-root user.

### ADD vs COPY

`ADD` auto-extracts tar archives and fetches URLs. This makes builds
non-deterministic and obscures what enters the image.

Bad:
```dockerfile
ADD app.tar.gz /app/
ADD https://example.com/config.json /app/config.json
```

Good:
```dockerfile
COPY app.tar.gz /app/
RUN tar -xzf /app/app.tar.gz -C /app/ && rm /app/app.tar.gz
```

`COPY` is explicit -- it copies files, nothing else. For archives,
copy then extract in a separate `RUN` step.

When this is safe: `ADD` for local tar auto-extraction when the
behavior is explicitly intended.

### Missing .dockerignore

Without `.dockerignore`, `COPY . /app/` sends the entire build context
including `.git`, `node_modules`, `.env` files, and test fixtures.

Bad:
```dockerfile
# No .dockerignore file
COPY . /app/
```

Good:
```dockerfile
# .dockerignore contains: .git, .env, node_modules, __pycache__, tests/
COPY . /app/
```

A `.dockerignore` reduces build context size, prevents secrets from
entering images, and avoids cache invalidation from irrelevant changes.

---

## CI/CD

### Long-Lived Credentials

Static access keys in CI secrets never expire. A leaked key grants
indefinite access.

Bad:
```yaml
env:
  AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
  AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
```

Good:
```yaml
permissions:
  id-token: write
steps:
  - uses: aws-actions/configure-aws-credentials@v4
    with:
      role-to-assume: arn:aws:iam::123456789012:role/deploy
```

OIDC issues short-lived tokens scoped to a single workflow run.

When this is safe: Environments without OIDC -- rotate credentials on
schedule and scope to minimum permissions.

### Apply on PR Branch

Applying on unreviewed PR branches deploys unreviewed changes.

Bad:
```yaml
on: { pull_request: {} }
jobs:
  terraform:
    steps:
      - run: terraform apply -auto-approve
```

Good:
```yaml
on: { pull_request: {} }
jobs:
  plan:
    steps:
      - run: terraform plan -out=tfplan | tee plan.txt
      # Post plan as PR comment; apply only on merge to main
```

Plan-only on PRs. Apply only on merge to main after approval.

### Shared CI Service Accounts

Same credentials for staging and production means a compromised staging
pipeline can modify production infrastructure.

Bad:
```yaml
deploy-staging:
  env:
    AWS_ROLE: arn:aws:iam::123456789012:role/deploy-all
deploy-production:
  env:
    AWS_ROLE: arn:aws:iam::123456789012:role/deploy-all
```

Good:
```yaml
deploy-staging:
  environment: staging
  steps:
    - uses: aws-actions/configure-aws-credentials@v4
      with:
        role-to-assume: arn:aws:iam::123456789012:role/deploy-staging
deploy-production:
  environment: production
  steps:
    - uses: aws-actions/configure-aws-credentials@v4
      with:
        role-to-assume: arn:aws:iam::111111111111:role/deploy-prod
```

Separate least-privilege accounts per environment. Use separate cloud
accounts for hard isolation between environments.
