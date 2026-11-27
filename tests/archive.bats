#!/usr/bin/env bats

load helpers

setup() {
	setup_sandbox
	git -C "$ENGRAMMA_DIR" init --quiet
	git -C "$ENGRAMMA_DIR" add -A
	git -C "$ENGRAMMA_DIR" commit --quiet -m "fixture"
	ARCHIVE="$TEST_ROOT/archive with spaces"
	git clone --quiet "$ENGRAMMA_DIR" "$ARCHIVE"
	mkdir -p "$XDG_CONFIG_HOME/engramma"
	printf '%s\n' "$ARCHIVE" >"$XDG_CONFIG_HOME/engramma/archive"
}

teardown() {
	teardown_sandbox
}

@test "saved archive takes precedence over the legacy environment" {
	run "$SYNC" --print-data-dir
	[ "$status" -eq 0 ]
	[ "$output" = "$ARCHIVE" ]
}

@test "explicit archive overrides environment and preserves the saved default" {
	export ENGRAMMA_DATA_DIR="$TEST_ROOT/missing"
	run "$SYNC" --data-dir "$ENGRAMMA_DIR" --print-data-dir
	[ "$status" -eq 0 ]
	[ "$output" = "$ENGRAMMA_DIR" ]
	[ "$(cat "$XDG_CONFIG_HOME/engramma/archive")" = "$ARCHIVE" ]
	run "$SYNC" --print-data-dir
	[ "$status" -eq 1 ]
	[[ "$output" == *"Archivio non valido"* ]]
	[ ! -e "$TEST_ROOT/missing" ]
}

@test "environment archive overrides the saved default" {
	export ENGRAMMA_DATA_DIR="$ENGRAMMA_DIR"
	run "$SYNC" --print-data-dir
	[ "$status" -eq 0 ]
	[ "$output" = "$ENGRAMMA_DIR" ]
}

@test "an archive path with spaces supports writes and command installation" {
	run "$SYNC" new saved-project
	[ "$status" -eq 0 ]
	[ -f "$ARCHIVE/workspaces/saved-project/repos.txt" ]
	[ ! -e "$ENGRAMMA_DIR/workspaces/saved-project" ]
	run "$SYNC" setup
	[ "$status" -eq 0 ]
	[ "$(readlink "$HOME/.local/bin/eng")" = "$(realpath "$SYNC")" ]
	run "$HOME/.local/bin/eng" list
	[ "$status" -eq 0 ]
	[[ "$output" == *"saved-project"* ]]
}

@test "missing selection fails without creating an archive while help remains available" {
	rm "$XDG_CONFIG_HOME/engramma/archive"
	unset ENGRAMMA_DIR
	local before
	before="$(snapshot)"
	run "$SYNC" list
	[ "$status" -eq 1 ]
	[[ "$output" == *"Archivio non configurato"* ]]
	run "$SYNC" --help
	[ "$status" -eq 0 ]
	[[ "$output" == *"--data-dir"* ]]
	run "$SYNC" --version
	[ "$status" -eq 0 ]
	[ "$output" = "Engramma $(cat "$BATS_TEST_DIRNAME/../VERSION")" ]
	[ "$(snapshot)" = "$before" ]
}

@test "archive selection rejects missing arguments and nested non-root directories" {
	run "$SYNC" --data-dir
	[ "$status" -eq 1 ]
	run "$SYNC" --data-dir "$ARCHIVE/workspaces" list
	[ "$status" -eq 1 ]
	mkdir -p "$ARCHIVE/nested/workspaces"
	run "$SYNC" --data-dir "$ARCHIVE/nested" list
	[ "$status" -eq 1 ]
	[[ "$output" == *"radice di un repository Git"* ]]
}

@test "saved archive configuration is literal text rather than executable shell" {
	printf '%s\n' '$(touch injected)' >"$XDG_CONFIG_HOME/engramma/archive"
	run "$SYNC" list
	[ "$status" -eq 1 ]
	[[ "$output" == *'$(touch injected)'* ]]
	[ ! -e injected ]
}

