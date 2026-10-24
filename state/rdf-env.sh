#!/usr/bin/env bash
# state/rdf-env.sh — environment assessment: what an optimal Claude Code + RDF setup has, and what this host lacks
# (C) 2026 R-fx Networks <proj@rfxn.com>
# GNU GPL v2
# shellcheck disable=SC2016  # literal $ in single-quoted jq programs
set -euo pipefail

# Thresholds: the evidence for each is in docs/specs/2026-10-24-env-assessment-and-pricing-design.md §5.2
_ENV_NOFILE_HARD_MIN=4096
_ENV_NPROC_MIN=2048
_ENV_RAM_MIN_KB=3670016
_ENV_DISK_MIN_KB=1048576
_ENV_PRICING_INFO_DAYS=45
_ENV_PRICING_WARN_DAYS=90
_ENV_CLAUDE_MD_LINES=200
_ENV_CLAUDE_MD_SKIP_BYTES=4194304
_ENV_MEMORY_LINES=200
_ENV_MEMORY_BYTES=25600
_ENV_LANG_MARKER_FILES=3
_ENV_LANG_MIN_FILES=50
_ENV_NET_TIMEOUT=5

_ENV_WORK=""
_ENV_DIR="$(cd "$(command dirname "${BASH_SOURCE[0]}")" && pwd)"
trap '[ -z "$_ENV_WORK" ] || command rm -rf "$_ENV_WORK"' EXIT

_env_usage() {
    cat <<'USAGE'
Usage: rdf-env.sh [options] [project]

Assess this host against an optimal Claude Code + RDF setup for a project:
code intelligence plugins and their language servers, the tools RDF relies
on, fd and process limits, sandbox dependencies, Claude Code currency, .claude
settings and memory files, and the age of the rdf tokens price table.
Read-only: it prints fixes, it never applies them. Run it through /r-env or
rdf doctor --scope env.

Options:
  --brief         fast offline subset (what /r-start shows)
  --json          JSON report
  --offline       no network lookups and no claude doctor (it can fetch
                  managed settings)
  --project-only  skip machine-wide checks (rdf doctor --all, after the
                  first project)
  --tool NAME     claude | codex | gemini (default: detected; Claude Code
                  plugin checks run only for claude)
  help            this text

Environment:
  CLAUDE_CONFIG_DIR  Claude Code config dir (default: ~/.claude)
  RDF_ENV_TODAY      YYYY-MM-DD override for the pricing-age check (tests)

Ignore a finding: put its id on a line of ~/.rdf/env-ignore (every project)
or <project>/.rdf/env-ignore (that project).
USAGE
}

_env_die() {
    printf 'rdf-env: error: %s\n' "$1" >&2
    exit "${2:-1}"
}

# _env_find id area severity title why [fix ...] — record one finding (severity: gap|warn|info)
_env_find() {
    local id="$1" area="$2" sev="$3" title="$4" why="$5" fixes=""
    shift 5
    [ $# -gt 0 ] && fixes="$(printf '%s\037' "$@")"
    jq -cn --arg id "$id" --arg area "$area" --arg sev "$sev" --arg title "$title" \
        --arg why "$why" --arg fixes "$fixes" \
        '{id: $id, area: $area, severity: $sev, title: $title, why: $why,
          fix: ($fixes | split("\u001f") | map(select(. != "")))}' >> "${_ENV_WORK}/findings"
}

# _env_fact key json — record one fact (json must be a valid JSON value)
_env_fact() {
    printf '%s\t%s\n' "$1" "$2" >> "${_ENV_WORK}/facts"
}

_env_has() { command -v "$1" >/dev/null 2>&1; }

_env_bool() { if "$@"; then printf true; else printf false; fi; }

# _env_first_line cmd... — first line of a command's output, empty on failure
_env_first_line() {
    "$@" 2>/dev/null | head -n 1 || true  # a missing or failing tool reports as empty
}

# _env_ver_num v — x.y.z as one comparable integer; empty when unparsable
_env_ver_num() {
    local v="$1" a b c
    v="${v%%[!0-9.]*}"
    a="${v%%.*}"; v="${v#*.}"
    b="${v%%.*}"; c="${v#*.}"
    c="${c%%.*}"
    case "${a}${b}${c}" in ''|*[!0-9]*) return 0 ;; esac
    printf '%s' "$(( 10#$a * 1000000 + 10#$b * 1000 + 10#$c ))"
}


_ENV_OS="" _ENV_PKG="unknown" _ENV_RHEL=0 _ENV_CFG="" _ENV_TOOL="claude"

_env_host() {
    local kernel id="" id_like="" ver="" pretty="" arch
    kernel="$(uname -s)"
    arch="$(uname -m)"
    if [ -r /etc/os-release ]; then
        # shellcheck disable=SC1091  # host file, read in a subshell so its variables stay out of ours
        IFS=$'\t' read -r id id_like ver pretty < <(. /etc/os-release \
            && printf '%s\t%s\t%s\t%s\n' "${ID:-}" "${ID_LIKE:-}" "${VERSION_ID:-}" "${PRETTY_NAME:-}") || true  # unreadable os-release → unknown distro
    elif [ "$kernel" = "Darwin" ]; then
        id="macos"; ver="$(_env_first_line sw_vers -productVersion)"; pretty="macOS ${ver}"
    fi
    _ENV_OS="$kernel"
    case " ${id} ${id_like} " in
        *" rhel "*|*" centos "*|*" rocky "*|*" almalinux "*|*" ol "*) [ "$id" != "fedora" ] && _ENV_RHEL=1 ;;
    esac
    if _env_has brew && [ "$kernel" = "Darwin" ]; then _ENV_PKG="brew"
    elif _env_has dnf; then _ENV_PKG="dnf"
    elif _env_has apt-get; then _ENV_PKG="apt"
    elif _env_has apk; then _ENV_PKG="apk"
    elif _env_has pacman; then _ENV_PKG="pacman"
    elif _env_has brew; then _ENV_PKG="brew"
    fi
    _env_fact os "$(jq -cn --arg k "$kernel" --arg a "$arch" --arg i "$id" --arg l "$id_like" \
        --arg v "$ver" --arg p "$pretty" '{kernel: $k, arch: $a, id: $i, id_like: $l, version: $v, name: $p}')"
    _env_fact pkg "$(jq -cn --arg p "$_ENV_PKG" '$p')"
}

