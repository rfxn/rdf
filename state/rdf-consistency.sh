#!/usr/bin/env bash
# state/rdf-consistency.sh — deterministic spec↔plan↔tasks cross-check
# (C) 2026 R-fx Networks <proj@rfxn.com>
# GNU GPL v2
#
# Provides: check [--warn-only] <plan-path> [spec-path]. Pure bash string
# parsing — no eval, no jq, POSIX sed only. Exit 0 clean / 1 warnings /
# 2 structural break. --warn-only downgrades structural errors (exit 2) to
# warnings (exit 1). Sourced by /r-build Section 1.
set -euo pipefail

RDF_CONSISTENCY_HOME="$(cd "$(command dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 1
NL=$'\n'

_usage() { printf 'usage: rdf-consistency.sh check [--warn-only] <plan-path> [spec-path]\n' >&2; }

# _add_unique <var> <value> — append value to a newline-delimited string var, skipping dups
_add_unique() {
    local __name="$1" __val="$2" __cur="${!1}"
    case "${NL}${__cur}${NL}" in
        *"${NL}${__val}${NL}"*) return 0 ;;
    esac
    printf -v "$__name" '%s' "${__cur:+${__cur}${NL}}${__val}"
}

# _contains <value> <newline-list> — 0 if value is a member
_contains() {
    case "${NL}${2}${NL}" in
        *"${NL}${1}${NL}"*) return 0 ;;
    esac
    return 1
}

# _count <newline-list> — echo the number of non-empty entries
_count() {
    local __l="$1" __n=0 __x
    [[ -n "$__l" ]] || { printf '0'; return 0; }
    while IFS= read -r __x; do [[ -n "$__x" ]] && __n=$((__n + 1)); done <<< "$__l"
    printf '%s' "$__n"
}

# _first_backtick <line> — echo the first backtick-quoted group's content (File-Map path column)
_first_backtick() {
    local s="$1"
    case "$s" in *'`'*) ;; *) return 0 ;; esac
    s="${s#*\`}"
    printf '%s' "${s%%\`*}"
}

# _harvest_files_line <line> <accumulator-var> — append every backtick group on a
# phase Files line (multi-path, M2), after stripping the trailing " (prose)" tail
_harvest_files_line() {
    local rest="${1#*:}" __acc="$2" p
    rest="${rest%% (*}"           # M4: paths never follow a parenthetical — drop the prose tail
    while [[ "$rest" == *'`'* ]]; do
        rest="${rest#*\`}"; p="${rest%%\`*}"; rest="${rest#*\`}"
        [[ -n "$p" ]] && _add_unique "$__acc" "$p"
    done
}

# _parse_spec_goals <spec> — echo each numbered goal under "## 2. Goals", one per line
_parse_spec_goals() {
    local spec="$1" in_goals=0 line
    local re_goals_head='^##[[:space:]]*2\.[[:space:]]*Goals'
    local re_h2='^##[[:space:]]'
    local re_num='^([0-9]+)\.[[:space:]]'
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ $re_goals_head ]]; then in_goals=1; continue; fi
        if [[ $in_goals -eq 1 && "$line" =~ $re_h2 ]]; then break; fi
        if [[ $in_goals -eq 1 && "$line" =~ $re_num ]]; then printf '%s\n' "${BASH_REMATCH[1]}"; fi
    done < "$spec"
}

