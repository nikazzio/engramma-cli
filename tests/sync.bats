#!/usr/bin/env bats

load helpers

setup() {
	setup_sandbox
}

teardown() {
	teardown_sandbox
}

@test "fails with an unknown workspace" {
	run "$SYNC" sync sconosciuto
	[ "$status" -eq 1 ]
	[[ "$output" == *"Workspace sconosciuto"* ]]
}

@test "fails with an unknown option" {
	run "$SYNC" sync demo --boh
	[ "$status" -eq 1 ]
	[[ "$output" == *"Opzione sconosciuta"* ]]
}

@test "sets up a fresh workspace from scratch" {
	run "$SYNC" sync demo
	[ "$status" -eq 0 ]

	[ "$(current_branch alpha)" = develop ]
	[ "$(current_branch beta)" = main ]

	[ "$(readlink "$WORKSPACE/.claude")" = "$NOTES/.claude" ]
	[ "$(readlink "$WORKSPACE/docs")" = "$NOTES/docs" ]
	[ "$(readlink "$(memory_dir_for "$WORKSPACE")")" = "$NOTES/memory/_workspace" ]
	[ "$(readlink "$(memory_dir_for "$WORKSPACE/alpha")")" = "$NOTES/memory/alpha" ]

	[ "$(cat "$WORKSPACE/alpha/CLAUDE.local.md")" = "@$NOTES/repo-notes/alpha.md" ]
	grep -qxF CLAUDE.local.md "$WORKSPACE/alpha/.git/info/exclude"
	[ ! -e "$WORKSPACE/beta/CLAUDE.local.md" ]
	[ -z "$(git -C "$WORKSPACE/alpha" status --porcelain)" ]
}

@test "a second run changes nothing" {
	"$SYNC" sync demo >/dev/null
	before="$(snapshot)"

	run "$SYNC" sync demo
	[ "$status" -eq 0 ]
	[[ "$output" != *"Clonato"* ]]
	[[ "$output" != *"creato"* ]]

	[ "$(snapshot)" = "$before" ]
	[ "$(grep -cxF CLAUDE.local.md "$WORKSPACE/alpha/.git/info/exclude")" -eq 1 ]
}

@test "dry run changes nothing" {
	run "$SYNC" sync demo --dry-run
	[ "$status" -eq 0 ]
	[[ "$output" == *"git clone"* ]]
	[[ "$output" == *"symlink a"* ]]
	[ ! -e "$WORKSPACE" ]
	[ ! -e "$ENGRAMMA_CLAUDE_HOME" ]
}

@test "check fails on a fresh machine and passes after setup" {
	run "$SYNC" check demo
	[ "$status" -eq 1 ]
	[[ "$output" == *"da sistemare"* ]]
	[ ! -e "$WORKSPACE" ]

	"$SYNC" sync demo >/dev/null

	run "$SYNC" check demo
	[ "$status" -eq 0 ]
	[[ "$output" == *"tutto a posto"* ]]
}

@test "never overwrites a real folder where a link should be" {
	mkdir -p "$WORKSPACE/docs"
	echo "mio" >"$WORKSPACE/docs/vecchio.md"

	run "$SYNC" sync demo
	[ "$status" -eq 1 ]
	[[ "$output" == *"docs: cartella locale con 1 file che engramma non ha"* ]]
	[ ! -L "$WORKSPACE/docs" ]
	[ "$(cat "$WORKSPACE/docs/vecchio.md")" = mio ]

	run "$SYNC" check demo
	[ "$status" -eq 1 ]
}

@test "never overwrites a personal note with its own content" {
	git clone --quiet "$(remote_path alpha)" "$WORKSPACE/alpha"
	echo "appunti miei" >"$WORKSPACE/alpha/CLAUDE.local.md"
	echo CLAUDE.local.md >>"$WORKSPACE/alpha/.git/info/exclude"

	run "$SYNC" sync demo
	[[ "$output" == *"ha un contenuto suo"* ]]
	[ "$(cat "$WORKSPACE/alpha/CLAUDE.local.md")" = "appunti miei" ]
}

@test "warns about a leftover CLAUDE.md in the workspace folder" {
	"$SYNC" sync demo >/dev/null
	echo "# vecchio" >"$WORKSPACE/CLAUDE.md"

	run "$SYNC" check demo
	[ "$status" -eq 1 ]
	[[ "$output" == *"CLAUDE.md residuo"* ]]
	[ -f "$WORKSPACE/CLAUDE.md" ]
}

@test "warns only once about a memory folder that should be linked" {
	"$SYNC" sync demo >/dev/null
	local memory
	memory="$(memory_dir_for "$WORKSPACE/alpha")"
	rm "$memory"
	mkdir -p "$memory"
	echo "- ricordo" >"$memory/MEMORY.md"

	run "$SYNC" check demo
	[ "$status" -eq 1 ]
	[[ "$output" == *"memoria di alpha: cartella locale con file diversi da engramma: MEMORY.md"* ]]
	[ "$(grep -c "memoria di alpha" <<<"${output%%────*}")" -eq 1 ]

	run "$SYNC" sync demo
	[ -d "$memory" ] && [ ! -L "$memory" ]
	[ "$(cat "$NOTES/memory/alpha/MEMORY.md")" = "- memoria alpha" ]
}

@test "leaves a link pointing elsewhere untouched" {
	mkdir -p "$WORKSPACE" "$TEST_ROOT/altrove"
	ln -s "$TEST_ROOT/altrove" "$WORKSPACE/docs"

	run "$SYNC" sync demo
	[[ "$output" == *"non verso engramma: non lo tocco"* ]]
	[ "$(readlink "$WORKSPACE/docs")" = "$TEST_ROOT/altrove" ]
}

@test "skips a repo with uncommitted changes" {
	"$SYNC" sync demo >/dev/null
	git -C "$WORKSPACE/alpha" switch --quiet main
	echo modifica >"$WORKSPACE/alpha/file.txt"

	run "$SYNC" sync demo
	[[ "$output" == *"file con modifiche non committate: aggiornamento saltato"* ]]
	[ "$(current_branch alpha)" = main ]
}

