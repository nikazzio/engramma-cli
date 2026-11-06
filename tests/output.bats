#!/usr/bin/env bats

load helpers

setup() {
	setup_sandbox
	unset ENGRAMMA_VERBOSE
}

teardown() {
	teardown_sandbox
}

log_files() {
	find "$HOME/.local/state/engramma/logs" -name '*.log' | sort
}

@test "in a terminal the live zone shows the progress and gives the cursor back" {
	run_in_terminal 100 "" '"$SYNC" sync demo'
	[ "$status" -eq 0 ]
	[[ "$output" == *$'\e[?25l'* ]]
	[[ "$output" == *"/2 repo · "* ]]
	[[ "$output" == *"tutto a posto"* ]]
	# The zone is erased and the cursor shown again after the last line.
	[[ "${output##*tutto a posto}" == *$'\e[?25h'* ]]
	[[ "${output##*$'\e[?25h'}" != *"repo · "* ]]
}

@test "the lines of the live zone are cut to the width of the terminal" {
	run_in_terminal 40 "" '"$SYNC" sync demo'
	[ "$status" -eq 0 ]
	[[ "$output" == *"…"* ]]
}

@test "outside a terminal the output has no control codes, even with colors allowed" {
	run env -u NO_COLOR "$SYNC" sync demo
	[ "$status" -eq 0 ]
	[[ "$output" != *$'\e'* ]]
	[[ "$output" == *"tutto a posto"* ]]
}

@test "Ctrl+C stops the zone, gives the cursor back and stops the repo jobs" {
	command -v script >/dev/null || skip "script non installato"
	"$SYNC" sync demo >/dev/null
	use_slow_fetch 5
	# Ctrl+C to engramma in the foreground, as the user presses it, once a fetch has
	# started however slow the machine is. A command started with & would ignore it,
	# and so does a CI runner that starts its jobs with SIGINT ignored: env resets it.
	export TEST_ROOT
	run_in_terminal 100 "" '(for i in $(seq 100); do [ -e "$TEST_ROOT/slow/fetching" ] && break; sleep 0.1; done; sleep 0.3; kill -INT "$(cat "$TEST_ROOT/eng.pid")") & sh -c "echo \$\$ >\"$TEST_ROOT/eng.pid\"; exec env --default-signal=INT \"$SYNC\" sync demo"; echo "uscita $?"'
	echo "$output"
	[[ "$output" == *"uscita 130"* ]]
	[[ "${output##*repo · }" == *$'\e[?25h'* ]]
	sleep 0.3
	! pgrep -f "$TEST_ROOT/slow/git" >/dev/null
}

@test "a question about merged branches stops the zone and is shown with its block" {
	"$SYNC" sync demo >/dev/null
	git -C "$WORKSPACE/alpha" branch issue/uno
	git -C "$WORKSPACE/beta" branch issue/due
	git -C "$WORKSPACE/beta" switch --quiet -c feat/locale
	git -C "$WORKSPACE/beta" push --quiet -u origin feat/locale
	git -C "$WORKSPACE/beta" commit --quiet --allow-empty -m "lavoro mai pushato"
	git -C "$WORKSPACE/beta" switch --quiet main
	git -C "$(remote_path beta)" branch --quiet -D feat/locale

	run_in_terminal 100 'c\nn\ns\n' '"$SYNC" sync demo'
	[ "$status" -eq 0 ]
	[[ "$output" == *"lasciati "*"feat/locale"*": commit non presenti sul remoto"* ]]
	git -C "$WORKSPACE/beta" rev-parse --verify --quiet refs/heads/feat/locale
	[[ "$output" == *"issue/uno"*"issue/due"*"Cancello i 2 branch locali elencati con commit presenti sul remoto (2 repo)?"* ]]
	[[ "$output" == *"alpha: cancello i branch locali issue/uno? [s/N]"*"beta: cancello i branch locali issue/due? [s/N]"* ]]
	git -C "$WORKSPACE/alpha" rev-parse --verify --quiet refs/heads/issue/uno
	! git -C "$WORKSPACE/beta" rev-parse --verify --quiet refs/heads/issue/due
}

@test "every run leaves a full log without colors, with the lines hidden without -v" {
	run_in_terminal 100 "" '"$SYNC" sync demo'
	[ "$status" -eq 0 ]
	local log
	log="$(log_files | tail -n 1)"
	[[ "$output" == *"log: ~/.local/state/engramma/logs/$(basename "$log")"* ]]
	grep -q 'localhost.demo.test nel file hosts' "$log"
	grep -q 'tutto a posto' "$log"
	! grep -q $'\e' "$log"

	run "$SYNC" sync demo
	[[ "$output" != *"localhost.demo.test nel file hosts"* ]]
	grep -q 'localhost.demo.test nel file hosts' "$(log_files | tail -n 1)"
}

