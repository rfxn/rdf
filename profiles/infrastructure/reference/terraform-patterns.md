# Terraform Patterns Reference

> Deep reference for Terraform module and state management patterns.
> Covers module design, state management, refactoring safely, environment
> separation, and upgrade paths. Companion to the Infrastructure
> governance template.

---

## Module Design

### Input Validation

Use `validation` blocks to catch invalid inputs at plan time rather
than failing at apply time with cryptic provider errors.

```hcl
variable "environment" {
  type = string
  validation {
    condition     = contains(["dev", "staging", "production"], var.environment)
    error_message = "Must be one of: dev, staging, production."
  }
}

variable "cidr_block" {
  type = string
  validation {
    condition     = can(cidrhost(var.cidr_block, 0))
    error_message = "Must be a valid CIDR block (e.g., 10.0.0.0/16)."
  }
}
```

Validation runs during `terraform plan` with no provider API calls.
Validate format and allowed values -- not external existence (AMI IDs),
which is the provider's job.

### Output Contracts

Outputs define the module's public API.

```hcl
output "vpc_id" {
  description = "ID of the created VPC"
  value       = aws_vpc.main.id
}

output "database_endpoint" {
  description = "RDS instance connection endpoint"
  value       = aws_db_instance.main.endpoint
  sensitive   = true
}
```

Convention: `{resource}_{attribute}`. Always include `description`.
Mark outputs with credentials or endpoints as `sensitive`.

### Minimal Dependencies

Modules should accept IDs and values, not entire resource objects.

```hcl
# Bad: passes entire module object -- tight coupling
module "app" {
  source = "./modules/app"
  vpc    = module.vpc
}

# Good: passes only the IDs needed -- testable in isolation
module "app" {
  source             = "./modules/app"
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  security_group_id  = module.network.app_sg_id
}
```

### Module Composition

Compose small, focused modules. Each owns one concern. The root
module handles composition and data flow.

```hcl
module "vpc" {
  source     = "./modules/vpc"
  cidr_block = var.vpc_cidr
  azs        = var.availability_zones
}

module "security" {
  source = "./modules/security"
  vpc_id = module.vpc.vpc_id
}

module "app" {
  source            = "./modules/app"
  vpc_id            = module.vpc.vpc_id
  subnet_ids        = module.vpc.private_subnet_ids
  security_group_id = module.security.app_sg_id
}
```

---

## State Management

### Remote Backend Configuration

Local state cannot be shared, locked, or encrypted. Remote backends
solve all three problems.

```hcl
terraform {
  backend "s3" {
    bucket         = "myorg-terraform-state"
    key            = "production/vpc/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-locks"
  }
}
```

S3 stores state with encryption. DynamoDB provides locking --
concurrent applies are blocked until the lock is released.

### State as a Secret

State files contain every resource attribute in plaintext -- database
passwords, TLS keys, API tokens. Treat state storage as a secrets
manager: encrypt at rest, restrict access to CI and operators, enable
versioning, audit access.

### State Backup

Before `terraform state mv`, `state rm`, or major refactors, pull a
backup.

```bash
terraform state pull > backup-$(date +%Y%m%d-%H%M%S).tfstate
terraform state mv aws_instance.old aws_instance.new
# Restore if needed: terraform state push backup-*.tfstate
```

### Import for Brownfield Resources

Adopt existing infrastructure without recreating it.

```hcl
# Terraform 1.5+ (declarative)
import {
  to = aws_s3_bucket.existing
  id = "my-existing-bucket-name"
}

resource "aws_s3_bucket" "existing" {
  bucket = "my-existing-bucket-name"
}
```

After import, run `terraform plan` to verify configuration matches.
Fix drift before applying -- import + apply with drift modifies the
existing resource.

---

## Refactoring Safely

### moved Blocks for Renames

`moved` blocks preserve resource identity during renames, preventing
destroy/recreate.

