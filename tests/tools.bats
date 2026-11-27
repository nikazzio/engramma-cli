#!/usr/bin/env bats

load helpers

setup() {
	setup_sandbox
	GLOBAL="$ENGRAMMA_DIR/global"
	mkdir -p "$GLOBAL/mise" "$TEST_ROOT/bin"
	printf '[tools]\nnode = "22"\njq = "1.7.1"\n' >"$GLOBAL/mise/config.toml"
	printf '[tools]\nphp = "8.3"\n' >"$NOTES/mise.toml"
	cat >"$GLOBAL/requires.txt" <<'EOF'
git
manca-qui   # apt install manca-qui
EOF
	export FAKE_MISE_LOG="$TEST_ROOT/mise.log" FAKE_MISE_LS="$TEST_ROOT/mise-ls.json"
	cat >"$FAKE_MISE_LS" <<EOF
{
  "node": [{"version": "22.23.3", "requested_version": "22", "installed": true, "source": {"path": "$GLOBAL/mise/config.toml"}}],
  "jq": [{"version": "1.7.1", "requested_version": "1.7.1", "installed": false, "source": {"path": "$GLOBAL/mise/config.toml"}}],
  "php": [{"version": "8.3.20", "requested_version": "8.3", "installed": false, "source": {"path": "$NOTES/mise.toml"}}],
  "estraneo": [{"version": "1", "requested_version": "1", "installed": false, "source": {"path": "$TEST_ROOT/altro/mise.toml"}}]
}
EOF
	cat >"$ENGRAMMA_MISE" <<'EOF'
#!/bin/sh
case "$1" in
	ls) cat "$FAKE_MISE_LS" ;;
	install) shift; echo "$*" >>"$FAKE_MISE_LOG" ;;
esac
exit 0
EOF
	"$SYNC" sync demo >/dev/null || true
}

teardown() {
	teardown_sandbox
}

@test "links the mise.toml of a workspace into its folder" {
	[ "$(readlink "$WORKSPACE/mise.toml")" = "$NOTES/mise.toml" ]
	[ -z "$(git -C "$WORKSPACE/alpha" status --porcelain)" ]
}

@test "tools lists the programs of mise and of requires.txt, with the counts" {
	local before
	before="$(snapshot)"
	run "$SYNC" tools
	[ "$status" -eq 1 ]
	[[ "$output" == *"global"*"jq"*"node"*"git"*"manca-qui"* ]]
	[[ "$output" == *"demo"*"php"* ]]
	[[ "$output" != *"estraneo"* ]]
	[[ "$output" == *"2 installati"*"3 mancanti"* ]]
	[[ "$output" == *"eng tools install"* ]]
	[[ "$output" == *"apt install manca-qui"* ]]
	[ ! -e "$FAKE_MISE_LOG" ]
	[ "$(snapshot)" = "$before" ]
}

@test "tools of one workspace or of global only" {
	run "$SYNC" tools demo
	[[ "$output" == *"php"* && "$output" != *"jq"* ]]
	run "$SYNC" tools global
	[[ "$output" == *"jq"* && "$output" != *"php"* ]]
	run "$SYNC" tools nessuno
	[ "$status" -eq 1 ]
	[[ "$output" == *"Workspace sconosciuto"* ]]
}

@test "tools install asks mise for the missing versions only" {
	run "$SYNC" tools install demo
	[ "$(cat "$FAKE_MISE_LOG")" = "php@8.3" ]

	rm "$FAKE_MISE_LOG"
	run "$SYNC" tools install
	grep -qx "jq@1.7.1" "$FAKE_MISE_LOG"
	grep -qx "php@8.3" "$FAKE_MISE_LOG"
	! grep -q "node" "$FAKE_MISE_LOG"
	[[ "$output" == *"apt install manca-qui"* ]]
}

@test "a missing mise is a problem, with the official install command" {
	export ENGRAMMA_MISE="$TEST_ROOT/nessuno/mise"
	run "$SYNC" check global
	[ "$status" -eq 1 ]
	[[ "$output" == *"mise non installato"* ]]
	[[ "$output" == *"curl https://mise.run | sh"* ]]
	run "$SYNC" tools
	[ "$status" -eq 1 ]
	[[ "$output" == *"mise non installato"* ]]
}

@test "in a terminal setup offers to install a missing mise" {
	command -v script >/dev/null || skip "script non installato"
	local stub="$ENGRAMMA_MISE"
	export ENGRAMMA_MISE="$TEST_ROOT/nuovo/mise"
	# The official installer, replaced by one that puts the stub in place.
	printf '#!/bin/sh\necho "mkdir -p %s && cp %s %s"\n' "$(dirname "$ENGRAMMA_MISE")" "$stub" "$ENGRAMMA_MISE" >"$TEST_ROOT/bin/curl"
	chmod +x "$TEST_ROOT/bin/curl"

	PATH="$TEST_ROOT/bin:$PATH" run_in_terminal 120 's\n' "$SYNC" setup
	[[ "$output" == *"installo mise"* ]]
	[ -x "$ENGRAMMA_MISE" ]
	[[ "$output" == *"mise installato"* ]]
}

@test "detach turns the mise.toml of a workspace into a copy" {
	run "$SYNC" detach demo
	[ "$status" -eq 0 ]
	[ ! -L "$WORKSPACE/mise.toml" ]
	grep -q 'php = "8.3"' "$WORKSPACE/mise.toml"
}

@test "tools and tools install report mise failures and stop before installation" {
	cat >"$ENGRAMMA_MISE" <<'STUB'
#!/bin/sh
case "$1" in
	ls)
		if [ "$PWD" = "$HOME" ]; then
			cat "$FAKE_MISE_LS"
		else
			echo "mise: invalid workspace configuration" >&2
			exit 1
		fi ;;
	install) echo unexpected >"$FAKE_MISE_LOG" ;;
esac
STUB
	for action in "" install; do
		local args=(tools)
		[[ -z "$action" ]] || args+=("$action")
		run "$SYNC" "${args[@]}"
		[ "$status" -eq 1 ]
		[[ "$output" == *"mise: invalid workspace configuration"* ]]
		[[ "$output" == *"demo: impossibile leggere i programmi di mise"* ]]
		[[ "$output" != *"niente da installare"* ]]
		[ ! -e "$FAKE_MISE_LOG" ]
	done

	echo 'not JSON' >"$FAKE_MISE_LS"
	run "$SYNC" tools global
	[ "$status" -eq 1 ]
	[[ "$output" == *"global: impossibile leggere i programmi di mise"* ]]
}