@test "skips a repo on a branch still in progress" {
	"$SYNC" sync demo >/dev/null
	push_to_remote alpha issue/in-corso "lavoro in corso"
	git -C "$WORKSPACE/alpha" fetch --quiet origin
	git -C "$WORKSPACE/alpha" switch --quiet issue/in-corso

	run "$SYNC" sync demo
	[[ "$output" == *"branch issue/in-corso ancora in corso: aggiornamento saltato"* ]]
	[ "$(current_branch alpha)" = issue/in-corso ]
}

@test "moves a finished branch back to develop and fast-forwards it" {
	"$SYNC" sync demo >/dev/null
	git -C "$WORKSPACE/alpha" switch --quiet -c issue/finita
	push_to_remote alpha develop "nuovo lavoro su develop"

	run "$SYNC" sync demo
	[ "$status" -eq 0 ]
	[ "$(current_branch alpha)" = develop ]
	[ "$(git -C "$WORKSPACE/alpha" rev-parse HEAD)" = "$(git -C "$(remote_path alpha)" rev-parse develop)" ]
	[[ "$output" == *"issue/finita"* ]]
	[[ "$output" == *"1 branch lasciato: eng sync demo --prune lo cancella"* ]]
	git -C "$WORKSPACE/alpha" rev-parse --verify --quiet refs/heads/issue/finita
}

@test "uses location.txt to find a workspace nested in another folder" {
	echo "clienti/demo" >"$NOTES/location.txt"

	run "$SYNC" sync demo
	[ "$status" -eq 0 ]
	[ -d "$HOME/workspace/clienti/demo/alpha/.git" ]
	[ "$(readlink "$HOME/workspace/clienti/demo/docs")" = "$NOTES/docs" ]
	[ ! -e "$WORKSPACE" ]
}

@test "links personal files into a repo and excludes them from git" {
	mkdir -p "$NOTES/repo-files/beta"
	echo "services: {}" >"$NOTES/repo-files/beta/compose.yaml"
	echo "{}" >"$NOTES/repo-files/beta/.prettierrc.json"

	run "$SYNC" sync demo
	[ "$status" -eq 0 ]
	[ "$(readlink "$WORKSPACE/beta/compose.yaml")" = "$NOTES/repo-files/beta/compose.yaml" ]
	[ "$(readlink "$WORKSPACE/beta/.prettierrc.json")" = "$NOTES/repo-files/beta/.prettierrc.json" ]
	[ -z "$(git -C "$WORKSPACE/beta" status --porcelain)" ]

	run "$SYNC" check demo
	[ "$status" -eq 0 ]
}

@test "never links a personal file over one versioned by the repo" {
	"$SYNC" sync demo >/dev/null
	echo "services: {}" >"$WORKSPACE/beta/compose.yaml"
	git -C "$WORKSPACE/beta" add compose.yaml
	git -C "$WORKSPACE/beta" commit --quiet -m "compose del team"
	mkdir -p "$NOTES/repo-files/beta"
	echo "services: {}" >"$NOTES/repo-files/beta/compose.yaml"

	run "$SYNC" sync demo
	[ ! -L "$WORKSPACE/beta/compose.yaml" ]
	[ -z "$(git -C "$WORKSPACE/beta" status --porcelain)" ]
	[[ "$output" == *"compose.yaml"*"versionato nel repo"* ]]
}

@test "excludes local-only files listed in excludes.txt" {
	echo "beta .env" >"$NOTES/excludes.txt"
	"$SYNC" sync demo >/dev/null
	echo "SEGRETO=1" >"$WORKSPACE/beta/.env"

	[ -z "$(git -C "$WORKSPACE/beta" status --porcelain)" ]
	! grep -qxF .env "$WORKSPACE/alpha/.git/info/exclude"
}

@test "links personal files before checking for uncommitted changes" {
	git clone --quiet "$(remote_path beta)" "$WORKSPACE/beta"
	mkdir -p "$NOTES/repo-files/beta"
	echo "services: {}" >"$NOTES/repo-files/beta/compose.yaml"

	run "$SYNC" sync demo
	[[ "$output" != *"file con modifiche non committate: aggiornamento saltato"* ]]
}

@test "any SSH server that accepts the key counts as authenticated, whatever it prints" {
	mkdir -p "$TEST_ROOT/bin"
	printf '#!/bin/sh\necho "logged in as utente"\nexit 0\n' >"$TEST_ROOT/bin/ssh"
	chmod +x "$TEST_ROOT/bin/ssh"
	echo "remoto git@example.test:team/remoto.git" >>"$NOTES/repos.txt"
	PATH="$TEST_ROOT/bin:$PATH" run "$SYNC" check demo
	[[ "$output" == *"ssh example.test autenticato"* ]]

	printf '#!/bin/sh\necho "Permission denied (publickey)." >&2\nexit 255\n' >"$TEST_ROOT/bin/ssh"
	PATH="$TEST_ROOT/bin:$PATH" run "$SYNC" check demo
	[[ "$output" == *"ssh example.test non autenticato"*"Permission denied"* ]]
}

@test "a comment at the end of a line is not a field" {
	sed -i "s#^beta .*#beta $(remote_path beta)   \# repo di prova#" "$NOTES/repos.txt"
	echo "demo.test   # sito locale" >"$NOTES/hosts.txt"
	echo "127.0.0.1 demo.test" >"$ENGRAMMA_HOSTS_FILE"
	run "$SYNC" sync demo
	[ "$status" -eq 0 ]
	[ "$(current_branch beta)" = main ]
}

@test "uses the main branch given in repos.txt" {
	push_to_remote beta release "lavoro su release"
	sed -i "s#^beta .*#beta $(remote_path beta) release#" "$NOTES/repos.txt"

	run "$SYNC" sync demo
	[ "$status" -eq 0 ]
	[ "$(current_branch beta)" = release ]

	push_to_remote beta release "altro lavoro su release"
	run "$SYNC" sync demo
	[ "$(current_branch beta)" = release ]
	[ "$(git -C "$WORKSPACE/beta" rev-parse HEAD)" = "$(git -C "$(remote_path beta)" rev-parse release)" ]
	[[ "$output" != *"ancora in corso: aggiornamento saltato"* ]]
}

