# IaC Testing Reference

> Deep reference for Infrastructure-as-Code testing and validation
> patterns. Covers the validation pipeline, plan-based testing,
> policy-as-code, and CI integration. Companion to the Infrastructure
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

## Validation Pipeline

Validation runs in tiers, ordered from fastest to slowest. A failure
at any tier halts the pipeline -- there is no value in running security
scans on syntactically invalid code.

### Tier 1: Syntax and Formatting

These checks run in milliseconds and catch typos, parse errors, and
style drift before deeper analysis.

```bash
# Terraform
terraform fmt -check -recursive
terraform validate

# Kubernetes
yamllint -d relaxed k8s/
kubeconform -strict -kubernetes-version 1.29.0 k8s/

# Ansible
ansible-lint playbooks/
ansible-playbook --syntax-check playbooks/site.yml

# Docker
hadolint Dockerfile
```

`terraform fmt -check` exits non-zero if any file needs formatting.
`terraform validate` checks syntax and internal consistency but does
not contact provider APIs. `kubeconform -strict` rejects unknown
fields, catching typos that would otherwise be silently ignored.

### Tier 2: Best Practices and Linting

Static analysis catches patterns that are syntactically valid but
operationally dangerous.

```bash
tflint --recursive        # Terraform
kube-linter lint k8s/     # Kubernetes
hadolint --strict Dockerfile  # Docker
```

Configure `tflint` rules in `.tflint.hcl`:

```hcl
plugin "aws" {
  enabled = true
  version = "0.30.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

rule "terraform_naming_convention" {
  enabled = true
  format  = "snake_case"
}
```

### Tier 3: Security Scanning

Security scanners check for misconfigurations -- open security groups,
unencrypted storage, excessive IAM permissions.

```bash
checkov -d .              # Terraform
tfsec .                   # Terraform
trivy config k8s/         # Kubernetes
trivy image myapp:1.0.0   # Container images
```

Suppress false positives with inline annotations:

```hcl
resource "aws_s3_bucket" "public_assets" {
  #checkov:skip=CKV_AWS_18:Public read access is intentional for CDN origin
  bucket = "myapp-public-assets"
}
```

---

## Plan-Based Testing

The Terraform plan is the single source of truth for what will change.
Testing the plan catches drift, unexpected side effects, and resource
replacement.

### Capturing Plans

Always save plans to a file for deterministic apply and testing.

```bash
terraform plan -out=tfplan
terraform show -json tfplan > tfplan.json
```

The JSON plan contains the full resource graph, attribute values, and
change actions (create, update, destroy).

### Drift Detection

A plan with zero changes confirms deployed state matches configuration.
Run drift detection on a schedule.

```bash
#!/usr/bin/env bash
set -euo pipefail

terraform plan -detailed-exitcode -out=tfplan 2>&1 | tee plan.log

case $? in
  0) echo "No changes -- infrastructure matches configuration" ;;
  1) echo "ERROR: Plan failed"; exit 1 ;;
  2) echo "DRIFT DETECTED"; terraform show -no-color tfplan; exit 2 ;;
esac
```

Exit code 2 from `-detailed-exitcode` means changes were detected.
Pipe into alerting to catch manual console changes.

### Resource Count Assertions

Parse the JSON plan to verify expected resource counts before apply.

```bash
#!/usr/bin/env bash
set -euo pipefail

terraform show -json tfplan > tfplan.json

creates=$(jq '[.resource_changes[] |
  select(.change.actions[] == "create")] | length' tfplan.json)
destroys=$(jq '[.resource_changes[] |
  select(.change.actions[] == "delete")] | length' tfplan.json)

echo "Creates: $creates, Destroys: $destroys"

if [ "$destroys" -gt 0 ]; then
  echo "WARNING: Plan includes resource destruction"
  jq '.resource_changes[] |
    select(.change.actions[] == "delete") | .address' tfplan.json
fi
```

### Test Fixtures

Isolated `.tf` files in a test directory exercise modules without
affecting real infrastructure.

```hcl
# tests/fixtures/vpc/main.tf
module "vpc" {
  source          = "../../../modules/vpc"
  cidr_block      = "10.99.0.0/16"
  environment     = "test"
  azs             = ["us-east-1a", "us-east-1b"]
  private_subnets = ["10.99.1.0/24", "10.99.2.0/24"]
}
```

