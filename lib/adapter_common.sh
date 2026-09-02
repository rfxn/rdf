#!/usr/bin/env bash
# lib/adapter_common.sh — shared adapter emitters (agents, skills, scripts, reference, staging)
# (C) 2026 R-fx Networks <proj@rfxn.com>
# GNU GPL v2
# Sourced by lib/cmd/generate.sh before any adapter — do not execute directly

[[ -n "${_RDF_ADAPTER_COMMON_LOADED:-}" ]] && return 0 2>/dev/null  # not-sourced-as-function context is a non-error return
_RDF_ADAPTER_COMMON_LOADED=1

# adp_require_hash_tool — die when no sha256sum/shasum/sha1sum is on PATH.
# Hashing itself goes through rdf_hash_stdin (portable across GNU/macOS/BSD).
adp_require_hash_tool() {
    if ! command -v sha256sum >/dev/null 2>&1 \
        && ! command -v shasum >/dev/null 2>&1 \
        && ! command -v sha1sum >/dev/null 2>&1; then
        rdf_die "no SHA tool found (need sha256sum, shasum, or sha1sum) — cannot generate .rdf-hash sidecars"
    fi
}

# adp_write_hash_sidecar canonical_src dst — write dst.rdf-hash with the hash
# of the canonical body, so doctor can re-derive the same value from canonical/.
adp_write_hash_sidecar() {
    local src="$1" dst="$2" hash
    hash="$(rdf_hash_stdin < "$src")"
    printf '%s\n' "$hash" > "${dst}.rdf-hash"
}

# adp_agent_frontmatter meta agent — YAML frontmatter (name, description,
# tools, disallowedTools, model) from an agent-meta.json entry. rc 1 + warn
# when the agent is absent from meta — caller falls back to a plain copy.
adp_agent_frontmatter() {
    local meta="$1" agent="$2"
    local name desc model tools_json disallowed_json

    if ! jq -e --arg a "$agent" '.[$a]' "$meta" >/dev/null 2>&1; then  # missing entry = signal caller to plain-copy
        rdf_warn "no metadata for agent: $agent — copying without frontmatter"
        return 1
    fi

    name="$(jq -r --arg a "$agent" '.[$a].name' "$meta")"
    desc="$(jq -r --arg a "$agent" '.[$a].description' "$meta")"
    model="$(jq -r --arg a "$agent" '.[$a].model' "$meta")"
    tools_json="$(jq -c --arg a "$agent" '.[$a].tools // []' "$meta")"
    disallowed_json="$(jq -c --arg a "$agent" '.[$a].disallowedTools // []' "$meta")"

    echo "---"
    echo "name: ${name}"
    echo "description: >"
    echo "  ${desc}"

    if [[ "$tools_json" != "[]" ]]; then
        echo "tools:"
        jq -r '.[]' <<< "$tools_json" | while IFS= read -r tool; do
            echo "  - ${tool}"
        done
    fi

    if [[ "$disallowed_json" != "[]" ]]; then
        echo "disallowedTools:"
        jq -r '.[]' <<< "$disallowed_json" | while IFS= read -r tool; do
            echo "  - ${tool}"
        done
    fi

    echo "model: ${model}"
    echo "---"
}

