# shellcheck shell=bash

PYTHON="$(command -v /usr/bin/python3 || command -v python3)"
export PYTHON
export SYNC="$BATS_TEST_DIRNAME/../bin/sync.sh"
# Bats 1.2 provides a run directory but no per-file directory.
TEST_TEMPLATE="${BATS_FILE_TMPDIR:-${BATS_RUN_TMPDIR:?}/${BATS_TEST_FILENAME##*/}}/template"

write_git_config() {
	cat >"$1" <<'EOF'
[user]
	name = Test
	email = test@example.com
[init]
	defaultBranch = main
[advice]
	detachedHead = false
EOF
}

# The fake remotes are the same in every test of a file: built once, then copied.
setup_file() {
	TEST_ROOT="$TEST_TEMPLATE"
	mkdir -p "$TEST_ROOT"
	export GIT_CONFIG_GLOBAL="$TEST_ROOT/gitconfig" GIT_CONFIG_NOSYSTEM=1
	write_git_config "$GIT_CONFIG_GLOBAL"
	make_remote alpha with-develop
	make_remote beta main-only
}

setup_sandbox() {
	TEST_ROOT="$(mktemp -d)"
	cp -a "$TEST_TEMPLATE/." "$TEST_ROOT/"
	export HOME="$TEST_ROOT/home"
	export PATH="$HOME/.local/bin:$PATH"
	export XDG_CONFIG_HOME="$HOME/.config"
	export XDG_DATA_HOME="$HOME/.local/share"
	export XDG_STATE_HOME="$HOME/.local/state"
	export XDG_CACHE_HOME="$HOME/.cache"
	export ENGRAMMA_DIR="$TEST_ROOT/engramma"
	unset ENGRAMMA_DATA_DIR ENGRAMMA_UPDATED
	export ENGRAMMA_CLAUDE_HOME="$HOME/.claude"
	export CODEX_HOME="$HOME/.codex"
	export COPILOT_HOME="$HOME/.copilot"
	export ENGRAMMA_HOSTS_FILE="$TEST_ROOT/hosts"
	export GIT_CONFIG_GLOBAL="$TEST_ROOT/gitconfig"
	export GIT_CONFIG_NOSYSTEM=1
	export NO_COLOR=1
	# Tests read also what is already in place, shown only with --verbose.
	export ENGRAMMA_VERBOSE=1
	# The tests put their own tools on PATH: mise is not asked for its tools.
	export ENGRAMMA_NO_MISE=1
	# A real mise found on PATH keeps its data outside the sandbox home.
	export MISE_DATA_DIR="$TEST_ROOT/mise-data" MISE_STATE_DIR="$TEST_ROOT/mise-state" MISE_CACHE_DIR="$TEST_ROOT/mise-cache"
	# The mise engramma requires: a stub that knows no tools, already activated.
	export ENGRAMMA_MISE="$TEST_ROOT/mise-stub/mise"
	mkdir -p "$HOME" "$(dirname "$ENGRAMMA_MISE")"
	# shellcheck disable=SC2016 # the stub and the rc files get these lines literally
	printf '#!/bin/sh\n[ "$1" = ls ] && echo "{}"\nexit 0\n' >"$ENGRAMMA_MISE"
	chmod +x "$ENGRAMMA_MISE"
	# shellcheck disable=SC2016
	echo 'eval "$(mise activate bash)"' >"$HOME/.bashrc"
	# shellcheck disable=SC2016
	echo 'eval "$(mise activate zsh)"' >"$HOME/.zshrc"

	WORKSPACE="$HOME/workspace/demo"
	NOTES="$ENGRAMMA_DIR/workspaces/demo"

	make_notes
}

teardown_sandbox() {
	rm -rf "$TEST_ROOT"
}

remote_path() {
	echo "$TEST_ROOT/remotes/$1.git"
}

make_remote() {
	local name="$1" kind="$2" seed="$TEST_ROOT/seeds/$1"
	git init --quiet "$seed"
	git -C "$seed" commit --quiet --allow-empty -m "init $name"
	if [[ "$kind" == with-develop ]]; then
		git -C "$seed" switch --quiet -c develop
		git -C "$seed" commit --quiet --allow-empty -m "develop work"
		git -C "$seed" switch --quiet main
	fi
	git clone --quiet --bare "$seed" "$(remote_path "$name")"
}

push_to_remote() {
	local name="$1" branch="$2" message="$3" seed="$TEST_ROOT/seeds/$1"
	git -C "$seed" switch --quiet "$branch" 2>/dev/null || git -C "$seed" switch --quiet -c "$branch"
	git -C "$seed" commit --quiet --allow-empty -m "$message"
	git -C "$seed" push --quiet "$(remote_path "$name")" "$branch"
}

make_notes() {
	mkdir -p "$NOTES/.claude" "$NOTES/docs" "$NOTES/repo-notes" "$NOTES/memory/_workspace" "$NOTES/memory/alpha"
	cat >"$NOTES/repos.txt" <<EOF
# repo del workspace demo
alpha $(remote_path alpha)
beta $(remote_path beta)
EOF
	echo "localhost.demo.test" >"$NOTES/hosts.txt"
	echo "127.0.0.1 localhost.demo.test" >"$ENGRAMMA_HOSTS_FILE"
	echo "# demo" >"$NOTES/.claude/CLAUDE.md"
	echo "guida" >"$NOTES/docs/guida.md"
	echo "nota alpha" >"$NOTES/repo-notes/alpha.md"
	echo "- memoria" >"$NOTES/memory/_workspace/MEMORY.md"
	echo "- memoria alpha" >"$NOTES/memory/alpha/MEMORY.md"
}

# Runs a command in a pseudo terminal of the given width, with colors and the
# live zone (CI turns it off), typing the given input.
run_in_terminal() {
	local columns="$1" input="$2"
	shift 2
	command -v script >/dev/null || skip "script non installato"
	# shellcheck disable=SC2016 # expanded by the inner bash
	run env -u CI -u NO_COLOR TERM=xterm-256color SHELL=/bin/bash bash -c 'printf "$1" | script -qec "stty cols $2; $3" /dev/null' _ "$input" "$columns" "$*"
}

# A git that waits before every fetch, first on PATH.
use_slow_fetch() {
	local real
	real="$(command -v git)"
	mkdir -p "$TEST_ROOT/slow"
	printf '#!/bin/sh\ncase " $* " in *" fetch "*) touch "%s/slow/fetching"; sleep %s ;; esac\nexec %s "$@"\n' "$TEST_ROOT" "$1" "$real" >"$TEST_ROOT/slow/git"
	chmod +x "$TEST_ROOT/slow/git"
	export PATH="$TEST_ROOT/slow:$PATH"
}

memory_dir_for() {
	echo "$ENGRAMMA_CLAUDE_HOME/projects/$(printf '%s' "$1" | sed 's#[^A-Za-z0-9]#-#g')/memory"
}

current_branch() {
	git -C "$WORKSPACE/$1" branch --show-current
}

snapshot() {
	# Every run writes its log: the log folders are not a change.
	find "$HOME" -path '*/.git' -prune -o -path '*/engramma/logs' -prune -o -printf '%P %y %l\n' |
		grep -vxE '\.local(/state(/engramma)?)? d ' | sort
	local repo
	for repo in "$WORKSPACE"/*/; do
		[[ -d "$repo/.git" ]] || continue
		echo "$(basename "$repo") $(git -C "$repo" rev-parse HEAD) $(git -C "$repo" branch --show-current)"
		cat "$repo/.git/info/exclude"
	done
}