@test "program-only installation sets up and detaches an independent archive" {
	local program="$TEST_ROOT/program only" root
	root="$(realpath "$BATS_TEST_DIRNAME/..")"
	mkdir -p "$program"
	cp -a "$root/bin" "$root/lib" "$root/completions" "$root/VERSION" "$program/"
	[ ! -e "$program/workspaces" ]
	[ ! -e "$program/global" ]
	run "$program/bin/sync.sh" sync demo
	[ "$status" -eq 0 ]
	[ "$(readlink "$HOME/.local/bin/eng")" = "$program/bin/sync.sh" ]
	[ "$(readlink "$HOME/.local/share/bash-completion/completions/eng")" = "$program/completions/eng.bash" ]
	local memory
	memory="$(memory_dir_for "$WORKSPACE/alpha")"
	[ "$(readlink "$memory")" = "$ARCHIVE/workspaces/demo/memory/alpha" ]
	run "$HOME/.local/bin/eng" detach all
	[ "$status" -eq 0 ]
	[ ! -L "$memory" ]
	[ "$(cat "$memory/MEMORY.md")" = "- memoria alpha" ]
	[ ! -L "$HOME/.local/bin/eng" ]
	[ -f "$program/bin/sync.sh" ]
}

@test "zsh completion uses an explicit archive without changing the default" {
	command -v zsh >/dev/null || skip "zsh non installato"
	mkdir -p "$TEST_ROOT/bin" "$ENGRAMMA_DIR/workspaces/explicit-only"
	ln -s "$(realpath "$SYNC")" "$TEST_ROOT/bin/eng"
	run env PATH="$TEST_ROOT/bin:$PATH" zsh -f -c '
		service=eng
		words=(eng --data-dir "$1" save "")
		CURRENT=5
		PREFIX=""
		compadd() { printf "%s\n" "$@"; }
		source "$2"
	' _ "$ENGRAMMA_DIR" "$BATS_TEST_DIRNAME/../completions/_eng"
	[ "$status" -eq 0 ]
	[[ "$output" == *"global"*"explicit-only"* ]]
	[ "$(cat "$XDG_CONFIG_HOME/engramma/archive")" = "$ARCHIVE" ]
}

@test "native memory travels between two isolated Claude configurations" {
	local first_memory second_memory other_home="$TEST_ROOT/second home"
	mkdir -p "$other_home"
	cp "$HOME/.bashrc" "$HOME/.zshrc" "$other_home/"
	local program_before
	program_before="$(sha256sum "$SYNC")"
	local remote="$TEST_ROOT/remotes/archive.git"
	git clone --quiet --bare "$ENGRAMMA_DIR" "$remote"
	git -C "$ENGRAMMA_DIR" remote add origin "$remote"
	git -C "$ENGRAMMA_DIR" fetch --quiet
	git -C "$ENGRAMMA_DIR" branch --quiet --set-upstream-to=origin/main
	git -C "$ARCHIVE" remote set-url origin "$remote"
	# Select the first archive explicitly; the saved default is the second clone.
	"$SYNC" --data-dir "$ENGRAMMA_DIR" sync demo >/dev/null
	first_memory="$(memory_dir_for "$WORKSPACE/alpha")"
	echo "ricordo dal primo computer" >"$first_memory/MEMORY.md"
	"$SYNC" --data-dir "$ENGRAMMA_DIR" sync demo >/dev/null
	# Both machines exchange through the same bare remote.
	env HOME="$other_home" XDG_CONFIG_HOME="$other_home/.config" XDG_DATA_HOME="$other_home/.local/share" \
		XDG_STATE_HOME="$other_home/.local/state" XDG_CACHE_HOME="$other_home/.cache" ENGRAMMA_CLAUDE_HOME="$other_home/.claude" \
		"$SYNC" --data-dir "$ARCHIVE" sync demo >/dev/null
	second_memory="$other_home/.claude/projects/$(printf '%s' "$other_home/workspace/demo/alpha" | sed 's#[^A-Za-z0-9]#-#g')/memory"
	[ -L "$second_memory" ]
	[ "$(cat "$second_memory/MEMORY.md")" = "ricordo dal primo computer" ]
	[ "$(sha256sum "$SYNC")" = "$program_before" ]
	[ "$(cat "$XDG_CONFIG_HOME/engramma/archive")" = "$ARCHIVE" ]
}

