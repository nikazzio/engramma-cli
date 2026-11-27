#!/usr/bin/env bats

load helpers

setup() {
	setup_sandbox
	git -C "$ENGRAMMA_DIR" init --quiet
	git -C "$ENGRAMMA_DIR" add -A
	git -C "$ENGRAMMA_DIR" commit --quiet -m "notes"
	git clone --quiet --bare "$ENGRAMMA_DIR" "$TEST_ROOT/remotes/engramma.git"
	git -C "$ENGRAMMA_DIR" remote add origin "$TEST_ROOT/remotes/engramma.git"
	git -C "$ENGRAMMA_DIR" fetch --quiet origin
	git -C "$ENGRAMMA_DIR" branch --quiet --set-upstream-to=origin/main
}

teardown() {
	teardown_sandbox
}

# A commit made on the other computer and pushed to the remote.
push_from_other_computer() {
	local other="$TEST_ROOT/other"
	[[ -d "$other" ]] || git clone --quiet "$TEST_ROOT/remotes/engramma.git" "$other"
	echo "$1" >>"$other/workspaces/demo/docs/guida.md"
	git -C "$other" commit --quiet -am "$1"
	git -C "$other" push --quiet
}

@test "downloads the commits of the other computer before syncing" {
	push_from_other_computer "dall'altro computer"

	run "$SYNC" setup
	[ "$status" -eq 0 ]
	[[ "$output" == *"engramma: fast-forward di 1 commit da"* ]]
	[[ "$output" == *"fast-forward di 1 commit da upstream"* ]]
	grep -q "dall'altro computer" "$NOTES/docs/guida.md"
}

@test "check and dry run only report the commits to download" {
	push_from_other_computer "dall'altro computer"
	local before
	before="$(git -C "$ENGRAMMA_DIR" rev-parse HEAD)"

	run "$SYNC" check
	[[ "$output" == *"1 commit sul remoto da scaricare"* ]]
	run "$SYNC" sync demo --dry-run
	[[ "$output" == *"1 commit sul remoto da scaricare"* ]]
	[ "$(git -C "$ENGRAMMA_DIR" rev-parse HEAD)" = "$before" ]
}

@test "shows the commit and its date in the header" {
	local revision
	revision="$(git -C "$ENGRAMMA_DIR" log -1 --format='%h · %cs')"
	run "$SYNC" check
	[[ "$output" == *"$revision"* ]]
}

@test "reports changes of engramma not saved or not sent" {
	echo "nuova nota" >>"$NOTES/docs/guida.md"
	run "$SYNC" setup
	[[ "$output" == *"1 file non committato"* ]]
	[[ "$output" == *"eng save demo"* ]]
	[[ "$output" != *"push di engramma:"* ]]

	git -C "$ENGRAMMA_DIR" commit --quiet -am "nota"
	run "$SYNC" setup
	[[ "$output" == *"1 commit non inviati al remoto"* ]]
	[[ "$output" == *"push di engramma:"* ]]
	[[ "$output" != *"eng save demo"* ]]
}

@test "does not stop when the remote of engramma cannot be reached" {
	git -C "$ENGRAMMA_DIR" remote set-url origin "$TEST_ROOT/remotes/manca.git"

	run "$SYNC" setup
	[ "$status" -eq 0 ]
	[[ "$output" == *"git fetch fallito"* ]]
}

@test "links the engramma command and removes it when detaching" {
	run "$SYNC" setup
	[ "$(readlink "$HOME/.local/bin/engramma")" = "$(realpath "$SYNC")" ]

	[ "$(readlink "$HOME/.local/bin/eng")" = "$(readlink "$HOME/.local/bin/engramma")" ]

	run "$SYNC" detach all
	[ ! -e "$HOME/.local/bin/engramma" ]
	[ ! -L "$HOME/.local/bin/engramma" ]
	[ ! -L "$HOME/.local/bin/eng" ]
}

@test "the session start report is empty when everything is saved" {
	run "$SYNC" session-start
	[ "$status" -eq 0 ]
	[ -z "$output" ]

	push_from_other_computer "dall'altro computer"
	echo "nuova nota" >>"$NOTES/repo-notes/alpha.md"
	run "$SYNC" session-start
	[ "$status" -eq 0 ]
	[[ "$output" == *"scaricati 1 commit dall'altro computer"* ]]
	[[ "$output" == *"1 file con modifiche non salvate"* ]]
	grep -q "dall'altro computer" "$NOTES/docs/guida.md"
}