@test "the log keeps the stderr of git and only the last 20 runs" {
	mkdir -p "$HOME/.local/state/engramma/logs"
	for day in $(seq -w 1 25); do
		touch "$HOME/.local/state/engramma/logs/2020-01-$day-000000.log"
	done
	echo "rotto $TEST_ROOT/remotes/manca.git" >>"$NOTES/repos.txt"

	run "$SYNC" sync demo
	[ "$status" -eq 1 ]
	[ "$(log_files | wc -l)" -eq 20 ]
	grep -q "manca.git" "$(log_files | tail -n 1)"
	grep -q "fatal" "$(log_files | tail -n 1)"
}

@test "outcome labels end in one column on the right, long lines keep it after the text" {
	export ENGRAMMA_VERBOSE=1
	run "$SYNC" check demo
	local line
	line="$(grep -E '^ +git +\[  OK  \]$' <<<"$output")"
	[ "${#line}" -eq 80 ]
	[[ "$output" =~ " demo  ~/workspace/demo  · "[0-9]+" da sistemare "·+" [ FAIL ]" ]]
	[[ "$output" =~ "symlink mancante  [ WARN ]" ]] || [[ "$output" =~ "symlink mancante "\ +"[ WARN ]" ]]
}

@test "in a tall terminal results are printed only once" {
	command -v script >/dev/null || skip "script non installato"
	run env -u CI -u NO_COLOR TERM=xterm-256color script -qec "stty rows 40 cols 100; \"$SYNC\" sync demo" /dev/null
	[ "$status" -eq 0 ]
	[[ ! "$output" =~ $'\e['[0-9]+";"[0-9]+"r" ]]
	[ "$(grep -o 'POSTAZIONE' <<<"$output" | wc -l)" -eq 1 ]
	[ "$(grep -o 'AGENTI' <<<"$output" | wc -l)" -eq 1 ]
	[[ "$output" == *"engramma"*"demo"*"alpha"*"tutto a posto"* ]]
}

@test "in a short terminal the header scrolls with the rest" {
	command -v script >/dev/null || skip "script non installato"
	run env -u CI -u NO_COLOR TERM=xterm-256color script -qec "stty rows 14 cols 100; \"$SYNC\" sync demo" /dev/null
	[ "$status" -eq 0 ]
	[[ ! "$output" =~ $'\e['[0-9]+";"[0-9]+"r" ]]
	[[ "$output" == *"tutto a posto"* ]]
}

@test "without -v a block with only warnings is one line, and the summary lists them" {
	"$SYNC" sync demo >/dev/null
	echo nuovo >"$WORKSPACE/alpha/nuovo.txt"

	run "$SYNC" check
	body="${output%%────*}"
	[[ "$body" == *"POSTAZIONE"*"AGENTI"*"WORKSPACE"* ]]
	[[ "$body" == *"demo"*"1 avviso"* ]]
	[[ "$body" != *"1 file non committato"* ]]
	[[ "$output" == *"modifiche locali e repo non aggiornati (1)"*"demo/alpha  1 file non committato"* ]]
}

@test "a workspace named on the command line shows its details" {
	"$SYNC" sync demo >/dev/null
	echo nuovo >"$WORKSPACE/alpha/nuovo.txt"

	run "$SYNC" check demo
	[[ "${output%%────*}" == *"1 file non committato"* ]]
}

@test "the command that fixes a problem is shown under it in the summary" {
	mkdir -p "$TEST_ROOT/bin" "$HOME/.codex"
	printf '#!/bin/sh\nexit 0\n' >"$TEST_ROOT/bin/codex"
	chmod +x "$TEST_ROOT/bin/codex"
	mkdir -p "$ENGRAMMA_DIR/global/codex"
	echo codex >"$ENGRAMMA_DIR/global/requires.txt"
	echo 'skill mancante  # installa-la-skill' >"$ENGRAMMA_DIR/global/codex/plugins.txt"

	PATH="$TEST_ROOT/bin:$PATH" run "$SYNC" check
	[[ "$output" == *"da sistemare ("*"skill mancante assente in Codex"$'\n'*"→ installa-la-skill"* ]]
	[[ "$output" == *"operazione conclusa: "*" da risolvere"*"[ WARN ]"* ]]
	[[ "$output" != *"eng sync sistema quelle automatiche"* ]]
}