```hcl
moved {
  from = aws_instance.web
  to   = aws_instance.app_server
}

resource "aws_instance" "app_server" {
  ami           = var.ami_id
  instance_type = var.instance_type
}
```

Remove `moved` blocks after all environments have applied the change.

### Moving Resources Into Modules

Use `moved` when extracting resources into a module.

```hcl
module "security" {
  source = "./modules/security"
  vpc_id = module.vpc.vpc_id
}

moved {
  from = aws_security_group.app
  to   = module.security.aws_security_group.app
}
```

### Cross-State Moves

When splitting state, use `terraform state mv -state-out`.

```bash
terraform state mv \
  -state-out=../networking/terraform.tfstate \
  aws_vpc.main aws_vpc.main
```

Always back up both states first. Plan moves on paper -- list every
resource, verify no cross-references between staying and moving.

### Zero-Downtime Refactoring

Protect stateful resources with `lifecycle` rules.

```hcl
resource "aws_db_instance" "primary" {
  lifecycle {
    prevent_destroy = true
  }
  identifier     = "myapp-primary"
  engine         = "postgres"
  instance_class = "db.r6g.large"
}
```

`prevent_destroy` errors if any plan includes destroying the resource.

---

## Environment Separation

### Directory-Based Separation

Each environment has its own directory, state, and backend.

```
infrastructure/
  modules/vpc/, app/
  environments/
    dev/        main.tf, variables.tf, terraform.tfvars, backend.tf
    staging/    main.tf, variables.tf, terraform.tfvars, backend.tf
    production/ main.tf, variables.tf, terraform.tfvars, backend.tf
```

Complete isolation and independent apply cycles. `main.tf` duplication
is the trade-off -- mitigate with shared modules.

### Workspace-Based Separation

Workspaces share configuration but maintain separate state.

```bash
terraform workspace new staging
terraform workspace select staging
terraform apply -var-file="staging.tfvars"
```

```hcl
resource "aws_instance" "app" {
  instance_type = terraform.workspace == "production" ? "m5.large" : "t3.micro"
  tags = { Environment = terraform.workspace }
}
```

Advantages: less duplication. Disadvantages: conditional logic in
configuration, accidental wrong-workspace apply, shared backend
credentials. Prefer directory-based for production workloads.

### Variable Hierarchy

Use `.tfvars` for environment-specific values, `variables.tf` defaults
for shared configuration.

```hcl
# variables.tf
variable "instance_type" {
  type    = string
  default = "t3.micro"
}
```

```hcl
# production.tfvars
instance_type = "m5.large"
min_capacity  = 3
```

Defaults serve development. Overrides serve higher environments.
Never put secrets in `.tfvars` -- use a secrets manager data source.

---

## Upgrade Paths

### Provider Version Bumps

1. Read the changelog for breaking changes
2. Update version constraint in `required_providers`
3. `terraform init -upgrade && terraform plan -out=tfplan`
4. Review plan for unexpected changes
5. Apply in staging first, then promote to production

### Module Version Migration

Check for input/output contract changes before upgrading. New required
variables, removed outputs, and renamed resources are common breaks.

```hcl
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.0.0"  # upgraded from 4.x
  # Verify: variable renames, output renames, internal moved blocks
}
```

Pin versions explicitly. Test upgrades in isolation before production.

### Terraform Core Upgrades

Core upgrades can change state format, plan format, and provider
protocol. State format changes are forward-only -- coordinate upgrades
across the team.

1. Read the upgrade guide
2. Back up state: `terraform state pull > backup.tfstate`
3. Update `required_version`
4. Run `terraform init` and `terraform plan`
5. Apply in the lowest environment first

### Lock File Discipline

Commit `.terraform.lock.hcl`. CI runs `terraform init` (without
`-upgrade`) to use locked versions. Upgrade deliberately, review the
lock file diff, and commit as a separate change.

```bash
# Deliberate upgrade
terraform init -upgrade
terraform plan -out=tfplan
# Review, then commit .terraform.lock.hcl changes
```
