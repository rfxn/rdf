#!/usr/bin/env bats
# tests/worktree-hook.bats — phase-branch scope guard in a consumer-project layout
# (C) 2026 R-fx Networks <proj@rfxn.com>
# GNU GPL v2
# shellcheck disable=SC2016  # literal $ in bash -c programs and generated hook bodies

RDF_SRC="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SID="0199aaaa-bbbb-7ccc-8ddd-eeeeeeeeeeee"
INCLUDE_KEY='includeIf.onbranch:rdf/phase-**.path'

# _git args — git with a throwaway identity (HOME is a sandbox, so no global config)
_git() {
    git -c user.email=t@t -c user.name=t "$@"
}

# _make_repo dir — consumer repo: no state/, a committed plan, a main-root session pointer
_make_repo() {
    local repo="$1"
    mkdir -p "$repo/src" "$repo/docs/plans"
    git -C "$repo" init -q
    git -C "$repo" symbolic-ref HEAD refs/heads/main
    printf 'echo a\n' > "$repo/src/a.sh"
    printf 'readme\n' > "$repo/README.md"
    printf '### Phase 1: thing\n\n**Files:**\n- Modify: `src/a.sh`\n- Modify: `README.md`\n' > "$repo/docs/plans/p.md"
    printf '.rdf/\n.worktrees/\n.husky/\n' >> "$repo/.git/info/exclude"
    _git -C "$repo" add src/a.sh README.md docs/plans/p.md
    _git -C "$repo" commit -q -m init
    mkdir -p "$repo/.rdf"
    printf '%s\n' "$repo/docs/plans/p.md" > "$repo/.rdf/active-plan-${SID}"
}

# _install [dir] — source the deployed bus in a child shell and install into dir's repo
_install() {
    bash -c 'source "$1" && rdf_phase_hook_install "$2"' _ "${HOME}/.rdf/state/rdf-bus.sh" "${1:-$REPO}"
}

# _uninstall [dir]
_uninstall() {
    bash -c 'source "$1" && rdf_phase_hook_uninstall "$2"' _ "${HOME}/.rdf/state/rdf-bus.sh" "${1:-$REPO}"
}

# _phase_wt [branch] — linked worktree on a phase branch; sets WT
_phase_wt() {
    local br="${1:-rdf/phase-1-${SID}}"
    WT="${REPO}/.worktrees/phase"
    git -C "$REPO" worktree add -q "$WT" -b "$br" HEAD
}

# _prior_hook name body — executable hook in the repo's default hooks dir
_prior_hook() {
    printf '#!/usr/bin/env bash\n%s\n' "$2" > "${REPO}/.git/hooks/$1"
    chmod +x "${REPO}/.git/hooks/$1"
}

setup() {
    SANDBOX="$(mktemp -d)"
    export HOME="${SANDBOX}/home"
    mkdir -p "${HOME}/.rdf/state/git-hooks"
    cp "$RDF_SRC/state/rdf-bus.sh" "${HOME}/.rdf/state/"
    cp "$RDF_SRC/state/git-hooks/pre-commit" "${HOME}/.rdf/state/git-hooks/"
    unset CLAUDE_CODE_SESSION_ID RDF_SESSION_ID
    export GIT_CONFIG_NOSYSTEM=1
    MARK="${SANDBOX}/marks"
    export MARK
    REPO="${SANDBOX}/café/app"   # non-ASCII path: git C-quotes it in non -z config output
    _make_repo "$REPO"
}

teardown() {
    rm -rf "$SANDBOX"
}

@test "install writes the onbranch include; main and feature worktrees keep their hooks path" {
    run _install
    [ "$status" -eq 0 ]
    [ "$(git -C "$REPO" config --get "$INCLUDE_KEY")" = "rdf-hooks.inc" ]
    _phase_wt
    [[ "$(git -C "$WT" rev-parse --git-path hooks)" == */.git/rdf-hooks ]]
    [[ "$(git -C "$REPO" rev-parse --git-path hooks)" == *.git/hooks ]]
    git -C "$REPO" worktree add -q "${REPO}/.worktrees/feat" -b feature/x HEAD
    [[ "$(git -C "${REPO}/.worktrees/feat" rev-parse --git-path hooks)" == */.git/hooks ]]
}