# _env_pkg tool — install command under this host's package manager (names verified, spec §5.2); empty when unmapped
_env_pkg() {
    local tool="$1" name=""
    case "${_ENV_PKG}:${tool}" in
        *:jq|*:git|*:ripgrep|*:socat) name="$tool" ;;
        dnf:shellcheck) name="ShellCheck" ;;
        *:shellcheck) name="shellcheck" ;;
        brew:bats) name="bats-core" ;;
        *:bats) name="bats" ;;
        apk:gh|pacman:gh) name="github-cli" ;;
        *:gh) name="gh" ;;
        apt:ctags|brew:ctags) name="universal-ctags" ;;
        *:ctags) name="ctags" ;;
        brew:bubblewrap) name="" ;;
        *:bubblewrap) name="bubblewrap" ;;
        brew:python3|pacman:python3) name="python" ;;
        *:python3) name="python3" ;;
        dnf:node) name="nodejs nodejs-npm" ;;
        brew:node) name="node" ;;
        *:node) name="nodejs npm" ;;
    esac
    [ -n "$name" ] || return 0
    case "$_ENV_PKG" in
        dnf)
            if [ "$_ENV_RHEL" -eq 1 ]; then
                case "$tool" in
                    shellcheck|bats|ripgrep) printf 'sudo dnf install epel-release && sudo dnf install %s' "$name"; return 0 ;;
                esac
            fi
            printf 'sudo dnf install %s' "$name" ;;
        apt)    printf 'sudo apt install %s' "$name" ;;
        brew)   printf 'brew install %s' "$name" ;;
        apk)    printf 'sudo apk add %s' "$name" ;;
        pacman) printf 'sudo pacman -S %s' "$name" ;;
    esac
}


_ENV_PRIMARY=""

# _env_languages project — languages from manifest markers and file counts; primary rules in spec §5.2
_env_languages() {
    local project="$1" in_git=0
    if git -C "$project" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        in_git=1
        git -C "$project" ls-files 2>/dev/null > "${_ENV_WORK}/files" || true  # an unreadable index lists nothing
    else
        (cd "$project" && find . -maxdepth 5 \( -name .git -o -name node_modules -o -name .venv -o -name venv -o -name vendor \) -prune \
            -o -type f -print 2>/dev/null | sed 's|^\./||') > "${_ENV_WORK}/files" || true  # unreadable subtrees are skipped
    fi
    : > "${_ENV_WORK}/excluded"
    if [ -f "${project}/.gitattributes" ]; then
        awk '{ for (i = 2; i <= NF; i++) if ($i ~ /^linguist-(vendored|generated)(=true)?$/) { p = $1; sub(/\*\*?$/, "", p); sub(/\/$/, "", p); if (p != "") print p; break } }' \
            "${project}/.gitattributes" > "${_ENV_WORK}/excluded"
    fi
    awk -v mk="$_ENV_LANG_MARKER_FILES" -v mn="$_ENV_LANG_MIN_FILES" -v git="$in_git" '
        FILENAME == ARGV[1] { if ($0 != "") ex[++nex] = $0; next }
        {
            path = "/" $0
            if (path ~ /\/(tests?\/samples|samples|fixtures|testdata|test-data|docs?|examples?|vendor|third_party|node_modules|dist|build|\.venv|venv|site-packages|tmp|temp|\.cache|cache|coverage)\//) next
            for (i = 1; i <= nex; i++) if (index($0, ex[i]) == 1) next
            depth = gsub(/\//, "/", path) - 1
            n = split($0, seg, "/"); base = seg[n]
            if (depth <= 2) {
                if (base == "tsconfig.json" || base == "package.json") m["typescript"] = 1
                if (base == "pyproject.toml" || base == "setup.py" || base == "setup.cfg" || base == "requirements.txt" || base == "Pipfile") m["python"] = 1
                if (base == "go.mod") m["go"] = 1
                if (base == "Cargo.toml") m["rust"] = 1
                if (base == "composer.json") m["php"] = 1
                if (base == "pom.xml" || base == "build.gradle") m["java"] = 1
                if (base == "build.gradle.kts") { m["kotlin"] = 1; m["java"] = 1 }
                if (base == "Gemfile") m["ruby"] = 1
                if (base == "Package.swift") m["swift"] = 1
                if (base ~ /\.(csproj|sln)$/) m["csharp"] = 1
                if (base == "CMakeLists.txt" || base == "meson.build" || base == "compile_commands.json") m["cpp"] = 1
                if (base == ".luarc.json") m["lua"] = 1
            }
            k = split(base, p, "."); if (k < 2) next; e = tolower(p[k]); l = ""
            if (e ~ /^(ts|tsx|js|jsx|mjs|cjs)$/) l = "typescript"
            else if (e == "py") l = "python"
            else if (e == "go") l = "go"
            else if (e == "rs") l = "rust"
            else if (e == "php") l = "php"
            else if (e ~ /^(c|h|cc|cpp|cxx|hpp|hh)$/) l = "cpp"
            else if (e == "java") l = "java"
            else if (e ~ /^(kt|kts)$/) l = "kotlin"
            else if (e == "rb") l = "ruby"
            else if (e == "swift") l = "swift"
            else if (e == "cs") l = "csharp"
            else if (e == "lua") l = "lua"
            else if (e ~ /^(sh|bash|bats)$/) l = "shell"
            if (l != "") c[l]++
        }
        END {
            for (l in c) printf "%s\t%d\t%d\t%d\n", l, c[l], (l in m) ? 1 : 0,
                (((l in m) && c[l] >= mk) || (git && (c[l] >= mn || (l == "shell" && c[l] >= 10)))) ? 1 : 0
        }
    ' "${_ENV_WORK}/excluded" "${_ENV_WORK}/files" | sort > "${_ENV_WORK}/langs"
    _ENV_PRIMARY="$(awk -F'\t' '$4 == 1 { printf "%s ", $1 }' "${_ENV_WORK}/langs")"
    _env_fact languages "$(jq -cR 'split("\t") | {lang: .[0], files: (.[1] | tonumber), marker: (.[2] == "1"), primary: (.[3] == "1")}' \
        "${_ENV_WORK}/langs" | jq -cs '.')"
}


# _env_lsp_row lang — "plugin binary" for a language with an official code intelligence plugin
_env_lsp_row() {
    case "$1" in
        typescript) printf 'typescript-lsp typescript-language-server' ;;
        python)     printf 'pyright-lsp pyright-langserver' ;;
        go)         printf 'gopls-lsp gopls' ;;
        rust)       printf 'rust-analyzer-lsp rust-analyzer' ;;
        php)        printf 'php-lsp intelephense' ;;
        cpp)        printf 'clangd-lsp clangd' ;;
        java)       printf 'jdtls-lsp jdtls' ;;
        kotlin)     printf 'kotlin-lsp kotlin-lsp' ;;
        ruby)       printf 'ruby-lsp ruby-lsp' ;;
        swift)      printf 'swift-lsp sourcekit-lsp' ;;
        csharp)     printf 'csharp-lsp csharp-ls' ;;
        lua)        printf 'lua-lsp lua-language-server' ;;
    esac
}

