#!/usr/bin/env bats
# tests/shell.bats — rdf shell init: the rdf function (rdf use, pass-through) and tab completion
# (C) 2026 R-fx Networks <proj@rfxn.com>
# GNU GPL v2
#
# Hermetic: HOME is a mktemp dir; a stub `claude` on PATH prints the env and argv it got.
#
# shellcheck disable=SC2154,SC2164,SC1090,SC1091,SC2016

RDF_SRC="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
export RDF_SRC

setup() {
    exec </dev/null  # a regression that reaches a stub must fail, not wait on inherited stdin
    HOME="$(mktemp -d)"
    export HOME
    unset IS_SANDBOX RDF_CLAUDE_ACCOUNT RDF_ACCOUNT CLAUDE_CONFIG_DIR CODEX_HOME
    mkdir -p "${HOME}/.claude/projects" "${HOME}/bin"
    cat > "${HOME}/bin/claude" <<'STUB'
#!/usr/bin/env bash
args=""
for a in "$@"; do args="${args}${a}|"; done
printf 'CFG=%s ACCT=%s SANDBOX=%s ARGS=%s\n' "${CLAUDE_CONFIG_DIR-unset}" \
    "${RDF_CLAUDE_ACCOUNT-unset}" "${IS_SANDBOX-unset}" "$args"
STUB
    chmod +x "${HOME}/bin/claude"
    PATH="${HOME}/bin:${PATH}"
    bash "${RDF_SRC}/bin/rdf" account add work --primary
    bash "${RDF_SRC}/bin/rdf" account add personal
    P="${HOME}/.claude-personal"
}

teardown() { rm -rf "$HOME" 2>/dev/null || true; }  # cleanup, ignore errors

# _sh script — run script in bash after eval'ing rdf shell init
_sh() { bash -c 'eval "$(bash "$RDF_SRC/bin/rdf" shell init)"; '"$1"; }

# _comp cword word... — run the completion bound to word[0] in bash as bash calls it; print COMPREPLY one per line
_comp() {
    bash -c 'eval "$(bash "$RDF_SRC/bin/rdf" shell init)"; cw="$1"; shift
COMP_WORDS=("$@"); COMP_CWORD="$cw"; COMP_LINE="$*"; COMP_POINT=${#COMP_LINE}
f="$(complete -p "$1" | sed "s/.*-F \([^ ]*\).*/\1/")"; "$f" "$1" "${COMP_WORDS[cw]}" "${COMP_WORDS[cw-1]}"
printf "%s\n" "${COMPREPLY[@]}"' _ "$@"
}

# _tty shell line — type line and TAB into an interactive bash or zsh on a pty; print the edited line
_tty() {
    cat > "${HOME}/tty.py" <<'PY'
import os, pty, re, select, sys, time
shell, line = sys.argv[1], sys.argv[2]
pid, fd = pty.fork()
if pid == 0:
    os.environ.update(PS1='PROMPT> ', TERM='vt100', EDITOR='', VISUAL='')
    argv = ['zsh', '-f', '-i'] if shell == 'zsh' else ['bash', '--norc', '--noprofile', '-i']
    os.execvp(argv[0], argv)
buf = ''
def until(pat, t=15):
    global buf
    end = time.time() + t
    while time.time() < end:
        if select.select([fd], [], [], 0.1)[0]:
            try:
                buf += os.read(fd, 4096).decode(errors='replace')
            except OSError:
                break
        clean = re.sub(r'\x1b\[[0-9;?]*[A-Za-z]|\x1b[=>]|\r', '', buf)
        m = re.findall(pat, clean, re.M)
        if m:
            return m[-1]
    return 'TIMEOUT'
pre = 'autoload -U compinit && compinit -u -D; bindkey -e; ' if shell == 'zsh' else ''
os.write(fd, (pre + 'eval "$(bash "$RDF_SRC/bin/rdf" shell init)"; echo RE""ADY\n').encode())
until(r'^READY$')
os.write(fd, (line + '\t').encode())
time.sleep(1)
os.write(fd, b'\x01echo LI""NE=\x05\n')
print(until(r'^LINE=(.*?)\s*$'))
os.write(fd, b'exit\n')
PY
    python3 -I "${HOME}/tty.py" "$@"
}

@test "init defines only rdf and its _rdf_ completion helpers; never shadows claude or codex" {
    cp "${HOME}/bin/claude" "${HOME}/bin/codex"
    run env -i HOME="$HOME" PATH="$PATH" RDF_SRC="$RDF_SRC" bash -c 'eval "$(bash "$RDF_SRC/bin/rdf" shell init)"
declare -F | cut -d" " -f3 | grep -v "^_rdf_"; type -t claude; type -t codex; complete -p rdf'
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "rdf" ]
    [ "${lines[1]}" = "file" ]
    [ "${lines[2]}" = "file" ]
    [ "${lines[3]}" = "complete -F _rdf_complete rdf" ]
}