# adp_emit_agents src_dir dst_dir meta filter_fn sidecar — frontmatter +
# filtered body per canonical agent; plain copy (through the same filter)
# when meta lacks the agent, with a warning; optional .rdf-hash sidecar.
# filter_fn "-" means stream the body unfiltered.
adp_emit_agents() {
    local src_dir="$1" dst_dir="$2" meta="$3" filter_fn="$4" sidecar="$5"
    local src_file count=0

    command mkdir -p "$dst_dir"

    for src_file in "${src_dir}"/*.md; do
        [[ -f "$src_file" ]] || continue
        local basename_f dst_file
        basename_f="$(basename "$src_file" .md)"
        dst_file="${dst_dir}/${basename_f}.md"

        if adp_agent_frontmatter "$meta" "$basename_f" > "${dst_file}.tmp" 2>/dev/null; then  # also swallows the missing-meta warn — matches 3.6.5
            echo "" >> "${dst_file}.tmp"
            if [[ "$filter_fn" == "-" ]]; then
                command cat "$src_file" >> "${dst_file}.tmp"
            else
                "$filter_fn" < "$src_file" >> "${dst_file}.tmp"
            fi
            command mv "${dst_file}.tmp" "$dst_file"
        else
            if [[ "$filter_fn" == "-" ]]; then
                command cp "$src_file" "$dst_file"
            else
                "$filter_fn" < "$src_file" > "$dst_file"
            fi
            command rm -f "${dst_file}.tmp"
        fi

        [[ "$sidecar" -eq 1 ]] && adp_write_hash_sidecar "$src_file" "$dst_file"
        count=$((count + 1))
    done
    rdf_log "generated ${count} agent files"
}

# adp_skill_description name src meta — echo the intent-trigger description:
# skill-meta.json[name] -> first non-heading line of src -> "RDF command: name".
adp_skill_description() {
    local name="$1" src="$2" meta="$3" desc
    desc="$(jq -r --arg c "$name" '.[$c] // empty' "$meta" 2>/dev/null || true)"  # missing key/file → empty, falls back to body
    if [[ -z "$desc" ]]; then
        desc="$(sed -n '/^[^#[:space:]]/{ s/[[:space:]]*$//; p; q; }' "$src")"
        [[ -z "$desc" ]] && desc="RDF command: ${name}"
    fi
    printf '%s' "$desc"
}

# adp_copy_scripts src_dir dst_dir — copy *.sh, chmod +x, log count.
adp_copy_scripts() {
    local src_dir="$1" dst_dir="$2"
    local src_file count=0

    command mkdir -p "$dst_dir"

    for src_file in "${src_dir}"/*.sh; do
        [[ -f "$src_file" ]] || continue
        local basename_f
        basename_f="$(basename "$src_file")"
        command cp "$src_file" "${dst_dir}/${basename_f}"
        command chmod +x "${dst_dir}/${basename_f}"
        count=$((count + 1))
    done
    rdf_log "generated ${count} script files"
}

# adp_copy_reference src_dir dst_dir sidecar [label] — copy *.md, optional
# .rdf-hash sidecars; label distinguishes the log line from a sibling copy.
adp_copy_reference() {
    local src_dir="$1" dst_dir="$2" sidecar="$3" label="${4:-}"
    local src_file count=0

    command mkdir -p "$dst_dir"

    for src_file in "${src_dir}"/*.md; do
        [[ -f "$src_file" ]] || continue
        local basename_f
        basename_f="$(basename "$src_file")"
        command cp "$src_file" "${dst_dir}/${basename_f}"
        [[ "$sidecar" -eq 1 ]] && adp_write_hash_sidecar "$src_file" "${dst_dir}/${basename_f}"
        count=$((count + 1))
    done
    rdf_log "generated ${count} reference docs${label:+ (${label})}"
}

# adp_names_all src_dir [meta] — all canonical command basenames, one per line.
# meta is accepted-and-ignored so callers can pass a uniform (src_dir, meta)
# pair to any names_fn (see adp_emit_skills).
adp_names_all() {
    local src_dir="$1" f b
    for f in "${src_dir}"/*.md; do
        [[ -f "$f" ]] || continue
        b="$(basename "$f" .md)"
        printf '%s\n' "$b"
    done
}

# adp_names_lite src_dir [meta] — adp_names_all intersected with rdf_lite_commands.
adp_names_lite() {
    local src_dir="$1" lite name
    lite="$(rdf_lite_commands)"
    while IFS= read -r name; do
        if printf '%s\n' "$lite" | grep -qx "$name"; then
            printf '%s\n' "$name"
        fi
    done < <(adp_names_all "$src_dir")
}

# adp_names_from_meta src_dir meta — non-_comment keys of meta, one per line.
# src_dir is accepted-and-ignored (uniform names_fn pair — see adp_names_all).
adp_names_from_meta() {
    local meta="$2"
    jq -r 'keys[] | select(. != "_comment")' "$meta"
}

# adp_emit_skills src_dir skills_root meta filter_fn sidecar names_fn ref_src —
# write <skills_root>/<name>/SKILL.md (name/description frontmatter + filtered
# body) for every name from "$names_fn" src_dir meta; optional .rdf-hash
# sidecar; copies ref_src into <skills_root>/reference ("-" skips the copy).
adp_emit_skills() {
    local src_dir="$1" skills_root="$2" meta="$3" filter_fn="$4" sidecar="$5" names_fn="$6" ref_src="$7"
    local name src desc count=0

    while IFS= read -r name; do
        [[ -z "$name" ]] && continue
        src="${src_dir}/${name}.md"
        if [[ ! -f "$src" ]]; then
            rdf_warn "no canonical command for skill '${name}' — skipped (${skills_root})"
            continue
        fi

        desc="$(adp_skill_description "$name" "$src" "$meta")"
        [[ "$filter_fn" != "-" ]] && desc="$(printf '%s\n' "$desc" | "$filter_fn")"

        command mkdir -p "${skills_root}/${name}"
        {
            echo "---"
            echo "name: ${name}"
            echo "description: >"
            echo "  ${desc}"
            echo "---"
            echo ""
            if [[ "$filter_fn" == "-" ]]; then
                command cat "$src"
            else
                "$filter_fn" < "$src"
            fi
        } > "${skills_root}/${name}/SKILL.md"

        [[ "$sidecar" -eq 1 ]] && adp_write_hash_sidecar "$src" "${skills_root}/${name}/SKILL.md"
        count=$((count + 1))
    done < <("$names_fn" "$src_dir" "$meta")

    [[ "$ref_src" != "-" ]] && adp_copy_reference "$ref_src" "${skills_root}/reference" "$sidecar" "skills tree"
    rdf_log "generated ${count} skills"
}

# adp_stage_begin final_dir — rm -rf + mkdir a fresh <final>.new staging dir; echoes its path.
adp_stage_begin() {
    local final_dir="$1" staging_dir="${1}.new"
    command rm -rf "$staging_dir"
    command mkdir -p "$staging_dir"
    printf '%s\n' "$staging_dir"
}

# adp_stage_commit final_dir staging_dir — atomic swap: rotate final -> .old,
# move staging -> final, drop .old.
adp_stage_commit() {
    local final_dir="$1" staging_dir="$2" old_dir="${1}.old"
    command rm -rf "$old_dir"
    if [[ -d "$final_dir" ]]; then
        command mv "$final_dir" "$old_dir"
    fi
    command mv "$staging_dir" "$final_dir"
    command rm -rf "$old_dir"
}

# adp_count dir glob — portable find-count; a missing dir counts as 0.
adp_count() {
    { find "$1" -name "$2" 2>/dev/null || true; } | wc -l  # dir may not exist on partial generation; find's rc must not trip the caller's pipefail
}