# _env_lsp_install lang — the language server install command from the plugin's README
_env_lsp_install() {
    case "${1}:${_ENV_PKG}" in
        typescript:*) printf 'npm install -g typescript-language-server typescript' ;;
        python:*)     printf 'npm install -g pyright' ;;
        go:*)         printf 'go install golang.org/x/tools/gopls@latest' ;;
        rust:*)       printf 'rustup component add rust-analyzer' ;;
        php:*)        printf 'npm install -g intelephense' ;;
        cpp:brew)     printf 'brew install llvm' ;;
        cpp:apt)      printf 'sudo apt install clangd' ;;
        cpp:dnf)      printf 'sudo dnf install clang-tools-extra' ;;
        cpp:pacman)   printf 'sudo pacman -S clang' ;;
        java:brew)    printf 'brew install jdtls' ;;
        kotlin:brew)  printf 'brew install JetBrains/utils/kotlin-lsp' ;;
        ruby:*)       printf 'gem install ruby-lsp' ;;
        swift:brew)   printf 'brew install swift' ;;
        csharp:*)     printf 'dotnet tool install --global csharp-ls' ;;
        lua:brew)     printf 'brew install lua-language-server' ;;
        lua:pacman)   printf 'sudo pacman -S lua-language-server' ;;
        lua:dnf)      printf 'sudo dnf install lua-language-server' ;;
    esac
}

# _env_settings_files project — settings files lowest to highest precedence (user, project, local, managed)
_env_settings_files() {
    local project="$1" managed="/etc/claude-code/managed-settings.json"
    [ "$_ENV_OS" = "Darwin" ] && managed="/Library/Application Support/ClaudeCode/managed-settings.json"
    printf '%s\n' "${_ENV_CFG}/settings.json" "${project}/.claude/settings.json" \
        "${project}/.claude/settings.local.json" "$managed"
}

# _env_plugin_state plugin project — "installed enabled" (0/1): installed in the active config dir, enabled in merged settings
_env_plugin_state() {
    local key="${1}@claude-plugins-official" project="$2" inst=0 en=0 f
    if jq -e --arg k "$key" '(.plugins // {}) | has($k)' "${_ENV_CFG}/plugins/installed_plugins.json" >/dev/null 2>&1; then  # missing or unreadable file → not installed
        inst=1
    fi
    while IFS= read -r f; do
        [ -f "$f" ] || continue
        case "$(jq -r --arg k "$key" '(.enabledPlugins // {})[$k] | tostring' "$f" 2>/dev/null || true)" in  # unparsable settings → no opinion
            true) en=1 ;;
            false) en=0 ;;
        esac
    done < <(_env_settings_files "$project")
    printf '%s %s' "$inst" "$en"
}

# _env_code_intel project — language server + plugin per language; gaps only for primary languages
_env_code_intel() {
    local project="$1" lang files primary row plugin bin state inst en have fix acct=""
    : > "${_ENV_WORK}/lsp"
    [ "$_ENV_TOOL" = "claude" ] || { _env_fact lsp 'null'; return 0; }
    [ -n "${CLAUDE_CONFIG_DIR:-}" ] && acct="CLAUDE_CONFIG_DIR=$(printf '%q' "$CLAUDE_CONFIG_DIR") "
    while IFS=$'\t' read -r lang files _ primary; do
        row="$(_env_lsp_row "$lang")"
        [ -n "$row" ] || continue
        plugin="${row%% *}"; bin="${row#* }"
        have=0; _env_has "$bin" && have=1
        state="$(_env_plugin_state "$plugin" "$project")"
        inst="${state%% *}"; en="${state#* }"
        jq -cn --arg l "$lang" --arg p "$plugin" --arg b "$bin" --argjson f "$files" --argjson pr "$primary" \
            --argjson h "$have" --argjson i "$inst" --argjson e "$en" \
            '{lang: $l, files: $f, primary: ($pr == 1), plugin: $p, binary: $b, binary_found: ($h == 1),
              plugin_installed: ($i == 1), plugin_enabled: ($e == 1)}' >> "${_ENV_WORK}/lsp"
        [ "$primary" = "1" ] || continue
        [ "$have" -eq 1 ] && [ "$inst" -eq 1 ] && [ "$en" -eq 1 ] && continue
        set --
        if [ "$have" -eq 0 ]; then
            fix="$(_env_lsp_install "$lang")"
            [ -n "$fix" ] || fix="see https://github.com/anthropics/claude-plugins-official/tree/main/plugins/${plugin}"
            set -- "$fix"
        fi
        if [ "$inst" -eq 0 ]; then
            set -- "$@" "${acct}claude plugin install ${plugin}@claude-plugins-official"
        elif [ "$en" -eq 0 ]; then
            set -- "$@" "${acct}claude plugin enable ${plugin}@claude-plugins-official"
        fi
        _env_find "lsp-${lang}" code-intel gap \
            "${lang} project (${files} files) without code intelligence" \
            "With ${plugin} and ${bin}, Claude navigates by symbol (definition, references) instead of grep plus whole-file reads, and sees type errors after each edit without a build" \
            "$@"
    done < "${_ENV_WORK}/langs"
    _env_fact lsp "$(jq -cs '.' "${_ENV_WORK}/lsp")"
}

