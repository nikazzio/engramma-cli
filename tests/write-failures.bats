#!/usr/bin/env bats

load helpers

setup() {
	setup_sandbox
}

teardown() {
	teardown_sandbox
}

# Refuse just the rename that publishes a prepared copy.
fail_publish() {
	export FAILED_DESTINATION="$1"
	mkdir -p "$TEST_ROOT/bin"
	cat >"$TEST_ROOT/bin/mv" <<'EOF'
#!/usr/bin/env bash
[[ "${!#}" != "$FAILED_DESTINATION" ]] || exit 1
exec /bin/mv "$@"
EOF
	chmod +x "$TEST_ROOT/bin/mv"
	export PATH="$TEST_ROOT/bin:$PATH"
}

@test "failed detach of a directory restores the original link and reports failure" {
	mkdir -p "$WORKSPACE"
	ln -s "$NOTES/docs" "$WORKSPACE/docs"
	fail_publish "$WORKSPACE/docs"
	run "$SYNC" detach demo
	[ "$status" -eq 1 ]
	[ "$(readlink "$WORKSPACE/docs")" = "$NOTES/docs" ]
	[ "$(cat "$WORKSPACE/docs/guida.md")" = guida ]
}

@test "failed detach of a repo note keeps its import and reports failure" {
	mkdir -p "$WORKSPACE/alpha/.git"
	echo "@$NOTES/repo-notes/alpha.md" >"$WORKSPACE/alpha/CLAUDE.local.md"
	fail_publish "$WORKSPACE/alpha/CLAUDE.local.md"
	run "$SYNC" detach demo
	[ "$status" -eq 1 ]
	[ "$(cat "$WORKSPACE/alpha/CLAUDE.local.md")" = "@$NOTES/repo-notes/alpha.md" ]
}

@test "failed new workspace leaves no partial folder and can be retried" {
	fail_publish "$ENGRAMMA_DIR/workspaces/fresh"
	run "$SYNC" new fresh clienti/fresh
	[ "$status" -eq 1 ]
	[ ! -e "$FAILED_DESTINATION" ]
	[ -z "$(find "$ENGRAMMA_DIR/workspaces" -name '.new-*')" ]
	export FAILED_DESTINATION=""
	run "$SYNC" new fresh clienti/fresh
	[ "$status" -eq 0 ]
	[ -f "$ENGRAMMA_DIR/workspaces/fresh/README.md" ]
}

@test "failed addition preserves a repo list without a trailing newline" {
	printf 'seed git@example.com:team/seed.git' >"$NOTES/repos.txt"
	cp "$NOTES/repos.txt" "$TEST_ROOT/before"
	fail_publish "$NOTES/repos.txt"
	run "$SYNC" add demo git@example.com:team/extra.git
	[ "$status" -eq 1 ]
	cmp "$NOTES/repos.txt" "$TEST_ROOT/before"
}

@test "new and add reject destinations that escape their workspace" {
	for location in /elsewhere ../elsewhere team/../../elsewhere 'team folder'; do
		run "$SYNC" new fresh "$location"
		[ "$status" -eq 2 ]
		[ ! -e "$ENGRAMMA_DIR/workspaces/fresh" ]
	done
	run "$SYNC" add ../workspaces/demo git@example.com:team/extra.git
	[ "$status" -eq 2 ]
	mkdir -p "$HOME/workspace" "$TEST_ROOT/elsewhere"
	ln -s "$TEST_ROOT/elsewhere" "$HOME/workspace/outside"
	run "$SYNC" new fresh outside/fresh
	[ "$status" -eq 2 ]
	ln -s "$TEST_ROOT/elsewhere" "$ENGRAMMA_DIR/workspaces/outside"
	run "$SYNC" add outside git@example.com:team/extra.git
	[ "$status" -eq 1 ]
	[ ! -e "$TEST_ROOT/elsewhere/repos.txt" ]
	for url in git@example.com:team/.. git@example.com:team/ git@example.com:team/.; do
		run "$SYNC" add demo "$url"
		[ "$status" -eq 2 ]
	done
}

@test "concurrent additions retain both repositories and reject a duplicate" {
	"$SYNC" add demo git@example.com:team/one.git >"$TEST_ROOT/one.log" &
	local first=$!
	"$SYNC" add demo git@example.com:team/two.git >"$TEST_ROOT/two.log" &
	local second=$!
	wait "$first"
	wait "$second"
	run "$SYNC" add demo git@example.com:team/one.git
	[ "$status" -eq 1 ]
	[ "$(grep -c '^one ' "$NOTES/repos.txt")" -eq 1 ]
	[ "$(grep -c '^two ' "$NOTES/repos.txt")" -eq 1 ]
}

@test "failed workspace path update keeps the saved paths intact" {
	mkdir -p "$XDG_CONFIG_HOME/engramma"
	printf 'demo %s\n' "$WORKSPACE" >"$XDG_CONFIG_HOME/engramma/paths"
	fail_publish "$XDG_CONFIG_HOME/engramma/paths"
	run "$SYNC" sync demo --path "$HOME/new-demo"
	[ "$status" -eq 1 ]
	[[ "$output" == *"impossibile salvare"* ]]
	[ "$(cat "$XDG_CONFIG_HOME/engramma/paths")" = "demo $WORKSPACE" ]
	[ ! -e "$HOME/new-demo" ]
}

@test "failed detach all preserves the archive selection and eng command" {
	unset ENGRAMMA_DIR
	mkdir -p "$XDG_CONFIG_HOME/engramma"
	git -C "${NOTES%/workspaces/demo}" init -q
	printf '%s\n' "${NOTES%/workspaces/demo}" >"$XDG_CONFIG_HOME/engramma/archive"
	"$SYNC" setup
	mkdir -p "$WORKSPACE"
	ln -s "$NOTES/docs" "$WORKSPACE/docs"
	fail_publish "$WORKSPACE/docs"
	run "$SYNC" detach all
	[ "$status" -eq 1 ]
	[ -f "$XDG_CONFIG_HOME/engramma/archive" ]
	[ -L "$HOME/.local/bin/eng" ]
	[ -L "$WORKSPACE/docs" ]
}