@test "consumer: out-of-scope commit on a phase branch is rejected" {
    _install
    _phase_wt
    printf 'x\n' > "$WT/outside.txt"
    git -C "$WT" add outside.txt
    run _git -C "$WT" commit -q -m oob
    [ "$status" -ne 0 ]
    [[ "$output" == *"SCOPE VIOLATION"* ]]
    [[ "$output" == *"outside.txt"* ]]
}

@test "consumer: in-scope commit on a phase branch succeeds" {
    _install
    _phase_wt
    printf 'echo b\n' >> "$WT/src/a.sh"
    git -C "$WT" add src/a.sh
    run _git -C "$WT" commit -q -m ok
    [ "$status" -eq 0 ]
}

@test "consumer: session id comes from the branch with no session env" {
    _install
    _phase_wt
    printf 'x\n' > "$WT/outside.txt"
    git -C "$WT" add outside.txt
    # A different ambient session id must not hide the branch's plan pointer.
    run env CLAUDE_CODE_SESSION_ID=0199ffff-ffff-7fff-8fff-ffffffffffff \
        git -c user.email=t@t -c user.name=t -C "$WT" commit -q -m oob
    [ "$status" -ne 0 ]
    [[ "$output" == *"SCOPE VIOLATION"* ]]
}

@test "worktree-local plan pointer takes precedence over the main-root pointer" {
    _install
    _phase_wt
    mkdir -p "$WT/.rdf"
    printf '### Phase 1: other\n\n**Files:**\n- Create: `other.txt`\n' > "$WT/local-plan.md"
    printf '%s\n' "$WT/local-plan.md" > "$WT/.rdf/active-plan-${SID}"
    printf 'x\n' > "$WT/other.txt"
    git -C "$WT" add other.txt
    run _git -C "$WT" commit -q -m local
    [ "$status" -eq 0 ]
}

@test "main-root session pointer outranks a stale committed PLAN.md in the worktree" {
    printf '### Phase 9: stale\n\n**Files:**\n- Modify: `nothing.txt`\n' > "$REPO/PLAN.md"
    _git -C "$REPO" add PLAN.md
    _git -C "$REPO" commit -q -m legacy
    _install
    _phase_wt
    printf 'echo b\n' >> "$WT/src/a.sh"
    git -C "$WT" add src/a.sh
    run _git -C "$WT" commit -q -m ok
    [ "$status" -eq 0 ]
}

@test "in-scope files with non-ASCII and quote characters in their names are accepted" {
    printf '### Phase 1: names\n\n**Files:**\n- Create: `docs/café.md`\n- Create: `docs/q"uote.md`\n' > "$REPO/docs/plans/p.md"
    _git -C "$REPO" add docs/plans/p.md
    _git -C "$REPO" commit -q -m names
    _install
    _phase_wt
    mkdir -p "$WT/docs"
    printf 'x\n' > "$WT/docs/café.md"
    printf 'y\n' > "$WT/docs/q\"uote.md"
    git -C "$WT" add docs
    run _git -C "$WT" commit -q -m names
    [ "$status" -eq 0 ]
}

@test "a file whose name embeds a newline between declared paths is rejected" {
    _install
    _phase_wt
    printf 'x\n' > "$WT/src/a.sh"$'\n'"README.md"
    git -C "$WT" add -- "src/a.sh"$'\n'"README.md"
    run _git -C "$WT" commit -q -m newline
    [ "$status" -ne 0 ]
    [[ "$output" == *"SCOPE VIOLATION"* ]]
}

@test "phase branch with a non-SID suffix is still enforced" {
    _install
    _phase_wt "rdf/phase-1-a.b"
    printf 'x\n' > "$WT/outside.txt"
    git -C "$WT" add outside.txt
    run env RDF_SESSION_ID="$SID" git -c user.email=t@t -c user.name=t -C "$WT" commit -q -m oob
    [ "$status" -ne 0 ]
    [[ "$output" == *"SCOPE VIOLATION"* ]]
}

