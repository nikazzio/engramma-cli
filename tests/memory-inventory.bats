#!/usr/bin/env bats

load helpers

setup() {
	setup_sandbox
	mkdir -p "$HOME/.local/bin"
	unset ENGRAMMA_VERBOSE
	git -C "$ENGRAMMA_DIR" init -q
	git -C "$ENGRAMMA_DIR" add -A
	git -C "$ENGRAMMA_DIR" commit -qm 'Archivio di prova'
	git clone -q --bare "$ENGRAMMA_DIR" "$TEST_ROOT/archive.git"
	git -C "$ENGRAMMA_DIR" remote add origin "$TEST_ROOT/archive.git"
	git -C "$ENGRAMMA_DIR" push -qu origin main
}

teardown() {
	teardown_sandbox
}

@test "inventory counts acquisition, commit and confirmed push and logs a file with spaces" {
	local root
	root="$(memory_dir_for "$WORKSPACE/beta")"
	mkdir -p "$root"
	printf 'Contenuto privato fittizio\n' >"$root/nota di prova.md"

	run "$SYNC" sync demo
	[ "$status" -eq 0 ]
	[[ "$output" == *"postazione · 1 copiato"* ]]
	[[ "$output" == *"salvataggio · 1 salvato"* && "$output" == *"invio · 1 inviato"* ]]
	[[ "$output" != *"nota di prova.md"* ]]
	[ -L "$root" ]

	run "$SYNC" log
	[[ "$output" == *'postazione · copiati · ambito demo/beta · file nota\ di\ prova.md'* ]]
	[[ "$output" == *'salvataggio · salvati · ambito demo/beta · file nota\ di\ prova.md'* ]]
	[[ "$output" == *'invio · inviati · ambito demo/beta · file nota\ di\ prova.md'* ]]
	[[ "$output" != *"Contenuto privato fittizio"* ]]
	local logfile
	for logfile in "$XDG_STATE_HOME"/engramma/logs/*.log; do
		[ "$(stat -c %a "$logfile")" = 600 ]
	done
}

@test "dry run and failed sync show both conflicting and blocked files without adopting them" {
	local root
	root="$(memory_dir_for "$WORKSPACE/alpha")"
	mkdir -p "$root"
	printf 'copia locale\n' >"$root/MEMORY.md"
	printf 'nuova nota\n' >"$root/extra.md"

	run "$SYNC" sync demo -n -v
	[ "$status" -eq 1 ]
	[[ "$output" == *"conflitto · ambito demo/alpha · file MEMORY.md"* ]]
	[[ "$output" == *"bloccati · ambito demo/alpha · file extra.md"* ]]
	[ ! -e "$NOTES/memory/alpha/extra.md" ]

	run "$SYNC" sync demo
	[ "$status" -eq 1 ]
	[[ "$output" == *"1 conflitto · 1 bloccato"* ]]
	[ ! -L "$root" ]
	[ ! -e "$NOTES/memory/alpha/extra.md" ]

	run "$SYNC" log
	[[ "$output" == *"conflitto · ambito demo/alpha · file MEMORY.md"* ]]
	[[ "$output" == *"bloccati · ambito demo/alpha · file extra.md"* ]]
}

@test "a partial local copy records the actual copied file and the file left behind" {
	local root
	root="$(memory_dir_for "$WORKSPACE/beta")"
	mkdir -p "$root"
	printf 'prima\n' >"$root/a.md"
	printf 'seconda\n' >"$root/b.md"
	cat >"$HOME/.local/bin/cp" <<'EOF'
#!/usr/bin/env bash
[[ $* != *' -n -T '* || "${@: -2:1}" != */b.md ]] || exit 9
exec /usr/bin/cp "$@"
EOF
	chmod +x "$HOME/.local/bin/cp"

	run "$SYNC" sync demo
	[ "$status" -eq 1 ]
	[ -f "$NOTES/memory/beta/a.md" ]
	[ ! -e "$NOTES/memory/beta/b.md" ]
	[ ! -L "$root" ]
	cmp "$root/a.md" "$NOTES/memory/beta/a.md"
	run "$SYNC" log
	[[ "$output" == *"copiati · ambito demo/beta · file a.md · collegamento non riuscito"* ]]
	[[ "$output" == *"bloccati · ambito demo/beta · file b.md"* ]]
}

