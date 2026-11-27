#!/usr/bin/env bats

load helpers

setup() {
	setup_sandbox
	GLOBAL="$ENGRAMMA_DIR/global"
	mkdir -p "$GLOBAL/claude" "$TEST_ROOT/bin" "$ENGRAMMA_CLAUDE_HOME" "$HOME/.codex"
	printf '#!/bin/sh\nexit 0\n' >"$TEST_ROOT/bin/boost"
	printf '#!/bin/sh\nexit 0\n' >"$TEST_ROOT/bin/codex"
	cp "$TEST_ROOT/bin/codex" "$TEST_ROOT/bin/claude"
	chmod +x "$TEST_ROOT/bin/boost" "$TEST_ROOT/bin/codex" "$TEST_ROOT/bin/claude"
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

@test "integration markers line up with headers" {
	echo boost >"$GLOBAL/integrations.txt"
	PATH="$TEST_ROOT/bin:$PATH" run "$SYNC" integrations
	[ "$status" -eq 0 ]
	local columns
	columns="$(printf '   %-20s ' 'boost')"
	[[ "$output" == *"${columns}●          ●        ●"* ]]
}

@test "plugin integrations require an enabled plugin in Claude settings" {
	printf 'caveman\nrepomix\n' >"$GLOBAL/integrations.txt"
	mkdir -p "$HOME/.codex/caveman" "$HOME/.codex/skills/repomix-explorer"
	echo '{"enabledPlugins":{"caveman@example":false,"tools@repomix":false}}' >"$ENGRAMMA_CLAUDE_HOME/settings.json"
	PATH="$TEST_ROOT/bin:$PATH" run "$SYNC" integrations
	[ "$status" -eq 1 ]
	echo '{"enabledPlugins":{"caveman@example":true,"tools@repomix":true}}' >"$ENGRAMMA_CLAUDE_HOME/settings.json"
	PATH="$TEST_ROOT/bin:$PATH" run "$SYNC" integrations
	[ "$status" -eq 0 ]
}

@test "Claude integrations are inapplicable when its command is absent" {
	run bash -c 'GLOBAL_DIR="" && source "$1" && PATH=/nonexistent && integration_part repomix claude' _ "$BATS_TEST_DIRNAME/../lib/integrations.sh"
	[ "$status" -eq 0 ]
	[ "$output" = "none" ]
}