@test "rdf passes every command but use to the binary, with its exit status" {
    run _sh 'rdf c @personal -y --fs -c; rdf run claude --chrome; rdf c @nope; echo "rc=$?"; rdf version'
    [ "${lines[0]}" = "CFG=${P} ACCT=personal SANDBOX=unset ARGS=--dangerously-skip-permissions|--fork-session|-c|" ]
    [ "${lines[1]}" = "CFG=unset ACCT=unset SANDBOX=unset ARGS=--chrome|" ]
    [[ "${lines[2]}" == *"unknown account: nope"* ]]
    [ "${lines[3]}" = "rc=2" ]
    [[ "${lines[4]}" == "rdf "* ]]
}

@test "rdf use is sticky over the stored default, @name overrides it, a bad name leaves it, '-' clears it, no name lists" {
    bash "${RDF_SRC}/bin/rdf" account default personal
    run _sh 'rdf c; rdf use work; rdf c; rdf c @personal; rdf use nope; echo "rc=$?"; rdf c; rdf use -; rdf c; rdf use'
    [ "${lines[0]}" = "CFG=${P} ACCT=personal SANDBOX=unset ARGS=" ]
    [ "${lines[1]}" = "CFG=unset ACCT=work SANDBOX=unset ARGS=" ]
    [ "${lines[2]}" = "CFG=${P} ACCT=personal SANDBOX=unset ARGS=" ]
    [[ "${lines[3]}" == *"unknown account: nope"* ]]
    [ "${lines[4]}" = "rc=2" ]
    [ "${lines[5]}" = "CFG=unset ACCT=work SANDBOX=unset ARGS=" ]
    [ "${lines[6]}" = "CFG=${P} ACCT=personal SANDBOX=unset ARGS=" ]
    [[ "$output" == *"personal"*"${P}"* ]]
    run _sh 'rdf use work; rdf use - extra; echo "rc=$? ${RDF_ACCOUNT-unset}"'
    [[ "${lines[0]}" == *"usage: rdf use"* ]]
    [ "${lines[1]}" = "rc=2 work" ]
}

@test "rdf use without the shell function explains how to get it" {
    run bash "${RDF_SRC}/bin/rdf" use work
    [ "$status" -eq 1 ]
    [[ "$output" == *'eval "$(rdf shell init)"'* ]]
}

@test "init replaces an existing rdf alias; --sandbox from 3.9 warns and still inits; other options fail" {
    run bash -c 'shopt -s expand_aliases
alias rdf="echo ALIAS"
eval "$(bash "$RDF_SRC/bin/rdf" shell init)"
rdf c'
    [ "$status" -eq 0 ]
    [ "$output" = "CFG=unset ACCT=unset SANDBOX=unset ARGS=" ]
    run bash -c 'bash "$RDF_SRC/bin/rdf" shell init --sandbox 2>"$HOME/err" | grep -c "^function rdf {"; cat "$HOME/err"'
    [ "${lines[0]}" = "1" ]
    [[ "${lines[1]}" == *"rdf c --root"* ]]
    run bash "${RDF_SRC}/bin/rdf" shell init --bogus
    [ "$status" -ne 0 ]
    run bash -euc 'eval "$(bash "$RDF_SRC/bin/rdf" shell init)"; echo REACHED'
    [ "$output" = "REACHED" ]
}

@test "rdf survives Claude Code's Bash-tool snapshot (functions only, _-prefixed dropped)" {
    bash -c 'eval "$(bash "$RDF_SRC/bin/rdf" shell init)"
for f in $(declare -F | cut -d" " -f3 | grep -vE "^_[^_]"); do declare -f "$f"; done' > "${HOME}/fns.sh"
    run env -i HOME="$HOME" PATH="$PATH" RDF_CLAUDE_ACCOUNT=personal bash -c 'source "$HOME/fns.sh"; rdf c --root; rdf use work; rdf c'
    [ "${lines[0]}" = "CFG=${P} ACCT=personal SANDBOX=1 ARGS=--dangerously-skip-permissions|" ]
    [ "${lines[1]}" = "CFG=unset ACCT=work SANDBOX=unset ARGS=" ]
}

