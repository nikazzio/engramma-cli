# shellcheck shell=bash

# Output model. Everything engramma prints belongs to a block (engramma itself,
# the workstation, Claude Code, Codex, each workspace). A block is buffered and
# printed when it ends, with one header line carrying its outcome: a block where
# everything is in place takes one line, with a count of what was checked. Inside
# a workspace each repo collects its own lines, and repos with the same outcome
# are printed together. While engramma works, the live zone at the bottom of the
# terminal says what it is doing.

# The python of the system, not the one a project selects with mise: engramma
# only needs the standard library.
# shellcheck disable=SC2034 # used by the other modules
PYTHON="$(command -v /usr/bin/python3 || command -v python3)"

# shellcheck source=theme.sh
source "$(dirname "${BASH_SOURCE[0]}")/theme.sh"

# Questions and the live zone need a terminal; colors also need NO_COLOR unset.
shopt -s extglob
if [[ -t 1 ]]; then
	IS_INTERACTIVE=true
else
	IS_INTERACTIVE=false
fi
if $IS_INTERACTIVE && [[ -z "${NO_COLOR:-}" ]]; then
	load_theme
else
	no_colors
fi

# The outcome of a line is a label of the same width on its right, in the color
# of the outcome: the eye reads one column. OK is what was already in place,
# DONE what this run has just done. A line carries it after BADGE_MARK
# (DOTS_MARK for a dotted leader), and put aligns it to OUTPUT_WIDTH.
BADGE_MARK=$'\x1d' DOTS_MARK=$'\x1c'
BADGE_WIDTH=8
declare -A BADGES=(
	[ok]="${DONE}[ DONE ]${RESET}" [fine]="${GREEN}[  OK  ]${RESET}" [info]="${BLUE}[ INFO ]${RESET}"
	[dry]="${CYAN}[ DRY  ]${RESET}" [skip]="${YELLOW}[ SKIP ]${RESET}" [warn]="${YELLOW}[ WARN ]${RESET}"
	[err]="${RED}[ FAIL ]${RESET}"
)

# Labels at the edge of the terminal, but not further than a comfortable line;
# outside a terminal at 80 columns.
output_width() {
	local width=80
	# One column free: a line as wide as the terminal wraps in some of them.
	$IS_INTERACTIVE && width=$(($(terminal_width) - 1))
	((width > 100)) && width=100
	OUTPUT_WIDTH=$width
}

QUOTES=(
	"May the fetch be with you."
	"All your branch are belong to develop."
	"It's not a bug, it's a feature branch."
	"There's no place like 127.0.0.1."
	"git gud."
	"Fast-forward: l'unico viaggio nel tempo consentito."
	"Un engramma al giorno toglie il context window di torno."
	"Ricordare è facile, se hai fatto git push."
	"rm -rf è per sempre. I symlink no."
	"Works on my machine. Ora anche sull'altra."
)

PROBLEM_COUNT=0
NEXT_STEPS=()
# What the summary lists, one entry per message: kind (problem, local, warning),
# where (block, or workspace/repo), text, and the command that fixes it.
NOTES=()
LAST_NOTE=-1
# Blocks print only their header line unless something was done or must be
# fixed; EXPAND_BLOCKS (a workspace named on the command line) shows them whole.
EXPAND_BLOCKS=false
VERBOSE=false
[[ -n "${ENGRAMMA_VERBOSE:-}" ]] && VERBOSE=true

# Outcome levels, from the best to the worst.
LEVEL_FINE=0 LEVEL_DONE=1 LEVEL_INFO=2 LEVEL_DRY=3 LEVEL_WARN=4 LEVEL_ERROR=5
LEVEL_BADGES=(fine ok info dry warn err)

tilde() {
	echo "${1/#$HOME/\~}"
}

# ── live zone ─────────────────────────────────────────────────────────────────

# In a terminal with colors the bottom of the screen is a zone redrawn by a
# background process, under a rule in the colors of the logo: a status line (spinner, what engramma is doing, progress,
# elapsed time) and the last lines of output. The final lines scroll above it.
# While the zone is active that process is the only one writing to the terminal:
# put appends to a queue it prints from, so nothing can interleave. Elsewhere
# (pipe, hook, CI, NO_COLOR) every line is printed as it comes, without codes.
LIVE=false
if $IS_INTERACTIVE && [[ -z "${NO_COLOR:-}" && "${TERM:-dumb}" != dumb && -z "${CI:-}" ]]; then
	LIVE=true
fi
LIVE_DIR=""
LIVE_PID=""
LIVE_QUEUE_FD=""
TRAIL_LINES=5

start_activity() {
	$LIVE && [[ -z "$LIVE_PID" ]] || return 0
	if [[ -z "$LIVE_DIR" ]]; then
		LIVE_DIR="$(mktemp -d)"
		: >"$LIVE_DIR/queue"
		: >"$LIVE_DIR/trail"
		exec {LIVE_QUEUE_FD}>>"$LIVE_DIR/queue"
	fi
	touch "$LIVE_DIR/running"
	render_live &
	LIVE_PID=$!
}

