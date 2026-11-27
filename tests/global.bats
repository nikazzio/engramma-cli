#!/usr/bin/env bats

load helpers

setup() {
	setup_sandbox
	GLOBAL="$ENGRAMMA_DIR/global"
	CONFIG="$XDG_CONFIG_HOME"
	mkdir -p "$GLOBAL/claude" "$GLOBAL/mise"
	echo '{"theme": "dark"}' >"$GLOBAL/claude/settings.json"
	echo '[tools]' >"$GLOBAL/mise/config.toml"
	cat >"$GLOBAL/links.txt" <<'EOF'
# <file in global/> <destinazione>
claude/settings.json  ${CLAUDE_HOME}/settings.json
mise/config.toml      ${XDG_CONFIG_HOME}/mise/config.toml
EOF
}

teardown() {
	teardown_sandbox
}

@test "links the global configuration on a fresh machine, without a workspace" {
	run "$SYNC" setup
	[ "$status" -eq 0 ]
	[[ "$output" == *"file globali"* ]]
	[[ "$output" != *"command not found"* ]]
	[ "$(readlink "$ENGRAMMA_CLAUDE_HOME/settings.json")" = "$GLOBAL/claude/settings.json" ]
	[ "$(readlink "$CONFIG/mise/config.toml")" = "$GLOBAL/mise/config.toml" ]
	[ ! -e "$WORKSPACE" ]

	run "$SYNC" check
	[ "$status" -eq 0 ]
}

@test "global is a target like a workspace: check, sync and detach" {
	run "$SYNC" check global
	[ "$status" -eq 1 ]
	[[ "$output" != *"Workspace sconosciuto"* ]]
	[[ "$output" == *"file globali"* ]]
	[ ! -e "$ENGRAMMA_CLAUDE_HOME/settings.json" ]

	run "$SYNC" sync global
	[ "$status" -eq 0 ]
	[ "$(readlink "$ENGRAMMA_CLAUDE_HOME/settings.json")" = "$GLOBAL/claude/settings.json" ]
	[ ! -e "$WORKSPACE" ]

	run "$SYNC" global
	[ "$status" -eq 0 ]
	run "$SYNC" check global
	[ "$status" -eq 0 ]

	run "$SYNC" sync global demo
	[ "$status" -eq 1 ]

	run "$SYNC" detach global
	[ "$status" -eq 0 ]
	[ ! -L "$ENGRAMMA_CLAUDE_HOME/settings.json" ]
	[ "$(cat "$ENGRAMMA_CLAUDE_HOME/settings.json")" = '{"theme": "dark"}' ]
}

@test "links the global configuration with every workspace sync" {
	run "$SYNC" sync demo
	[ "$status" -eq 0 ]
	[ "$(readlink "$ENGRAMMA_CLAUDE_HOME/settings.json")" = "$GLOBAL/claude/settings.json" ]
}

@test "a second global run changes nothing" {
	"$SYNC" setup >/dev/null
	local before
	before="$(snapshot)"

	run "$SYNC" setup
	[ "$status" -eq 0 ]
	[ "$(snapshot)" = "$before" ]
}

@test "global dry run and check change nothing" {
	local before
	before="$(snapshot)"

	run "$SYNC" setup --dry-run
	[ "$status" -eq 0 ]
	[[ "$output" == *"symlink a"* ]]

	run "$SYNC" check
	[ "$status" -eq 1 ]
	[[ "$output" == *"symlink mancante"* ]]
	[ "$(snapshot)" = "$before" ]
}

@test "replaces a real file identical to engramma with a link" {
	mkdir -p "$ENGRAMMA_CLAUDE_HOME"
	cp "$GLOBAL/claude/settings.json" "$ENGRAMMA_CLAUDE_HOME/settings.json"

	run "$SYNC" setup
	[ "$status" -eq 0 ]
	[ "$(readlink "$ENGRAMMA_CLAUDE_HOME/settings.json")" = "$GLOBAL/claude/settings.json" ]
}

