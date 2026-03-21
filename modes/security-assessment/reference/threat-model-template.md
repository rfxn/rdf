# Threat Model Template

> Reference doc for security-assessment mode. Copied to
> .rdf/governance/reference/ during /r:init.

## Template Structure

Use this structure when creating a threat model for a project or
component. Fill in each section based on assessment findings.

### 1. System Overview

- Component name and purpose
- Technology stack
- Data flows (input sources, output destinations)
- Trust boundaries (network, process, privilege level)
- External dependencies and their trust level

### 2. Attack Surface

| Surface | Entry Points | Trust Level |
|---------|-------------|-------------|
| Network | Ports, protocols, APIs | Untrusted / Authenticated |
| File system | Config files, temp dirs, logs | Local user / Root |
| CLI | Arguments, stdin, env vars | Local user |
| Supply chain | Dependencies, update mechanism | External |

### 3. Threat Enumeration

For each identified threat:

| ID | Threat | STRIDE Category | Likelihood | Impact | Risk |
|----|--------|----------------|------------|--------|------|
| T1 | Description | S/T/R/I/D/E | Low/Med/High | Low/Med/High | Score |

STRIDE categories:
- **S**poofing -- identity impersonation
- **T**ampering -- unauthorized modification
- **R**epudiation -- deniable actions
- **I**nformation disclosure -- data leakage
- **D**enial of service -- availability attacks
- **E**levation of privilege -- unauthorized access escalation

### 4. Mitigations

| Threat ID | Mitigation | Status | Evidence |
|-----------|-----------|--------|----------|
| T1 | Specific countermeasure | Implemented/Planned/Accepted | File:line or test |

### 5. Residual Risk

Document accepted risks with justification:
- Risk description
- Why mitigation is not feasible or cost-effective
- Monitoring or detection controls in place
- Review schedule
