#!/usr/bin/env bats

load helpers

setup() {
	setup_sandbox
	GLOBAL="$ENGRAMMA_DIR/global"
	mkdir -p "$GLOBAL/claude" "$ENGRAMMA_DIR/skills/demo-workflow" "$HOME/.local/bin"
	printf '# Regole di prova\n' >"$GLOBAL/claude/CLAUDE.md"
	printf '{}\n' >"$GLOBAL/claude/settings.json"
	printf 'claude/CLAUDE.md ${CLAUDE_HOME}/CLAUDE.md\nclaude/settings.json ${CLAUDE_HOME}/settings.json unisci\n' >"$GLOBAL/links.txt"
	printf '# Skill fittizia\n' >"$ENGRAMMA_DIR/skills/demo-workflow/SKILL.md"
	printf '# Regole del workspace\n' >"$NOTES/AGENTS.md"
	printf 'claude\n' >"$GLOBAL/requires.txt"
	printf '#!/bin/sh\nexit 0\n' >"$HOME/.local/bin/claude"
	cp "$HOME/.local/bin/claude" "$HOME/.local/bin/copilot"
	cp "$HOME/.local/bin/claude" "$HOME/.local/bin/codex"
	chmod +x "$HOME/.local/bin/"{claude,codex,copilot}
}

teardown() {
	teardown_sandbox
}

@test "an existing archive retains its Claude configuration and automatic memory" {
	run "$SYNC" sync demo
	[ "$status" -eq 0 ]
	[ -L "$ENGRAMMA_CLAUDE_HOME/CLAUDE.md" ]
	[ -L "$(memory_dir_for "$WORKSPACE/alpha")" ]
	[ ! -e "$COPILOT_HOME" ]
}

@test "new archives start with no selected agents or memory import" {
	run "$SYNC" init "$HOME/new-archive"
	[ "$status" -eq 0 ]
	run "$SYNC" agents
	[ "$status" -eq 0 ]
	[[ "$output" == *"claude   disattivato"* && "$output" == *"sincronizzazione disattivata"* ]]
	run "$SYNC" setup
	[ "$status" -eq 0 ]
	[ ! -e "$ENGRAMMA_CLAUDE_HOME" ]
}

@test "selection validates the complete list and previews without saving or linking" {
	run "$SYNC" setup --agents copilot,copilot
	[ "$status" -eq 2 ]
	run "$SYNC" setup --agents copilot --claude-memory on
	[ "$status" -eq 2 ]
	run "$SYNC" setup --agents copilot --dry-run
	[ "$status" -eq 0 ]
	[[ "$output" == *"salverei la scelta"* && "$output" == *"istruzioni personali di Copilot"* ]]
	[ ! -e "$COPILOT_HOME" ]
	[ ! -e "$XDG_CONFIG_HOME/engramma/agent-profiles" ]
}