# _env_accounts — primary-language plugins missing from another RDF account (~/.rdf/accounts; plugins install per config dir)
_env_accounts() {
    local reg="${HOME}/.rdf/accounts" name dir lang primary row plugin missing
    : > "${_ENV_WORK}/accounts"
    if [ ! -f "$reg" ] || [ "$_ENV_TOOL" != "claude" ]; then
        _env_fact accounts '[]'
        return 0
    fi
    while IFS=$'\t' read -r name dir; do
        case "$name" in ''|'#'*) continue ;; esac
        [ "$dir" = "@primary" ] && dir="${HOME}/.claude"
        [ -d "$dir" ] || continue
        missing=""
        while IFS=$'\t' read -r lang _ _ primary; do
            [ "$primary" = "1" ] || continue
            row="$(_env_lsp_row "$lang")"
            [ -n "$row" ] || continue
            plugin="${row%% *}"
            jq -e --arg k "${plugin}@claude-plugins-official" '(.plugins // {}) | has($k)' \
                "${dir}/plugins/installed_plugins.json" >/dev/null 2>&1 || missing="${missing} ${plugin}"  # no plugins file → missing
        done < "${_ENV_WORK}/langs"
        printf '%s\t%s\t%s\n' "$name" "$dir" "${missing# }" >> "${_ENV_WORK}/accounts"
        if [ -n "$missing" ] && [ "$dir" != "$_ENV_CFG" ]; then
            set --
            for plugin in $missing; do
                set -- "$@" "CLAUDE_CONFIG_DIR=$(printf '%q' "$dir") claude plugin install ${plugin}@claude-plugins-official"
            done
            _env_find "account-${name}" code-intel info "account ${name} lacks${missing}" \
                "Plugins install per account, so sessions launched as ${name} get no code intelligence for this project" "$@"
        fi
    done < "$reg"
    _env_fact accounts "$(jq -cR 'split("\t") | {name: .[0], dir: .[1], missing_lsp_plugins: (.[2] | split(" ") | map(select(. != "")))}' \
        "${_ENV_WORK}/accounts" | jq -cs '.')"
}


# _env_tool name binary — record presence and version of one tool
_env_tool() {
    local name="$1" bin="$2" path="" ver=""
    if _env_has "$bin"; then
        path="$(command -v "$bin")"
        case "$bin" in
            shellcheck) ver="$(shellcheck --version 2>/dev/null | sed -n 's/^version: //p' || true)" ;;  # odd output → unknown version
            *) ver="$(_env_first_line "$bin" --version)" ;;
        esac
    fi
    printf '%s\t%s\t%s\n' "$name" "$path" "$ver" >> "${_ENV_WORK}/tools"
}

# _env_tools_project project — the tools this project's RDF workflow needs
_env_tools_project() {
    local project="$1" gitver gn fix origin
    _env_tool git git
    if ! _env_has git; then
        _env_find tool-git tools gap "git is not installed" "RDF and Claude Code's git features need it" "$(_env_pkg git)"
    else
        gitver="$(git --version 2>/dev/null | awk '{print $3}')"  # unparsable version → unknown
        gn="$(_env_ver_num "$gitver")"
        if [ -n "$gn" ] && [ "$gn" -lt 2023000 ]; then
            _env_find tool-git-version tools gap "git ${gitver} is older than 2.23" \
                "RDF's phase scope guard needs git 2.23 or later; el7's base repository ships 1.8, so it needs a newer git from outside it" \
                "upgrade git to 2.23 or later"
        fi
    fi
    case " ${_ENV_PRIMARY} " in
        *" shell "*)
            _env_tool shellcheck shellcheck
            _env_tool bats bats
            if ! _env_has shellcheck; then
                fix="$(_env_pkg shellcheck)"
                _env_find tool-shellcheck tools gap "shell project without shellcheck" \
                    "RDF verification lints shell with shellcheck before every commit" ${fix:+"$fix"}
            fi
            if ! _env_has bats && [ ! -d "${project}/tests/infra" ] && [ ! -f "${project}/tests/Dockerfile" ]; then
                fix="$(_env_pkg bats)"
                _env_find tool-bats tools gap "shell project without bats" \
                    "RDF projects test shell with BATS (this one has no container test harness that would supply it)" ${fix:+"$fix"}
            fi
            ;;
    esac
    origin="$(git -C "$project" remote get-url origin 2>/dev/null || true)"  # no git or no origin → no GitHub check
    case "$origin" in
        *github.com[:/]*)
            _env_tool gh gh
            if ! _env_has gh; then
                fix="$(_env_pkg gh)"
                [ "$_ENV_RHEL" -eq 1 ] && fix="see https://github.com/cli/cli/blob/trunk/docs/install_linux.md (GitHub's own repository)"
                _env_find tool-gh tools gap "GitHub project without the gh CLI" \
                    "RDF's /r-ship, issue rituals and PR checks drive GitHub through gh" ${fix:+"$fix"}
            fi
            ;;
    esac
}

_env_tools_machine() {
    local fix
    _env_tool jq jq
    _env_tool ripgrep rg
    _env_tool ctags ctags
    _env_tool python3 python3
    _env_tool node node
    _env_tool npm npm
    _env_tool docker docker
    _env_tool timeout timeout
    _env_tool codex codex
    if ! _env_has python3; then
        fix="$(_env_pkg python3)"
        _env_find tool-python3 tools info "python3 is not installed" \
            "/r-start shows the last session line, and context-audit breaks down settings sizes, only with python3" ${fix:+"$fix"}
    fi
    case " ${_ENV_PRIMARY} " in
        *" typescript "*|*" cpp "*)
            if ! _env_has ctags; then
                fix="$(_env_pkg ctags)"
                _env_find tool-ctags tools info "no Universal Ctags" \
                    "/r-util-code-map gets end lines for TypeScript and C symbols only through ctags" ${fix:+"$fix"}
            fi
            ;;
    esac
    if ! _env_has npm && grep -q '"fix":\["npm ' "${_ENV_WORK}/findings"; then
        fix="$(_env_pkg node)"
        _env_find tool-node tools gap "node and npm are needed for the language servers above" \
            "typescript-language-server, pyright and intelephense install through npm" ${fix:+"$fix"}
    fi
}


# _env_npm_tag pkg tag — a dist-tag version from the npm registry (no identifiers are sent); empty offline
_env_npm_tag() {
    local tags
    _env_has curl || return 0
    tags="$(curl -fsS --max-time "$_ENV_NET_TIMEOUT" "https://registry.npmjs.org/-/package/${1}/dist-tags" 2>/dev/null || true)"  # offline or registry error → unknown, never fatal
    printf '%s' "$tags" | jq -r --arg t "$2" '.[$t] // empty' 2>/dev/null || true  # non-JSON reply → unknown
}

