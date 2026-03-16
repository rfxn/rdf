# OS Compatibility Matrix

> Reference for systems-engineering profile. Maps OS targets to feature
> availability and known pitfalls.

## Supported Targets

| OS | Version | Bash | usr-merge | systemd | Notes |
|----|---------|------|-----------|---------|-------|
| CentOS | 6 | 4.1 | No | No | Floor target. `/bin/` for coreutils |
| CentOS | 7 | 4.2 | No | Yes | bash 4.x `${var/pat/repl}` trap |
| Rocky | 8 | 4.4 | Yes | Yes | RHEL 8 rebuild |
| Rocky | 9 | 5.1 | Yes | Yes | RHEL 9 rebuild |
| Ubuntu | 20.04 | 5.0 | Yes | Yes | LTS |
| Ubuntu | 24.04 | 5.2 | Yes | Yes | LTS |
| Debian | 12 | 5.2 | Yes | Yes | Primary test target |
| Gentoo | rolling | 5.x | Yes | Optional | Source-based |
| Slackware | 15.0 | 5.1 | No | No | Traditional layout |
| FreeBSD | 13+ | 5.x (pkg) | N/A | No | LMD partial support only |

## Key Pitfalls

### usr-merge

CentOS 6 has NOT undergone the `/usr` merge:
- Coreutils at `/bin/`, not `/usr/bin/`
- Use `command <util>` for portable resolution
- Never hardcode `/usr/bin/rm` or `/bin/rm` in project source

### sbin split

`/sbin/` vs `/usr/sbin/` differs across distros. Discover via `command -v` at runtime.

### TLS

CentOS 6 ships OpenSSL 1.0.1 — no TLS 1.3, limited TLS 1.2 cipher support.
Use `--tlsv1.2` flag with curl where available, fall back gracefully.

### systemd

CentOS 6 and Slackware use SysV init. Service management code must support both
`systemctl` and legacy init scripts.
