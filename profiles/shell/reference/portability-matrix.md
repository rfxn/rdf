# Portability Matrix

> Cross-distro compatibility reference for bash/shell projects. Covers
> path layout, bash feature availability, AWK variants, init systems,
> and package managers.

---

## Path Differences

The usr-merge transition moved coreutils from `/bin/` to `/usr/bin/`.
Older distros retain the original layout. Never hardcode either path.

| Distro | Version | `/bin/` coreutils | `/usr/bin/` coreutils | usr-merge |
|--------|---------|-------------------|-----------------------|-----------|
| CentOS | 6 | Yes | No (symlinks absent) | No |
| CentOS | 7 | Yes | Partial symlinks | No |
| Rocky | 8 | Symlinks | Yes | Yes |
| Rocky | 9 | Symlinks | Yes | Yes |
| Ubuntu | 20.04 | Symlinks | Yes | Yes |
| Ubuntu | 24.04 | Symlinks | Yes | Yes |
| Debian | 12 | Symlinks | Yes | Yes |
| Alpine | 3.18+ | Symlinks via busybox | Yes | Yes |
| Arch | rolling | Symlinks | Yes | Yes |

The same split applies to `/sbin/` vs `/usr/sbin/`. Use `command -v`
to discover binary paths at runtime.

---

## Bash Version Features

Features available by bash version. Do not use features above your
project's declared version floor (default: 4.3).

| Feature | Bash Version | Notes |
|---------|-------------|-------|
| Associative arrays (`declare -A`) | 4.0 | Breaks when sourced from functions |
| `&>>` append redirect | 4.0 | |
| `mapfile` / `readarray` | 4.0 | |
| `${var,,}` / `${var^^}` (case) | 4.0 | |
| `|&` pipe stderr shorthand | 4.0 | |
| `mapfile -d` (delimiter) | 4.4 | |
| `${var@Q}` (quoting operator) | 4.4 | |
| Nameref (`declare -n`) | 4.3 | |
| Negative subscripts (`${arr[-1]}`) | 4.3 | |
| `wait -n` (any child) | 4.3 | |
| `BASH_ARGV0` | 5.0 | |
| `EPOCHSECONDS` / `EPOCHREALTIME` | 5.0 | |
| `wait -p` (capture PID) | 5.1 | |
| `${var/pat/repl}` brace bug fixed | 5.0 | bash 4.x requires variable workaround |

---

## AWK Variants

Many distros default to `mawk`, which lacks GNU AWK extensions. Assume
`mawk` unless your project explicitly requires `gawk`.

| Feature | mawk | gawk | Notes |
|---------|------|------|-------|
| `gensub()` | No | Yes | Use `gsub()` + assignment |
| `strftime()` | No | Yes | Use external `date` command |
| `mktime()` | No | Yes | |
| `systime()` | No | Yes | |
| Multi-dimensional arrays | No | Yes | Simulate with `SUBSEP` |
| `length(array)` | No | Yes | Iterate and count instead |
| `asort()` / `asorti()` | No | Yes | Pipe to `sort` externally |
| `@include` | No | Yes | |
| `/regex/` in field split | Limited | Yes | |

Default AWK by distro: Debian/Ubuntu use `mawk`, RHEL/Rocky use `gawk`,
Alpine uses busybox `awk` (most limited).

---

## Init Systems

| Distro | Version | systemd | SysV init | Notes |
|--------|---------|---------|-----------|-------|
| CentOS | 6 | No | Yes | `service` and `chkconfig` |
| CentOS | 7 | Yes | Compat layer | `systemctl` preferred |
| Rocky | 8-9 | Yes | No | `systemctl` only |
| Ubuntu | 20.04+ | Yes | Compat layer | `systemctl` preferred |
| Debian | 12 | Yes | Compat layer | `systemctl` preferred |
| Alpine | 3.x | No | OpenRC | `rc-service` and `rc-update` |
| Slackware | 15.0 | No | BSD-style init | `/etc/rc.d/` scripts |

Service management code must detect the init system at runtime:
```bash
if command -v systemctl >/dev/null 2>&1; then
    systemctl restart "$service"
else
    service "$service" restart
fi
```

---

## Package Managers

| Distro | Manager | Install Command | Notes |
|--------|---------|-----------------|-------|
| CentOS 6-7 | yum | `yum install -y` | EPEL for extras |
| Rocky 8-9 | dnf | `dnf install -y` | `yum` symlink exists |
| Ubuntu / Debian | apt | `apt-get install -y` | Use `apt-get`, not `apt` in scripts |
| Alpine | apk | `apk add` | No `-y` needed (non-interactive default) |
| Arch | pacman | `pacman -S --noconfirm` | |
| Gentoo | portage | `emerge` | Source-based, slow |
| Slackware | slackpkg | `slackpkg install` | Limited dependency resolution |

Use `apt-get` instead of `apt` in scripts -- `apt` is designed for
interactive use and its output format is not stable.