@test "warns about a missing hostname" {
	: >"$ENGRAMMA_HOSTS_FILE"

	run "$SYNC" check demo
	[ "$status" -eq 1 ]
	[[ "$output" == *"localhost.demo.test non è nel file hosts"* ]]
}

@test "moves into engramma a Claude memory written before it was versioned" {
	"$SYNC" sync demo >/dev/null
	local unversioned
	unversioned="$(memory_dir_for "$WORKSPACE/beta")"
	mkdir -p "$unversioned"
	echo "- ricordo" >"$unversioned/MEMORY.md"

	run "$SYNC" check demo
	[ "$status" -eq 1 ]
	[[ "$output" == *"memoria di beta: cartella locale al posto del symlink"* ]]

	run "$SYNC" sync demo
	[ "$status" -eq 0 ]
	[ "$(readlink "$unversioned")" = "$NOTES/memory/beta" ]
	[ "$(cat "$NOTES/memory/beta/MEMORY.md")" = "- ricordo" ]
	ls "$XDG_STATE_HOME"/engramma/backup/adopted/*/* >/dev/null
	[ ! -e "$ENGRAMMA_DIR/backup" ]
}

@test "leaves the original memory intact when its backup fails" {
	"$SYNC" sync demo >/dev/null
	local unversioned
	unversioned="$(memory_dir_for "$WORKSPACE/beta")"
	mkdir -p "$unversioned" "$TEST_ROOT/bin"
	echo "ricordo originale" >"$unversioned/MEMORY.md"
	cat >"$TEST_ROOT/bin/cp" <<'EOF'
#!/bin/bash
for arg in "$@"; do
	[[ "$arg" == */backup/adopted/* ]] && exit 1
done
exec /bin/cp "$@"
EOF
	chmod +x "$TEST_ROOT/bin/cp"
	PATH="$TEST_ROOT/bin:$PATH" run "$SYNC" sync demo
	[ "$status" -eq 1 ]
	[[ "$output" == *"backup non riuscito o diverso dall'originale"* ]]
	[ ! -L "$unversioned" ]
	[ "$(cat "$unversioned/MEMORY.md")" = "ricordo originale" ]
	[ ! -e "$NOTES/memory/beta/MEMORY.md" ]
}

@test "rejects a memory backup that differs from its original" {
	"$SYNC" sync demo >/dev/null
	local unversioned
	unversioned="$(memory_dir_for "$WORKSPACE/beta")"
	mkdir -p "$unversioned" "$TEST_ROOT/bin"
	echo "ricordo originale" >"$unversioned/MEMORY.md"
	cat >"$TEST_ROOT/bin/cp" <<'EOF'
#!/bin/bash
/bin/cp "$@" || exit "$?"
for arg in "$@"; do
	if [[ "$arg" == */backup/adopted/* ]]; then
		echo "backup incompleto" >"$arg/MEMORY.md"
	fi
done
EOF
	chmod +x "$TEST_ROOT/bin/cp"
	PATH="$TEST_ROOT/bin:$PATH" run "$SYNC" sync demo
	[ "$status" -eq 1 ]
	[[ "$output" == *"backup non riuscito o diverso dall'originale"* ]]
	[ ! -L "$unversioned" ]
	[ "$(cat "$unversioned/MEMORY.md")" = "ricordo originale" ]
	[ ! -e "$NOTES/memory/beta/MEMORY.md" ]
}

@test "leaves the original memory intact when copying a file fails" {
	"$SYNC" sync demo >/dev/null
	local unversioned
	unversioned="$(memory_dir_for "$WORKSPACE/beta")"
	mkdir -p "$unversioned" "$TEST_ROOT/bin"
	echo "ricordo originale" >"$unversioned/MEMORY.md"
	cat >"$TEST_ROOT/bin/cp" <<'EOF'
#!/bin/bash
for arg in "$@"; do
	[[ "$arg" == */memory/beta/MEMORY.md ]] && exit 1
done
exec /bin/cp "$@"
EOF
	chmod +x "$TEST_ROOT/bin/cp"
	PATH="$TEST_ROOT/bin:$PATH" run "$SYNC" sync demo
	[ "$status" -eq 1 ]
	[[ "$output" == *"copia non riuscita"* ]]
	[ ! -L "$unversioned" ]
	[ "$(cat "$unversioned/MEMORY.md")" = "ricordo originale" ]
	[ -n "$(find "$XDG_STATE_HOME/engramma/backup/adopted" -name MEMORY.md -type f)" ]
}

@test "does not overwrite a file created in the destination during adoption" {
	"$SYNC" sync demo >/dev/null
	local unversioned
	unversioned="$(memory_dir_for "$WORKSPACE/beta")"
	mkdir -p "$unversioned" "$TEST_ROOT/bin"
	echo "ricordo originale" >"$unversioned/MEMORY.md"
	cat >"$TEST_ROOT/bin/cp" <<'EOF'
#!/bin/bash
for arg in "$@"; do
	if [[ "$arg" == */memory/beta/MEMORY.md ]]; then
		echo "nuovo ricordo" >"$arg"
		break
	fi
done
exec /bin/cp "$@"
EOF
	chmod +x "$TEST_ROOT/bin/cp"
	PATH="$TEST_ROOT/bin:$PATH" run "$SYNC" sync demo
	[ "$status" -eq 1 ]
	[[ "$output" == *"copia non riuscita o diversa dall'originale"* ]]
	[ ! -L "$unversioned" ]
	[ "$(cat "$unversioned/MEMORY.md")" = "ricordo originale" ]
	[ "$(cat "$NOTES/memory/beta/MEMORY.md")" = "nuovo ricordo" ]
}