@test "never overwrites a real file that differs from engramma" {
	mkdir -p "$ENGRAMMA_CLAUDE_HOME"
	echo '{"theme": "light"}' >"$ENGRAMMA_CLAUDE_HOME/settings.json"

	run "$SYNC" setup
	[ "$status" -eq 1 ]
	[[ "$output" == *"un programma ha sostituito il symlink con un file diverso"* ]]
	[[ "$output" == *"eng setup in un terminale interattivo: diff di claude/settings.json e scelta della copia da tenere"* ]]
	[ ! -L "$ENGRAMMA_CLAUDE_HOME/settings.json" ]
	[ "$(cat "$ENGRAMMA_CLAUDE_HOME/settings.json")" = '{"theme": "light"}' ]
	[ "$(cat "$GLOBAL/claude/settings.json")" = '{"theme": "dark"}' ]

	run "$SYNC" check
	[ "$status" -eq 1 ]
}

@test "keeps the local file when copying it into engramma fails" {
	mkdir -p "$ENGRAMMA_CLAUDE_HOME"
	echo '{"theme": "light"}' >"$ENGRAMMA_CLAUDE_HOME/settings.json"
	chmod 444 "$GLOBAL/claude/settings.json"

	run_in_terminal 120 'c\n' "$SYNC" setup
	chmod 644 "$GLOBAL/claude/settings.json"
	[ ! -L "$ENGRAMMA_CLAUDE_HOME/settings.json" ]
	[ "$(cat "$ENGRAMMA_CLAUDE_HOME/settings.json")" = '{"theme": "light"}' ]
	[[ "$output" == *"copia in engramma non riuscita"* ]]
}

@test "keeps the local file when its backup fails" {
	mkdir -p "$ENGRAMMA_CLAUDE_HOME"
	echo '{"theme": "light"}' >"$ENGRAMMA_CLAUDE_HOME/settings.json"
	mkdir -p "$XDG_STATE_HOME/engramma"
	echo "non una cartella" >"$XDG_STATE_HOME/engramma/backup"

	run_in_terminal 120 'e\n' "$SYNC" setup
	[ ! -L "$ENGRAMMA_CLAUDE_HOME/settings.json" ]
	[ "$(cat "$ENGRAMMA_CLAUDE_HOME/settings.json")" = '{"theme": "light"}' ]
	[[ "$output" == *"backup non riuscito"* ]]
}

@test "leaves a global link pointing elsewhere untouched" {
	mkdir -p "$ENGRAMMA_CLAUDE_HOME"
	ln -s /tmp/altrove.json "$ENGRAMMA_CLAUDE_HOME/settings.json"

	run "$SYNC" setup
	[[ "$output" == *"non verso engramma: non lo tocco"* ]]
	[ "$(readlink "$ENGRAMMA_CLAUDE_HOME/settings.json")" = /tmp/altrove.json ]
}

@test "uses a custom configuration folder" {
	export XDG_CONFIG_HOME="$TEST_ROOT/config-altrove"

	run "$SYNC" setup
	[ "$status" -eq 0 ]
	[ "$(readlink "$XDG_CONFIG_HOME/mise/config.toml")" = "$GLOBAL/mise/config.toml" ]
}

@test "reports a file listed in links.txt that engramma does not have" {
	echo 'manca.json ${CLAUDE_HOME}/manca.json' >>"$GLOBAL/links.txt"

	run "$SYNC" setup
	[ "$status" -eq 1 ]
	[[ "$output" == *"manca.json: elencato in global/links.txt ma assente in global/"* ]]
	[ ! -e "$ENGRAMMA_CLAUDE_HOME/manca.json" ]
}

@test "rejects a destination with an unknown placeholder" {
	echo 'claude/settings.json ${PWD}/settings.json' >"$GLOBAL/links.txt"

	run "$SYNC" setup
	[ "$status" -eq 1 ]
	[[ "$output" == *"segnaposto non ammesso"* ]]
}

@test "suggests how to install a missing global command" {
	cat >"$GLOBAL/requires.txt" <<'EOF'
git
comando-che-non-esiste            # installa con: mise install
facoltativo-che-non-esiste facoltativo  # npm install -g esempio
EOF

	run "$SYNC" check
	[ "$status" -eq 1 ]
	[[ "$output" == *"comando-che-non-esiste non installato"*"mise install"* ]]
	[[ "$output" == *"facoltativo-che-non-esiste assente, facoltativo"*"npm install -g esempio"* ]]
}