@test "prior pre-commit runs after RDF passes and its failure blocks the commit" {
    _prior_hook pre-commit 'echo pre >> "$MARK"; exit 1'
    _install
    _phase_wt
    printf 'echo b\n' >> "$WT/src/a.sh"
    git -C "$WT" add src/a.sh
    run _git -C "$WT" commit -q -m ok
    [ "$status" -ne 0 ]
    [ "$(grep -c pre "$MARK")" -eq 1 ]
}

@test "prior pre-commit does not run when RDF rejects" {
    _prior_hook pre-commit 'echo pre >> "$MARK"'
    _install
    _phase_wt
    printf 'x\n' > "$WT/outside.txt"
    git -C "$WT" add outside.txt
    run _git -C "$WT" commit -q -m oob
    [ "$status" -ne 0 ]
    [ ! -e "$MARK" ]
}

@test "other prior hooks run through the passthrough (commit-msg), including from a non-ASCII repo path" {
    _prior_hook commit-msg 'echo "msg $(head -1 "$1")" >> "$MARK"'
    _install
    _phase_wt
    printf 'echo b\n' >> "$WT/src/a.sh"
    git -C "$WT" add src/a.sh
    run _git -C "$WT" commit -q -m hello
    [ "$status" -eq 0 ]
    [ "$(cat "$MARK")" = "msg hello" ]
}

@test "prior pre-commit running git checkout fires post-checkout, not itself again" {
    _prior_hook pre-commit 'echo pre >> "$MARK"; git checkout -q -- README.md'
    _prior_hook post-checkout 'echo post >> "$MARK"'
    _install
    _phase_wt
    rm -f "$MARK"   # worktree add already fired post-checkout once
    printf 'echo b\n' >> "$WT/src/a.sh"
    git -C "$WT" add src/a.sh
    run _git -C "$WT" commit -q -m ok
    [ "$status" -eq 0 ]
    [ "$(grep -c pre "$MARK")" -eq 1 ]
    [ "$(grep -c post "$MARK")" -eq 1 ]
}

@test "relative hooksPath absent in the phase worktree: commit proceeds" {
    git -C "$REPO" config core.hooksPath .husky/_
    mkdir -p "$REPO/.husky/_"
    printf '#!/usr/bin/env bash\nexit 1\n' > "$REPO/.husky/_/pre-commit"
    chmod +x "$REPO/.husky/_/pre-commit"
    _install
    _phase_wt
    printf 'echo b\n' >> "$WT/src/a.sh"
    git -C "$WT" add src/a.sh
    run _git -C "$WT" commit -q -m ok
    [ "$status" -eq 0 ]
}

@test "an RDF hook copy in the prior hooks dir is not re-run" {
    grep -q 'RDF worktree scope enforcement' "$RDF_SRC/state/git-hooks/pre-commit"   # the passthrough's guard keys on this marker
    _prior_hook pre-commit '# RDF worktree scope enforcement (stale copy)
echo copy >> "$MARK"'
    _install
    _phase_wt
    printf 'echo b\n' >> "$WT/src/a.sh"
    git -C "$WT" add src/a.sh
    run _git -C "$WT" commit -q -m ok
    [ "$status" -eq 0 ]
    [ ! -e "$MARK" ]
}

@test "worktree added from inside a phase worktree on a feature branch is not enforced" {
    _install
    _phase_wt
    git -C "$WT" worktree add -q "${REPO}/.worktrees/nested" -b feature/y HEAD
    [[ "$(git -C "${REPO}/.worktrees/nested" rev-parse --git-path hooks)" == */.git/hooks ]]
    printf 'x\n' > "${REPO}/.worktrees/nested/outside.txt"
    git -C "${REPO}/.worktrees/nested" add outside.txt
    run _git -C "${REPO}/.worktrees/nested" commit -q -m free
    [ "$status" -eq 0 ]
}