@test "Copilot alone receives its rules, skills and private project context" {
	run "$SYNC" setup --agents copilot
	[ "$status" -eq 0 ]
	run "$SYNC" sync demo
	[ "$status" -eq 0 ]
	run "$SYNC" agents
	[[ "$output" == *"claude   disattivato"* && "$output" == *"copilot  attivo"* ]]
	grep -q 'Regole di prova' "$COPILOT_HOME/copilot-instructions.md"
	[ -L "$COPILOT_HOME/skills/demo-workflow" ]
	[ ! -e "$ENGRAMMA_CLAUDE_HOME" ]
	[ ! -e "$CODEX_HOME" ]
	[ ! -e "$WORKSPACE/.claude" ]
	[ ! -e "$WORKSPACE/alpha/CLAUDE.local.md" ]
	cmp "$NOTES/AGENTS.md" "$WORKSPACE/alpha/.engramma-workspace.md"
	cmp "$NOTES/repo-notes/alpha.md" "$WORKSPACE/alpha/.engramma-notes.md"
	git -C "$WORKSPACE/alpha" check-ignore .engramma-workspace.md .engramma-notes.md
	run "$SYNC" session-start
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "selection is independent for separate archives on the same computer" {
	"$SYNC" setup --agents copilot
	local other="$TEST_ROOT/other"
	mkdir -p "$other/workspaces" "$other/global"
	git -C "$other" init -q
	printf 'none off\n' >"$other/global/agents-defaults.txt"
	run "$SYNC" --data-dir "$other" agents
	[ "$status" -eq 0 ]
	[[ "$output" == *"copilot  disattivato"* ]]
	run "$SYNC" agents
	[[ "$output" == *"copilot  attivo"* ]]
}

@test "Copilot and Codex can be selected without Claude and each sees the shared rules" {
	mkdir -p "$CODEX_HOME"
	printf 'project_doc_fallback_filenames = ["CLAUDE.md"]\n[features]\nshell_snapshot = false\n' >"$CODEX_HOME/config.toml"
	run "$SYNC" setup --agents codex,copilot
	[ "$status" -eq 0 ]
	grep -q 'Regole di prova' "$CODEX_HOME/AGENTS.md"
	grep -q 'Regole di prova' "$COPILOT_HOME/copilot-instructions.md"
	[ ! -e "$ENGRAMMA_CLAUDE_HOME" ]
}

@test "Copilot personal instructions and team-owned context are preserved" {
	mkdir -p "$COPILOT_HOME"
	printf '# Istruzioni scritte a mano\n' >"$COPILOT_HOME/copilot-instructions.md"
	run "$SYNC" setup --agents copilot
	[ "$status" -eq 1 ]
	[[ "$output" == *"scritto a mano"* ]]
	grep -qx '# Istruzioni scritte a mano' "$COPILOT_HOME/copilot-instructions.md"
	local seed="$TEST_ROOT/seeds/alpha"
	git -C "$seed" switch -q develop
	printf '# Regole del team\n' >"$seed/.engramma-workspace.md"
	git -C "$seed" add .engramma-workspace.md
	git -C "$seed" commit -qm 'Regola del team'
	git -C "$seed" push -q "$(remote_path alpha)" develop
	run "$SYNC" sync demo
	[ "$status" -eq 1 ]
	[[ "$output" == *"lascio intatto il file del team"* ]]
	grep -qx '# Regole del team' "$WORKSPACE/alpha/.engramma-workspace.md"
	! grep -qF '/.engramma-workspace.md' "$WORKSPACE/alpha/.git/info/exclude"
}

@test "turning Claude memory off freezes linked copies in both active and old paths" {
	"$SYNC" sync demo >/dev/null
	local memory old="$ENGRAMMA_CLAUDE_HOME/projects/old-project/memory"
	memory="$(memory_dir_for "$WORKSPACE/alpha")"
	mkdir -p "${old%/*}"
	ln -s "$NOTES/memory/alpha" "$old"
	run "$SYNC" setup --claude-memory off
	[ "$status" -eq 0 ]
	[ ! -L "$memory" ]
	[ ! -L "$old" ]
	cmp "$memory/MEMORY.md" "$NOTES/memory/alpha/MEMORY.md"
	cmp "$old/MEMORY.md" "$NOTES/memory/alpha/MEMORY.md"
	[ -L "$ENGRAMMA_CLAUDE_HOME/CLAUDE.md" ]
	printf 'nuova memoria locale\n' >>"$memory/MEMORY.md"
	run "$SYNC" sync demo
	[ "$status" -eq 0 ]
	! grep -q 'nuova memoria locale' "$NOTES/memory/alpha/MEMORY.md"
}

@test "an existing failure during detach leaves memory enabled and untouched" {
	"$SYNC" sync demo >/dev/null
	local memory
	memory="$(memory_dir_for "$WORKSPACE/alpha")"
	printf '#!/bin/sh\nexit 1\n' >"$HOME/.local/bin/cp"
	chmod +x "$HOME/.local/bin/cp"
	run "$SYNC" setup --claude-memory off
	[ "$status" -eq 1 ]
	[ -L "$memory" ]
	run "$SYNC" agents
	[[ "$output" == *"Memoria di Claude: sincronizzata"* ]]
}

@test "when memory is off save and sync commit project notes without pending memory files" {
	git -C "$ENGRAMMA_DIR" init -q
	git -C "$ENGRAMMA_DIR" add -A
	git -C "$ENGRAMMA_DIR" commit -qm 'Archivio di prova'
	git clone -q --bare "$ENGRAMMA_DIR" "$TEST_ROOT/archive.git"
	git -C "$ENGRAMMA_DIR" remote add origin "$TEST_ROOT/archive.git"
	git -C "$ENGRAMMA_DIR" push -qu origin main
	"$SYNC" setup --agents copilot >/dev/null
	printf 'memoria da lasciare locale\n' >>"$NOTES/memory/alpha/MEMORY.md"
	printf 'nota sincronizzata\n' >>"$NOTES/repo-notes/alpha.md"
	run "$SYNC" save demo
	[ "$status" -eq 0 ]
	[[ "$output" == *"memoria di Claude esclusa"* ]]
	[[ "$(git -C "$TEST_ROOT/archive.git" show main:workspaces/demo/memory/alpha/MEMORY.md)" != *"memoria da lasciare locale"* ]]
	printf 'seconda nota\n' >>"$NOTES/repo-notes/alpha.md"
	run "$SYNC" sync demo
	[ "$status" -eq 0 ]
	[[ "$output" == *"memoria di Claude esclusa"* ]]
	[[ "$(git -C "$TEST_ROOT/archive.git" show main:workspaces/demo/repo-notes/alpha.md)" == *"seconda nota"* ]]
	[[ "$(git -C "$TEST_ROOT/archive.git" show main:workspaces/demo/memory/alpha/MEMORY.md)" != *"memoria da lasciare locale"* ]]
	grep -q 'memoria da lasciare locale' "$NOTES/memory/alpha/MEMORY.md"
}

@test "detaching all preserves Copilot skills and context as local copies" {
	"$SYNC" setup --agents copilot
	"$SYNC" sync demo
	run "$SYNC" detach all
	[ "$status" -eq 0 ]
	[ ! -L "$COPILOT_HOME/skills/demo-workflow" ]
	[ -f "$COPILOT_HOME/skills/demo-workflow/SKILL.md" ]
	[ ! -L "$WORKSPACE/alpha/.engramma-workspace.md" ]
	[ -f "$WORKSPACE/alpha/.engramma-notes.md" ]
}

@test "switching to Claude freezes Copilot context but keeps the workspace rules connected" {
	"$SYNC" setup --agents copilot
	"$SYNC" sync demo
	run "$SYNC" setup --agents claude --claude-memory off
	[ "$status" -eq 0 ]
	[ ! -L "$COPILOT_HOME/skills/demo-workflow" ]
	[ -f "$COPILOT_HOME/skills/demo-workflow/SKILL.md" ]
	[ -L "$WORKSPACE/AGENTS.md" ]
	[ ! -L "$WORKSPACE/alpha/.engramma-workspace.md" ]
	[ ! -L "$WORKSPACE/alpha/.engramma-notes.md" ]
	cmp "$NOTES/AGENTS.md" "$WORKSPACE/alpha/.engramma-workspace.md"
}