@test "version works before archive selection and after a command" {
	for prefix in check save integrations; do
		run "$SYNC" --data-dir "$TEST_ROOT/missing" "$prefix" --version
		[ "$status" -eq 0 ]
		[ "$output" = "Engramma $(cat "$BATS_TEST_DIRNAME/../VERSION")" ]
	done
}

@test "zsh completes options and tool targets in context for both command names" {
	for name in eng engramma; do
		run zsh -f -c '
			service="$1"
			commands[$service]="$2"
			_describe() { local -a values; values=("${(@P)2}"); print -l -- $values; }
			compadd() { print -l -- "$@"; }
			PREFIX=-- CURRENT=3 words=("$service" setup --)
			source "$3" | grep -q -- --dry-run || exit 1
			source "$3" | grep -q -- --prune && exit 1
			PREFIX="" CURRENT=4 words=("$service" tools install "")
			source "$3" | grep -qx install && exit 1
			exit 0
		' _ "$name" "$SYNC" "$BATS_TEST_DIRNAME/../completions/_eng"
		[ "$status" -eq 0 ]
	done
}

@test "check without an archive shows the screen, reports the problem and changes nothing" {
	rm "$XDG_CONFIG_HOME/engramma/archive"
	unset ENGRAMMA_DIR
	local before
	before="$(snapshot)"
	run "$SYNC"
	[ "$status" -eq 1 ]
	[[ "$output" == *"archivio:"*"non disponibile"* ]]
	[[ "$output" == *"Archivio non configurato"* ]]
	[[ "$output" == *"POSTAZIONE"* ]]
	[ ! -e "$HOME/.local/bin/eng" ]
	[ "$(snapshot)" = "$before" ]
}

@test "setup without an archive installs the commands and still reports the missing archive" {
	rm "$XDG_CONFIG_HOME/engramma/archive"
	unset ENGRAMMA_DIR
	run "$SYNC" setup
	[ "$status" -eq 1 ]
	[[ "$output" == *"Archivio non configurato"* ]]
	[ "$(readlink "$HOME/.local/bin/eng")" = "$(realpath "$SYNC")" ]
	[ "$(readlink "$HOME/.local/bin/engramma")" = "$(realpath "$SYNC")" ]
}

@test "setup dry run without an archive creates nothing" {
	rm "$XDG_CONFIG_HOME/engramma/archive"
	unset ENGRAMMA_DIR
	run "$SYNC" setup -n
	[ "$status" -eq 1 ]
	[ ! -e "$HOME/.local/bin/eng" ]
}

@test "an invalid saved archive shows the screen with its path" {
	printf '%s\n' "$TEST_ROOT/missing" >"$XDG_CONFIG_HOME/engramma/archive"
	run "$SYNC"
	[ "$status" -eq 1 ]
	[[ "$output" == *"Archivio non valido: $TEST_ROOT/missing"* ]]
	[[ "$output" == *"POSTAZIONE"* ]]
}

@test "commands that need the archive stop with the same screen and write nothing" {
	rm "$XDG_CONFIG_HOME/engramma/archive"
	unset ENGRAMMA_DIR
	for command in "list" "save demo" "new demo" "tools" "integrations"; do
		# shellcheck disable=SC2086
		run "$SYNC" $command
		[ "$status" -eq 1 ]
		[[ "$output" == *"Archivio non configurato"* ]]
		[[ "$output" != *"POSTAZIONE"* ]]
	done
	[ ! -e "$HOME/.local/bin/eng" ]
}

@test "the log command works without an archive" {
	rm "$XDG_CONFIG_HOME/engramma/archive"
	unset ENGRAMMA_DIR
	run "$SYNC" log
	[[ "$output" == *"nessun log"* ]]
	[[ "$output" != *"Archivio non configurato"* ]]
}