_env_claude() {
    local online="$1" project="$2" cur channel="latest" latest="" cn ln behind=0 autoupd="enabled" f v out install="" search="" issues=""
    cur="$(_env_first_line claude --version | awk '{print $1}')"
    while IFS= read -r f; do
        [ -f "$f" ] || continue
        v="$(jq -r '.autoUpdatesChannel // empty' "$f" 2>/dev/null || true)"  # unparsable settings → no opinion
        [ -n "$v" ] && channel="$v"
        [ "$(jq -r '.env.DISABLE_AUTOUPDATER // empty | tostring' "$f" 2>/dev/null || true)" = "1" ] && autoupd="disabled"  # unparsable → no opinion
    done < <(_env_settings_files "$project")
    [ "${DISABLE_AUTOUPDATER:-}" = "1" ] && autoupd="disabled"
    if [ "$online" -eq 1 ] && [ -n "$cur" ]; then
        latest="$(_env_npm_tag @anthropic-ai/claude-code "$channel")"
        cn="$(_env_ver_num "$cur")"; ln="$(_env_ver_num "$latest")"
        if [ -n "$cn" ] && [ -n "$ln" ] && [ "$ln" -gt "$cn" ]; then
            if [ $(( ln / 1000 )) -eq $(( cn / 1000 )) ]; then behind=$(( ln - cn )); else behind=-1; fi
            _env_find claude-version claude info \
                "Claude Code ${cur}; ${latest} is current on the ${channel} channel" \
                "Releases carry cost and reliability fixes$( [ "$autoupd" = "disabled" ] && printf '; auto-update is disabled, so this host moves only when you update')" \
                "claude update"
        fi
        if _env_has claude; then
            if _env_has timeout; then
                out="$(timeout 30 claude doctor 2>&1 || true)"  # a failing or hung doctor is reported from its output
            else
                out="$(claude doctor 2>&1 || true)"  # a failing doctor is reported from its output
            fi
            out="$(printf '%s\n' "$out" | sed 's/\x1b\[[0-9;]*m//g')"
            install="$(printf '%s\n' "$out" | sed -n 's/^Running: //p' | head -n 1)"
            search="$(printf '%s\n' "$out" | sed -n 's/^Search: //p' | head -n 1)"
            case "$out" in
                *"No installation issues found"*) ;;
                "") issues="claude doctor produced no output" ;;
                *) issues="$(printf '%s\n' "$out" | grep -iE 'warn|error|fail|issue|not found|invalid' | head -n 5 || true)"  # no keyword line → generic text
                   [ -n "$issues" ] || issues="claude doctor did not report a clean install" ;;
            esac
            [ -z "$issues" ] || _env_find claude-doctor claude warn "claude doctor reports installation issues" \
                "$issues" "claude doctor" "/doctor (inside a session, to apply fixes)"
        fi
    fi
    _env_fact claude "$(jq -cn --arg c "$cur" --arg l "$latest" --argjson b "$behind" --arg ch "$channel" \
        --arg a "$autoupd" --arg i "$install" --arg s "$search" \
        '{version: (if $c == "" then null else $c end), channel: $ch, latest: (if $l == "" then null else $l end),
          releases_behind: (if $b < 0 then null else $b end), auto_update: $a,
          install: (if $i == "" then null else $i end), search: (if $s == "" then null else $s end)}')"
}

_env_codex() {
    local online="$1" cur latest="" cn ln
    _env_has codex || { _env_fact codex 'null'; return 0; }
    cur="$(_env_first_line codex --version | awk '{print $NF}')"
    if [ "$online" -eq 1 ]; then
        latest="$(_env_npm_tag @openai/codex latest)"
        cn="$(_env_ver_num "$cur")"; ln="$(_env_ver_num "$latest")"
        if [ -n "$cn" ] && [ -n "$ln" ] && [ "$ln" -gt "$cn" ]; then
            _env_find codex-version codex info "Codex ${cur}; ${latest} is available" \
                "RDF deploys skills and AGENTS.md for Codex; current releases read them as documented" \
                "npm install -g @openai/codex"
        fi
    fi
    _env_fact codex "$(jq -cn --arg c "$cur" --arg l "$latest" '{version: $c, latest: (if $l == "" then null else $l end)}')"
}


_env_limits() {
    local mode="$1" soft hard nproc watches=""
    soft="$(ulimit -Sn)"; hard="$(ulimit -Hn)"; nproc="$(ulimit -Su)"
    # Claude Code raises its soft fd limit to the hard limit at startup, so the hard limit is what it gets
    if [ "$hard" != "unlimited" ] && [ "$hard" -lt "$_ENV_NOFILE_HARD_MIN" ]; then
        _env_find limit-nofile limits warn "hard open-file limit is ${hard}" \
            "Claude Code raises its soft limit to this ceiling and has run out of descriptors with many agents, background sessions or large finds (changelog fixes for each); MCP and language servers add more" \
            "raise nofile in /etc/security/limits.conf, or LimitNOFILE= for a systemd unit, to 65536 or more"
    fi
    if [ "$mode" = "full" ] && [ "$nproc" != "unlimited" ] && [ "$nproc" -lt "$_ENV_NPROC_MIN" ]; then
        _env_find limit-nproc limits warn "process limit is ${nproc}" \
            "Parallel subagents, test suites and language servers each fork processes" "ulimit -u 8192"
    fi
    [ -r /proc/sys/fs/inotify/max_user_watches ] && watches="$(command cat /proc/sys/fs/inotify/max_user_watches)"
    _env_fact limits "$(jq -cn --arg s "$soft" --arg h "$hard" --arg p "$nproc" --arg w "$watches" \
        '{nofile_soft: $s, nofile_hard: $h, nproc_soft: $p, inotify_watches: (if $w == "" then null else $w end)}')"
}