@test "consumer: anti-pattern classes are off by default" {
    _install
    _phase_wt
    printf 'rm /tmp/x\n' >> "$WT/src/a.sh"
    git -C "$WT" add src/a.sh
    run _git -C "$WT" commit -q -m bare
    [ "$status" -eq 0 ]
}

@test "anti-pattern-enable opts a consumer in; non-shell files are never scanned" {
    mkdir -p "$REPO/.rdf/governance"
    printf '# anti-pattern-enable: all\n' > "$REPO/.rdf/governance/ignore.md"
    _install
    _phase_wt
    printf 'rm the cache before release\n' >> "$WT/README.md"
    git -C "$WT" add README.md
    run _git -C "$WT" commit -q -m prose
    [ "$status" -eq 0 ]
    printf 'rm /tmp/x\n' >> "$WT/src/a.sh"
    git -C "$WT" add src/a.sh
    run _git -C "$WT" commit -q -m bare
    [ "$status" -ne 0 ]
    [[ "$output" == *"ANTI-PATTERN [bare-coreutils-no-prefix]"* ]]
}

@test "install refuses with rc 2 when git is older than 2.23" {
    local real_git shim
    real_git="$(command -v git)"
    shim="${SANDBOX}/shim"
    mkdir -p "$shim"
    printf '#!/usr/bin/env bash\nif [ "$1" = version ]; then echo "git version 2.22.0"; exit 0; fi\nexec "%s" "$@"\n' "$real_git" > "$shim/git"
    chmod +x "$shim/git"
    run env PATH="${shim}:${PATH}" bash -c 'source "$1" && rdf_phase_hook_install "$2"' _ "${HOME}/.rdf/state/rdf-bus.sh" "$REPO"
    [ "$status" -eq 2 ]
    [[ "$output" == *"git >= 2.23 required"* ]]
    run git -C "$REPO" config --get "$INCLUDE_KEY"
    [ "$status" -ne 0 ]
    [ ! -e "$REPO/.git/rdf-hooks" ]
}

@test "reinstall is idempotent: one include entry, symlinked repo path handled" {
    ln -s "$REPO" "${SANDBOX}/link"
    _install "${SANDBOX}/link"
    run _install "${SANDBOX}/link"
    [ "$status" -eq 0 ]
    [ "$(git -C "$REPO" config --get-all "$INCLUDE_KEY" | wc -l | tr -d ' ')" -eq 1 ]
    [ "$(git config --file "$REPO/.git/rdf-hooks.inc" --get core.hooksPath)" = "$(cd -P "$REPO/.git" && pwd -P)/rdf-hooks" ]
    _phase_wt
    printf 'x\n' > "$WT/outside.txt"
    git -C "$WT" add outside.txt
    run _git -C "$WT" commit -q -m oob
    [ "$status" -ne 0 ]
}

@test "uninstall removes the include and files, restores prior hook resolution, and is repeatable" {
    _install
    _phase_wt
    run _uninstall
    [ "$status" -eq 0 ]
    run _uninstall
    [ "$status" -eq 0 ]
    run git -C "$REPO" config --get "$INCLUDE_KEY"
    [ "$status" -ne 0 ]
    [ ! -e "$REPO/.git/rdf-hooks" ]
    [ ! -e "$REPO/.git/rdf-hooks.inc" ]
    [[ "$(git -C "$WT" rev-parse --git-path hooks)" == */.git/hooks ]]
    printf 'x\n' > "$WT/outside.txt"
    git -C "$WT" add outside.txt
    run _git -C "$WT" commit -q -m free
    [ "$status" -eq 0 ]
}