# Stops the zone after it has printed every queued line, and erases it.
stop_activity() {
	[[ -n "$LIVE_PID" ]] || return 0
	rm -f "$LIVE_DIR/running"
	# A trapped signal (SIGWINCH on a resize) ends wait early: wait again until
	# the zone has printed its last lines.
	while kill -0 "$LIVE_PID" 2>/dev/null; do
		wait "$LIVE_PID" 2>/dev/null
	done
	LIVE_PID=""
	: >"$LIVE_DIR/queue"
	: >"$LIVE_DIR/trail"
}

# What engramma is doing now, on the status line of the zone.
activity() {
	[[ -n "$LIVE_DIR" ]] || return 0
	if [[ -n "${JOB_ID:-}" ]]; then
		trail_line "$*"
	else
		printf '%s' "$*" >"$LIVE_DIR/activity"
	fi
	return 0
}

# A line for the zone, among the last ones shown under the status line.
trail_line() {
	[[ -n "$LIVE_DIR" ]] && printf '%s\n' "${1%%["$BADGE_MARK$DOTS_MARK"]*}" >>"$LIVE_DIR/trail"
	return 0
}

# The progress on the status line: the folder where every finished job leaves a
# .done file, how many jobs there are and what they are ("repo").
live_progress() {
	[[ -n "$LIVE_DIR" ]] && printf '%s %s %s' "$1" "$2" "$3" >"$LIVE_DIR/progress"
	return 0
}

# Prints one line: through the zone when it is active, directly otherwise.
put() {
	local text="$1"
	[[ "$text" == *["$BADGE_MARK$DOTS_MARK"]* ]] && align_badge text
	log_line "$text"
	if [[ -n "$LIVE_PID" ]]; then
		printf '%s\n' "$text" >&"$LIVE_QUEUE_FD"
	else
		printf '%s\n' "$text"
	fi
}