@test "detach-all turns the global links into independent copies" {
	"$SYNC" setup >/dev/null

	run "$SYNC" detach all
	[ "$status" -eq 0 ]
	[ ! -L "$ENGRAMMA_CLAUDE_HOME/settings.json" ]

	rm -rf "$ENGRAMMA_DIR"
	[ "$(cat "$ENGRAMMA_CLAUDE_HOME/settings.json")" = '{"theme": "dark"}' ]
	[ "$(cat "$CONFIG/mise/config.toml")" = '[tools]' ]
}

@test "does nothing global when engramma has no global folder" {
	rm -rf "$GLOBAL"

	run "$SYNC" sync demo
	[ "$status" -eq 0 ]
	[[ "$output" != *"file globali"* ]]
}

@test "reports a command installed in more than one place" {
	mkdir -p "$TEST_ROOT/bin-a" "$TEST_ROOT/bin-b" "$TEST_ROOT/mise/shims"
	printf '#!/bin/sh\necho a\n' >"$TEST_ROOT/bin-a/strumento"
	printf '#!/bin/sh\necho b\n' >"$TEST_ROOT/bin-b/strumento"
	printf '#!/bin/sh\necho shim\n' >"$TEST_ROOT/mise/shims/unico"
	printf '#!/bin/sh\necho unico\n' >"$TEST_ROOT/bin-a/unico"
	chmod +x "$TEST_ROOT"/bin-*/* "$TEST_ROOT/mise/shims/unico"
	printf 'strumento\nunico\n' >"$GLOBAL/requires.txt"

	PATH="$TEST_ROOT/bin-a:$TEST_ROOT/bin-b:$TEST_ROOT/mise/shims:$TEST_ROOT/bin-a:$PATH" run "$SYNC" check
	[[ "$output" == *"strumento: 2 installazioni trovate"*"$TEST_ROOT/bin-a/strumento"*"$TEST_ROOT/bin-b/strumento"* ]]
	[[ "$output" != *"unico: "*"copie"* ]]
}

fake_command() {
	mkdir -p "$(dirname "$1")"
	printf '#!/bin/sh\n' >"$1"
	chmod +x "$1"
}

@test "lists the next steps in order, grouping commands installed the same way" {
	cat >"$GLOBAL/requires.txt" <<'EOF2'
git
manca-installer   # curl https://example.test/install | sh
manca-uno         # mise install
manca-due         # mise install
manca-senza-come
EOF2

	run "$SYNC" check
	[ "$status" -eq 1 ]
	[[ "$output" == *"altri comandi"*"1. curl https://example.test/install | sh (installa manca-installer)"*"2. mise install (installa manca-uno, manca-due)"*"3. installa manca-senza-come"* ]]
}

@test "suggests to keep the copy installed with mise and to remove the others" {
	fake_command "$HOME/.local/bin/strumento"
	fake_command "$HOME/.local/share/mise/installs/strumento/1/bin/strumento"
	fake_command "$HOME/node/lib/node_modules/@scope/strumento/bin/strumento.js"
	mkdir -p "$HOME/node/bin"
	ln -s ../lib/node_modules/@scope/strumento/bin/strumento.js "$HOME/node/bin/strumento"
	echo 'strumento # mise install' >"$GLOBAL/requires.txt"

	PATH="$HOME/.local/bin:$HOME/.local/share/mise/installs/strumento/1/bin:$HOME/node/bin:$PATH" run "$SYNC" check
	[ "$status" -eq 1 ]
	[[ "$output" == *"strumento: 3 installazioni trovate; quella prevista non è la prima rilevata"* ]]
	[[ "$output" == *"~/.local/share/mise/installs/strumento/1/bin/strumento copia prevista"* ]]
	[[ "$output" == *"facoltativo, rimuovi la copia aggiuntiva di strumento: rm ~/.local/bin/strumento"*"~/node/bin/npm uninstall -g @scope/strumento"* ]]
}

@test "suggests to point git to the copy that stays" {
	fake_command "$TEST_ROOT/bin-a/strumento"
	fake_command "$TEST_ROOT/bin-b/strumento"
	echo 'strumento' >"$GLOBAL/requires.txt"
	git config --global credential.https://example.test.helper "!$TEST_ROOT/bin-b/strumento auth git-credential"

	PATH="$TEST_ROOT/bin-a:$TEST_ROOT/bin-b:$PATH" run "$SYNC" check
	[[ "$output" == *"git config --global --replace-all credential.https://example.test.helper '!strumento auth git-credential' '$TEST_ROOT/bin-b/strumento'"* ]]
}

@test "reports the hooks of the Claude Code settings that do not exist" {
	fake_command "$TEST_ROOT/bin/strumento"
	echo 'strumento # curl https://example.test/strumento | sh' >"$GLOBAL/requires.txt"
	cat >"$GLOBAL/claude/settings.json" <<'EOF2'
{"hooks": {"Stop": [{"hooks": [
  {"type": "command", "command": "~/.claude/hooks/strumento-hook.sh"},
  {"type": "command", "command": "\"$HOME/.claude/hooks/sconosciuto.mjs\""},
  {"type": "command", "command": "~/.claude/hooks/presente.sh"}
]}]}}
EOF2
	fake_command "$HOME/.claude/hooks/presente.sh"

	PATH="$TEST_ROOT/bin:$PATH" run "$SYNC" setup
	[ "$status" -eq 1 ]
	[[ "$output" == *"hook di Claude Code verso ~/.claude/hooks/strumento-hook.sh: file inesistente, lo installa strumento"* ]]
	[[ "$output" == *"reinstalla gli hook di strumento: curl https://example.test/strumento | sh"* ]]
	[[ "$output" == *"hook di Claude Code verso ~/.claude/hooks/sconosciuto.mjs: file inesistente, ogni evento darà errore"* ]]
	[[ "$output" != *"presente.sh"* ]]
}

@test "reports a shell that does not activate mise" {
	rm "$HOME/.zshrc"
	"$SYNC" setup >/dev/null || true

	SHELL=/bin/zsh PATH="$TEST_ROOT/bin:$PATH" run "$SYNC" check
	[ "$status" -eq 1 ]
	[[ "$output" == *"mise non attivato in ~/.zshrc"* ]]
	[[ "$output" == *"eval \"\$($ENGRAMMA_MISE activate zsh)\"' >> ~/.zshrc"* ]]

	echo 'eval "$(~/.local/bin/mise activate zsh)"' >"$HOME/.zshrc"
	SHELL=/bin/zsh PATH="$TEST_ROOT/bin:$PATH" run "$SYNC" check
	[ "$status" -eq 0 ]
}

@test "counts the copy installed under the Ubuntu name as a copy of the same program" {
	fake_command "$HOME/.local/share/mise/installs/fd/1/bin/fd"
	fake_command "$TEST_ROOT/usr/bin/fdfind"
	echo 'fd # mise install' >"$GLOBAL/requires.txt"

	# System installations may add more copies; the fake must still be identified.
	PATH="$HOME/.local/share/mise/installs/fd/1/bin:$TEST_ROOT/usr/bin:/usr/bin:/bin" run "$SYNC" check
	[[ "$output" == *"fd: "*"installazioni trovate; quella prevista è la prima rilevata"* ]]
	[[ "$output" == *"$TEST_ROOT/usr/bin/fdfind altra copia"* ]]
}

@test "reports a shell that does not run the zoxide init" {
	fake_command "$TEST_ROOT/bin/zoxide"
	echo 'zoxide' >"$GLOBAL/requires.txt"
	"$SYNC" setup >/dev/null || true

	SHELL=/bin/zsh PATH="$TEST_ROOT/bin:$PATH" run "$SYNC" check
	[ "$status" -eq 1 ]
	[[ "$output" == *"zoxide non attivato in ~/.zshrc"* ]]
	[[ "$output" == *"echo 'eval \"\$(zoxide init zsh)\"' >> ~/.zshrc"* ]]

	echo 'eval "$(zoxide init zsh)"' >>"$HOME/.zshrc"
	SHELL=/bin/zsh PATH="$TEST_ROOT/bin:$PATH" run "$SYNC" check
	[ "$status" -eq 0 ]
}

@test "turns off the Codex shell snapshot and makes Codex read the CLAUDE.md of the repos" {
	mkdir -p "$TEST_ROOT/bin"
	cat >"$TEST_ROOT/bin/codex" <<'EOF2'
#!/bin/sh
if [ "$1 $2 $3" = "features disable shell_snapshot" ]; then
	printf '[features]\nshell_snapshot = false\n' >>"$HOME/.codex/config.toml"
fi
exit 0
EOF2
	chmod +x "$TEST_ROOT/bin/codex"
	echo 'codex' >"$GLOBAL/requires.txt"
	mkdir -p "$HOME/.codex"
	printf "model = 'esempio'\n\n[tui]\ntheme = 'dark'\n" >"$HOME/.codex/config.toml"

	PATH="$TEST_ROOT/bin:$PATH" run "$SYNC" check
	[ "$status" -eq 1 ]
	[[ "$output" == *"shell_snapshot attivo"* ]]
	[[ "$output" == *"project_doc_fallback_filenames assente"* ]]

	PATH="$TEST_ROOT/bin:$PATH" run "$SYNC" setup
	[ "$status" -eq 0 ]
	[ "$(sed -n 3p "$HOME/.codex/config.toml")" = 'project_doc_fallback_filenames = ["CLAUDE.md"]' ]
	[ "$(sed -n 5p "$HOME/.codex/config.toml")" = '[tui]' ]
	grep -qx 'shell_snapshot = false' "$HOME/.codex/config.toml"

	PATH="$TEST_ROOT/bin:$PATH" run "$SYNC" check
	[ "$status" -eq 0 ]
}

@test "registers a new marketplace before installing its plugin, keeping autoUpdate" {
	mkdir -p "$TEST_ROOT/bin"
	cat >"$TEST_ROOT/bin/claude" <<'EOF2'
#!/bin/sh
added="$TEST_ROOT/added"
case "$*" in
	"plugin list --json") echo '[]' ;;
	"plugin marketplace list --json") [ -f "$added" ] && echo '[{"name": "team"}]' || echo '[]' ;;
	"plugin marketplace add git@example.com:team/plugins.git")
		touch "$added"
		printf '{"enabledPlugins": {"plugin@team": true}, "extraKnownMarketplaces": {"team": {"source": {"source": "git", "url": "git@example.com:team/plugins.git"}}}}\n' >"$HOME/.claude/settings.json" ;;
	"plugin install plugin@team") [ -f "$added" ] || { echo 'Plugin "plugin" not found in marketplace "team"'; exit 1; } ;;
esac
exit 0
EOF2
	chmod +x "$TEST_ROOT/bin/claude"
	echo 'claude' >"$GLOBAL/requires.txt"
	printf '{"enabledPlugins": {"plugin@team": true}, "extraKnownMarketplaces": {"team": {"source": {"source": "git", "url": "git@example.com:team/plugins.git"}, "autoUpdate": true}}}\n' >"$GLOBAL/claude/settings.json"

	TEST_ROOT="$TEST_ROOT" PATH="$TEST_ROOT/bin:$PATH" run "$SYNC" setup
	[[ "$output" == *"marketplace team registrato in Claude Code"* ]]
	[[ "$output" == *"plugin@team installato"* ]]
	"$PYTHON" -c 'import json, sys; sys.exit(0 if json.load(open(sys.argv[1]))["extraKnownMarketplaces"]["team"].get("autoUpdate") is True else 1)' "$HOME/.claude/settings.json"
}

@test "reports a declared marketplace not registered, and one without automatic update" {
	mkdir -p "$TEST_ROOT/bin"
	cat >"$TEST_ROOT/bin/claude" <<'EOF2'
#!/bin/sh
case "$*" in
	"plugin list --json") echo '[]' ;;
	"plugin marketplace list --json") echo '[{"name": "manuale"}]' ;;
esac
exit 0
EOF2
	chmod +x "$TEST_ROOT/bin/claude"
	echo 'claude' >"$GLOBAL/requires.txt"
	printf '{"extraKnownMarketplaces": {"team": {"source": {"source": "git", "url": "git@example.com:a/b.git"}, "autoUpdate": true}, "manuale": {"source": {"source": "git", "url": "git@example.com:c/d.git"}}}}\n' >"$GLOBAL/claude/settings.json"
	mkdir -p "$ENGRAMMA_CLAUDE_HOME"
	ln -s "$GLOBAL/claude/settings.json" "$ENGRAMMA_CLAUDE_HOME/settings.json"

	PATH="$TEST_ROOT/bin:$PATH" run "$SYNC" check
	[[ "$output" == *"marketplace team dichiarato in settings.json ma non registrato in Claude Code"* ]]
	[[ "$output" == *"marketplace manuale: aggiornamento automatico spento"* ]]
}

@test "removes the Codex link of a skill removed from engramma" {
	mkdir -p "$TEST_ROOT/bin" "$HOME/.codex" "$HOME/.agents/skills"
	printf '#!/bin/sh\nexit 0\n' >"$TEST_ROOT/bin/codex"
	chmod +x "$TEST_ROOT/bin/codex"
	echo 'codex' >"$GLOBAL/requires.txt"
	ln -s "$ENGRAMMA_DIR/skills/vecchia" "$HOME/.agents/skills/vecchia"

	PATH="$TEST_ROOT/bin:$PATH" run "$SYNC" setup
	[[ "$output" == *"skill vecchia (~/.agents): non è più in engramma, symlink tolto"* ]]
	[ ! -L "$HOME/.agents/skills/vecchia" ]
}

@test "writes the Codex instructions from the global rules and boost" {
	fake_command "$TEST_ROOT/bin/codex"
	echo 'codex' >"$GLOBAL/requires.txt"
	echo 'boost' >"$GLOBAL/integrations.txt"
	echo '# Regole generali' >"$GLOBAL/claude/CLAUDE.md"
	echo 'claude/CLAUDE.md ${CLAUDE_HOME}/CLAUDE.md' >>"$GLOBAL/links.txt"
	mkdir -p "$HOME/.codex"
	printf 'project_doc_fallback_filenames = ["CLAUDE.md"]\n[features]\nshell_snapshot = false\n' >"$HOME/.codex/config.toml"
	printf '# Boost\n\n## Rule\n\nAlways pipe: (cmd) | boost\n\n## Meta commands\n\nboost report\n' >"$HOME/.codex/BOOST.md"
	echo '@BOOST.md' >"$HOME/.codex/AGENTS.md"

	PATH="$TEST_ROOT/bin:$PATH" run "$SYNC" check
	[ "$status" -eq 1 ]
	[[ "$output" == *"AGENTS.md globale non allineato alle regole globali"* ]]
	[ "$(cat "$HOME/.codex/AGENTS.md")" = '@BOOST.md' ]

	PATH="$TEST_ROOT/bin:$PATH" run "$SYNC" setup
	[ "$status" -eq 0 ]
	grep -q '^# Regole generali' "$HOME/.codex/AGENTS.md"
	grep -q '^boost report' "$HOME/.codex/AGENTS.md"
	grep -q 'do not add `| boost`' "$HOME/.codex/AGENTS.md"
	! grep -q 'Always pipe' "$HOME/.codex/AGENTS.md"

	echo '# Regole aggiornate' >"$GLOBAL/claude/CLAUDE.md"
	PATH="$TEST_ROOT/bin:$PATH" run "$SYNC" setup
	grep -q '^# Regole aggiornate' "$HOME/.codex/AGENTS.md"
	PATH="$TEST_ROOT/bin:$PATH" run "$SYNC" check
	[ "$status" -eq 0 ]
}

@test "leaves boost out of the Codex instructions when it is not an active integration" {
	fake_command "$TEST_ROOT/bin/codex"
	echo 'codex' >"$GLOBAL/requires.txt"
	echo '# Regole generali' >"$GLOBAL/claude/CLAUDE.md"
	echo 'claude/CLAUDE.md ${CLAUDE_HOME}/CLAUDE.md' >>"$GLOBAL/links.txt"
	mkdir -p "$HOME/.codex"
	printf 'project_doc_fallback_filenames = ["CLAUDE.md"]\n[features]\nshell_snapshot = false\n' >"$HOME/.codex/config.toml"
	printf '# Boost\n\nboost report\n' >"$HOME/.codex/BOOST.md"

	PATH="$TEST_ROOT/bin:$PATH" run "$SYNC" setup
	[ "$status" -eq 0 ]
	grep -q '^# Regole generali' "$HOME/.codex/AGENTS.md"
	! grep -q 'boost' "$HOME/.codex/AGENTS.md"
}

@test "never replaces Codex instructions written by hand" {
	fake_command "$TEST_ROOT/bin/codex"
	echo 'codex' >"$GLOBAL/requires.txt"
	echo '# Regole' >"$GLOBAL/claude/CLAUDE.md"
	echo 'claude/CLAUDE.md ${CLAUDE_HOME}/CLAUDE.md' >>"$GLOBAL/links.txt"
	mkdir -p "$HOME/.codex"
	printf 'project_doc_fallback_filenames = ["CLAUDE.md"]\n[features]\nshell_snapshot = false\n' >"$HOME/.codex/config.toml"
	echo '# Mie istruzioni' >"$HOME/.codex/AGENTS.md"

	PATH="$TEST_ROOT/bin:$PATH" run "$SYNC" setup
	[ "$status" -eq 1 ]
	[[ "$output" == *"AGENTS.md globale: ~/.codex/AGENTS.md scritto a mano, non lo sovrascrivo"* ]]
	[ "$(cat "$HOME/.codex/AGENTS.md")" = '# Mie istruzioni' ]
}

@test "reports code-review-graph not connected to Claude Code and Codex" {
	fake_command "$TEST_ROOT/bin/code-review-graph"
	fake_command "$TEST_ROOT/bin/codex"
	printf 'code-review-graph\ncodex\n' >"$GLOBAL/requires.txt"
	echo 'code-review-graph' >"$GLOBAL/integrations.txt"
	mkdir -p "$HOME/.codex"
	printf 'project_doc_fallback_filenames = ["CLAUDE.md"]\n[features]\nshell_snapshot = false\n' >"$HOME/.codex/config.toml"
	"$SYNC" setup >/dev/null || true

	PATH="$TEST_ROOT/bin:$PATH" run "$SYNC" check
	[ "$status" -eq 1 ]
	[[ "$output" == *"claude mcp add -s user code-review-graph -- ~/.local/share/mise/shims/code-review-graph serve --auto-watch"* ]]
	[[ "$output" == *"codex mcp add code-review-graph -- "* ]]

	echo '{"mcpServers": {"code-review-graph": {}}}' >"$HOME/.claude.json"
	printf '[mcp_servers.code-review-graph]\n' >>"$HOME/.codex/config.toml"
	PATH="$TEST_ROOT/bin:$PATH" run "$SYNC" check
	[ "$status" -eq 0 ]
}

use_merged_settings() {
	cat >"$GLOBAL/links.txt" <<'EOF2'
claude/settings.json  ${CLAUDE_HOME}/settings.json  unisci
EOF2
}

json_value() {
	"$PYTHON" -c 'import json, sys; data = json.load(open(sys.argv[1])); print(json.dumps(eval("data" + sys.argv[2])))' "$1" "$2"
}

@test "merges the Claude settings in both directions instead of linking them" {
	use_merged_settings
	echo '{"theme": "dark", "enabledPlugins": {"a@m": true}}' >"$GLOBAL/claude/settings.json"
	mkdir -p "$ENGRAMMA_CLAUDE_HOME"
	echo '{"theme": "dark", "enabledPlugins": {"b@m": true}, "effortLevel": "high"}' >"$ENGRAMMA_CLAUDE_HOME/settings.json"

	run "$SYNC" check
	[ "$status" -eq 1 ]
	[[ "$output" == *"enabledPlugins.a@m ← engramma, da applicare"* ]]
	[[ "$output" == *"enabledPlugins.b@m → engramma, da adottare"* ]]

	run "$SYNC" setup
	[ "$status" -eq 0 ]
	[ ! -L "$ENGRAMMA_CLAUDE_HOME/settings.json" ]
	for file in "$GLOBAL/claude/settings.json" "$ENGRAMMA_CLAUDE_HOME/settings.json"; do
		[ "$(json_value "$file" '["enabledPlugins"]')" = '{"a@m": true, "b@m": true}' ] ||
			[ "$(json_value "$file" '["enabledPlugins"]')" = '{"b@m": true, "a@m": true}' ]
		[ "$(json_value "$file" '["effortLevel"]')" = '"high"' ]
	done

	run "$SYNC" check
	[ "$status" -eq 0 ]

	# A change made on this computer goes into engramma, one made in engramma comes here.
	"$PYTHON" -c 'import json, sys; p = sys.argv[1]; d = json.load(open(p)); d["theme"] = "light"; json.dump(d, open(p, "w"))' "$ENGRAMMA_CLAUDE_HOME/settings.json"
	"$PYTHON" -c 'import json, sys; p = sys.argv[1]; d = json.load(open(p)); del d["enabledPlugins"]["a@m"]; json.dump(d, open(p, "w"))' "$GLOBAL/claude/settings.json"
	run "$SYNC" setup
	[ "$status" -eq 0 ]
	[ "$(json_value "$GLOBAL/claude/settings.json" '["theme"]')" = '"light"' ]
	[ "$(json_value "$ENGRAMMA_CLAUDE_HOME/settings.json" '["enabledPlugins"]')" = '{"b@m": true}' ]
}

@test "leaves a setting changed on both sides as it is and says how to choose" {
	use_merged_settings
	echo '{"theme": "dark"}' >"$GLOBAL/claude/settings.json"
	"$SYNC" setup >/dev/null
	echo '{"theme": "light"}' >"$ENGRAMMA_CLAUDE_HOME/settings.json"
	echo '{"theme": "blue"}' >"$GLOBAL/claude/settings.json"

	run "$SYNC" setup
	[ "$status" -eq 1 ]
	[[ "$output" == *"theme: conflitto, modificato su entrambi i lati"* ]]
	[[ "$output" == *"eng setup in un terminale interattivo: risolvi i conflitti di claude/settings.json"* ]]
	[ "$(json_value "$ENGRAMMA_CLAUDE_HOME/settings.json" '["theme"]')" = '"light"' ]
	[ "$(json_value "$GLOBAL/claude/settings.json" '["theme"]')" = '"blue"' ]
}

@test "replaces an old link to the Claude settings with a merged copy" {
	use_merged_settings
	mkdir -p "$ENGRAMMA_CLAUDE_HOME"
	ln -s "$GLOBAL/claude/settings.json" "$ENGRAMMA_CLAUDE_HOME/settings.json"

	run "$SYNC" check
	[ "$status" -eq 1 ]
	[[ "$output" == *"è ancora un symlink"* ]]

	run "$SYNC" setup
	[ "$status" -eq 0 ]
	[ ! -L "$ENGRAMMA_CLAUDE_HOME/settings.json" ]
	cmp -s "$GLOBAL/claude/settings.json" "$ENGRAMMA_CLAUDE_HOME/settings.json"

	run "$SYNC" check
	[ "$status" -eq 0 ]
}

@test "the session start merges the Claude settings and says what changed" {
	use_merged_settings
	echo '{"theme": "dark", "enabledPlugins": {}}' >"$GLOBAL/claude/settings.json"
	"$SYNC" setup >/dev/null
	echo '{"theme": "dark", "enabledPlugins": {"nuovo@m": true}}' >"$GLOBAL/claude/settings.json"

	run "$SYNC" session-start
	[ "$status" -eq 0 ]
	[[ "$output" == *"impostazioni portate da engramma su questo computer: enabledPlugins.nuovo@m"* ]]
	[ "$(json_value "$ENGRAMMA_CLAUDE_HOME/settings.json" '["enabledPlugins"]')" = '{"nuovo@m": true}' ]

	run "$SYNC" session-start
	[[ "$output" != *"impostazioni"* ]]
}

@test "in a terminal the question about a conflict is shown and the answer applied" {
	command -v script >/dev/null || skip "script non installato"
	use_merged_settings
	echo '{"theme": "dark"}' >"$GLOBAL/claude/settings.json"
	"$SYNC" setup >/dev/null
	echo '{"theme": "light"}' >"$ENGRAMMA_CLAUDE_HOME/settings.json"
	echo '{"theme": "blue"}' >"$GLOBAL/claude/settings.json"

	run bash -c 'printf "e\n" | script -qec "\"$SYNC\" setup" /dev/null'
	[[ "$output" == *"theme"*"modificato su entrambi i lati"* ]]
	[[ "$output" == *"tengo [c] computer · [e] engramma · [s] salto?"* ]]
	[ "$(json_value "$ENGRAMMA_CLAUDE_HOME/settings.json" '["theme"]')" = '"blue"' ]
	[ "$(json_value "$GLOBAL/claude/settings.json" '["theme"]')" = '"blue"' ]
}