_env_system() {
    local cores ram_kb="" tmp disk_home disk_tmp
    cores="$(getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || printf 0)"  # neither interface → unknown
    if [ -r /proc/meminfo ]; then
        ram_kb="$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)"
    elif _env_has sysctl; then
        ram_kb="$(( $(sysctl -n hw.memsize 2>/dev/null || printf 0) / 1024 ))"  # no hw.memsize → unknown
    fi
    tmp="${CLAUDE_CODE_TMPDIR:-${TMPDIR:-/tmp}}"
    disk_home="$(df -Pk "$HOME" 2>/dev/null | awk 'NR == 2 {print $4}')"  # df failure → unknown
    disk_tmp="$(df -Pk "$tmp" 2>/dev/null | awk 'NR == 2 {print $4}')"  # missing tmp dir → unknown
    if [ -n "$ram_kb" ] && [ "$ram_kb" -gt 0 ] && [ "$ram_kb" -lt "$_ENV_RAM_MIN_KB" ]; then
        _env_find system-ram system warn "$(( ram_kb / 1024 )) MB RAM" "Claude Code's requirements call for 4 GB or more"
    fi
    if [ -n "$disk_home" ] && [ "$disk_home" -lt "$_ENV_DISK_MIN_KB" ]; then
        _env_find system-disk-home system warn "$(( disk_home / 1024 )) MB free under ${HOME}" \
            "Transcripts, plugin caches and tool-result files grow there; Claude Code fails commands and token refreshes on a full disk"
    fi
    if [ -n "$disk_tmp" ] && [ "$disk_tmp" -lt "$_ENV_DISK_MIN_KB" ]; then
        _env_find system-disk-tmp system warn "$(( disk_tmp / 1024 )) MB free in ${tmp}" \
            "Bash command output files and test scratch space live there"
    fi
    _env_fact system "$(jq -cn --arg c "$cores" --arg r "$ram_kb" --arg h "$disk_home" --arg t "$disk_tmp" --arg d "$tmp" \
        '{cores: ($c | tonumber? // null), ram_kb: ($r | tonumber? // null),
          free_kb_home: ($h | tonumber? // null), free_kb_tmp: ($t | tonumber? // null), tmp_dir: $d}')"
}

_env_sandbox() {
    local project="$1" enabled="false" f fix
    if [ "$_ENV_OS" != "Linux" ]; then
        _env_fact sandbox '{"platform":"seatbelt"}'
        return 0
    fi
    while IFS= read -r f; do
        [ -f "$f" ] || continue
        case "$(jq -r '.sandbox.enabled // empty | tostring' "$f" 2>/dev/null || true)" in  # unparsable settings → no opinion
            true) enabled="true" ;;
            false) enabled="false" ;;
        esac
    done < <(_env_settings_files "$project")
    if ! _env_has bwrap || ! _env_has socat; then
        set --
        _env_has bwrap || { fix="$(_env_pkg bubblewrap)"; [ -n "$fix" ] && set -- "$fix"; }
        _env_has socat || { fix="$(_env_pkg socat)"; [ -n "$fix" ] && set -- "$@" "$fix"; }
        if [ "$enabled" = "true" ]; then
            _env_find sandbox-deps sandbox warn "sandbox enabled but bubblewrap or socat is missing" \
                "On Linux the Bash sandbox needs both; without them sandboxed commands cannot run" "$@"
        else
            _env_find sandbox-deps sandbox info "bubblewrap or socat is missing" \
                "Needed only to turn on the Bash sandbox (/sandbox)" "$@"
        fi
    fi
    if [ -r /proc/sys/kernel/apparmor_restrict_unprivileged_userns ] && _env_has bwrap \
        && [ "$(command cat /proc/sys/kernel/apparmor_restrict_unprivileged_userns)" = "1" ]; then
        _env_find sandbox-userns sandbox info "AppArmor restricts unprivileged user namespaces" \
            "Ubuntu 24.04+ blocks bubblewrap from starting the sandbox until a profile allows it; /sandbox names the fix" \
            "see https://code.claude.com/docs/en/sandboxing"
    fi
    _env_fact sandbox "$(jq -cn --arg e "$enabled" --argjson b "$(_env_bool _env_has bwrap)" \
        --argjson s "$(_env_bool _env_has socat)" '{platform: "bubblewrap", enabled: ($e == "true"), bubblewrap: $b, socat: $s}')"
}


# _env_md_file path scope — size facts and findings for one CLAUDE.md-family file
_env_md_file() {
    local path="$1" scope="$2" lines bytes id
    [ -f "$path" ] || return 0
    lines="$(wc -l < "$path" | command tr -d ' ')"
    bytes="$(wc -c < "$path" | command tr -d ' ')"
    printf '%s\t%s\t%s\t%s\n' "$scope" "$path" "$lines" "$bytes" >> "${_ENV_WORK}/md"
    id="$(printf '%s' "$path" | cksum | awk '{print $1}')"
    if [ "$bytes" -gt "$_ENV_CLAUDE_MD_SKIP_BYTES" ]; then
        _env_find "md-skip-${id}" config warn "${path} is over 4 MiB" \
            "Claude Code skips a CLAUDE.md that large; nothing in it loads"
    elif [ "$lines" -gt "$_ENV_CLAUDE_MD_LINES" ]; then
        _env_find "md-long-${id}" config info "${path} has ${lines} lines" \
            "Claude Code's memory guide targets under 200 lines per CLAUDE.md; longer files cost context on every request and reduce adherence; scoped instructions fit path-scoped rules or skills"
    fi
}

