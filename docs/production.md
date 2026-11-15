---
title: Production Use
parent: Project
nav_order: 3
description: "RDF governs development of security tooling on ~350,000 servers: APF, LMD and BFD. Measured sessions, commits, tests and releases."
---

# Production use

RDF governs development of security infrastructure deployed across ~350,000 active
servers.

| Project | What it does |
|---------|--------------|
| **APF** (Advanced Policy Firewall) | Network access control and rate limiting |
| **LMD** (Linux Malware Detect) | Filesystem malware scanning with daily signature updates |
| **BFD** (Brute Force Detection) | Real-time authentication attack detection |

Daily check-ins come from government (NIST, NOAA, NIH), defense (NATO CCDCOE),
universities (Stanford, Harvard), telecom (Deutsche Telekom, Vodafone, Telefonica) and
infrastructure providers (AWS, Hetzner, OVHcloud, DigitalOcean), across cPanel, Plesk
and bare-metal environments.

## Why the gates exist

| Project | What a bug costs |
|---------|------------------|
| LMD | A false positive quarantines legitimate files on every server that pulls the update |
| APF | A regression in rule parsing locks administrators out of their own servers |
| BFD | A threshold change floods block lists or stops detecting real attacks |

These are security tools. A regression changes the security posture of hundreds of
thousands of machines.

## Measured usage

Derived from session logs and git history, March to July 2026:

| Metric | Value |
|--------|-------|
| Active servers running governed tools | ~350,000 |
| Governed work sessions logged | 518 across 30+ projects (~17 weeks, ~4.3 per day) |
| Commits landed portfolio-wide | 2,513 (git-verified) |
| BATS test cases across governed repos | 6,871 (13 repos, all CI-runnable) |
| Major releases shipped under governance | LMD 2.0, APF 2.0, BFD 2.0, plus 26 RDF releases in 18 weeks |
| Design artifacts committed | 25 specs and 22 implementation plans, designed in the open |

One operator, thirty-plus projects, and a sustained multi-month cadence, with every
release backed by committed specs, adversarial review and a test suite that runs in
CI. That is the throughput the governance layer exists to make safe.

## Design in the open

Read how it was built: the [spec archive](https://github.com/rfxn/rdf/tree/main/docs/specs)
holds the design records, and the [demo walkthrough](demo-walkthrough.md) follows one
production change from spec to ship.