@test "status lists the work not saved or not sent in every workspace, without changing anything" {
	"$SYNC" sync demo >/dev/null
	echo "modifica" >"$WORKSPACE/alpha/nuovo.txt"
	git -C "$WORKSPACE/beta" switch --quiet -c solo-qui
	git -C "$WORKSPACE/beta" commit --quiet --allow-empty -m "lavoro locale"
	local before
	before="$(snapshot)"

	run "$SYNC" check
	[ "$status" -eq 0 ]
	[[ "$output" == *"alpha"*"1 file non committato"* ]]
	[[ "$output" == *"beta"*"branch solo-qui solo locale, mai pushato"* ]]
	[ "$(snapshot)" = "$before" ]
}

@test "status says when everything is saved and sent" {
	"$SYNC" sync demo >/dev/null

	run "$SYNC" check
	[ "$status" -eq 0 ]
	[[ "$output" == *"tutto a posto"* ]]
}

@test "links the completion of the names for bash and zsh, and removes it when detaching" {
	local data="$HOME/.local/share"
	local program="$(realpath "$BATS_TEST_DIRNAME/..")"

	run "$SYNC" setup
	[ "$(readlink "$data/bash-completion/completions/eng")" = "$program/completions/eng.bash" ]
	[ "$(readlink "$data/bash-completion/completions/engramma")" = "$program/completions/eng.bash" ]
	[ "$(readlink "$data/zsh/site-functions/_eng")" = "$program/completions/_eng" ]

	run "$SYNC" detach all
	[ ! -L "$data/bash-completion/completions/eng" ]
	[ ! -L "$data/zsh/site-functions/_eng" ]
}

