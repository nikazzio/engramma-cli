#!/usr/bin/env bats

load helpers

setup() {
	setup_sandbox
	unset ENGRAMMA_DIR
	ARCHIVE_CONFIG="$XDG_CONFIG_HOME/engramma/archive"
	# A valid archive to connect: a Git repo with workspaces/.
	SOURCE="$TEST_ROOT/source archive"
	mkdir -p "$SOURCE/workspaces/demo"
	printf '# <cartella> <url git> [branch]\n' >"$SOURCE/workspaces/demo/repos.txt"
	git -C "$SOURCE" init --quiet
	git -C "$SOURCE" add -A
	git -C "$SOURCE" commit --quiet -m "fixture"
}

teardown() {
	teardown_sandbox
}

@test "init creates an archive from the example with a first commit and remembers it" {
	run "$SYNC" init "$HOME/dati"
	[ "$status" -eq 0 ]
	[ -d "$HOME/dati/workspaces/demo" ]
	[ -f "$HOME/dati/global/links.txt" ]
	[ "$(git -C "$HOME/dati" log --format=%s)" = "archivio iniziale" ]
	[ "$(git -C "$HOME/dati" rev-parse --abbrev-ref HEAD)" = "main" ]
	[ "$(cat "$ARCHIVE_CONFIG")" = "$HOME/dati" ]
	[[ "$output" == *"remote add origin"* ]]
	[[ "$(ls -A "$HOME")" != *".engramma-init-"* ]]
}

@test "init without a folder uses the default one" {
	run "$SYNC" init
	[ "$status" -eq 0 ]
	[ -d "$HOME/engramma-dati/.git" ]
	[ "$(cat "$ARCHIVE_CONFIG")" = "$HOME/engramma-dati" ]
}

@test "init refuses a folder that is not empty and leaves it as it was" {
	mkdir -p "$HOME/dati"
	echo keep >"$HOME/dati/mine.txt"
	run "$SYNC" init "$HOME/dati"
	[ "$status" -eq 1 ]
	[[ "$output" == *"non è vuota"* ]]
	[ "$(ls -A "$HOME/dati")" = "mine.txt" ]
	[ ! -e "$ARCHIVE_CONFIG" ]
}

@test "init accepts an empty folder" {
	mkdir -p "$HOME/dati"
	run "$SYNC" init "$HOME/dati"
	[ "$status" -eq 0 ]
	[ -d "$HOME/dati/.git" ]
}

@test "init keeps another saved archive and creates nothing" {
	mkdir -p "$XDG_CONFIG_HOME/engramma"
	printf '%s\n' "$SOURCE" >"$ARCHIVE_CONFIG"
	run "$SYNC" init "$HOME/dati"
	[ "$status" -eq 1 ]
	[[ "$output" == *"già salvato un altro archivio"* ]]
	[ ! -e "$HOME/dati" ]
	[ "$(cat "$ARCHIVE_CONFIG")" = "$SOURCE" ]
}

@test "init dry run creates and saves nothing" {
	run "$SYNC" init "$HOME/dati" -n
	[ "$status" -eq 0 ]
	[[ "$output" == *"creerei"* ]]
	[ ! -e "$HOME/dati" ]
	[ ! -e "$ARCHIVE_CONFIG" ]
}

@test "a failed first commit leaves no archive, no leftovers and no saved path" {
	: >"$TEST_ROOT/empty-gitconfig"
	run env GIT_CONFIG_GLOBAL="$TEST_ROOT/empty-gitconfig" GIT_CONFIG_COUNT=1 \
		GIT_CONFIG_KEY_0=user.useConfigOnly GIT_CONFIG_VALUE_0=true "$SYNC" init "$HOME/dati"
	[ "$status" -eq 1 ]
	[[ "$output" == *"primo commit fallito"* ]]
	[ ! -e "$HOME/dati" ]
	[ ! -e "$ARCHIVE_CONFIG" ]
	[[ "$(ls -A "$HOME")" != *".engramma-init-"* ]]
}

@test "init is not a name a workspace can take" {
	git -C "$SOURCE" config user.name Test
	run "$SYNC" --data-dir "$SOURCE" new init
	[ "$status" -eq 2 ]
	[[ "$output" == *"nome riservato"* ]]
}

@test "setup with an archive folder remembers it and runs the setup" {
	run "$SYNC" setup "$SOURCE"
	[ "$status" -eq 0 ]
	[ "$(cat "$ARCHIVE_CONFIG")" = "$SOURCE" ]
	[ "$(readlink "$HOME/.local/bin/eng")" = "$(realpath "$SYNC")" ]
}

@test "setup dry run with an archive folder saves nothing" {
	run "$SYNC" setup "$SOURCE" -n
	[ "$status" -eq 0 ]
	[[ "$output" == *"salverei"* ]]
	[ ! -e "$ARCHIVE_CONFIG" ]
	[ ! -e "$HOME/.local/bin/eng" ]
}