```bash
cd tests/fixtures/vpc || exit 1
terraform init
terraform workspace new "test-run-$$"
terraform plan -out=tfplan
terraform workspace select default
terraform workspace delete "test-run-$$"
```

---

## Policy-as-Code

Policy-as-code enforces organizational rules beyond linting -- business
requirements like "all S3 buckets must be encrypted" or "all resources
must have a cost-center tag."

### Open Policy Agent (OPA)

OPA evaluates JSON inputs against Rego policies. Combined with
`conftest`, it tests Terraform plans against organizational rules.

```rego
# policy/terraform/encryption.rego
package terraform.encryption

deny[msg] {
  resource := input.resource_changes[_]
  resource.type == "aws_s3_bucket"
  not resource.change.after.server_side_encryption_configuration
  msg := sprintf("S3 bucket '%s' must have encryption", [resource.address])
}
```

```bash
terraform show -json tfplan | conftest test --policy policy/terraform/ -
```

### Kyverno for Kubernetes

Kyverno policies run as an admission controller, enforcing rules at
deploy time.

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-resource-limits
spec:
  validationFailureAction: Enforce
  rules:
    - name: check-limits
      match:
        any:
          - resources:
              kinds: [Pod]
      validate:
        message: "All containers must have CPU and memory limits"
        pattern:
          spec:
            containers:
              - resources:
                  limits:
                    cpu: "?*"
                    memory: "?*"
```

### Policy Testing

Policies are code and need tests. OPA has a built-in test framework.

```rego
# policy/terraform/encryption_test.rego
package terraform.encryption

test_deny_unencrypted_bucket {
  count(deny) > 0 with input as {
    "resource_changes": [{
      "type": "aws_s3_bucket",
      "address": "aws_s3_bucket.test",
      "change": {"after": {}}
    }]
  }
}

test_allow_encrypted_bucket {
  count(deny) == 0 with input as {
    "resource_changes": [{
      "type": "aws_s3_bucket",
      "address": "aws_s3_bucket.test",
      "change": {"after": {
        "server_side_encryption_configuration": [{}]
      }}
    }]
  }
}
```

```bash
opa test policy/ -v
```

---

## CI Integration

CI pipelines for infrastructure follow a strict sequence: validate on
every push, plan on every PR, apply only on merge to main.

### Pre-Commit Hooks

Catch formatting and syntax errors before code reaches the repository.

```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/antonbabenko/pre-commit-terraform
    rev: v1.88.0
    hooks:
      - id: terraform_fmt
      - id: terraform_validate
      - id: terraform_tflint
```

### PR Pipeline: Plan Only

Pull requests generate a plan and post the output as a PR comment.
No infrastructure changes are made until code is merged.

```yaml
# .github/workflows/terraform-pr.yml
name: Terraform Plan
on:
  pull_request:
    branches: [main]
    paths: ["terraform/**"]
permissions:
  id-token: write
  contents: read
  pull-requests: write
jobs:
  plan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ vars.PLAN_ROLE_ARN }}
          aws-region: us-east-1
      - uses: hashicorp/setup-terraform@v3
      - run: terraform init -input=false
        working-directory: terraform/
      - run: terraform plan -no-color -out=tfplan 2>&1 | tee plan.txt
        working-directory: terraform/
      # Post plan.txt as PR comment via actions/github-script
```

### Merge Pipeline: Apply with Approval

Apply runs only after merge to main. Production requires manual
approval via GitHub environment protection rules.

```yaml
# .github/workflows/terraform-apply.yml
on:
  push:
    branches: [main]
    paths: ["terraform/**"]
jobs:
  apply-staging:
    environment: staging
    steps:
      - uses: actions/checkout@v4
      - run: terraform init -input=false && terraform apply -auto-approve

  apply-production:
    needs: apply-staging
    environment: production  # requires manual approval
    steps:
      - uses: actions/checkout@v4
      - run: terraform init -input=false && terraform plan -out=tfplan
      - run: terraform apply tfplan
```

### Pipeline Order Summary

| Trigger | Actions | Environment |
|---------|---------|-------------|
| Push to feature branch | fmt, validate, lint, security scan | None |
| Pull request to main | All above + plan + PR comment | None |
| Merge to main | Plan + apply (auto) | Staging |
| Merge to main + approval | Plan + apply (gated) | Production |

Fast checks run on every push. Expensive operations (plan, apply) run
only on the main branch pipeline. Production always requires explicit
human approval.
