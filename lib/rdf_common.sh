#!/usr/bin/env bash
# lib/rdf_common.sh — Shared functions for RDF CLI
# (C) 2026 R-fx Networks <proj@rfxn.com>
# GNU GPL v2
# Sourced by bin/rdf — do not execute directly
# shellcheck disable=SC2034  # variables consumed by sourcing scripts

[[ -n "${_RDF_COMMON_LOADED:-}" ]] && return 0 2>/dev/null
_RDF_COMMON_LOADED=1

# Paths — set by rdf_init(); RDF_HOME set by caller before sourcing
RDF_VERSION="${RDF_VERSION:-}"
RDF_LIBDIR="${RDF_LIBDIR:-}"
RDF_CANONICAL="${RDF_CANONICAL:-}"
RDF_ADAPTERS="${RDF_ADAPTERS:-}"
RDF_STATE_DIR="${RDF_STATE_DIR:-}"

rdf_init() {
    # Idempotent — skip if already fully initialized
    [[ -n "${RDF_CANONICAL:-}" ]] && return 0

    # RDF_HOME is set by bin/rdf before sourcing us
    # Validate it exists
    if [[ -z "${RDF_HOME:-}" ]]; then
        echo "rdf: fatal: RDF_HOME not set" >&2
        exit 1
    fi
    if [[ ! -d "$RDF_HOME" ]]; then
        echo "rdf: fatal: RDF_HOME not a directory: ${RDF_HOME}" >&2
        exit 1
    fi

    RDF_LIBDIR="${RDF_LIBDIR:-${RDF_HOME}/lib}"
    RDF_CANONICAL="${RDF_HOME}/canonical"
    RDF_ADAPTERS="${RDF_HOME}/adapters"
    RDF_STATE_DIR="${RDF_HOME}/state"

    # Read version
    if [[ -f "${RDF_HOME}/VERSION" ]]; then
        RDF_VERSION="$(< "${RDF_HOME}/VERSION")"
        RDF_VERSION="${RDF_VERSION%%[[:space:]]}"
    else
        RDF_VERSION="unknown"
    fi
}