@test "the remote inventory counts additions and deletions only after fast forward" {
	local other="$TEST_ROOT/other"
	git clone -q "$TEST_ROOT/archive.git" "$other"
	git -C "$other" rm -q workspaces/demo/memory/alpha/MEMORY.md
	mkdir -p "$other/workspaces/demo/memory/beta"
	printf 'nota ricevuta\n' >"$other/workspaces/demo/memory/beta/note.md"
	git -C "$other" add -A
	git -C "$other" commit -qm 'Sostituzione memoria'
	git -C "$other" push -q

	run "$SYNC" sync demo
	[ "$status" -eq 0 ]
	[[ "$output" == *"ricezione · 2 ricevuti"* ]]
	run "$SYNC" log
	[[ "$output" == *"ricezione · ricevuti · ambito demo/alpha · file MEMORY.md · eliminazione"* ]]
	[[ "$output" == *"ricezione · ricevuti · ambito demo/beta · file note.md · aggiunta"* ]]
}

@test "save keeps its own log and distinguishes a failed push from a successful retry" {
	printf 'modifica locale\n' >>"$NOTES/memory/alpha/MEMORY.md"
	printf '#!/bin/sh\nexit 1\n' >"$TEST_ROOT/archive.git/hooks/pre-receive"
	chmod +x "$TEST_ROOT/archive.git/hooks/pre-receive"

	run "$SYNC" save demo
	[ "$status" -eq 1 ]
	[[ "$output" == *"salvataggio · 1 salvato"* && "$output" == *"invio · 1 invio da riprovare"* ]]
	run "$SYNC" log
	[[ "$output" == *"salvataggio · salvati · ambito demo/alpha · file MEMORY.md"* ]]
	[[ "$output" == *"push dell’archivio fallito"* && "$output" == *"invio da riprovare · ambito demo/alpha"* ]]
	[[ "$output" != *"invio · inviati"* ]]

	printf '#!/bin/sh\nexit 0\n' >"$TEST_ROOT/archive.git/hooks/pre-receive"
	run "$SYNC" save demo
	[ "$status" -eq 0 ]
	[[ "$output" == *"invio · 1 inviato"* && "$output" != *"salvataggio · 1 salvato"* ]]
	run "$SYNC" log
	[[ "$output" == *"invio · inviati · ambito demo/alpha · file MEMORY.md"* ]]
}

@test "disabled memory and unknown scopes show the reasons for each exclusion" {
	"$SYNC" setup --agents none >/dev/null
	mkdir -p "$NOTES/memory/fuori-archivio"
	printf 'nota non collegata\n' >"$NOTES/memory/fuori-archivio/vecchia.md"

	run "$SYNC" sync demo -n -v
	[ "$status" -eq 0 ]
	[[ "$output" == *"postazione · esclusi · ambito demo/alpha · file MEMORY.md · sincronizzazione della memoria disattivata"* ]]
	[[ "$output" == *"postazione · esclusi · ambito demo/fuori-archivio · file vecchia.md · ambito non dichiarato"* ]]
	[[ "$output" == *"salvataggio · esclusi · ambito demo/fuori-archivio · file vecchia.md"* ]]
}

@test "eng log uses the newest write even when the newest filename sorts first" {
	local logs="$XDG_STATE_HOME/engramma/logs"
	mkdir -p "$logs"
	printf 'prima esecuzione\n' >"$logs/2026-11-28-000000.log"
	printf 'seconda esecuzione\n' >"$logs/2026-11-28-000000-123.log"
	touch -t 202611280000.00 "$logs/2026-11-28-000000.log"
	touch -t 202611280000.01 "$logs/2026-11-28-000000-123.log"

	run "$SYNC" log
	[ "$status" -eq 0 ]
	[ "$output" = "seconda esecuzione" ]
}
