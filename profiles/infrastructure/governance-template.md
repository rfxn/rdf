# Infrastructure Governance Template

> Seed template for /r:init. Merged with codebase scan results during
> governance generation. Not copied verbatim -- scan data overrides
> where conflicts exist.

## Secrets

- Never hardcode secrets, API keys, account IDs, or credentials in IaC
  files -- use variables, data sources, or secret managers
- No AWS access keys, GCP service account keys, or Azure credentials
  in `.tf`, `.yaml`, or `.yml` files
- Use HashiCorp Vault, AWS Secrets Manager, GCP Secret Manager, or
  Azure Key Vault for runtime secrets
- `.env` files never committed -- add to `.gitignore` and use
  `.env.example` with placeholder values
- Rotate secrets on exposure -- assume any secret that touched version
  control is compromised, even if the commit was force-pushed away

## Terraform

- `for_each` over `count` for collections -- `count` uses fragile
  integer indices (removing item 2 of 5 renumbers items 3-5, triggering
  destroy/recreate); `for_each` uses stable keys
- Always include `moved` blocks during refactors -- prevents
  destroy/recreate of renamed or reorganized resources
- Plan before apply always -- `terraform plan -out=tfplan` then
  `terraform apply tfplan`; never `terraform apply` without reviewing
  the plan
- Never `terraform apply -auto-approve` in production -- human review
  gate required for production changes
- Use `lifecycle { prevent_destroy = true }` on stateful resources
  (databases, storage buckets, DNS zones)
- Tag all resources with `environment`, `team`, `managed-by` at minimum
- Workspaces or directory-based separation for environment isolation --
  never share state between production and staging
- `terraform fmt` is non-negotiable -- all `.tf` files must be formatted

## Kubernetes

- Always set `resources.requests` AND `resources.limits` on every
  container -- requests affect scheduling, limits prevent runaway usage
- `securityContext.runAsNonRoot: true` by default -- containers running
  as root can escape to the host via kernel exploits
- `readOnlyRootFilesystem: true` unless the application requires write
  access (use `emptyDir` volumes for temp data)
- No `latest` image tags -- use immutable digests (`image@sha256:...`)
  or semver-pinned tags; `latest` causes silent drift between deploys
- Liveness and readiness probes on every pod -- liveness for restart on
  deadlock, readiness for traffic routing
- `PodDisruptionBudget` for availability during node maintenance
- NetworkPolicy to restrict pod-to-pod communication -- deny-all default,
  allow specific ingress/egress
- Namespaces for isolation -- never deploy application workloads to
  `default` or `kube-system`
- `automountServiceAccountToken: false` unless the pod needs Kubernetes
  API access

## Ansible

- Purpose-built modules over `shell`/`command` -- modules are idempotent
  by design; `shell` re-executes every run unless guarded
- `no_log: true` on any task handling secrets, passwords, or tokens --
  prevents credentials from appearing in logs and stdout
- `creates:` / `removes:` guards when `shell` or `command` is
  unavoidable -- provides idempotency for imperative tasks
- Handlers for service restarts -- `notify: restart nginx` not
  inline `service: state=restarted` (handlers run once at end,
  preventing unnecessary restarts)
- Vault-encrypted variables for secrets (`ansible-vault encrypt_string`)
  -- never plaintext secrets in group_vars or host_vars
- `--check` mode (dry run) before every production apply -- verify
  changes without making them
- `--diff` flag to show file content changes for template/copy tasks
- Roles from Ansible Galaxy: pin versions, review source before use --
  roles execute arbitrary code on target hosts

## CI/CD

- OIDC for cloud authentication, not long-lived credentials --
  GitHub Actions OIDC, GitLab CI OIDC, CircleCI OIDC all support
  short-lived tokens for AWS/GCP/Azure
- Plan-only on pull request, apply-only on merge to main -- prevents
  accidental infrastructure changes from unreviewed branches
- Human approval gate for production changes -- automated staging,
  gated production
- Artifact signing for container images -- `cosign` or Notary v2;
  verify signatures before deployment
- Pipeline secrets via platform secret store (GitHub Secrets, GitLab
  CI Variables) -- never inline in pipeline config
- Separate CI service accounts per environment with least-privilege --
  staging CI cannot modify production resources

## State Management

- Remote backend with encryption for Terraform state -- S3 + DynamoDB
  (AWS), GCS (GCP), or Azure Blob Storage with server-side encryption
- State locking enabled -- prevents concurrent applies that corrupt state
- Never local state for shared infrastructure -- local `.tfstate` files
  cannot be shared, locked, or encrypted
- State files contain plaintext secrets (database passwords, API keys,
  TLS certificates) -- treat state storage with the same security as
  a secrets manager
- `terraform state` commands for manual state operations -- never edit
  `.tfstate` files directly
- State backup before destructive operations (`terraform state pull >
  backup.tfstate`)

## Validation

- Terraform: `terraform validate` (syntax) + `tflint` (best practices) +
  `checkov` or `tfsec` (security scanning) -- all three in CI
- Kubernetes: `kubeval` or `kubeconform` (schema validation) +
  `KubeLinter` or `kube-score` (best practices) -- validate before apply
- Ansible: `ansible-lint` (style and best practices) + `--check` mode
  (dry run) + `--syntax-check` (parse validation)
- Docker: `hadolint` for Dockerfile linting -- catches common mistakes
  (missing `--no-cache`, running as root, `COPY` vs `ADD`)
- YAML: `yamllint` for all YAML files -- catches indentation errors
  that cause silent misconfigurations
- Policy-as-code: Open Policy Agent (OPA) or Kyverno for organizational
  policy enforcement beyond tool-specific linters

## Versioning

- Pin provider versions in Terraform (`required_providers` block with
  version constraints) -- unversioned providers auto-upgrade and break
- Pin module versions (git tags or registry versions) -- `source =
  "hashicorp/consul/aws"` with `version = "~> 0.11"` not unversioned
- Document upgrade paths for major version bumps -- provider and module
  upgrades can require state migrations
- Use version constraints not floating references -- `"~> 4.0"` (any
  4.x) or `"= 4.2.1"` (exact), never `">= 0"` (anything goes)
- Helm chart versions pinned in `Chart.yaml` and `requirements.yaml`
- Container base image versions pinned -- `FROM python:3.12-slim` not
  `FROM python:latest`
- Changelog for infrastructure changes -- track what changed, when,
  and why, even for IaC