@test "restores the original memory if creating its link fails" {
	"$SYNC" sync demo >/dev/null
	local unversioned
	unversioned="$(memory_dir_for "$WORKSPACE/beta")"
	mkdir -p "$unversioned" "$TEST_ROOT/bin"
	echo "ricordo originale" >"$unversioned/MEMORY.md"
	cat >"$TEST_ROOT/bin/ln" <<'EOF'
#!/bin/bash
for arg in "$@"; do
	[[ "$arg" == */projects/*/memory ]] && exit 1
done
exec /bin/ln "$@"
EOF
	chmod +x "$TEST_ROOT/bin/ln"
	PATH="$TEST_ROOT/bin:$PATH" run "$SYNC" sync demo
	[ "$status" -eq 1 ]
	[[ "$output" == *"cartella locale ripristinata"* ]]
	[ ! -L "$unversioned" ]
	[ "$(cat "$unversioned/MEMORY.md")" = "ricordo originale" ]
}

@test "keeps the original memory and its backup if interrupted while linking" {
	"$SYNC" sync demo >/dev/null
	local unversioned original
	unversioned="$(memory_dir_for "$WORKSPACE/beta")"
	mkdir -p "$unversioned" "$TEST_ROOT/bin"
	echo "ricordo originale" >"$unversioned/MEMORY.md"
	cat >"$TEST_ROOT/bin/ln" <<'EOF'
#!/bin/bash
for arg in "$@"; do
	if [[ "$arg" == */projects/*/memory ]]; then
		kill -TERM "$PPID"
		exit 1
	fi
done
exec /bin/ln "$@"
EOF
	chmod +x "$TEST_ROOT/bin/ln"
	PATH="$TEST_ROOT/bin:$PATH" run "$SYNC" sync demo
	[ "$status" -ne 0 ]
	original="$(find "$(dirname "$unversioned")" -path '*/memory.engramma-*/original/MEMORY.md' -type f -print -quit)"
	[ -n "$original" ]
	[ "$(cat "$original")" = "ricordo originale" ]
	[ -n "$(find "$XDG_STATE_HOME/engramma/backup/adopted" -name MEMORY.md -type f)" ]
	run "$SYNC" sync demo
	[ "$status" -eq 1 ]
	[[ "$output" == *"acquisizione interrotta; cartella originale conservata"* ]]
	[ ! -e "$unversioned" ]
}

@test "ignores memory of projects not listed in the workspace" {
	"$SYNC" sync demo >/dev/null
	local other
	other="$(memory_dir_for "$WORKSPACE/altro-progetto")"
	mkdir -p "$other"
	echo "- ricordo" >"$other/MEMORY.md"

	run "$SYNC" check demo
	[ "$status" -eq 0 ]
	[[ "$output" != *"non versionata"* ]]
}

@test "does not link a workspace memory that engramma does not have" {
	rm -rf "$NOTES/memory/_workspace"

	run "$SYNC" sync demo
	[ "$status" -eq 0 ]
	[ ! -e "$(memory_dir_for "$WORKSPACE")" ]
}

@test "clones into the folder given with --path and remembers it" {
	local custom="$HOME/progetti/demo"

	run "$SYNC" sync demo --path "$custom"
	[ "$status" -eq 0 ]
	[ -d "$custom/alpha/.git" ]
	[ ! -e "$WORKSPACE" ]
	[ "$(readlink "$custom/docs")" = "$NOTES/docs" ]
	[ "$(readlink "$(memory_dir_for "$custom/alpha")")" = "$NOTES/memory/alpha" ]
	grep -qxF "demo $custom" "$HOME/.config/engramma/paths"

	run "$SYNC" check demo
	[ "$status" -eq 0 ]
	[[ "$output" == *"~/progetti/demo"* ]]
}

@test "dry run with --path does not save the folder" {
	run "$SYNC" sync demo --path "$HOME/progetti/demo" --dry-run
	[ "$status" -eq 0 ]
	[[ "$output" == *"salverei"* ]]
	[ ! -e "$HOME/.config/engramma/paths" ]
	[ ! -e "$HOME/progetti" ]
}

@test "changing --path keeps other workspaces and leaves the old folder in place" {
	echo "altro /da/qualche/parte" >"$HOME/.config-tmp"
	mkdir -p "$HOME/.config/engramma"
	mv "$HOME/.config-tmp" "$HOME/.config/engramma/paths"
	"$SYNC" sync demo --path "$HOME/vecchia/demo" >/dev/null

	run "$SYNC" sync demo --path "$HOME/nuova/demo"
	[[ "$output" == *"prima era"* ]]
	[ -d "$HOME/vecchia/demo/alpha/.git" ]
	[ -d "$HOME/nuova/demo/alpha/.git" ]
	grep -qxF "altro /da/qualche/parte" "$HOME/.config/engramma/paths"
	grep -qxF "demo $HOME/nuova/demo" "$HOME/.config/engramma/paths"
	[ "$(grep -c '^demo ' "$HOME/.config/engramma/paths")" -eq 1 ]
}

@test "fails when an option has no value" {
	run "$SYNC" sync demo --path
	[ "$status" -eq 1 ]
	[[ "$output" == *"Manca la cartella dopo --path"* ]]
}

@test "checks only git when the workspace has no requires.txt" {
	run "$SYNC" check demo
	[[ "$output" =~ "     git "\ +"[  OK  ]" ]]
	[[ "$output" != *"pnpm"* ]]
}

@test "checks the commands listed in requires.txt" {
	printf 'git\ncomando-che-non-esiste   # serve per il deploy\n' >"$NOTES/requires.txt"
	"$SYNC" sync demo >/dev/null || true

	run "$SYNC" check demo
	[ "$status" -eq 1 ]
	[[ "$output" == *"comando-che-non-esiste non installato"* ]]
	[ "$(grep -cE "^ +git +\[  OK  \]$" <<<"$output")" -eq 1 ]
}

@test "warns without failing when node does not match .nvmrc" {
	command -v node >/dev/null || skip "node non installato"
	"$SYNC" sync demo >/dev/null
	echo "v1.0.0" >"$WORKSPACE/alpha/.nvmrc"

	run "$SYNC" check demo
	[ "$status" -eq 0 ]
	[[ "$output" == *"alpha richiede Node 1, ma nel progetto risulta Node "* ]]
	[[ "$output" == *"attiva Node 1 per alpha"* ]]
}

@test "checks the Node version selected by mise inside each project" {
	"$SYNC" sync demo >/dev/null
	echo 22 >"$WORKSPACE/alpha/.nvmrc"
	mkdir -p "$TEST_ROOT/bin"
	cat >"$TEST_ROOT/bin/mise" <<'EOF'
#!/bin/bash
if [[ "$1" == exec && "$PWD" == */alpha ]]; then
	echo v22.23.3
fi
EOF
	chmod +x "$TEST_ROOT/bin/mise"
	unset ENGRAMMA_NO_MISE
	PATH="$TEST_ROOT/bin:$PATH" run "$SYNC" check demo
	[[ "$output" == *"alpha: Node 22 richiesto e disponibile nel progetto"* ]]
	[[ "$output" != *"alpha richiede Node 22, ma"* ]]
}

@test "reports a missing optional command without failing" {
	printf 'comando-che-non-esiste facoltativo  # solo per il deploy\n' >"$NOTES/requires.txt"
	"$SYNC" sync demo >/dev/null

	run "$SYNC" check demo
	[ "$status" -eq 0 ]
	[[ "$output" == *"comando-che-non-esiste assente, facoltativo"* ]]
}

@test "reads .nvmrc files without a trailing newline" {
	command -v node >/dev/null || skip "node non installato"
	"$SYNC" sync demo >/dev/null
	printf '1' >"$WORKSPACE/alpha/.nvmrc"
	printf '1' >"$WORKSPACE/beta/.nvmrc"

	run "$SYNC" check demo
	[[ "$output" == *"alpha richiede Node 1"* ]]
	[[ "$output" == *"beta richiede Node 1"* ]]
}

@test "reports a missing .env for variables used by personal files" {
	mkdir -p "$NOTES/repo-files/beta"
	printf 'services:\n  app:\n    environment:\n      A: "${PRIMA}"\n      B: "${SECONDA:-predefinita}"\n      C: "${TERZA}"\n' >"$NOTES/repo-files/beta/compose.yaml"
	"$SYNC" sync demo >/dev/null || true

	run "$SYNC" check demo
	[ "$status" -eq 1 ]
	[[ "$output" == *".env mancante, servono PRIMA TERZA"* ]]
	[[ "$output" != *"SECONDA"* ]]

	printf 'PRIMA=valore\nTERZA=\n' >"$WORKSPACE/beta/.env"
	run "$SYNC" check demo
	[ "$status" -eq 1 ]
	[[ "$output" == *".env: variabili mancanti o vuote TERZA"* ]]

	printf 'PRIMA=valore\nTERZA=altro\n' >"$WORKSPACE/beta/.env"
	run "$SYNC" check demo
	[[ "$output" != *".env"* ]]
}

@test "ignores variables in personal files that are not Docker Compose files" {
	mkdir -p "$NOTES/repo-files/beta/.claude"
	echo 'const x = `${index}`' >"$NOTES/repo-files/beta/.claude/esempio.md"
	echo 'valore: ${NON_COMPOSE}' >"$NOTES/repo-files/beta/altro.yaml"
	"$SYNC" sync demo >/dev/null

	run "$SYNC" check demo
	[ "$status" -eq 0 ]
}

@test "links personal skills into Claude Code, whatever the workspace" {
	mkdir -p "$ENGRAMMA_DIR/skills/esempio"
	printf -- '---\nname: esempio\n---\n' >"$ENGRAMMA_DIR/skills/esempio/SKILL.md"

	run "$SYNC" sync demo
	[ "$status" -eq 0 ]
	[ "$(readlink "$ENGRAMMA_CLAUDE_HOME/skills/esempio")" = "$ENGRAMMA_DIR/skills/esempio" ]

	run "$SYNC" check global
	[ "$status" -eq 0 ]
	[[ "$output" == *"skill esempio → symlink ok"* ]]
}

@test "never overwrites a real skill folder with the same name" {
	mkdir -p "$ENGRAMMA_DIR/skills/esempio" "$ENGRAMMA_CLAUDE_HOME/skills/esempio"
	echo "mia" >"$ENGRAMMA_CLAUDE_HOME/skills/esempio/SKILL.md"

	run "$SYNC" sync demo
	[[ "$output" == *"skill esempio: cartella locale con 1 file che engramma non ha"* ]]
	[ "$(cat "$ENGRAMMA_CLAUDE_HOME/skills/esempio/SKILL.md")" = mia ]
}

@test "reports unversioned skills without failing, unless ignored" {
	mkdir -p "$ENGRAMMA_CLAUDE_HOME/skills/mia" "$ENGRAMMA_CLAUDE_HOME/skills/strumento" "$ENGRAMMA_CLAUDE_HOME/skills/cartella-senza-skill"
	touch "$ENGRAMMA_CLAUDE_HOME/skills/mia/SKILL.md" "$ENGRAMMA_CLAUDE_HOME/skills/strumento/SKILL.md"
	echo "strumento  # installata da uno strumento" >"$ENGRAMMA_DIR/skills-ignore.txt"
	"$SYNC" sync demo >/dev/null

	run "$SYNC" check global
	[ "$status" -eq 0 ]
	[[ "$output" == *"skill mia non versionata"* ]]
	[[ "$output" != *"skill strumento"* ]]
	[[ "$output" != *"cartella-senza-skill"* ]]
}

@test "removes the link of a skill removed from engramma, and only that" {
	mkdir -p "$ENGRAMMA_DIR/skills/esempio" "$TEST_ROOT/altrove/esterna" "$ENGRAMMA_CLAUDE_HOME/skills"
	echo skill >"$ENGRAMMA_DIR/skills/esempio/SKILL.md"
	"$SYNC" sync demo >/dev/null
	rm -r "$ENGRAMMA_DIR/skills/esempio"
	ln -s "$TEST_ROOT/altrove/esterna" "$ENGRAMMA_CLAUDE_HOME/skills/esterna"
	ln -s "$TEST_ROOT/altrove/sparita" "$ENGRAMMA_CLAUDE_HOME/skills/sparita"

	run "$SYNC" check global
	[[ "$output" == *"skill esempio: non è più in engramma, symlink rimasto"* ]]
	[ -L "$ENGRAMMA_CLAUDE_HOME/skills/esempio" ]

	run "$SYNC" sync demo -n
	[[ "$output" == *"skill esempio: non è più in engramma → toglierei il symlink"* ]]
	[ -L "$ENGRAMMA_CLAUDE_HOME/skills/esempio" ]

	run "$SYNC" sync demo
	[ "$status" -eq 0 ]
	[[ "$output" == *"skill esempio: non è più in engramma, symlink tolto"* ]]
	[ ! -L "$ENGRAMMA_CLAUDE_HOME/skills/esempio" ]
	[ -L "$ENGRAMMA_CLAUDE_HOME/skills/esterna" ]
	[ -L "$ENGRAMMA_CLAUDE_HOME/skills/sparita" ]
}

engramma_links_under_home() {
	find "$HOME" -path '*/.git' -prune -o -type l -lname "$ENGRAMMA_DIR/*" -print
}

setup_full_workspace() {
	mkdir -p "$NOTES/repo-files/beta" "$ENGRAMMA_DIR/skills/esempio"
	echo "services: {}" >"$NOTES/repo-files/beta/compose.yaml"
	echo "skill" >"$ENGRAMMA_DIR/skills/esempio/SKILL.md"
	"$SYNC" sync demo >/dev/null
}

@test "detach replaces every engramma link of the workspace with an independent copy" {
	setup_full_workspace

	run "$SYNC" detach demo
	[ "$status" -eq 0 ]

	[ ! -L "$WORKSPACE/docs" ]
	[ "$(cat "$WORKSPACE/docs/guida.md")" = guida ]
	[ ! -L "$WORKSPACE/.claude" ]
	[ ! -L "$(memory_dir_for "$WORKSPACE/alpha")" ]
	[ "$(cat "$(memory_dir_for "$WORKSPACE/alpha")/MEMORY.md")" = "- memoria alpha" ]
	[ ! -L "$WORKSPACE/beta/compose.yaml" ]
	[ "$(cat "$WORKSPACE/alpha/CLAUDE.local.md")" = "nota alpha" ]
	[ -z "$(git -C "$WORKSPACE/alpha" status --porcelain)" ]
	[ -z "$(git -C "$WORKSPACE/beta" status --porcelain)" ]
	[ -L "$ENGRAMMA_CLAUDE_HOME/skills/esempio" ]
}

@test "after detach-all engramma can be deleted without breaking anything" {
	setup_full_workspace

	run "$SYNC" detach all
	[ "$status" -eq 0 ]
	[ -z "$(engramma_links_under_home)" ]

	rm -rf "$ENGRAMMA_DIR"
	[ "$(cat "$WORKSPACE/docs/guida.md")" = guida ]
	[ "$(cat "$WORKSPACE/beta/compose.yaml")" = "services: {}" ]
	[ "$(cat "$ENGRAMMA_CLAUDE_HOME/skills/esempio/SKILL.md")" = skill ]
	[ "$(cat "$WORKSPACE/alpha/CLAUDE.local.md")" = "nota alpha" ]
}

@test "detach with --dry-run changes nothing" {
	setup_full_workspace
	before="$(snapshot)"

	run "$SYNC" detach all --dry-run
	[ "$status" -eq 0 ]
	[[ "$output" == *"symlink → copia"* ]]
	[ "$(snapshot)" = "$before" ]
}

@test "detach leaves links that do not point into engramma untouched" {
	mkdir -p "$WORKSPACE" "$TEST_ROOT/altrove"
	ln -s "$TEST_ROOT/altrove" "$WORKSPACE/docs"

	run "$SYNC" detach demo
	[ "$status" -eq 0 ]
	[ "$(readlink "$WORKSPACE/docs")" = "$TEST_ROOT/altrove" ]
}

@test "detach is idempotent" {
	setup_full_workspace
	"$SYNC" detach demo >/dev/null
	before="$(snapshot)"

	run "$SYNC" detach demo
	[ "$status" -eq 0 ]
	[ "$(snapshot)" = "$before" ]
}

@test "detach refuses --check" {
	run "$SYNC" detach --check demo
	[ "$status" -eq 1 ]
}

@test "detach-all refuses a workspace name, --path or --skip" {
	run "$SYNC" detach all --path "$HOME/altrove"
	[ "$status" -eq 1 ]
	run "$SYNC" detach all demo
	[ "$status" -eq 1 ]
	run "$SYNC" detach all --skip alpha
	[ "$status" -eq 1 ]
}

@test "detach-all uses the folder saved for each workspace" {
	mkdir -p "$ENGRAMMA_DIR/skills/esempio"
	echo skill >"$ENGRAMMA_DIR/skills/esempio/SKILL.md"
	"$SYNC" sync demo --path "$HOME/dev/demo" >/dev/null

	run "$SYNC" detach all
	[ "$status" -eq 0 ]
	[ ! -L "$HOME/dev/demo/docs" ]
	[ "$(cat "$HOME/dev/demo/docs/guida.md")" = guida ]
}


@test "a workspace named alone is a read-only check of that workspace" {
	local before
	before="$(snapshot)"
	run "$SYNC" demo
	[ "$status" -eq 1 ]
	[[ "$output" == *"demo"* ]]
	[[ "$output" != *"POSTAZIONE"* ]]
	[ "$(snapshot)" = "$before" ]
	[ ! -e "$WORKSPACE/alpha" ]

	"$SYNC" sync demo >/dev/null
	run "$SYNC" demo
	[ "$status" -eq 0 ]
}

@test "without a workspace sync and check cover the workspaces present on this computer" {
	"$SYNC" setup >/dev/null
	run "$SYNC"
	[ "$status" -eq 0 ]
	[[ "$output" == *"non ancora su questo computer"*"eng sync demo"* ]]

	"$SYNC" sync demo >/dev/null
	push_to_remote beta main "nuovo lavoro"
	run "$SYNC" sync
	[ "$status" -eq 0 ]
	[ "$(git -C "$WORKSPACE/beta" rev-parse HEAD)" = "$(git -C "$(remote_path beta)" rev-parse main)" ]
}

@test "shows only changes and problems unless verbose" {
	"$SYNC" sync demo >/dev/null
	ENGRAMMA_VERBOSE= run "$SYNC" check
	[ "$status" -eq 0 ]
	[[ "$output" != *"symlink ok"* ]]
	[[ "$output" =~ " demo  ~/workspace/demo  · "[0-9]+" controlli ok "·+" [  OK  ]" ]]
	[[ "$output" == *"tutto a posto"* ]]

	ENGRAMMA_VERBOSE= run "$SYNC" check -v
	[[ "$output" == *"symlink ok"* ]]
}

@test "rejects the old options with a pointer to the help" {
	run "$SYNC" --global
	[ "$status" -eq 1 ]
	[[ "$output" == *"Opzione sconosciuta: --global"* ]]
	[[ "$output" == *"eng --help"* ]]

	run "$SYNC" check demo --dry-run
	[ "$status" -eq 1 ]
}

@test "links the workspace AGENTS.md and warns about instructions too big for Codex" {
	mkdir -p "$TEST_ROOT/bin" "$ENGRAMMA_DIR/global"
	printf '#!/bin/sh\nexit 0\n' >"$TEST_ROOT/bin/codex"
	chmod +x "$TEST_ROOT/bin/codex"
	echo codex >"$ENGRAMMA_DIR/global/requires.txt"
	mkdir -p "$HOME/.codex"
	printf 'project_doc_fallback_filenames = ["CLAUDE.md"]\n[features]\nshell_snapshot = false\n' >"$HOME/.codex/config.toml"
	echo "regole del workspace" >"$NOTES/AGENTS.md"
	echo "@../AGENTS.md" >"$NOTES/.claude/CLAUDE.md"
	head -c 40000 /dev/zero | tr '\0' 'x' >"$TEST_ROOT/seeds/alpha/AGENTS.md"
	git -C "$TEST_ROOT/seeds/alpha" add AGENTS.md
	push_to_remote alpha develop "istruzioni del team"

	PATH="$TEST_ROOT/bin:$PATH" run "$SYNC" sync demo
	[ "$(readlink "$WORKSPACE/AGENTS.md")" = "$NOTES/AGENTS.md" ]
	[[ "$output" == *"AGENTS.md: 39 KB, oltre i 32 KB di project_doc_max_bytes"* ]]
	[[ "$output" != *"AGENTS.md del workspace"* ]]
	[ ! -e "$WORKSPACE/alpha/AGENTS.override.md" ]
}

@test "refuses a repo listed in a folder reserved to the notes of the workspace" {
	make_remote docs main-only
	echo "docs $(remote_path docs)" >>"$NOTES/repos.txt"

	run "$SYNC" sync demo
	[ "$status" -eq 1 ]
	[[ "$output" == *"docs"*"cartella riservata agli appunti del workspace, repo non toccato"* ]]
	[[ "$output" == *"rinomina la cartella del repo: remotes-docs $(remote_path docs)"* ]]
	[ "$(readlink "$WORKSPACE/docs")" = "$NOTES/docs" ]
}

@test "names the repo cloned by hand where the notes should be linked, and how to move it" {
	make_remote docs main-only
	mkdir -p "$WORKSPACE"
	git clone --quiet "$(remote_path docs)" "$WORKSPACE/docs"

	run "$SYNC" sync demo
	[ "$status" -eq 1 ]
	[[ "$output" == *"docs è un clone git di $(remote_path docs), non gli appunti di engramma: non lo tocco"* ]]
	[[ "$output" == *"mv ~/workspace/demo/docs ~/workspace/demo/remotes-docs"*"aggiungi remotes-docs $(remote_path docs)"* ]]
	[ -d "$WORKSPACE/docs/.git" ]
}

# The output without what changes at every run: time, quote, log.
stable_output() {
	"$SYNC" "$@" | sed -E 's/ · [0-9]+s/ · Ns/; s/(·)+ \[/· [/; /❝/d; /log: /d'
}

@test "the output does not depend on how many repos are synced at the same time" {
	for name in gamma delta; do
		make_remote "$name" main-only
		echo "$name $(remote_path "$name")" >>"$NOTES/repos.txt"
	done
	"$SYNC" sync demo >/dev/null
	push_to_remote beta main "nuovo lavoro su beta"
	git -C "$WORKSPACE/gamma" switch --quiet -c issue/aperta
	git -C "$WORKSPACE/gamma" commit --quiet --allow-empty -m "lavoro in corso"
	local first second

	first="$(stable_output sync demo -j 1)"
	git -C "$WORKSPACE/beta" reset --quiet --hard HEAD~1
	second="$(stable_output sync demo --jobs 4)"
	[ "$first" = "$second" ]
	[[ "$first" == *"beta"*"main"*"→"* ]]
	[[ "$first" == *"gamma"*"issue/aperta"*"ancora in corso"* ]]

	git -C "$WORKSPACE/beta" reset --quiet --hard HEAD~1
	mkdir -p "$XDG_CONFIG_HOME/engramma"
	echo "parallel = false  # uno alla volta" >"$XDG_CONFIG_HOME/engramma/config"
	[ "$(stable_output sync demo)" = "$first" ]
}

@test "--prune deletes the merged branches without asking" {
	"$SYNC" sync demo >/dev/null
	git -C "$WORKSPACE/alpha" branch issue/finita

	run "$SYNC" sync demo --prune
	[ "$status" -eq 0 ]
	[[ "$output" == *"alpha: branch locale issue/finita eliminato"* ]]
	! git -C "$WORKSPACE/alpha" rev-parse --verify --quiet refs/heads/issue/finita
}

@test "names the slow repos and the failed ones in the summary" {
	echo "rotto $TEST_ROOT/remotes/manca.git" >>"$NOTES/repos.txt"

	ENGRAMMA_SLOW_REPO_SECONDS=-1 run "$SYNC" sync demo
	[ "$status" -eq 1 ]
	[[ "$output" == *"repo falliti  demo/rotto"* ]]
	[[ "$output" =~ "repo lenti  oltre -1s  demo/alpha "[0-9]+"s · demo/beta "[0-9]+"s" ]]
}

@test "--jobs wants a number, and --jobs and --prune work only with sync" {
	run "$SYNC" sync demo -j
	[ "$status" -eq 1 ]
	[[ "$output" == *"Manca il numero dopo -j"* ]]
	run "$SYNC" sync demo --jobs tre
	[ "$status" -eq 1 ]
	run "$SYNC" setup --prune
	[ "$status" -eq 1 ]
	[[ "$output" == *"--jobs e --prune valgono solo con sync"* ]]
}

@test "warns about absolute paths in engramma and proposes the ~/ form" {
	echo 'Leggi /home/nessuno-qui/progetto/README.md, poi /home/nessuno-qui/progetto/**' >"$NOTES/AGENTS.md"
	echo 'Read($HOME/x) e /home' >>"$NOTES/AGENTS.md"
	echo '{"permissions": {"allow": ["Read(/home/nessuno-qui/dati/**)"]}}' >"$NOTES/.claude/settings.json"
	echo '- /home/nessuno-qui/ricordo' >>"$NOTES/memory/alpha/MEMORY.md"

	run "$SYNC" sync demo
	[ "$status" -eq 0 ]
	[[ "$output" == *"percorso assoluto /home/nessuno-qui/progetto/README.md: scrivi ~/progetto/README.md · qui non esiste in workspaces/demo/AGENTS.md"* ]]
	[[ "$output" == *"percorso assoluto /home/nessuno-qui/progetto: scrivi ~/progetto · qui non esiste"* ]]
	[[ "$output" == *"permesso Read(/home/nessuno-qui/dati/**) con una sola / iniziale"*"scrivi Read(~/dati/**) in workspaces/demo/.claude/settings.json"* ]]
	[ "$(grep -c 'percorso assoluto\|una sola /' <<<"${output%%────*}")" -eq 3 ]
}

@test "a branch removed on origin with commits never pushed is only listed, --prune deletes it" {
	"$SYNC" sync demo >/dev/null
	git -C "$WORKSPACE/alpha" switch --quiet -c feat/locale
	git -C "$WORKSPACE/alpha" push --quiet -u origin feat/locale
	git -C "$WORKSPACE/alpha" commit --quiet --allow-empty -m "lavoro mai pushato"
	git -C "$WORKSPACE/alpha" switch --quiet develop
	git -C "$(remote_path alpha)" branch --quiet -D feat/locale

	run "$SYNC" sync demo
	[ "$status" -eq 0 ]
	[[ "$output" == *"alpha lasciati feat/locale: commit non presenti sul remoto"* ]]
	[[ "$output" == *"eng sync demo --prune: cancella senza chiedere i branch locali mergiati o rimossi dal remoto, anche quelli con commit solo locali"* ]]
	git -C "$WORKSPACE/alpha" rev-parse --verify --quiet refs/heads/feat/locale

	run "$SYNC" sync demo --prune
	[ "$status" -eq 0 ]
	[[ "$output" == *"alpha: branch locale feat/locale eliminato"* ]]
	! git -C "$WORKSPACE/alpha" rev-parse --verify --quiet refs/heads/feat/locale
}

@test "list shows the workspaces with their folder and repos, changing nothing" {
	run "$SYNC" list
	[ "$status" -eq 0 ]
	[[ "$output" == *"demo"*"non su questo computer"*"alpha"* ]]
	[ ! -d "$WORKSPACE" ]

	"$SYNC" sync demo >/dev/null
	run "$SYNC" list demo
	[ "$status" -eq 0 ]
	[[ "$output" == *"● alpha"* ]]
	[[ "$output" != *"non su questo computer"* ]]
}

@test "a git lock left by an interrupted operation is reported, then removed" {
	"$SYNC" sync demo >/dev/null
	touch -d '-5 minutes' "$WORKSPACE/alpha/.git/index.lock" 2>/dev/null || touch -t 202001010000 "$WORKSPACE/alpha/.git/index.lock"

	run "$SYNC" check demo
	[[ "$output" == *"blocco di git rimasto da un'operazione interrotta"* ]]
	[ -f "$WORKSPACE/alpha/.git/index.lock" ]

	run "$SYNC" sync demo
	[[ "$output" == *"blocco di git rimasto da un'operazione interrotta: tolto"* ]]
	[ ! -f "$WORKSPACE/alpha/.git/index.lock" ]
}

@test "a fresh git lock is left alone" {
	"$SYNC" sync demo >/dev/null
	touch "$WORKSPACE/alpha/.git/index.lock"

	run "$SYNC" sync demo
	[ -f "$WORKSPACE/alpha/.git/index.lock" ]
	rm "$WORKSPACE/alpha/.git/index.lock"
}

@test "project skill is private to its repository and detachable" {
	mkdir -p "$NOTES/skills/beta/layout"
	echo "Layout" >"$NOTES/skills/beta/layout/SKILL.md"
	run "$SYNC" sync demo
	[ "$status" -eq 0 ]
	[ -L "$WORKSPACE/beta/.agents/skills/layout" ]
	[ ! -e "$WORKSPACE/alpha/.agents/skills/layout" ]
	[ -z "$(git -C "$WORKSPACE/beta" status --porcelain)" ]
	run "$SYNC" detach demo
	[ "$status" -eq 0 ]
	[ ! -L "$WORKSPACE/beta/.agents/skills/layout" ]
	[ "$(cat "$WORKSPACE/beta/.agents/skills/layout/SKILL.md")" = Layout ]
}
