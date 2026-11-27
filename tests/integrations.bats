#!/usr/bin/env bats

load helpers

setup() {
	setup_sandbox
	GLOBAL="$ENGRAMMA_DIR/global"
	mkdir -p "$GLOBAL/claude" "$TEST_ROOT/bin" "$ENGRAMMA_CLAUDE_HOME" "$HOME/.codex"
	printf '#!/bin/sh\nexit 0\n' >"$TEST_ROOT/bin/boost"
	printf '#!/bin/sh\nexit 0\n' >"$TEST_ROOT/bin/codex"
	chmod +x "$TEST_ROOT/bin/boost" "$TEST_ROOT/bin/codex"
	echo '{"hooks": {"PreToolUse": [{"hooks": [{"command": "~/.claude/hooks/boost-hook-claude.sh"}]}]}}' >"$ENGRAMMA_CLAUDE_HOME/settings.json"
	echo '# Boost' >"$HOME/.codex/BOOST.md"
	cat >"$GLOBAL/integrations.txt" <<'EOF'
# <integrazione>   # come installarla
boost              # curl boost.example/install | sh
code-review-graph  # mise use -g code-review-graph
EOF
}

teardown() {
	teardown_sandbox
}

@test "integrations shows each active one, for the program, Claude and Codex" {
	PATH="$TEST_ROOT/bin:$PATH" run "$SYNC" integrations
	[ "$status" -eq 1 ]
	[[ "$output" == *"boost"* ]]
	[[ "$output" == *"code-review-graph"*"mise use -g code-review-graph"* ]]
	[[ "$output" != *"curl boost.example"* ]]
	[[ "$output" == *"disponibili"*"caveman"*"repomix"* ]]
}

@test "integrations is fine when every active one is in place" {
	echo boost >"$GLOBAL/integrations.txt"
	PATH="$TEST_ROOT/bin:$PATH" run "$SYNC" integrations
	[ "$status" -eq 0 ]
	[[ "$output" == *"boost"* ]]
}

@test "an unknown integration is reported" {
	echo inventata >>"$GLOBAL/integrations.txt"
	PATH="$TEST_ROOT/bin:$PATH" run "$SYNC" integrations
	[ "$status" -eq 1 ]
	[[ "$output" == *"inventata"*"sconosciuta"* ]]
}

@test "without the list no integration is active, and none is checked" {
	rm "$GLOBAL/integrations.txt"
	printf '#!/bin/sh\nexit 0\n' >"$TEST_ROOT/bin/code-review-graph"
	chmod +x "$TEST_ROOT/bin/code-review-graph"
	PATH="$TEST_ROOT/bin:$PATH" run "$SYNC" integrations
	[ "$status" -eq 0 ]
	[[ "$output" == *"nessuna integrazione attiva"* ]]
	PATH="$TEST_ROOT/bin:$PATH" run "$SYNC" check global
	[[ "$output" != *"MCP code-review-graph"* ]]
}