@test "zsh: rdf evals over an alias, launches and uses accounts" {
    command -v zsh >/dev/null || skip "zsh not installed"
    run zsh -c 'alias rdf="echo ALIAS"
eval "$(bash "$RDF_SRC/bin/rdf" shell init)"
rdf c @personal -y --fs
rdf use work; CLAUDE_CONFIG_DIR=/elsewhere rdf c "@src/a.ts hi"'
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "CFG=${P} ACCT=personal SANDBOX=unset ARGS=--dangerously-skip-permissions|--fork-session|" ]
    [ "${lines[1]}" = "CFG=unset ACCT=work SANDBOX=unset ARGS=@src/a.ts hi|" ]
}

@test "bash completion: subcommands, tools, per-tool options, @accounts split or not at @, account names and file names with spaces" {
    run _comp 1 rdf r
    [ "$output" = $'run\nreview\nrefresh' ]
    run _comp 1 rdf u
    [ "$output" = "use" ]
    run _comp 2 rdf run c
    [ "$output" = $'claude\ncodex' ]
    run _comp 3 rdf run claude @p
    [ "$output" = "@personal" ]
    run bash -c 'eval "$(bash "$RDF_SRC/bin/rdf" shell init)"
COMP_WORDS=(rdf c @ p); COMP_CWORD=3; COMP_LINE="rdf c @p"; COMP_POINT=${#COMP_LINE}
_rdf_complete rdf "@p" "c"; printf "%s|" "${COMPREPLY[@]}"; echo
_rdf_complete rdf p @; printf "%s|" "${COMPREPLY[@]}"; echo'
    [ "${lines[0]}" = "@personal|" ]
    [ "${lines[1]}" = "|" ]
    run _comp 2 rdf c @w
    [ "$output" = "@work" ]
    run _comp 3 rdf run codex --
    [ "$output" = $'--yolo\n--sandbox' ]
    run _comp 2 rdf x --
    [ "$output" = $'--yolo\n--sandbox' ]
    run _comp 2 rdf c --
    [ "$output" = $'--yolo\n--root\n--sandbox\n--chrome\n--fs' ]
    run _comp 2 rdf use ""
    [ "$output" = $'work\npersonal\n-' ]
    run _comp 3 rdf use work ""
    [ "$output" = "" ]
    run _comp 3 rdf account default ""
    [ "$output" = $'work\npersonal\n-' ]
    run _comp 3 rdf tokens --by ""
    [ "$output" = $'day\nweek\nmonth\nsession\nproject' ]
    run _comp 3 rdf review --effort h
    [ "$output" = "high" ]
    mkdir -p "${HOME}/w" && : > "${HOME}/w/my prompt.md"
    run bash -c 'cd "$HOME/w" || exit 1; eval "$(bash "$RDF_SRC/bin/rdf" shell init)"
COMP_WORDS=(rdf review -f my); COMP_CWORD=3; _rdf_complete; printf "%s|" "${COMPREPLY[@]}"'
    [ "$output" = "my prompt.md|" ]
}

@test "a real terminal completes @accounts in place: rdf c @p<TAB> keeps the @ (bash, and zsh when installed)" {
    command -v python3 >/dev/null || skip "python3 not installed"
    run _tty bash 'rdf c @p'
    [ "$output" = "rdf c @personal" ]
    run _tty bash 'rdf run claude @w'
    [ "$output" = "rdf run claude @work" ]
    run _tty bash 'rdf use p'
    [ "$output" = "rdf use personal" ]
    run _tty bash 'rdf c @ p'
    [ "$output" = "rdf c @ p" ]
    if command -v zsh >/dev/null; then
        run _tty zsh 'rdf c @p'
        [ "$output" = "rdf c @personal" ]
        run _tty zsh 'rdf use p'
        [ "$output" = "rdf use personal" ]
    fi
}

@test "zsh completion: bashcompinit's 1-based COMP_WORDS completes the current word" {
    command -v zsh >/dev/null || skip "zsh not installed"
    run zsh -fc 'autoload -U compinit && compinit -u -D
eval "$(bash "$RDF_SRC/bin/rdf" shell init)"
COMP_WORDS=(rdf r); COMP_CWORD=1; _rdf_complete; print -r -- "${COMPREPLY[*]}"
COMP_WORDS=(rdf c @p); COMP_CWORD=2; _rdf_complete; print -r -- "${COMPREPLY[*]}"
COMP_WORDS=(rdf account dir ""); COMP_CWORD=3; _rdf_complete; print -r -- "${COMPREPLY[*]}"'
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "run review refresh" ]
    [ "${lines[1]}" = "@personal" ]
    [ "${lines[2]}" = "work personal --codex" ]
}
