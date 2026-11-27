# shellcheck shell=bash
# shellcheck disable=SC2153 # FILE, REF, CMD and the other colors come from lib/theme.sh

read_list_file() {
	local file="$1"
	[[ -f "$file" ]] || return 0
	grep -vE '^[[:space:]]*(#|$)' "$file"
}

# The entries of a list file without their trailing "# comment", for the files
# where a comment never carries data (requires.txt and integrations.txt do).
read_list_entries() {
	read_list_file "$1" | sed -E 's/[[:space:]]*#.*$//' | grep -vE '^[[:space:]]*$'
	return 0
}

repo_entries() {
	read_list_entries "$WORKSPACE_NOTES_DIR/repos.txt"
}

PATHS_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/engramma/paths"
CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/engramma/config"

# A value of the local configuration: "key = value" lines, # for comments.
config_value() {
	[[ -f "$CONFIG_FILE" ]] || return 0
	sed -nE "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*([^#[:space:]]*).*/\1/p" "$CONFIG_FILE" | tail -n 1
}

# How many repos are cloned or fetched at the same time: "parallel = false" means
# one, otherwise "threads" (3 when missing or not a number).
configured_repo_jobs() {
	local threads
	threads="$(config_value threads)"
	if [[ "$(config_value parallel)" == false ]]; then
		echo 1
	elif [[ "$threads" =~ ^[1-9][0-9]*$ ]]; then
		echo "$threads"
	else
		echo 3
	fi
}
DEFAULT_WORKSPACES_ROOT="$HOME/workspace"

saved_workspace_path() {
	[[ -f "$PATHS_FILE" ]] || return 0
	awk -v name="$1" '$1 == name { print $2; exit }' "$PATHS_FILE"
}

default_workspace_path() {
	local location
	location="$(read_list_entries "$WORKSPACE_NOTES_DIR/location.txt" | head -n 1)"
	echo "$DEFAULT_WORKSPACES_ROOT/${location:-$WORKSPACE_NAME}"
}

# shellcheck disable=SC2034
resolve_workspace_dir() {
	local saved
	saved="$(saved_workspace_path "$WORKSPACE_NAME")"
	SAVED_WORKSPACE_DIR="$saved"

	if [[ -n "$REQUESTED_PATH" ]]; then
		WORKSPACE_DIR="$(realpath -m "$REQUESTED_PATH")"
		WORKSPACE_DIR_SOURCE="scelta con --path"
	elif [[ -n "$saved" ]]; then
		WORKSPACE_DIR="$saved"
		WORKSPACE_DIR_SOURCE="salvata in $PATHS_FILE"
	else
		WORKSPACE_DIR="$(default_workspace_path)"
		WORKSPACE_DIR_SOURCE="predefinita"
	fi
}

remember_workspace_path() {
	[[ -n "$REQUESTED_PATH" && "$WORKSPACE_DIR" != "$SAVED_WORKSPACE_DIR" ]] || return 0

	section "cartella"
	if [[ -n "$SAVED_WORKSPACE_DIR" ]]; then
		warn "prima era $(path "$SAVED_WORKSPACE_DIR"): non viene né spostata né cancellata"
	fi

	case "$MODE" in
		dry) would "salverei $(path "$WORKSPACE_DIR") in $(path "$PATHS_FILE")" ;;
		*)
			if save_workspace_path; then
				ok "$(path "$WORKSPACE_DIR") salvata in $(path "$PATHS_FILE")"
			else
				problem "impossibile salvare $(path "$WORKSPACE_DIR") in $(path "$PATHS_FILE")"
				return 1
			fi
			;;
	esac
}

save_workspace_path() (
	local staging
	lock_config || return 1
	staging="$(mktemp -- "$PATHS_FILE.XXXXXXXX")" || return 1
	trap 'rm -f -- "$staging"' EXIT
	if [[ -e "$PATHS_FILE" ]]; then
		awk -v name="$WORKSPACE_NAME" '$1 != name' "$PATHS_FILE" >"$staging" || return 1
	fi
	printf '%s %s\n' "$WORKSPACE_NAME" "$WORKSPACE_DIR" >>"$staging" &&
		mv -T -- "$staging" "$PATHS_FILE"
)

claude_project_key() {
	printf '%s' "$1" | sed 's#[^A-Za-z0-9]#-#g'
}

claude_memory_dir_for() {
	echo "$CLAUDE_HOME/projects/$(claude_project_key "$1")/memory"
}