# rdf_canonical_path PATH — print an absolute, symlink-resolved path; always returns 0.
# Tries readlink -f, then realpath, then a cd -P + readlink fallback (non-GNU hosts).
# On failure prints a blank line (empty when captured with "$(...)").
rdf_canonical_path() {
    local _p="${1:-}" _t _d
    # BSD readlink -f / realpath still print to stdout on a nonzero exit, so gate on
    # exit status (and non-empty output) before trusting the captured value.
    if _t="$(command readlink -f "$_p" 2>/dev/null)" && [[ -n "$_t" ]]; then
        printf '%s\n' "$_t"; return 0
    fi
    if command -v realpath >/dev/null 2>&1 \
        && _t="$(command realpath "$_p" 2>/dev/null)" && [[ -n "$_t" ]]; then
        printf '%s\n' "$_t"; return 0
    fi
    if [[ -L "$_p" ]]; then
        _t="$(command readlink "$_p" 2>/dev/null)"
        case "$_t" in
            /*) _d="$(cd -P "$(command dirname "$_t")" 2>/dev/null && pwd)" \
                    && printf '%s/%s\n' "$_d" "$(command basename "$_t")" || printf '%s\n' "$_t" ;;   # dangling target: canonicalize its parent (macOS /var -> /private/var)
            *)  _d="$(cd -P "$(command dirname "$_p")" 2>/dev/null && pwd)" \
                    && printf '%s/%s\n' "$_d" "$_t" || printf '\n' ;;
        esac
        return 0
    fi
    _d="$(cd -P "$(command dirname "$_p")" 2>/dev/null && pwd)" \
        && printf '%s/%s\n' "$_d" "$(command basename "$_p")" || printf '\n'
    return 0
}

# rdf_hash_stdin — emit hex digest of stdin; portable (sha256sum → shasum -a 256 →
# sha1sum). Returns nonzero if no hashing tool exists. macOS ships shasum, not sha256sum.
rdf_hash_stdin() {
    if command -v sha256sum >/dev/null 2>&1; then command sha256sum | command awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then command shasum -a 256 | command awk '{print $1}'
    elif command -v sha1sum >/dev/null 2>&1; then command sha1sum | command awk '{print $1}'
    else return 1
    fi
}

# rdf_strip_frontmatter FILE — emit FILE's body, stripping ONLY a leading
# --- ... --- frontmatter block plus one following blank separator; files not
# starting with --- pass through verbatim. Single strip implementation for
# sync (reverse flow) and doctor (drift hashing). Unclosed frontmatter emits
# nothing — callers must empty-guard.
rdf_strip_frontmatter() {
    command awk '
        NR==1 && /^---[[:space:]]*$/ { fm=1; next }
        fm==1 && /^---[[:space:]]*$/ { fm=2; next }
        fm==1 { next }
        fm==2 { fm=3; if ($0 ~ /^[[:space:]]*$/) next }
        { print }
    ' "$1"
}

# rdf_require_agent_meta META_FILE AGENTS_DIR — die listing canonical agents
# absent from the catalog: a plain-copied agent deploys broken and arms the
# sync truncation path, so generation must fail instead.
rdf_require_agent_meta() {
    local meta="$1" agents_dir="$2" missing="" f b
    for f in "${agents_dir}"/*.md; do
        [[ -f "$f" ]] || continue
        b="$(command basename "$f" .md)"
        if ! jq -e --arg a "$b" 'has($a)' "$meta" >/dev/null 2>&1; then  # missing key → collect for the die message
            missing="${missing:+${missing}, }${b}"
        fi
    done
    [[ -z "$missing" ]] || rdf_die "agents missing from agent-meta.json: ${missing} — add entries before generating"
    local errors
    errors="$(rdf_agent_routing_errors "$meta" "$agents_dir")"
    [[ -z "$errors" ]] || rdf_die "invalid agent routing in agent-meta.json: ${errors//$'\n'/; }"
}

# rdf_agent_routing_errors META AGENTS_DIR — one line per invalid model, effort,
# or variant in agent-meta.json (empty = valid; a missing model/effort is valid)
rdf_agent_routing_errors() {
    local meta="$1" agents_dir="$2" label field value
    while IFS=$'\t' read -r label field value; do
        case "$field" in
            model)
                case "$value" in
                    opus|sonnet|haiku|fable|inherit) ;;
                    claude-*)
                        case "$value" in
                            *[!a-z0-9.-]*) printf "%s: model '%s' is not a valid model id\n" "$label" "$value" ;;
                        esac
                        ;;
                    *) printf "%s: model '%s' not in opus|sonnet|haiku|fable|inherit or a claude-* id\n" "$label" "$value" ;;
                esac
                ;;
            effort)
                case "$value" in
                    low|medium|high|xhigh|max) ;;
                    *) printf "%s: effort '%s' not in low|medium|high|xhigh|max\n" "$label" "$value" ;;
                esac
                ;;
            variants-type) printf '%s: variants must be an object\n' "$label" ;;
            variant-key)
                case "$value" in
                    ""|[!a-z]*|*[!a-z0-9-]*) printf "%s: variant key '%s' must start with a-z and use only a-z, 0-9, -\n" "$label" "$value" ;;
                    *)
                        if [[ -e "${agents_dir}/${label}-${value}.md" ]]; then
                            printf '%s: variant %s collides with canonical agent %s-%s.md\n' "$label" "$value" "$label" "$value"
                        fi
                        ;;
                esac
                ;;
            variant-noeffort) printf '%s: variant requires effort\n' "$label" ;;
        esac
    done < <(jq -r '
        to_entries[]
        | select((.key | startswith("_") | not) and (.value | type == "object" and has("name")))
        | .key as $k | .value as $v
        | (if ($v | has("model")) then [$k, "model", ($v.model | tostring)] else empty end),
          (if ($v | has("effort")) then [$k, "effort", ($v.effort | tostring)] else empty end),
          (if ($v | has("variants")) then
             (if ($v.variants | type) != "object" then [$k, "variants-type", "-"]
              else ($v.variants | to_entries[]
                    | .key as $vk | .value as $vv
                    | [$k, "variant-key", $vk],
                      (if ($vv | type) != "object" or (($vv | has("effort")) | not)
                       then [($k + "." + $vk), "variant-noeffort", "-"]
                       else [($k + "." + $vk), "effort", ($vv.effort | tostring)],
                            (if ($vv | has("model")) then [($k + "." + $vk), "model", ($vv.model | tostring)] else empty end)
                       end))
              end)
           else empty end)
        | @tsv' "$meta" 2>/dev/null)  # unparseable meta → no rows (the missing-agent check reports it)
}

# rdf_agent_variant_stems META — "<agent>-<variant>" per declared variant
rdf_agent_variant_stems() {
    jq -r 'to_entries[]
        | select((.key | startswith("_") | not) and (.value | type == "object") and ((.value.variants | type) == "object"))
        | .key as $k | .value.variants | keys[] | "\($k)-\(.)"' "$1" 2>/dev/null || true  # absent/unparseable meta → no stems
}

# Working files kept out of git — single source of truth: init writes these,
# doctor checks for exactly these. Keep the two in step by editing only here.
RDF_GIT_EXCLUDE_HEADER="# RDF working files (managed by rdf init)"
RDF_GIT_EXCLUDE_ENTRIES=(
    "CLAUDE.md"
    "PLAN*.md"
    "AUDIT.md"
    "MEMORY.md"
    ".rdf/"
    ".agents/"
)

rdf_die() {
    echo "rdf: error: $*" >&2
    exit 1
}

rdf_warn() {
    echo "rdf: warning: $*" >&2
}

rdf_log() {
    echo "rdf: $*" >&2
}

rdf_require_bin() {
    local bin="$1"
    if ! command -v "$bin" >/dev/null 2>&1; then
        rdf_die "required binary not found: $bin"
    fi
}

rdf_require_file() {
    local file="$1"
    local desc="${2:-file}"
    if [[ ! -f "$file" ]]; then
        rdf_die "$desc not found: $file"
    fi
}

rdf_require_dir() {
    local dir="$1"
    local desc="${2:-directory}"
    if [[ ! -d "$dir" ]]; then
        rdf_die "$desc not found: $dir"
    fi
}

# Profile helpers — used by profile.sh and adapter.sh
RDF_PROFILES_DIR=""
RDF_PROFILES_STATE=""

rdf_profile_init() {
    RDF_PROFILES_DIR="${RDF_HOME}/profiles"
    RDF_PROFILES_STATE="${RDF_HOME}/.rdf-profiles"

    # One-time migration: systems-engineering -> shell (RDF 3.x profile rename)
    if [[ -f "$RDF_PROFILES_STATE" ]]; then
        if grep -q '^systems-engineering$' "$RDF_PROFILES_STATE"; then
            local _mig_tmp
            _mig_tmp="$(mktemp "${RDF_PROFILES_STATE}.XXXXXX")"
            sed 's/^systems-engineering$/shell/' "$RDF_PROFILES_STATE" > "$_mig_tmp" && \
                command mv "$_mig_tmp" "$RDF_PROFILES_STATE"
            rdf_log "migrated profile: systems-engineering -> shell"
        fi
    fi
}

# Get list of active profile names (one per line, core always included)
rdf_get_active_profiles() {
    rdf_profile_init
    echo "core"
    if [[ -f "$RDF_PROFILES_STATE" ]]; then
        while IFS= read -r line; do
            [[ -z "$line" || "$line" == \#* || "$line" == "core" ]] && continue
            echo "$line"
        done < "$RDF_PROFILES_STATE"
    fi
}

# rdf_lite_commands — lifecycle command basenames shipped by rdf-lite
rdf_lite_commands() { printf '%s\n' r-spec r-plan r-build r-ship r-start r-save; }

# rdf_cc_dir_surfaces — ~/.claude directory symlinks owned by rdf deploy (skills are per-entry)
rdf_cc_dir_surfaces() { printf '%s\n' agents scripts governance reference; }