# _env_config project — allowlisted settings knobs, CLAUDE.md sizes, the auto-memory index, transcript disk use
_env_config() {
    local project="$1" f d root common slug mem mlines=0 mbytes=0 knobs mcp_user=0 mcp_proj=0 cleanup projects_kb="" here cj
    : > "${_ENV_WORK}/settings"
    while IFS= read -r f; do
        [ -f "$f" ] || continue
        if ! jq -e . "$f" >/dev/null 2>&1; then  # parse failure is the finding
            _env_find "settings-parse-$(printf '%s' "$f" | cksum | awk '{print $1}')" config warn "${f} is not valid JSON" \
                "Claude Code ignores settings it cannot parse" "claude doctor"
            continue
        fi
        command cat "$f" >> "${_ENV_WORK}/settings"
    done < <(_env_settings_files "$project")
    knobs="$(jq -cs '
        reduce .[] as $s ({}; . * $s)
        | {model: (.model // null), effort: (.effortLevel // null),
           effort_by_model: ((.modelSettings // {}) | with_entries(.value = (.value.effortLevel? // null))),
           prompt_cache_ttl: (.promptCacheTtl // null), subagent_prompt_cache_ttl: (.subagentPromptCacheTtl // null),
           bash_output_max_chars: (.bashOutputMaxChars // null),
           bash_max_output_length: ((.env // {}).BASH_MAX_OUTPUT_LENGTH // null),
           use_builtin_ripgrep: ((.env // {}).USE_BUILTIN_RIPGREP // null),
           disable_autoupdater: ((.env // {}).DISABLE_AUTOUPDATER // null),
           env_names: ((.env // {}) | keys),
           cleanup_period_days: (.cleanupPeriodDays // null),
           hooks: ((.hooks // {}) | with_entries(.value = (.value | length))),
           permissions: {allow: ((.permissions.allow // []) | length), deny: ((.permissions.deny // []) | length)},
           plugins_enabled: ((.enabledPlugins // {}) | to_entries | map(select(.value == true) | .key))}
    ' "${_ENV_WORK}/settings" 2>/dev/null || printf '{}')"  # no readable settings → empty knobs
    if [ "$(jq -r '(.bash_max_output_length | tonumber? // 0) > 30000 and .bash_output_max_chars == null' <<< "$knobs")" = "true" ]; then
        _env_find bash-output-length config info "BASH_MAX_OUTPUT_LENGTH is set above 30000" \
            "It only widens the window a failing command's excerpt is cut from; inline output stays at 30,000 characters unless bashOutputMaxChars is set (Claude Code 2.1.261+)"
    fi
    if [ "$(jq -r '.use_builtin_ripgrep | tostring' <<< "$knobs")" = "0" ] && ! _env_has rg; then
        _env_find ripgrep-system config warn "USE_BUILTIN_RIPGREP=0 but no system ripgrep" \
            "Search, @file mentions, agents and skills discovery use the system rg when the bundled one is off" "$(_env_pkg ripgrep)"
    fi
    cj="${HOME}/.claude.json"
    [ -n "${CLAUDE_CONFIG_DIR:-}" ] && cj="${CLAUDE_CONFIG_DIR}/.claude.json"
    if [ -f "$cj" ]; then
        mcp_user="$(jq -r '(.mcpServers // {}) | length' "$cj" 2>/dev/null || printf 0)"  # unparsable → 0
    fi
    if [ -f "${project}/.mcp.json" ]; then
        mcp_proj="$(jq -r '(.mcpServers // {}) | length' "${project}/.mcp.json" 2>/dev/null || printf 0)"  # unparsable → 0
    fi
    cleanup="$(jq -r '.cleanup_period_days // empty | tostring' <<< "$knobs")"
    case "$cleanup" in
        ''|*[!0-9]*) ;;
        *)
            if [ "$cleanup" -gt 90 ] && [ -d "${_ENV_CFG}/projects" ]; then
                if _env_has timeout; then
                    projects_kb="$(timeout 15 du -skH "${_ENV_CFG}/projects" 2>/dev/null | awk '{print $1}' || true)"  # slow or unreadable tree → unknown
                else
                    projects_kb="$(du -skH "${_ENV_CFG}/projects" 2>/dev/null | awk '{print $1}' || true)"  # unreadable tree → unknown
                fi
                case "$projects_kb" in ''|0|*[!0-9]*) projects_kb="" ;; esac
                [ -z "$projects_kb" ] || _env_find transcripts-size config info \
                    "transcripts use $( [ "$projects_kb" -ge 1024 ] && printf '%s MB' "$(( projects_kb / 1024 ))" || printf '%s KB' "$projects_kb") with cleanupPeriodDays ${cleanup}" \
                    "Transcripts are kept ${cleanup} days; rdf tokens and /resume read them, so keep the window only as long as you use it"
            fi
            ;;
    esac
    : > "${_ENV_WORK}/md"
    _env_md_file "${_ENV_CFG}/CLAUDE.md" global
    here="$(cd "$project" && pwd -P)"
    d="$here"
    while [ -n "$d" ]; do
        if [ "$d" = "$here" ]; then _env_md_file "${d}/CLAUDE.md" project; else _env_md_file "${d}/CLAUDE.md" ancestor; fi
        _env_md_file "${d}/CLAUDE.local.md" local
        [ "$d" = "/" ] && break
        d="$(command dirname "$d")"
    done
    root="$here"
    common="$(git -C "$project" rev-parse --git-common-dir 2>/dev/null || true)"  # not a git repo → the project dir
    if [ -n "$common" ] && common="$(cd "$project" && cd "$common" 2>/dev/null && pwd -P)"; then  # worktrees share the main checkout's memory dir
        root="$(command dirname "$common")"
    fi
    slug="$(printf '%s' "$root" | sed 's/[^A-Za-z0-9-]/-/g')"
    mem="${_ENV_CFG}/projects/${slug}/memory/MEMORY.md"
    if [ -f "$mem" ]; then
        mlines="$(wc -l < "$mem" | command tr -d ' ')"
        mbytes="$(wc -c < "$mem" | command tr -d ' ')"
        if [ "$mlines" -gt "$_ENV_MEMORY_LINES" ] || [ "$mbytes" -gt "$_ENV_MEMORY_BYTES" ]; then
            _env_find memory-index config warn "auto-memory index is ${mlines} lines / $(( mbytes / 1024 )) KB" \
                "Only the first 200 lines or 25 KB of MEMORY.md load at session start; entries past that stay invisible until read"
        fi
    fi
    _env_fact config "$(jq -cn --arg dir "$_ENV_CFG" --argjson k "$knobs" --arg mu "$mcp_user" --arg mp "$mcp_proj" \
        --arg mem "$mem" --arg ml "$mlines" --arg mb "$mbytes" --arg pk "$projects_kb" \
        --argjson md "$(jq -cR 'split("\t") | {scope: .[0], path: .[1], lines: (.[2] | tonumber), bytes: (.[3] | tonumber), est_tokens: ((.[3] | tonumber) / 4 | floor)}' "${_ENV_WORK}/md" | jq -cs '.')" \
        '{dir: $dir, settings: $k, mcp_servers: {user: ($mu | tonumber? // 0), project: ($mp | tonumber? // 0)},
          claude_md: $md, memory: {path: $mem, lines: ($ml | tonumber), bytes: ($mb | tonumber)},
          transcripts_kb: (if $pk == "" then null else ($pk | tonumber) end)}')"
}


_env_pricing() {
    local p as_of expires today age
    [ -f "${_ENV_DIR}/rdf-tokens.sh" ] || { _env_fact pricing 'null'; return 0; }
    p="$(bash "${_ENV_DIR}/rdf-tokens.sh" --pricing --json 2>/dev/null || true)"  # old helper without --pricing → skipped
    [ -n "$p" ] || { _env_fact pricing 'null'; return 0; }
    as_of="$(jq -r '.as_of // empty' <<< "$p" 2>/dev/null || true)"  # unparsable → skipped
    [ -n "$as_of" ] || { _env_fact pricing 'null'; return 0; }
    expires="$(jq -r '.expires // empty' <<< "$p")"
    today="${RDF_ENV_TODAY:-$(command date -u +%Y-%m-%d)}"
    age="$(jq -rn --arg a "$as_of" --arg t "$today" \
        '((($t + "T00:00:00Z") | fromdateiso8601) - (($a + "T00:00:00Z") | fromdateiso8601)) / 86400 | floor')"
    if [ -n "$expires" ] && [ "$today" \> "$expires" ]; then
        _env_find pricing-expired pricing warn "a promotional price in the rdf tokens table ended ${expires}" \
            "rdf tokens may understate that model's cost until the table is refreshed" "/r-env --pricing"
    elif [ "$age" -gt "$_ENV_PRICING_WARN_DAYS" ]; then
        _env_find pricing-age pricing warn "rdf tokens price table is ${age} days old (${as_of})" \
            "Its costs drift as vendors change prices" "/r-env --pricing"
    elif [ "$age" -gt "$_ENV_PRICING_INFO_DAYS" ]; then
        _env_find pricing-age pricing info "rdf tokens price table is ${age} days old (${as_of})" \
            "Worth comparing against the vendors' pricing pages" "/r-env --pricing"
    fi
    _env_fact pricing "$(jq -c --argjson age "$age" '{as_of, expires, age_days: $age, sources}' <<< "$p")"
}


# _env_ignored project — finding ids to drop, from ~/.rdf/env-ignore and <project>/.rdf/env-ignore
_env_ignored() {
    local f
    for f in "${HOME}/.rdf/env-ignore" "${1}/.rdf/env-ignore"; do
        [ -f "$f" ] && sed -e 's/#.*//' -e 's/[[:space:]]//g' "$f"
    done | grep -v '^$' || true  # no ignore files → nothing ignored
}

_env_report() {
    local mode="$1" json="$2" project="$3"
    _env_fact tools "$(jq -cR 'split("\t") | {(.[0]): {path: (if .[1] == "" then null else .[1] end), version: (if .[2] == "" then null else .[2] end)}}' \
        "${_ENV_WORK}/tools" | jq -cs 'add // {}')"
    _env_ignored "$project" | jq -cR '.' | jq -cs '.' > "${_ENV_WORK}/ignored"
    jq -cn --arg mode "$mode" --arg project "$project" --arg tool "$_ENV_TOOL" \
        --slurpfile f "${_ENV_WORK}/findings" --slurpfile ig "${_ENV_WORK}/ignored" \
        --argjson facts "$(jq -cR 'index("\t") as $i | {(.[0:$i]): (.[($i + 1):] | fromjson)}' "${_ENV_WORK}/facts" | jq -cs 'add // {}')" '
        def rank: if . == "gap" then 0 elif . == "warn" then 1 else 2 end;
        ($ig[0]) as $ids
        | ($f | sort_by([(.severity | rank), .area, .id])) as $all
        | ([$all[] | select(.id as $i | $ids | index($i) | not)]) as $fs
        | {schema: 1, mode: $mode, tool: $tool, generated_at: (now | todate), project: $project,
           summary: {gap: ([$fs[] | select(.severity == "gap")] | length),
                     warn: ([$fs[] | select(.severity == "warn")] | length),
                     info: ([$fs[] | select(.severity == "info")] | length),
                     ignored: (($all | length) - ($fs | length))},
           findings: $fs, facts: $facts}' > "${_ENV_WORK}/report"
    if [ "$json" -eq 1 ]; then
        command cat "${_ENV_WORK}/report"
        return 0
    fi
    jq -r '
        "rdf env — \(.project) · \(.mode) · gap \(.summary.gap) · warn \(.summary.warn) · info \(.summary.info)\(if .summary.ignored > 0 then " · ignored \(.summary.ignored)" else "" end)",
        "",
        (if (.findings | length) == 0 then "No findings: this host has what an optimal setup needs for this project." else empty end),
        (.findings[] | "[\(.severity)] \(.area): \(.title)  (\(.id))", "      why: \(.why)", (.fix[] | "      fix: \(.)"), ""),
        ([(if .facts.claude and .facts.claude.version then "claude \(.facts.claude.version)\(if .facts.claude.latest then " (\(.facts.claude.channel) \(.facts.claude.latest))" else "" end)" else empty end),
          (if .facts.codex then "codex \(.facts.codex.version)" else empty end),
          (if .facts.limits then "nofile \(.facts.limits.nofile_soft)/\(.facts.limits.nofile_hard)" else empty end),
          "pkg \(.facts.pkg // "unknown")",
          (if (.facts.os.name // "") != "" then .facts.os.name else empty end),
          (if .facts.pricing then "prices \(.facts.pricing.as_of)" else empty end)] | "facts: " + join(" · "))
    ' "${_ENV_WORK}/report"
}

# _env_detect_tool — the agent CLI running this helper
_env_detect_tool() {
    if [ "${CLAUDECODE:-}" = "1" ]; then printf claude
    elif [ -n "${GEMINI_CLI:-}" ]; then printf gemini
    elif [ -n "${CODEX_THREAD_ID:-}${CODEX_SESSION_ID:-}" ] || env | grep -q '^CODEX_SANDBOX'; then printf codex
    else printf claude
    fi
}

main() {
    local mode="full" json=0 offline=0 project_only=0 project="." tool="" online
    while [ $# -gt 0 ]; do
        case "$1" in
            --brief)        mode="brief"; shift ;;
            --json)         json=1; shift ;;
            --offline)      offline=1; shift ;;
            --project-only) project_only=1; shift ;;
            --tool)         [ $# -ge 2 ] || _env_die "--tool needs a value" 2; tool="$2"; shift 2 ;;
            help|--help|-h) _env_usage; return 0 ;;
            -*) _env_die "unknown option: $1 — run 'rdf-env.sh help'" 2 ;;
            *) project="$1"; shift ;;
        esac
    done
    case "$tool" in ''|claude|codex|gemini) ;; *) _env_die "--tool expects claude, codex or gemini" 2 ;; esac
    [ -d "$project" ] || _env_die "no such directory: ${project}" 1
    _env_has jq || _env_die "jq is required (apt/dnf install jq, or brew install jq)" 1
    case "${RDF_ENV_TODAY:-2000-01-01}" in
        [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
        *) _env_die "RDF_ENV_TODAY expects YYYY-MM-DD" 2 ;;
    esac
    project="$(cd "$project" && pwd)"
    _ENV_TOOL="${tool:-$(_env_detect_tool)}"
    online=0
    [ "$mode" = "full" ] && [ "$offline" -eq 0 ] && online=1

    _ENV_WORK="$(command mktemp -d "${TMPDIR:-/tmp}/rdf-env.XXXXXX")"
    : > "${_ENV_WORK}/findings"; : > "${_ENV_WORK}/facts"; : > "${_ENV_WORK}/tools"; : > "${_ENV_WORK}/lsp"
    _ENV_CFG="${CLAUDE_CONFIG_DIR:-${HOME}/.claude}"

    _env_host
    _env_languages "$project"
    _env_code_intel "$project"
    _env_tools_project "$project"
    if [ "$project_only" -eq 0 ]; then
        _env_limits "$mode"
    fi
    if [ "$mode" = "full" ] && [ "$project_only" -eq 0 ]; then
        _env_config "$project"
        _env_accounts
        _env_tools_machine
        _env_claude "$online" "$project"
        _env_codex "$online"
        _env_system
        _env_sandbox "$project"
        _env_pricing
    fi
    _env_report "$mode" "$json" "$project"
}

main "$@"