# Moves the label of the line in the variable $1 to the right edge. In a terminal
# a line too long for the label goes on below, under its indentation (and rail).
align_badge() {
	local -n aligned="$1"
	local marks="$BADGE_MARK$DOTS_MARK"
	local left="${aligned%%["$marks"]*}" badge="${aligned#*["$marks"]}"
	local leader="${aligned:${#left}:1}" plain fill indent="" rest="" piece
	local room=$((OUTPUT_WIDTH - BADGE_WIDTH - 2))
	strip_colors plain "$left"
	# Outside a terminal a long line stays whole, easier to search.
	if ((${#plain} > room)) && ! $IS_INTERACTIVE; then
		aligned="$left  $badge"
		return
	fi
	if ((${#plain} > room)); then
		indent="${plain%%[^ │├└─]*}"
		indent="${indent//├/│}" indent="${indent//[└─]/ }"
		indent="${RULE}$indent${RESET}  "
		split_visible "$left" "$room"
		left="$SPLIT_HEAD" rest="$SPLIT_TAIL"
		strip_colors plain "$left"
		leader="$BADGE_MARK"
	fi
	if [[ "$leader" == "$DOTS_MARK" ]]; then
		printf -v fill '%*s' $((OUTPUT_WIDTH - ${#plain} - BADGE_WIDTH - 2)) ''
		fill=" ${RULE}${fill// /·}${RESET} "
	else
		printf -v fill '%*s' $((OUTPUT_WIDTH - ${#plain} - BADGE_WIDTH)) ''
	fi
	aligned="$left$fill$badge"
	strip_colors piece "$indent"
	while [[ -n "${rest:-}" ]]; do
		split_visible "$rest" $((OUTPUT_WIDTH - ${#piece}))
		aligned+=$'\n'"$indent$SPLIT_HEAD"
		rest="$SPLIT_TAIL"
	done
}

# Sets the variable $1 to the text $2 without its color codes. A loop and not
# ${2//$'\e'\[*([0-9;])m/}: that pattern slows down with the number of codes,
# 0.6 s for a line of the logo with a color per character.
strip_colors() {
	local -n stripped="$1"
	local rest="$2" params
	stripped=""
	while [[ "$rest" == *$'\e['* ]]; do
		stripped+="${rest%%$'\e['*}"
		rest="${rest#*$'\e['}"
		params="${rest%%[!0-9;]*}"
		if [[ "${rest:${#params}:1}" == m ]]; then
			rest="${rest:${#params}+1}"
		else
			stripped+=$'\e['
		fi
	done
	stripped+="$rest"
}

# Cuts a colored text after at most $2 visible characters, at a space when there is
# one in the second half: SPLIT_HEAD and SPLIT_TAIL, which starts again with the
# color in use at the cut.
split_visible() {
	local text="$1" width="$2" index=0 visible=0 color="" sequence
	local space=-1 space_color=""
	while ((index < ${#text})); do
		if [[ "${text:index:1}" == $'\e' ]]; then
			sequence="${text:index}"
			sequence="${sequence%%m*}m"
			if [[ "$sequence" == $'\e[0m' ]]; then color=""; else color+="$sequence"; fi
			index=$((index + ${#sequence}))
			continue
		fi
		((visible == width)) && break
		if [[ "${text:index:1}" == " " ]] && ((visible > width / 2)); then
			space=$index space_color="$color"
		fi
		visible=$((visible + 1))
		index=$((index + 1))
	done
	if ((index >= ${#text})); then
		SPLIT_HEAD="$text" SPLIT_TAIL=""
	elif ((space > 0)); then
		SPLIT_HEAD="${text:0:space}$RESET" SPLIT_TAIL="$space_color${text:space+1}"
	else
		SPLIT_HEAD="${text:0:index}$RESET" SPLIT_TAIL="$color${text:index}"
	fi
}

terminal_height() {
	local height
	height="$({ tput lines 2>/dev/tty </dev/null; } 2>/dev/null)"
	[[ "$height" =~ ^[0-9]+$ ]] && ((height > 5)) || height=24
	echo "$height"
}

# Before the header: what is on the screen goes up into the scrollback, and the
# header starts at the first row.
clear_for_header() {
	$LIVE || return 0
	local rows newlines
	rows="$(terminal_height)"
	printf -v newlines '%*s' "$rows" ''
	printf '%s\e[H' "${newlines// /$'\n'}"
}

terminal_width() {
	local width
	width="$({ tput cols 2>/dev/tty </dev/null; } 2>/dev/null)"
	[[ "$width" =~ ^[0-9]+$ ]] && ((width > 20)) || width=80
	echo "$width"
}

# Sets the variable $1 to the time in $2 seconds: "42s", "1m 05s".
elapsed_label() {
	if (($2 < 60)); then
		printf -v "$1" '%ds' "$2"
	else
		printf -v "$1" '%dm %02ds' $(($2 / 60)) $(($2 % 60))
	fi
}

# Sets the variable $1 to a line of the zone: without colors and tabs, cut to the
# width $3 so it never wraps (a wrapped line would shift every redraw).
fit_line() {
	local text
	strip_colors text "$2"
	text="${text##*$'\r'}"
	# Characters two columns wide (emoji, ideograms) would wrap the line: only
	# Latin letters, punctuation, arrows, box drawing and dingbats stay.
	text="${text//[^ -~ -ɏ‐-⋿─-◿✀-➿]/?}"
	text="${text//$'\t'/  }"
	(($3 < 1)) && text=""
	((${#text} > $3 && $3 > 0)) && text="${text:0:$3-1}…"
	printf -v "$1" '%s' "$text"
}

# Sets the variable $1 to a rule $2 columns wide in the brand gradient, one
# escape sequence per color.
brand_rule() {
	local width="$2" stops=${#THEME_BRAND[@]} column stop last=-1 line="" color
	for ((column = 0; column < width; column++)); do
		stop=$((stops ? column * stops / width : -1))
		if ((stop != last && stop >= 0)); then
			theme_color color "${THEME_BRAND[stop]}"
			line+="$color"
			last=$stop
		fi
		line+="─"
	done
	printf -v "$1" '%s' "$line$RESET"
}

# The loop of the background process that draws the zone. Ctrl+C is left to the
# main process, which stops the zone and restores the cursor.
render_live() {
	trap '' INT
	trap 'width="$(terminal_width)"' WINCH
	shopt -s nullglob
	local width frames='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏' frame=0 drawn=0 running line pending="" queue trail_fd
	local trail=() text fitted out zone dir total noun done_files suffix elapsed separator separator_width=0
	width="$(terminal_width)"
	exec {queue}<"$LIVE_DIR/queue" {trail_fd}<"$LIVE_DIR/trail"
	printf '\e[?25l'
	while :; do
		running=true
		[[ -e "$LIVE_DIR/running" ]] && kill -0 "$$" 2>/dev/null || running=false
		out=""
		while IFS= read -r -u "$queue" line; do
			out+="$pending$line"$'\n'
			pending=""
		done
		pending+="$line"
		while IFS= read -r -u "$trail_fd" line; do
			trail+=("$line")
		done
		((${#trail[@]} > TRAIL_LINES)) && trail=("${trail[@]: -TRAIL_LINES}")
		# Back to the first line of the zone, then erase down to the end.
		zone=$'\r'
		((drawn > 1)) && zone+=$'\e['"$((drawn - 1))A"
		zone+=$'\e[J'"$out"
		drawn=0
		if $running; then
			suffix=""
			if [[ -f "$LIVE_DIR/progress" ]]; then
				read -r dir total noun <"$LIVE_DIR/progress"
				done_files=("$dir"/*.done)
				suffix+=" · ${#done_files[@]}/$total $noun"
			fi
			elapsed_label elapsed "$SECONDS"
			suffix+=" · $elapsed"
			text=""
			[[ -f "$LIVE_DIR/activity" ]] && IFS= read -r text <"$LIVE_DIR/activity"
			fit_line fitted "$text" $((width - 5 - ${#suffix}))
			if ((separator_width != width)); then
				brand_rule separator $((width - 1))
				separator_width=$width
			fi
			zone+="$separator"$'\n'"  $CYAN${frames:frame++%10:1}$RESET $TEXT$fitted$RESET$DIM$suffix$RESET"
			drawn=2
			for line in "${trail[@]}"; do
				fit_line fitted "$line" $((width - 7))
				zone+=$'\n'"    $RULE│$RESET $DIM$fitted$RESET"
				drawn=$((drawn + 1))
			done
		fi
		printf '%s' "$zone"
		$running || break
		sleep 0.08
	done
	printf '\e[?25h'
}

output_width
$IS_INTERACTIVE && trap output_width WINCH

# ── log ───────────────────────────────────────────────────────────────────────

# Every run leaves a full log: all the lines, also the ones hidden without -v, and
# what git, claude and codex wrote on stderr. The last LOG_KEEP are kept.
LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/engramma/logs"
LOG_KEEP=20
LOG_FILE=""
LOG_FD=""

# A restart after the pull of engramma keeps writing the same log.
start_log() {
	LOG_FILE="${ENGRAMMA_LOG_FILE:-}"
	if [[ -z "$LOG_FILE" ]]; then
		mkdir -p "$LOG_DIR" || return 0
		LOG_FILE="$LOG_DIR/$(date +%Y-%m-%d-%H%M%S).log"
		[[ -e "$LOG_FILE" ]] && LOG_FILE="${LOG_FILE%.log}-$$.log"
		export ENGRAMMA_LOG_FILE="$LOG_FILE"
		: >"$LOG_FILE"
		local old
		while IFS= read -r old; do
			rm -f "$old"
		done < <(find "$LOG_DIR" -maxdepth 1 -name '*.log' | sort | head -n -"$LOG_KEEP")
	fi
	exec {LOG_FD}>>"$LOG_FILE" || LOG_FD=""
}

log_line() {
	[[ -n "$LOG_FD" ]] && printf '%s\n' "$1" >&"$LOG_FD"
	return 0
}

# The output of a command, in the log and in the zone.
log_output() {
	local line
	while IFS= read -r line; do
		[[ -n "${line//[[:space:]]/}" ]] || continue
		log_line "     │ $line"
		trail_line "$line"
	done <<<"$1"
}

# The log is written with the colors of the screen: they are removed at the end.
finish_log() {
	[[ -n "$LOG_FD" ]] || return 0
	exec {LOG_FD}>&-
	LOG_FD=""
	sed -i 's/\x1b\[[0-9;]*m//g' "$LOG_FILE" 2>/dev/null
}

# Ctrl+C or the end of the run: the zone is stopped and the cursor comes back.
cleanup_output() {
	stop_activity
	declare -F stop_repo_jobs >/dev/null && stop_repo_jobs
	finish_log
	[[ -n "$LIVE_DIR" ]] && rm -rf "$LIVE_DIR"
	[[ -n "${SSH_PROBE_DIR:-}" ]] && rm -rf "$SSH_PROBE_DIR"
	$LIVE && printf '\e[?25h'
	return 0
}

trap cleanup_output EXIT
trap 'cleanup_output; trap - EXIT; exit 130' INT
trap 'cleanup_output; trap - EXIT; exit 143' TERM
trap 'cleanup_output; trap - EXIT; exit 129' HUP

# ── blocks ────────────────────────────────────────────────────────────────────

BLOCK_OPEN=false
BLOCK_FLUSHED=false
BLOCK_TITLE="" BLOCK_DETAIL="" BLOCK_NOUN=""
BLOCK_LINES=() BLOCK_HIDDEN=()
BLOCK_LEVEL=0 BLOCK_FINE=0 BLOCK_ISSUES=0 BLOCK_WARNINGS=0 BLOCK_CHANGES=0
BLOCK_EXPANDED=false
GROUP_TITLE="" GROUP_SHOWN=false
REPO_NAME="" REPO_STATUS="" REPO_MESSAGE="" REPO_LEVEL=0
REPO_LINES=()
REPO_KEYS=() REPO_NAMES=() REPO_BODIES=()

# Starts a block: a title, a detail in grey, and the noun for the count shown when
# everything is in place ("12 programmi").
block() {
	block_end
	BLOCK_OPEN=true BLOCK_FLUSHED=false
	BLOCK_TITLE="$1" BLOCK_DETAIL="${2:-}" BLOCK_NOUN="${3:-controlli}"
	BLOCK_LINES=() BLOCK_HIDDEN=() BLOCK_LEVEL=0 BLOCK_FINE=0 BLOCK_ISSUES=0 BLOCK_WARNINGS=0 BLOCK_CHANGES=0
	BLOCK_EXPANDED=$EXPAND_BLOCKS
	GROUP_TITLE="" GROUP_SHOWN=false
	REPO_KEYS=() REPO_NAMES=() REPO_BODIES=()
	activity "$1"
}

# A titled group of lines inside the block, printed only if it has any.
section() {
	repo_end
	GROUP_TITLE="$1" GROUP_SHOWN=false
	$BLOCK_OPEN || block "$1"
	activity "$BLOCK_TITLE › $1"
}

raise_level() {
	((${1} == LEVEL_DONE || ${1} == LEVEL_INFO || ${1} == LEVEL_DRY)) && BLOCK_CHANGES=$((BLOCK_CHANGES + 1))
	((${1} > BLOCK_LEVEL)) && BLOCK_LEVEL=$1
	[[ -n "$REPO_NAME" ]] && ((${1} > REPO_LEVEL)) && REPO_LEVEL=$1
	return 0
}

# Adds a line to the repo, to the block, or prints it when nothing is buffered.
say() {
	local text="$1"
	trail_line "$text"
	if $BLOCK_FLUSHED; then
		put "        $text"
	elif [[ -n "$REPO_NAME" ]]; then
		REPO_LINES+=("$text")
	elif $BLOCK_OPEN; then
		if [[ -n "$GROUP_TITLE" ]] && ! $GROUP_SHOWN; then
			BLOCK_LINES+=("${DIM}$GROUP_TITLE${RESET}")
			GROUP_SHOWN=true
		fi
		BLOCK_LINES+=("  $text")
	else
		put "     $text"
	fi
	return 0
}

line() {
	local level="$1" kind="$2"
	shift 2
	raise_level "$level"
	say "$*$BADGE_MARK${BADGES[$kind]}"
}

ok() { line "$LEVEL_DONE" ok "$@"; }
info() { line "$LEVEL_INFO" info "$@"; }
would() { line "$LEVEL_DRY" dry "$@"; }
skip() {
	line "$LEVEL_WARN" skip "$@"
	note warning "$*"
}
warn() {
	BLOCK_WARNINGS=$((BLOCK_WARNINGS + 1))
	line "$LEVEL_WARN" warn "$@"
	note "${NOTE_KIND:-warning}" "$*"
}
fail() {
	BLOCK_ISSUES=$((BLOCK_ISSUES + 1))
	line "$LEVEL_ERROR" err "$@"
	note problem "$*"
}

# Work that exists only on this computer (uncommitted files, unpushed branches):
# a warning, listed apart in the summary.
local_work() {
	NOTE_KIND=local warn "$@"
}

# Remembers a message for the summary, with where it comes from.
note() {
	NOTES+=("$1"$'\t'"$BLOCK_TITLE${REPO_NAME:+/$REPO_NAME}"$'\t'"$2"$'\t')
	LAST_NOTE=$((${#NOTES[@]} - 1))
}

# Something already in place: counted, and shown only with --verbose.
fine() {
	BLOCK_FINE=$((BLOCK_FINE + 1))
	if $VERBOSE; then
		say "${DIM}$*${RESET}$BADGE_MARK${BADGES[fine]}"
	else
		trail_line "$*"
		if $BLOCK_OPEN && ! $BLOCK_FLUSHED; then
			BLOCK_HIDDEN+=("$*")
		else
			log_line "     $*  [  OK  ]"
		fi
	fi
	return 0
}

# Something to fix: counted in the outcome and in the exit status.
problem() {
	PROBLEM_COUNT=$((PROBLEM_COUNT + 1))
	BLOCK_ISSUES=$((BLOCK_ISSUES + 1))
	BLOCK_WARNINGS=$((BLOCK_WARNINGS - 1))
	NOTE_KIND=problem warn "$@"
}

# ── repos inside a workspace ──────────────────────────────────────────────────

repo_begin() {
	repo_end
	GROUP_TITLE=""
	REPO_NAME="$1" REPO_STATUS="fine" REPO_MESSAGE="" REPO_LINES=() REPO_LEVEL=0
	activity "$BLOCK_TITLE › $1"
	$BLOCK_FLUSHED && put "   ${RULE}├─${RESET} ${TEXT}$1${RESET}"
	return 0
}

# The one-line outcome of the repo: fine, ok, dry, skip, warn or err.
repo_status() {
	REPO_STATUS="$1" REPO_MESSAGE="$2"
	case "$1" in
		err) raise_level "$LEVEL_ERROR" ;;
		warn | skip) raise_level "$LEVEL_WARN" ;;
		dry) raise_level "$LEVEL_DRY" ;;
		ok) raise_level "$LEVEL_DONE" ;;
	esac
}

repo_end() {
	[[ -n "$REPO_NAME" ]] || return 0
	if $BLOCK_FLUSHED; then
		put "        ${DIM}$REPO_MESSAGE${RESET}$BADGE_MARK${BADGES[$REPO_STATUS]}"
		REPO_NAME=""
		return 0
	fi
	# The lines can be worse than the outcome: the icon follows the worst.
	if [[ "$REPO_STATUS" == fine || "$REPO_STATUS" == ok ]]; then
		if ((REPO_LEVEL >= LEVEL_WARN)); then
			REPO_STATUS=warn
		elif ((REPO_LEVEL == LEVEL_DRY)); then
			REPO_STATUS=dry
		fi
	fi
	local body="$REPO_STATUS"$'\x1f'"$REPO_MESSAGE" index
	((${#REPO_LINES[@]})) && body+=$'\x1f'"$(printf '%s\x1e' "${REPO_LINES[@]}")"
	for index in "${!REPO_BODIES[@]}"; do
		if [[ "${REPO_BODIES[index]}" == "$body" ]]; then
			REPO_NAMES[index]+=" $REPO_NAME"
			REPO_NAME=""
			return 0
		fi
	done
	REPO_BODIES+=("$body")
	REPO_NAMES+=("$REPO_NAME")
	REPO_NAME=""
}

# "a, b, c +4": the names of a group, cut to fit one line.
name_list() {
	local names=("$@") text="" width=0 shown=0 name
	for name in "${names[@]}"; do
		if ((width + ${#name} > 46 && shown > 0)); then
			echo "$text${RESET} ${DIM}+$((${#names[@]} - shown))${RESET}"
			return
		fi
		((shown)) && text+="${RESET}${DIM}, ${RESET}${TEXT}" && width=$((width + 2))
		text+="$name"
		width=$((width + ${#name}))
		shown=$((shown + 1))
	done
	echo "$text"
}

# Renders the repos as a tree, one branch per group of repos with the same outcome.
render_repos() {
	local count=${#REPO_BODIES[@]} index status message rest names branch rail detail
	local listed plain column=0
	((count)) || return 0
	# The messages start in one column, after the longest list of names.
	for index in "${!REPO_NAMES[@]}"; do
		read -ra names <<<"${REPO_NAMES[index]}"
		listed="$(name_list "${names[@]}")"
		strip_colors plain "$listed"
		((${#plain} > column)) && column=${#plain}
	done
	BLOCK_LINES+=("${DIM}repo${RESET}")
	for index in "${!REPO_BODIES[@]}"; do
		IFS=$'\x1f' read -r status message rest <<<"${REPO_BODIES[index]}"
		read -ra names <<<"${REPO_NAMES[index]}"
		if ((index == count - 1)); then
			branch="└─" rail="   "
		else
			branch="├─" rail="${RULE}│${RESET}  "
		fi
		listed="$(name_list "${names[@]}")"
		strip_colors plain "$listed"
		printf -v plain '%*s' $((column - ${#plain})) ''
		BLOCK_LINES+=("${RULE}$branch${RESET} ${TEXT}$listed${RESET}$plain  ${DIM}$message${RESET}$BADGE_MARK${BADGES[$status]}")
		[[ -n "$rest" ]] || continue
		while IFS= read -r -d $'\x1e' detail; do
			BLOCK_LINES+=("$rail  $detail")
		done <<<"$rest"
	done
}

block_header() {
	local outcome="$1"
	put ""
	put " ${TITLE}$BLOCK_TITLE${RESET}${BLOCK_DETAIL:+  ${FILE}$BLOCK_DETAIL${RESET}}${outcome:+  ${RULE}·${RESET} $outcome}$DOTS_MARK${BADGES[${LEVEL_BADGES[BLOCK_LEVEL]}]}"
}

block_outcome() {
	local warnings=""
	((BLOCK_WARNINGS == 1)) && warnings="1 avviso"
	((BLOCK_WARNINGS > 1)) && warnings="$BLOCK_WARNINGS avvisi"
	if ((BLOCK_ISSUES)); then
		echo "${YELLOW}$BLOCK_ISSUES da sistemare${RESET}${warnings:+ ${DIM}· $warnings${RESET}}"
	elif [[ -n "$warnings" ]]; then
		echo "${DIM}$warnings${RESET}"
	elif ((BLOCK_LEVEL == LEVEL_FINE)); then
		((BLOCK_FINE)) && echo "${DIM}$BLOCK_FINE $BLOCK_NOUN ok${RESET}" || echo "${DIM}ok${RESET}"
	fi
}

# Moves the repos seen so far into the lines of the block, as a tree: what follows
# in the block comes after them.
close_repos() {
	repo_end
	render_repos
	REPO_KEYS=() REPO_NAMES=() REPO_BODIES=()
}

block_end() {
	$BLOCK_OPEN || return 0
	repo_end
	BLOCK_OPEN=false
	if $BLOCK_FLUSHED; then
		return 0
	fi
	render_repos
	block_header "$(block_outcome)"
	local text
	if block_collapsed; then
		for text in "${BLOCK_LINES[@]}"; do
			text="   $text"
			[[ "$text" == *["$BADGE_MARK$DOTS_MARK"]* ]] && align_badge text
			log_line "$text"
		done
	else
		for text in "${BLOCK_LINES[@]}"; do
			put "   $text"
		done
	fi
	log_hidden_lines
}

# Only warnings, or nothing: the header line says it, the summary lists them.
block_collapsed() {
	! $VERBOSE && ! $BLOCK_EXPANDED && ((BLOCK_ISSUES == 0 && BLOCK_CHANGES == 0))
}

# The lines of the block hidden without --verbose, only in the log.
log_hidden_lines() {
	local text
	for text in "${BLOCK_HIDDEN[@]}"; do
		log_line "     $text  [  OK  ]"
	done
	BLOCK_HIDDEN=()
}

# Prints what the block holds so far, before a question in the terminal: the rest
# of the block, and of the repo being processed, is then printed as it comes.
flush_block() {
	$BLOCK_OPEN && ! $BLOCK_FLUSHED || return 0
	local text
	close_repos
	block_header ""
	for text in "${BLOCK_LINES[@]}"; do
		put "   $text"
	done
	if [[ -n "$REPO_NAME" ]]; then
		put "   ${RULE}├─${RESET} ${TEXT}$REPO_NAME${RESET}"
		for text in "${REPO_LINES[@]}"; do
			put "        $text"
		done
	fi
	log_hidden_lines
	BLOCK_FLUSHED=true
}

# Asks in the terminal and leaves the answer, lowercase, in ASK_ANSWER (empty when
# not interactive). It runs in the current shell, never in $(...): the question and
# the block it belongs to must reach the terminal, and the live zone is stopped and
# erased first so it cannot cover them.
ASK_ANSWER=""
ask() {
	ASK_ANSWER=""
	$IS_INTERACTIVE || return 0
	flush_block
	local resume=false
	[[ -n "$LIVE_PID" ]] && resume=true && stop_activity
	read -r -p "        ${BOLD}$1${RESET} " ASK_ANSWER </dev/tty
	log_line "        $1 $ASK_ANSWER"
	ASK_ANSWER="${ASK_ANSWER,,}"
	$resume && start_activity
	return 0
}

# A part of the output (postazione, agenti, workspace): its title and a rule.
heading() {
	block_end
	local rule
	printf -v rule '%*s' $((OUTPUT_WIDTH - ${#1} - 3)) ''
	put ""
	put " ${BOLD}${TITLE}$1${RESET} ${RULE}${rule// /━}${RESET}"
}

# ── next steps and summary ────────────────────────────────────────────────────

# Records a command for the user to run, shown in order at the end. Lower order
# comes first: 10 install, 20 shell, 30 configuration, 40 duplicates, 50 other.
next_step() {
	local order="$1" text="$2" step
	for step in "${NEXT_STEPS[@]}"; do
		[[ "${step#*$'\t'}" == "$text" ]] && return 0
	done
	NEXT_STEPS+=("$order"$'\t'"$text")
}

# The command that fixes the message just reported: shown under it in the summary.
fix_with() {
	local order="$1" text="$2" kind where message step
	if ((LAST_NOTE >= 0)); then
		IFS=$'\t' read -r kind where message step <<<"${NOTES[LAST_NOTE]}"
		if [[ -z "$step" ]]; then
			NOTES[LAST_NOTE]="$kind"$'\t'"$where"$'\t'"$message"$'\t'"$text"
			return 0
		fi
	fi
	next_step "$order" "$text"
}

# One list of the summary: the messages of a kind, aligned on where they come from.
print_notes() {
	local wanted="$1" title="$2" color="$3" entry kind where message step width=0 count=0 pad
	for entry in "${NOTES[@]}"; do
		IFS=$'\t' read -r kind where message step <<<"$entry"
		[[ "$kind" == "$wanted" ]] || continue
		count=$((count + 1))
		((${#where} > width)) && width=${#where}
	done
	((count)) || return 0
	put " ${BOLD}$color$title${RESET} ${DIM}($count)${RESET}"
	for entry in "${NOTES[@]}"; do
		IFS=$'\t' read -r kind where message step <<<"$entry"
		[[ "$kind" == "$wanted" ]] || continue
		printf -v pad '%*s' $((width - ${#where})) ''
		put "   ${REPO}$where${RESET}$pad  ${TEXT}$message${RESET}"
		[[ -n "$step" ]] && put "   $pad${where//?/ }  ${RULE}→${RESET} $step"
	done
	put ""
}

# The commands that belong to no message, in order.
print_next_steps() {
	((${#NEXT_STEPS[@]})) || return 0
	put " ${BOLD}${TITLE}altri comandi${RESET}"
	local number=0 text
	while IFS= read -r text; do
		number=$((number + 1))
		put "   ${DIM}$number.${RESET} $text"
	done < <(printf '%s\n' "${NEXT_STEPS[@]}" | sort -s -t $'\t' -k1,1n | cut -f2-)
	put ""
}

# Repos whose clone or fetch took long, and repos that failed: "<ws>/<repo>".
SLOW_REPOS=() FAILED_REPOS=()

print_slow_and_failed() {
	local text
	if ((${#FAILED_REPOS[@]})); then
		put " ${TITLE}repo falliti${RESET}  ${TEXT}$(name_list "${FAILED_REPOS[@]}")${RESET}$DOTS_MARK${BADGES[err]}"
	fi
	if ((${#SLOW_REPOS[@]})); then
		printf -v text '%s · ' "${SLOW_REPOS[@]}"
		put " ${TITLE}repo lenti${RESET}  ${DIM}oltre ${SLOW_REPO_SECONDS}s${RESET}  ${text% · }$DOTS_MARK${BADGES[warn]}"
	fi
	((${#FAILED_REPOS[@]} + ${#SLOW_REPOS[@]})) && put ""
	return 0
}

print_summary() {
	block_end
	stop_activity
	# The rule of the live zone stays, once, between the blocks and the summary.
	local separator
	brand_rule separator $((OUTPUT_WIDTH - 1))
	put ""
	put " $separator"
	put ""
	print_notes problem "da sistemare" "$RED"
	print_notes local "modifiche locali e repo non aggiornati" "$YELLOW"
	print_notes warning "avvisi" "$BLUE"
	print_next_steps
	print_slow_and_failed
	local elapsed="${DIM}${SECONDS}s${RESET}"
	if ((PROBLEM_COUNT)); then
		local outcome="${BADGES[warn]}" noun="problemi da risolvere"
		((${#FAILED_REPOS[@]})) && outcome="${BADGES[err]}"
		((PROBLEM_COUNT == 1)) && noun="problema da risolvere"
		put " ${BOLD}operazione conclusa: $PROBLEM_COUNT $noun${RESET}  ${DIM}·${RESET} $elapsed$DOTS_MARK$outcome"
	elif [[ "$MODE" == dry ]]; then
		put " ${BOLD}prova finita${RESET}  ${DIM}·${RESET} $elapsed  ${DIM}· niente è stato modificato${RESET}$DOTS_MARK${BADGES[dry]}"
	else
		put " ${BOLD}tutto a posto${RESET}  ${DIM}·${RESET} $elapsed$DOTS_MARK${BADGES[fine]}"
	fi
	put ""
	put "   ${REF}❝${RESET} ${DIM}${QUOTES[RANDOM % ${#QUOTES[@]}]}${RESET}"
	[[ -n "$LOG_FILE" ]] && put "   ${DIM}log: $(tilde "$LOG_FILE")${RESET}"
	return 0
}

# ── header ────────────────────────────────────────────────────────────────────

LOGO=(
	"┏━╸┏┓╻┏━╸┏━┓┏━┓┏┳┓┏┳┓┏━┓"
	"┣╸ ┃┗┫┃╺┓┣┳┛┣━┫┃┃┃┃┃┃┣━┫"
	"┗━╸╹ ╹┗━┛╹┗╸╹ ╹╹ ╹╹ ╹╹ ╹"
)

# The logo in the brand gradient, column by column.
print_logo() {
	local row width=${#LOGO[0]} stops=${#THEME_BRAND[@]} column text color
	put ""
	for row in "${LOGO[@]}"; do
		if ((stops == 0)); then
			put "   $row"
			continue
		fi
		text=""
		for ((column = 0; column < width; column++)); do
			theme_color color "${THEME_BRAND[column * stops / width]}"
			text+="$BOLD$color${row:column:1}"
		done
		put "   $text$RESET"
	done
	put "   ${DIM}contesto personale per gli agenti, versionato e proiettato su ogni macchina${RESET}"
}

print_header() {
	local mode_label
	case "$MODE" in
		dry) mode_label="${CYAN}--dry-run${RESET} ${DIM}nessuna modifica${RESET}" ;;
		check) mode_label="${DIM}sola lettura${RESET}" ;;
		*) mode_label="" ;;
	esac
	clear_for_header
	print_logo
	put ""
	put " $(brand ◆)  ${TITLE}$1${RESET}${mode_label:+  ${RULE}·${RESET} $mode_label}  ${RULE}·${RESET} ${DIM}$(hostname -s 2>/dev/null) · ${REF}$(engramma_revision)${RESET}"
	put "    ${DIM}archivio: $(tilde "$ENGRAMMA_DIR")${RESET}"
	$VERBOSE || put "    ${DIM}una riga per sezione, riepilogo in fondo; eng <workspace> o -v per i dettagli${RESET}"
	start_activity
}

engramma_revision() {
	git -C "$ENGRAMMA_DIR" log -1 --format='%h · %cs' 2>/dev/null || echo "senza git"
}