# _md_block file start-ere idx — idx-th (0-based) fenced block after the first start-ere line, indent stripped
_md_block() {
    awk -v start="$2" -v want="$3" '
        !on && $0 ~ start { on = 1; next }
        on && /^[[:space:]]*```/ { if (inb) { inb = 0; n++; if (n > want) exit; next } inb = 1; next }
        on && inb && n == want { sub(/^   /, ""); print }
    ' "$1"
}

# _rbuild_step idx N cwd [extra] — run an r-build worktree-dispatch block for phase N from cwd, pasting placeholders as the controller would
_rbuild_step() {
    local body
    body="$(_md_block "$RDF_SRC/canonical/commands/r-build.md" '^[*][*]Worktree dispatch [(]parallel-worktree[)]:[*][*]' "$1")"
    [[ -n "$body" ]] || { echo "r-build.md worktree-dispatch block $1 not found"; return 1; }
    body="$(printf '%s\n' "$body" | sed -e "s/{N}/$2/g" -e "s/{base-branch}/$(git -C "$REPO" branch --show-current)/g")"
    [[ -n "$body" ]] || { echo "placeholder substitution emptied block $1"; return 1; }
    (cd "$3" && bash -c "${body}"$'\n'"${4:-}")
}

# _rbuild_env — stable harness session id and a git identity for rebase
_rbuild_env() {
    export CLAUDE_CODE_SESSION_ID="$SID"
    export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
    printf '\n### Phase 2: other\n\n**Files:**\n- Create: `src/b.sh`\n' >> "$REPO/docs/plans/p.md"
    _git -C "$REPO" commit -q -am "plan: phase 2"
}

@test "r-build worktree protocol: two phases dispatch, commit under the guard, merge linearly, clean up" {
    _rbuild_env
    local wt1="$REPO/.worktrees/rdf-phase-1-$SID" wt2="$REPO/.worktrees/rdf-phase-2-$SID"
    _rbuild_step 0 1 "$REPO"
    _rbuild_step 0 2 "$REPO"
    _rbuild_step 1 1 "$REPO"
    run git -C "$REPO" config --get "$INCLUDE_KEY"
    [ "$output" = "rdf-hooks.inc" ]
    # The controller's cd lands in the right worktree even from inside another phase's worktree.
    run _rbuild_step 2 1 "$REPO" 'pwd -P'
    [ "$status" -eq 0 ]
    [ "$output" = "$(cd "$wt1" && pwd -P)" ]
    run _rbuild_step 2 2 "$wt1" 'pwd -P'
    [ "$status" -eq 0 ]
    [ "$output" = "$(cd "$wt2" && pwd -P)" ]
    # Dispatchers commit in their worktrees; the guard still rejects out-of-scope work.
    printf 'x\n' > "$wt1/src/b.sh"
    git -C "$wt1" add src/b.sh
    run _git -C "$wt1" commit -q -m oob
    [ "$status" -ne 0 ]
    [[ "$output" == *"SCOPE VIOLATION"* ]]
    git -C "$wt1" reset -q
    rm "$wt1/src/b.sh"
    printf 'echo p1\n' >> "$wt1/src/a.sh"
    git -C "$wt1" add src/a.sh
    _git -C "$wt1" commit -q -m p1
    printf 'echo p2\n' > "$wt2/src/b.sh"
    git -C "$wt2" add src/b.sh
    _git -C "$wt2" commit -q -m p2
    mkdir -p "$wt1/.rdf/work-output" "$wt2/.rdf/work-output"
    printf 'PASS\n' > "$wt1/.rdf/work-output/phase-1-result-$SID.md"
    printf 'PASS\n' > "$wt2/.rdf/work-output/phase-2-result-$SID.md"
    # Merge from wherever the controller was left (phase 2's worktree), in plan order.
    run _rbuild_step 3 1 "$wt2"
    [ "$status" -eq 0 ]
    run _rbuild_step 3 2 "$wt2"
    [ "$status" -eq 0 ]
    run _rbuild_step 4 1 "$REPO"
    [ "$status" -eq 0 ]
    run _rbuild_step 4 2 "$REPO"
    [ "$status" -eq 0 ]
    [ "$(git -C "$REPO" branch --show-current)" = "main" ]
    [ "$(git -C "$REPO" log --format=%s -3 main | tr '\n' ' ')" = "p2 p1 plan: phase 2 " ]
    [ "$(git -C "$REPO" rev-list --count --merges main)" -eq 0 ]
    [ "$(git -C "$REPO" worktree list | wc -l)" -eq 1 ]
    [ -z "$(git -C "$REPO" branch --list 'rdf/phase-*')" ]
    [ -f "$REPO/.rdf/work-output/phase-1-result-$SID.md" ]
    [ -f "$REPO/.rdf/work-output/phase-2-result-$SID.md" ]
}

@test "r-build merge refuses a phase branch with no commits (work landed elsewhere)" {
    _rbuild_env
    _rbuild_step 0 1 "$REPO"
    local before
    before="$(git -C "$REPO" rev-parse main)"
    run _rbuild_step 3 1 "$REPO"
    [ "$status" -eq 1 ]
    [[ "$output" == *"has no commits"* ]]
    [ "$(git -C "$REPO" rev-parse main)" = "$before" ]
}

# _dispatcher_step start-ere launch-dir project-root [project-root-main] — run a dispatcher worktree-setup block for phase 1, launched in launch-dir
_dispatcher_step() {
    local body
    body="$(_md_block "$RDF_SRC/canonical/agents/dispatcher.md" "$1" 0)"
    [[ -n "$body" ]] || { echo "dispatcher.md block after /$1/ not found"; return 1; }
    (cd "$2" && N=1 PROJECT_ROOT="$3" PROJECT_ROOT_MAIN="${4:-}" bash -c "$body")
}

GUARD_RE='^[*][*][(]0[)] Confirm you were launched in the phase worktree'

@test "dispatcher location guard checks the launch directory, not the payload path" {
    _rbuild_env
    _rbuild_step 0 1 "$REPO"
    local wt1="$REPO/.worktrees/rdf-phase-1-$SID"
    run _dispatcher_step "$GUARD_RE" "$wt1" "$wt1"
    [ "$status" -eq 0 ]
    # Launched in a harness worktree or the main worktree, with the payload still naming the phase worktree.
    git -C "$REPO" worktree add -q "$REPO/.claude/worktrees/agent-x" -b worktree-agent-x HEAD
    run _dispatcher_step "$GUARD_RE" "$REPO/.claude/worktrees/agent-x" "$wt1"
    [ "$status" -eq 1 ]
    [[ "$output" == *"worktree-agent-x"* ]]
    run _dispatcher_step "$GUARD_RE" "$REPO" "$wt1"
    [ "$status" -eq 1 ]
    run _dispatcher_step "$GUARD_RE" "$wt1/src" "$wt1"
    [ "$status" -eq 1 ]
}

@test "dispatcher plan sync leaves a tracked plan alone, so the worktree stays removable" {
    _rbuild_env
    _rbuild_step 0 1 "$REPO"
    local wt1="$REPO/.worktrees/rdf-phase-1-$SID"
    run _dispatcher_step '^[*][*][(]a[)] Sync the active plan' "$wt1" "$wt1" "$REPO"
    [ "$status" -eq 0 ]
    [ -z "$(git -C "$wt1" status --porcelain)" ]
    [ "$(cat "$wt1/.rdf/active-plan-$SID")" = "$wt1/docs/plans/p.md" ]
    git -C "$REPO" worktree remove "$wt1"
}

@test "dispatcher plan sync resolves a pointer written through a symlinked checkout path" {
    _rbuild_env
    _rbuild_step 0 1 "$REPO"
    local wt1="$REPO/.worktrees/rdf-phase-1-$SID"
    ln -s "$REPO" "$SANDBOX/link"
    printf '%s\n' "$SANDBOX/link/docs/plans/p.md" > "$REPO/.rdf/active-plan-${SID}"
    run _dispatcher_step '^[*][*][(]a[)] Sync the active plan' "$wt1" "$wt1" "$REPO"
    [ "$status" -eq 0 ]
    [ "$(cat "$wt1/.rdf/active-plan-$SID")" = "$wt1/docs/plans/p.md" ]
    [ -z "$(git -C "$wt1" status --porcelain)" ]
}

@test "r-build setup refuses a detached HEAD, an uncommitted plan edit, and a submodule" {
    _rbuild_env
    git -C "$REPO" checkout -q --detach
    run _rbuild_step 0 1 "$REPO"
    [ "$status" -eq 1 ]
    [[ "$output" == *"detached"* ]]
    git -C "$REPO" checkout -q main
    printf 'uncommitted operator edit\n' >> "$REPO/docs/plans/p.md"
    run _rbuild_step 0 1 "$REPO"
    [ "$status" -eq 1 ]
    [[ "$output" == *"commit the plan first"* ]]
    [ -z "$(git -C "$REPO" branch --list 'rdf/phase-*')" ]
    git -C "$REPO" checkout -q -- docs/plans/p.md
    local super="$SANDBOX/super"
    git init -q "$super"
    _git -C "$super" -c protocol.file.allow=always submodule add -q "$REPO" app
    run _rbuild_step 0 1 "$super/app"
    [ "$status" -eq 1 ]
    [[ "$output" == *"not a worktree toplevel"* ]]
    [ -z "$(git -C "$super" worktree list | sed 1d)" ]
}

@test "r-build never executes the base branch name" {
    _rbuild_env
    # shellcheck disable=SC2016  # the branch name is the literal payload
    git -C "$REPO" checkout -q -b 'b$(touch${IFS}PWNED)'
    local wt1="$REPO/.worktrees/rdf-phase-1-$SID"
    _rbuild_step 0 1 "$REPO"
    printf 'echo p1\n' >> "$wt1/src/a.sh"
    git -C "$wt1" add src/a.sh
    _git -C "$wt1" commit -q -m p1
    run _rbuild_step 3 1 "$wt1"
    [ ! -e "$REPO/PWNED" ]
    [ ! -e "$wt1/PWNED" ]
    [ "$status" -eq 0 ]
    [ "$(git -C "$REPO" log -1 --format=%s)" = "p1" ]
}

@test "r-build merge refuses a phase worktree with uncommitted changes" {
    _rbuild_env
    local wt1="$REPO/.worktrees/rdf-phase-1-$SID" before
    _rbuild_step 0 1 "$REPO"
    printf 'echo p1\n' >> "$wt1/src/a.sh"
    git -C "$wt1" add src/a.sh
    _git -C "$wt1" commit -q -m p1
    printf 'stray\n' > "$wt1/test.log"
    before="$(git -C "$REPO" rev-parse main)"
    run _rbuild_step 3 1 "$REPO"
    [ "$status" -eq 1 ]
    [[ "$output" == *"uncommitted changes"* ]]
    [ "$(git -C "$REPO" rev-parse main)" = "$before" ]
}

@test "r-build merge: uncommitted-only work, a vanished worktree, and a tag shadowing the base" {
    _rbuild_env
    local wt1="$REPO/.worktrees/rdf-phase-1-$SID"
    _rbuild_step 0 1 "$REPO"
    # Work left uncommitted (e.g. the hook rejected the commit) is reported as such, not as "no commits".
    printf 'echo p1\n' >> "$wt1/src/a.sh"
    run _rbuild_step 3 1 "$REPO"
    [ "$status" -eq 1 ]
    [[ "$output" == *"uncommitted changes"* ]]
    git -C "$wt1" add src/a.sh
    _git -C "$wt1" commit -q -m p1
    # A tag named like the base branch must not redirect the rebase or the merge.
    _git -C "$REPO" tag main HEAD~1
    run _rbuild_step 3 1 "$REPO"
    [ "$status" -eq 0 ]
    [ "$(git -C "$REPO" log -1 --format=%s refs/heads/main)" = "p1" ]
    # A phase worktree that disappeared is reported, not misread as a clean tree.
    _rbuild_step 0 2 "$REPO"
    rm -rf "$REPO/.worktrees/rdf-phase-2-$SID"
    run _rbuild_step 3 2 "$REPO"
    [ "$status" -eq 1 ]
    [[ "$output" == *"missing or unreadable"* ]]
}