@test "setup with a folder that is not an archive saves nothing" {
	mkdir -p "$TEST_ROOT/plain"
	run "$SYNC" setup "$TEST_ROOT/plain"
	[ "$status" -eq 1 ]
	[[ "$output" == *"Archivio non valido"* ]]
	[ ! -e "$ARCHIVE_CONFIG" ]
}

@test "setup keeps a different saved archive" {
	mkdir -p "$XDG_CONFIG_HOME/engramma" "$TEST_ROOT/other/workspaces"
	git -C "$TEST_ROOT/other" init --quiet
	printf '%s\n' "$TEST_ROOT/other" >"$ARCHIVE_CONFIG"
	run "$SYNC" setup "$SOURCE"
	[ "$status" -eq 1 ]
	[[ "$output" == *"già salvato un altro archivio"* ]]
	[ "$(cat "$ARCHIVE_CONFIG")" = "$TEST_ROOT/other" ]
}

@test "setup with a Git address clones the archive and remembers it" {
	run "$SYNC" setup "file://$SOURCE" "$HOME/dati"
	[ "$status" -eq 0 ]
	[ -d "$HOME/dati/workspaces/demo" ]
	[ "$(cat "$ARCHIVE_CONFIG")" = "$HOME/dati" ]
}

@test "setup with an address that is not an archive removes the clone" {
	mkdir -p "$TEST_ROOT/not-archive"
	git -C "$TEST_ROOT/not-archive" init --quiet
	echo x >"$TEST_ROOT/not-archive/file"
	git -C "$TEST_ROOT/not-archive" add -A
	git -C "$TEST_ROOT/not-archive" commit --quiet -m x
	run "$SYNC" setup "file://$TEST_ROOT/not-archive" "$HOME/dati"
	[ "$status" -eq 1 ]
	[[ "$output" == *"non è un archivio Engramma"* ]]
	[ ! -e "$HOME/dati" ]
	[ ! -e "$ARCHIVE_CONFIG" ]
	[[ "$(ls -A "$HOME")" != *".engramma-clone-"* ]]
}

@test "setup with an address refuses a folder that is not empty" {
	mkdir -p "$HOME/dati"
	echo keep >"$HOME/dati/mine.txt"
	run "$SYNC" setup "file://$SOURCE" "$HOME/dati"
	[ "$status" -eq 1 ]
	[ "$(ls -A "$HOME/dati")" = "mine.txt" ]
	[ ! -e "$ARCHIVE_CONFIG" ]
}

@test "setup with something that is neither a folder nor an address fails" {
	run "$SYNC" setup "non-esiste"
	[ "$status" -eq 1 ]
	[[ "$output" == *"né un indirizzo Git"* ]]
	[ ! -e "$ARCHIVE_CONFIG" ]
}

@test "help is available without archive and invalid arguments cannot install anything" {
	run "$SYNC" sync --help
	[ "$status" -eq 0 ]
	[[ "$output" == *"Uso: eng sync"*"eng sync demo --dry-run"* ]]
	run bash -c '"$1" setup --bad-option >"$2" 2>"$3"' _ "$SYNC" "$TEST_ROOT/out" "$TEST_ROOT/err"
	[ "$status" -eq 2 ]
	[ ! -s "$TEST_ROOT/out" ]
	grep -qF 'Opzione sconosciuta: --bad-option' "$TEST_ROOT/err"
	[ ! -e "$HOME/.local/bin/eng" ]
	[ ! -e "$ARCHIVE_CONFIG" ]
	run "$SYNC" integrations inesperato
	[ "$status" -eq 2 ]
}

@test "init prints a usable path to setup even when eng is absent and paths contain spaces" {
	run "$SYNC" init "$HOME/dati con spazi"
	[ "$status" -eq 0 ]
	[[ "$output" == *'~/dati\ con\ spazi remote add origin git@github.com:ACCOUNT/ARCHIVIO-PRIVATO.git'* ]]
	[[ "$output" == *"infine: $(realpath "$SYNC") setup"* ]]
	[ ! -e "$HOME/.local/bin/eng" ]
}

@test "detach all forgets its saved archive only after success" {
	"$SYNC" setup "$SOURCE"
	run "$SYNC" detach all --dry-run
	[ "$status" -eq 0 ]
	[[ "$output" == *"dimenticherei l’archivio"* ]]
	[ "$(cat "$ARCHIVE_CONFIG")" = "$SOURCE" ]
	run "$SYNC" detach all
	[ "$status" -eq 0 ]
	[ ! -e "$ARCHIVE_CONFIG" ]
	[ -d "$SOURCE/.git" ]
	run "$SYNC" --print-data-dir
	[ "$status" -eq 1 ]
}

@test "detaching an alternate archive preserves the default archive and commands" {
	"$SYNC" setup "$SOURCE"
	git clone -q "$SOURCE" "$TEST_ROOT/second"
	run "$SYNC" --data-dir "$TEST_ROOT/second" detach all
	[ "$status" -eq 0 ]
	[ "$(cat "$ARCHIVE_CONFIG")" = "$SOURCE" ]
	[ -L "$HOME/.local/bin/eng" ]
}