# What bash would propose after the given words of the command line.
complete_eng() {
	mkdir -p "$TEST_ROOT/bin"
	ln -sf "$BATS_TEST_DIRNAME/../bin/sync.sh" "$TEST_ROOT/bin/eng"
	PATH="$TEST_ROOT/bin:$PATH" bash -c '
		source "$1"
		shift
		COMP_WORDS=("$@")
		COMP_CWORD=$((${#COMP_WORDS[@]} - 1))
		_eng
		printf "%s\n" "${COMPREPLY[@]}"' _ "$BATS_TEST_DIRNAME/../completions/eng.bash" eng "$@"
}

@test "bash completes commands, workspaces of engramma and options" {
	[[ "$(complete_eng "")" == *"sync"*"setup"*"detach"* ]]
	[[ "$(complete_eng "")" == *"demo"* ]]
	[ "$(complete_eng --data-dir "$ENGRAMMA_DIR" save "")" = $'global\ndemo' ]
	[[ "$(complete_eng detach "")" == *"all"* ]]
	[ "$(complete_eng sync --pr)" = "--prune" ]
	[ "$(complete_eng sync -j "")" = "" ]
}

@test "save commits and pushes only the files of one workspace" {
	echo "nota" >"$NOTES/docs/nuova.md"
	mkdir -p "$ENGRAMMA_DIR/global"
	echo "altro" >"$ENGRAMMA_DIR/global/altro.txt"

	run "$SYNC" save demo
	[ "$status" -eq 0 ]
	[[ "$output" == *"1 file in un commit"*"docs(demo): update notes and memory"* ]]
	[[ "$output" == *"push fatto"* ]]
	[ "$(git -C "$ENGRAMMA_DIR" log -1 --format=%s origin/main)" = "docs(demo): update notes and memory" ]
	[ -z "$(git -C "$ENGRAMMA_DIR" status --porcelain -- workspaces/demo)" ]
	[ -n "$(git -C "$ENGRAMMA_DIR" status --porcelain -- global)" ]

	run "$SYNC" save demo
	[[ "$output" == *"niente da salvare"* ]]
}

@test "save retries a failed push when there are no new files" {
	echo "nota" >"$NOTES/docs/nuova.md"
	git -C "$ENGRAMMA_DIR" remote set-url origin "$TEST_ROOT/remotes/manca.git"
	run "$SYNC" save demo
	[ "$status" -eq 1 ]
	[[ "$output" == *"push fallito"* ]]
	local saved
	saved="$(git -C "$ENGRAMMA_DIR" rev-parse HEAD)"
	git -C "$ENGRAMMA_DIR" remote set-url origin "$TEST_ROOT/remotes/engramma.git"
	run "$SYNC" save demo
	[ "$status" -eq 0 ]
	[[ "$output" == *"commit già salvati da inviare"*"push fatto"* ]]
	[ "$(git -C "$ENGRAMMA_DIR" rev-parse HEAD)" = "$saved" ]
	[ "$(git -C "$TEST_ROOT/remotes/engramma.git" rev-parse main)" = "$saved" ]
}

@test "native memory saved on one computer reaches the other through sync" {
	local other="$TEST_ROOT/other" memory
	git clone --quiet "$TEST_ROOT/remotes/engramma.git" "$other"
	"$SYNC" sync demo >/dev/null
	memory="$(memory_dir_for "$WORKSPACE/alpha")"
	echo "ricordo dal primo computer" >"$memory/MEMORY.md"
	"$SYNC" sync demo >/dev/null
	git -C "$other" pull --quiet --ff-only
	[ "$(cat "$other/workspaces/demo/memory/alpha/MEMORY.md")" = "ricordo dal primo computer" ]
	echo "ricordo dal secondo computer" >"$other/workspaces/demo/memory/alpha/MEMORY.md"
	git -C "$other" commit --quiet -am "second computer"
	git -C "$other" push --quiet
	run "$SYNC" sync demo
	[ "$status" -eq 0 ]
	[ "$(cat "$memory/MEMORY.md")" = "ricordo dal secondo computer" ]
}

@test "conflicting local memory survives an update from another computer" {
	"$SYNC" sync demo >/dev/null
	local memory other="$TEST_ROOT/other"
	memory="$(memory_dir_for "$WORKSPACE/alpha")"
	git clone --quiet "$TEST_ROOT/remotes/engramma.git" "$other"
	echo "ricordo locale" >"$memory/MEMORY.md"
	echo "ricordo remoto" >"$other/workspaces/demo/memory/alpha/MEMORY.md"
	git -C "$other" commit --quiet -am "second computer"
	git -C "$other" push --quiet
	run "$SYNC" sync demo
	[[ "$output" == *"non applicati"* ]]
	[ "$(cat "$memory/MEMORY.md")" = "ricordo locale" ]
	[ "$(git -C "$ENGRAMMA_DIR" show origin/main:workspaces/demo/memory/alpha/MEMORY.md)" = "ricordo remoto" ]
}

@test "new creates an empty workspace and add puts a repo in it" {
	run "$SYNC" new prova clienti/prova
	[ "$status" -eq 0 ]
	[ "$(cat "$ENGRAMMA_DIR/workspaces/prova/location.txt")" = clienti/prova ]
	[ -f "$ENGRAMMA_DIR/workspaces/prova/README.md" ]

	run "$SYNC" add prova git@example.com:team/prova-api.git main
	[ "$status" -eq 0 ]
	grep -qx 'prova-api git@example.com:team/prova-api.git main' "$ENGRAMMA_DIR/workspaces/prova/repos.txt"

	run "$SYNC" add prova https://example.com/team/prova-api.git
	[ "$status" -eq 1 ]
	run "$SYNC" new prova
	[ "$status" -eq 1 ]
}

@test "log prints the log of the last run outside a terminal" {
	"$SYNC" check demo >/dev/null || true
	run "$SYNC" log
	[ "$status" -eq 0 ]
	[[ "$output" == *"check"* ]]
}

@test "sync retries offline workspace changes without committing other workspaces" {
	mkdir -p "$ENGRAMMA_DIR/workspaces/altro"
	echo privata >"$ENGRAMMA_DIR/workspaces/altro/nota.md"
	echo locale >"$NOTES/docs/nuova.md"
	git -C "$ENGRAMMA_DIR" remote set-url origin "$TEST_ROOT/missing.git"
	run "$SYNC" sync demo
	[ "$status" -ne 0 ]
	local saved
	saved="$(git -C "$ENGRAMMA_DIR" rev-parse HEAD)"
	[ "$(git -C "$ENGRAMMA_DIR" show HEAD:workspaces/demo/docs/nuova.md)" = locale ]
	! git -C "$ENGRAMMA_DIR" cat-file -e HEAD:workspaces/altro/nota.md
	git -C "$ENGRAMMA_DIR" remote set-url origin "$TEST_ROOT/remotes/engramma.git"
	run "$SYNC" sync demo
	[ "$status" -eq 0 ]
	[ "$(git -C "$TEST_ROOT/remotes/engramma.git" rev-parse main)" = "$saved" ]
}
