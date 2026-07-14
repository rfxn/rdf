#!/usr/bin/env bash
# adapters/claude-plugin/adapter.sh — Claude Code plugin adapter
# (C) 2026 R-fx Networks <proj@rfxn.com>
# GNU GPL v2
# Sourced by lib/cmd/generate.sh — do not execute directly

# Requires: RDF_HOME, RDF_CANONICAL, RDF_ADAPTERS, RDF_VERSION, jq

_CPL_ADAPTER_DIR="${RDF_ADAPTERS}/claude-plugin"
_CPL_OUTPUT_DIR="${_CPL_ADAPTER_DIR}/output"

# Rewrite /r-NAME cross-references to /rdf:r-NAME in a command body.
# Plugin commands are always namespaced by the loader; unrewritten
# references would point at commands that do not exist in plugin installs.
# Boundary rules: leading context is line start or one of space/tab,
# backtick, (, |, ", ', *; trailing boundary is EOL or any char outside
# [a-z-]. Names are applied longest-first so /r-example-extra rewrites
# before /r-example can partially match. POSIX BRE only (macOS CI).
# Args: $1 = src file, $2 = dst file
_cpl_rewrite_namespace() {
    local src="$1"
    local dst="$2"
    local sed_args=()
    local name
    while IFS= read -r name; do
        [[ -z "$name" ]] && continue
        sed_args+=(-e "s#^/${name}\$#/rdf:${name}#")
        sed_args+=(-e "s#^/${name}\([^a-z-]\)#/rdf:${name}\1#")
        sed_args+=(-e "s#\([[:space:]\`(|\"'*]\)/${name}\$#\1/rdf:${name}#")
        sed_args+=(-e "s#\([[:space:]\`(|\"'*]\)/${name}\([^a-z-]\)#\1/rdf:${name}\2#g")
    done < <(_cpl_command_names_longest_first)
    sed "${sed_args[@]}" "$src" > "$dst"
}

# Emit canonical command basenames (no .md), longest name first.
_cpl_command_names_longest_first() {
    local f b
    for f in "${RDF_CANONICAL}/commands"/*.md; do
        [[ -f "$f" ]] || continue
        b="$(basename "$f" .md)"
        printf '%d %s\n' "${#b}" "$b"
    done | sort -rn | cut -d' ' -f2-
}

# Generate plugin command files: canonical/commands/*.md -> output/commands/
# with namespace rewrite. No .rdf-hash sidecars — strict plugin validation
# rejects non-component files in the commands dir.
cpl_generate_commands() {
    local src_dir="${RDF_CANONICAL}/commands"
    local dst_dir="${_CPL_OUTPUT_DIR}/commands"
    local count=0

    command mkdir -p "$dst_dir"

    for src_file in "${src_dir}"/*.md; do
        [[ -f "$src_file" ]] || continue
        local basename_f
        basename_f="$(basename "$src_file")"
        _cpl_rewrite_namespace "$src_file" "${dst_dir}/${basename_f}"
        count=$((count + 1))
    done
    rdf_log "generated ${count} command files (namespace-rewritten)"
}

# Full plugin generation pipeline
cpl_generate_all() {
    rdf_log "generating Claude Plugin adapter output..."
    rdf_require_dir "$RDF_CANONICAL" "canonical directory"
    rdf_require_bin jq

    local _output_final="$_CPL_OUTPUT_DIR"
    local _output_new="${_CPL_OUTPUT_DIR}.new"
    local _output_old="${_CPL_OUTPUT_DIR}.old"

    # Build into staging directory, then atomic swap (cc adapter pattern)
    command rm -rf "$_output_new"
    command mkdir -p "$_output_new"
    _CPL_OUTPUT_DIR="$_output_new"

    cpl_generate_commands

    _CPL_OUTPUT_DIR="$_output_final"
    command rm -rf "$_output_old"
    if [[ -d "$_output_final" ]]; then
        command mv "$_output_final" "$_output_old"
    fi
    command mv "$_output_new" "$_output_final"
    command rm -rf "$_output_old"

    local command_count
    command_count="$(find "${_CPL_OUTPUT_DIR}/commands" -name '*.md' 2>/dev/null | wc -l)"  # dir may not exist on partial generation

    rdf_log "plugin generation complete: ${command_count} commands"
}
