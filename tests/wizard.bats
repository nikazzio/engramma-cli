#!/usr/bin/env bats

load helpers

setup() {
	setup_sandbox
	ARCHIVE_CONFIG="$XDG_CONFIG_HOME/engramma/archive"
	SOURCE="$ENGRAMMA_DIR"
	unset ENGRAMMA_DIR ENGRAMMA_VERBOSE
	mkdir -p "$HOME/.local/bin"
	printf '#!/bin/sh\nexit 0\n' >"$HOME/.local/bin/claude"
	chmod +x "$HOME/.local/bin/claude"
	git -C "$SOURCE" init -q
	git -C "$SOURCE" add -A
	git -C "$SOURCE" commit -qm 'Archivio di prova'
	git clone -q --bare "$SOURCE" "$TEST_ROOT/archive.git"
	git -C "$SOURCE" remote add origin "$TEST_ROOT/archive.git"
	git -C "$SOURCE" push -qu origin main
}

teardown() {
	teardown_sandbox
}

@test "first setup in a terminal opens the wizard and q leaves the workstation untouched" {
	run_in_terminal 110 'q\n' '"$SYNC" setup --plain'
	[ "$status" -eq 0 ]
	[[ "$output" == *"Configurazione guidata di Engramma"*"Configurazione annullata"* ]]
	[ ! -e "$ARCHIVE_CONFIG" ]
	[ ! -e "$HOME/engramma-dati" ]
	[ ! -L "$HOME/.local/bin/eng" ]
	[ ! -d "$XDG_STATE_HOME/engramma" ]
}

@test "first wizard setup creates an archive with Claude and defaults memory to off" {
	run_in_terminal 110 '\n\nclaude\n\ns\n' '"$SYNC" setup --plain'
	[ "$status" -eq 0 ]
	[[ "$output" == *"1. Archivio"*"2. Agenti"*"3. Memoria di Claude"*"4. Anteprima"* ]]
	[[ "$output" == *"Memoria di Claude: disattivata"* ]]
	[ "$(cat "$ARCHIVE_CONFIG")" = "$HOME/engramma-dati" ]
	[ -L "$HOME/.local/bin/eng" ]
	[ -L "$ENGRAMMA_CLAUDE_HOME/CLAUDE.md" ]
	run "$SYNC" agents
	[[ "$output" == *"claude   attivo"* && "$output" == *"sincronizzazione disattivata"* ]]
}

@test "the wizard can go back and change agent choice before cancelling at review" {
	run_in_terminal 110 '\n\nclaude\ni\nnone\ni\nnone\nn\n' '"$SYNC" setup --plain'
	[ "$status" -eq 0 ]
	[[ "$output" == *"3. Memoria di Claude"*"2. Agenti"*"Agenti: none"*"4. Anteprima"*"Configurazione annullata"* ]]
	[ ! -e "$ARCHIVE_CONFIG" ]
	[ ! -e "$HOME/engramma-dati" ]
	[ ! -L "$HOME/.local/bin/eng" ]
}

@test "wizard preview on an existing local archive writes neither settings nor logs" {
	run_in_terminal 110 "2\n$SOURCE\nnone\nn\n" '"$SYNC" setup --wizard --plain'
	[ "$status" -eq 0 ]
	[[ "$output" == *"4. Anteprima"*"prova finita"*"Configurazione annullata"* ]]
	[ ! -e "$ARCHIVE_CONFIG" ]
	[ ! -d "$XDG_STATE_HOME/engramma" ]
	[ ! -e "$XDG_CONFIG_HOME/engramma/agent-profiles" ]
	[ ! -L "$HOME/.local/bin/eng" ]
}

@test "the guided dry run stops at review and does not clone the remote" {
	run_in_terminal 110 "3\nfile://$TEST_ROOT/archive.git\n\nnone\n" '"$SYNC" setup --wizard -n --plain'
	[ "$status" -eq 0 ]
	[[ "$output" == *"4. Anteprima"*"clonerei"* ]]
	[[ "$output" != *"Applicare la configurazione?"* ]]
	[ ! -e "$ARCHIVE_CONFIG" ]
	[ ! -e "$HOME/engramma-dati" ]
}

@test "the wizard clones a remote to a path with spaces and syncs the chosen workspace" {
	run_in_terminal 110 "3\nfile://$TEST_ROOT/archive.git\n$HOME/dati di prova\nnone\ns\ndemo\n" '"$SYNC" setup --wizard --plain'
	[ "$status" -eq 0 ]
	[[ "$output" == *"archivio clonato"*"5. Primo workspace"* ]]
	[ "$(cat "$ARCHIVE_CONFIG")" = "$HOME/dati di prova" ]
	[ -d "$WORKSPACE/alpha/.git" ]
}

@test "an archive created through init is guided once and the wizard can be reopened" {
	"$SYNC" init >/dev/null
	run_in_terminal 110 '\nnone\ns\n\n' '"$SYNC" setup --plain'
	[ "$status" -eq 0 ]
	[[ "$output" == *"Archivio selezionato: ~/engramma-dati"* ]]
	run_in_terminal 110 '' '"$SYNC" setup --plain'
	[ "$status" -eq 0 ]
	[[ "$output" != *"Configurazione guidata di Engramma"* ]]
	run_in_terminal 110 'q\n' '"$SYNC" setup --wizard --plain'
	[ "$status" -eq 0 ]
	[[ "$output" == *"Configurazione guidata di Engramma"*"Configurazione annullata"* ]]
}

@test "direct setup flags and noninteractive mode do not start the wizard" {
	run_in_terminal 110 '' '"$SYNC" setup --non-interactive --plain'
	[ "$status" -eq 1 ]
	[[ "$output" != *"Configurazione guidata di Engramma"* ]]
	run "$SYNC" setup --wizard --non-interactive
	[ "$status" -eq 2 ]
	[[ "$output" == *"richiede un terminale interattivo"* ]]
	run_in_terminal 110 '' '"$SYNC" setup --agents none --plain'
	[ "$status" -eq 1 ]
	[[ "$output" != *"Configurazione guidata di Engramma"* ]]
}