_check() {
    local warn_only=0
    if [[ "${1:-}" == "--warn-only" ]]; then warn_only=1; shift; fi
    local plan="${1:-}" spec="${2:-}"

    if [[ -z "$plan" ]]; then
        # shellcheck source=/dev/null
        source "${RDF_CONSISTENCY_HOME}/rdf-bus.sh"
        plan="$(rdf_active_plan_path)" || plan=""   # 1 = no active plan resolved
    fi
    if [[ -z "$plan" || ! -f "$plan" ]]; then
        printf 'rdf-consistency: plan not found: %s\n' "$plan" >&2
        return 2
    fi

    local declared_phases="" tier="" phase_count=0
    local in_filemap=0 in_phase=0 cur_has_goals=0 phases_missing_goals=0 has_edge_field=0
    local fm_list="" ph_list="" goal_union="" line
    local re_phases='^\*\*Phases:\*\*[[:space:]]+([0-9]+)'
    local re_tier='^\*\*Tier:\*\*[[:space:]]+([a-z-]+)'
    local re_h2='^##[[:space:]]'
    local re_sep='^\|[[:space:]]*:?-+'
    local re_phase='^###[[:space:]]Phase[[:space:]]([0-9]+):'
    local re_files_field='^\*\*Files:\*\*'
    local re_files_bullet='^-[[:space:]](Create|Modify|Delete):'
    local re_goals='\*\*Goals:\*\*[[:space:]]*([0-9,[:space:]]+)'
    local re_edge='\*\*Edge cases\*\*'
    local p g nums

    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$declared_phases" && "$line" =~ $re_phases ]] && declared_phases="${BASH_REMATCH[1]}"
        [[ -z "$tier" && "$line" =~ $re_tier ]] && tier="${BASH_REMATCH[1]}"

        if [[ "$line" == "## File Map"* ]]; then in_filemap=1; continue; fi
        if [[ $in_filemap -eq 1 && "$line" =~ $re_h2 ]]; then in_filemap=0; fi
        if [[ $in_filemap -eq 1 && "$line" == '|'* ]]; then
            if [[ ! "$line" =~ $re_sep ]]; then
                p="$(_first_backtick "$line")"
                [[ -n "$p" ]] && _add_unique fm_list "$p"
            fi
            continue
        fi

        if [[ "$line" =~ $re_phase ]]; then
            [[ $in_phase -eq 1 && $cur_has_goals -eq 0 ]] && phases_missing_goals=$((phases_missing_goals + 1))
            in_phase=1; cur_has_goals=0; phase_count=$((phase_count + 1)); continue
        fi
        if [[ $in_phase -eq 1 && "$line" =~ $re_h2 ]]; then
            [[ $cur_has_goals -eq 0 ]] && phases_missing_goals=$((phases_missing_goals + 1))
            in_phase=0
        fi

        if [[ $in_phase -eq 1 ]]; then
            if [[ "$line" =~ $re_files_field || "$line" =~ $re_files_bullet ]]; then
                _harvest_files_line "$line" ph_list
            fi
            if [[ "$line" =~ $re_goals ]]; then
                cur_has_goals=1
                nums="${BASH_REMATCH[1]//,/ }"
                for g in $nums; do
                    [[ "$g" =~ ^[0-9]+$ ]] && _add_unique goal_union "$g"
                done
            fi
            [[ "$line" =~ $re_edge ]] && has_edge_field=1
        fi
    done < "$plan"
    [[ $in_phase -eq 1 && $cur_has_goals -eq 0 ]] && phases_missing_goals=$((phases_missing_goals + 1))

    local errors="" warns="" oks=""
    local fm_total covered=0 uncovered_fm="" extra_ph=""

    if [[ -z "$fm_list" ]]; then
        # No File Map section: nothing to compare against — plan-schema does not
        # mandate one, and historical hand-authored plans lack it. Skip the
        # structural comparison (mirrors the no-spec graceful skip).
        _add_unique oks "No File Map section — coverage comparison skipped"
        ph_list=""
    fi

    while IFS= read -r p; do
        [[ -n "$p" ]] || continue
        if _contains "$p" "$ph_list"; then covered=$((covered + 1)); else _add_unique uncovered_fm "$p"; fi
    done <<< "$fm_list"
    while IFS= read -r p; do
        [[ -n "$p" ]] || continue
        _contains "$p" "$fm_list" || _add_unique extra_ph "$p"
    done <<< "$ph_list"

    fm_total="$(_count "$fm_list")"
    if [[ -z "$uncovered_fm" && -z "$extra_ph" ]]; then
        _add_unique oks "File Map ↔ phases: ${covered}/${fm_total} files covered"
    else
        while IFS= read -r p; do
            [[ -n "$p" ]] && _add_unique errors "File Map lists \`${p}\` — no phase touches it"
        done <<< "$uncovered_fm"
        while IFS= read -r p; do
            [[ -n "$p" ]] && _add_unique errors "Phase file \`${p}\` is not in the File Map"
        done <<< "$extra_ph"
    fi

    if [[ -n "$declared_phases" ]]; then
        if [[ "$declared_phases" -ne "$phase_count" ]]; then
            _add_unique errors "Phase count: ${phase_count} headings != **Phases:** ${declared_phases}"
        else
            _add_unique oks "Phase count: ${phase_count} headings == **Phases:** ${declared_phases}"
        fi
    fi

    if [[ -n "$spec" && -f "$spec" ]]; then
        while IFS= read -r g; do
            [[ -n "$g" ]] || continue
            _contains "$g" "$goal_union" || _add_unique warns "Goal coverage: spec Goal ${g} is not referenced by any phase **Goals:** field"
        done <<< "$(_parse_spec_goals "$spec")"
        if grep -qiE '^#+[[:space:]].*[Ee]dge [Cc]ase' "$spec" 2>/dev/null && [[ $has_edge_field -eq 0 ]]; then  # spec defines edge cases but no phase field
            _add_unique warns "Edge coverage: spec defines edge cases but no phase carries an **Edge cases** field"
        fi
    fi

    [[ $phases_missing_goals -gt 0 ]] && _add_unique warns "Goals field: ${phases_missing_goals} phase(s) omit the **Goals:** field"
    if [[ "$tier" == "bugfix" && $phase_count -gt 2 ]]; then
        _add_unique warns "Tier sanity: bugfix plan has ${phase_count} phases (expected <= 2)"
    elif [[ "$tier" == "quick-plan" && $phase_count -gt 6 ]]; then
        _add_unique warns "Tier sanity: quick-plan plan has ${phase_count} phases (expected <= 6)"
    fi

    if [[ $warn_only -eq 1 && -n "$errors" ]]; then
        while IFS= read -r p; do [[ -n "$p" ]] && _add_unique warns "$p"; done <<< "$errors"
        errors=""
    fi

    while IFS= read -r p; do [[ -n "$p" ]] && printf '  \342\234\223 %s\n' "$p"; done <<< "$oks"
    while IFS= read -r p; do [[ -n "$p" ]] && printf '  \342\232\240 %s\n' "$p"; done <<< "$warns"
    while IFS= read -r p; do [[ -n "$p" ]] && printf '  \342\234\227 %s\n' "$p"; done <<< "$errors"

    [[ -n "$errors" ]] && return 2
    [[ -n "$warns" ]] && return 1
    return 0
}

main() {
    [[ $# -ge 1 ]] || { _usage; exit 2; }
    local sub="$1"; shift
    case "$sub" in
        check) _check "$@" ;;
        *) _usage; exit 2 ;;
    esac
}

main "$@"
