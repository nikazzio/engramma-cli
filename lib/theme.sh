# shellcheck shell=bash
# shellcheck disable=SC2034 # the colors are used by the other modules

# Colors by meaning, filled from a theme in lib/themes/. A theme sets THEME_*
# values: "r;g;b" triplets when THEME_TRUECOLOR is true, plain SGR codes
# otherwise. ENGRAMMA_THEME picks one; the default is mocha on terminals that
# announce truecolor (COLORTERM), basic everywhere else. NO_COLOR or output that
# is not a terminal turns every color off.

THEMES_DIR="$(dirname "${BASH_SOURCE[0]}")/themes"

# Truecolor when the terminal says so, or when it is one known to support it
# without saying it (Windows Terminal does not set COLORTERM).
supports_truecolor() {
	[[ "${COLORTERM:-}" == truecolor || "${COLORTERM:-}" == 24bit ]] && return 0
	[[ -n "${WT_SESSION:-}" || -n "${KITTY_WINDOW_ID:-}" || -n "${ALACRITTY_SOCKET:-}" ]] && return 0
	case "${TERM_PROGRAM:-}" in
		vscode | iTerm.app | WezTerm | ghostty | Hyper) return 0 ;;
	esac
	[[ "${TERM:-}" == *direct* || "${TERM:-}" == xterm-kitty || "${TERM:-}" == xterm-ghostty ]]
}

default_theme() {
	if supports_truecolor; then
		echo mocha
	else
		echo basic
	fi
}

# Sets the variable $1 to the escape sequence of the theme value $2, without a
# subshell: a $(...) per color made the logo visibly slow in a busy shell.
theme_color() {
	if $THEME_TRUECOLOR; then
		printf -v "$1" '\e[38;2;%sm' "$2"
	else
		printf -v "$1" '\e[%sm' "$2"
	fi
}

load_theme() {
	local theme="${ENGRAMMA_THEME:-$(default_theme)}"
	[[ -f "$THEMES_DIR/$theme.sh" ]] || theme="$(default_theme)"
	# shellcheck source=themes/mocha.sh
	source "$THEMES_DIR/$theme.sh"

	RESET=$'\e[0m' BOLD=$'\e[1m'
	theme_color GREEN "$THEME_OK"
	theme_color DONE "$THEME_DONE"
	theme_color YELLOW "$THEME_WARN"
	theme_color RED "$THEME_ERROR"
	theme_color CYAN "$THEME_DRY"
	theme_color BLUE "$THEME_INFO"
	theme_color TEXT "$THEME_TEXT"
	theme_color DIM "$THEME_MUTED"
	theme_color RULE "$THEME_RULE"
	theme_color TITLE "$THEME_TITLE"
	TITLE="$BOLD$TITLE"
	theme_color REPO "$THEME_REPO"
	REPO="$BOLD$REPO"
	theme_color FILE "$THEME_FILE"
	theme_color CMD "$THEME_CMD"
	theme_color REF "$THEME_REF"
	MAGENTA="$REF"
}

no_colors() {
	RESET='' BOLD='' GREEN='' DONE='' YELLOW='' RED='' CYAN='' BLUE='' TEXT='' DIM='' RULE=''
	TITLE='' REPO='' FILE='' CMD='' REF='' MAGENTA=''
	THEME_BRAND=()
}

# The name of the tool, one color per letter along the theme gradient.
brand() {
	local word="${1:-engramma}" stops=${#THEME_BRAND[@]} index text="" color
	if ((stops == 0)); then
		echo "$word"
		return
	fi
	for ((index = 0; index < ${#word}; index++)); do
		theme_color color "${THEME_BRAND[index * stops / ${#word}]}"
		text+="$BOLD$color${word:index:1}"
	done
	echo "$text$RESET"
}

# A path for the messages: ~ for the home folder, in the color of files.
path() {
	echo "$FILE$(tilde "$1")$RESET"
}
