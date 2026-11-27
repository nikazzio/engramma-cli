# shellcheck shell=bash

# Select data without evaluating configuration as shell code. This module is
# also used before the workstation modules, which depend on the selected root.
# shellcheck disable=SC2034 # read by bin/sync.sh and lib/standalone.sh
ARCHIVE_ERROR=""

select_archive() {
	local selected="${ENGRAMMA_DATA_DIR:-}" saved
	ARCHIVE_LEGACY=false
	if [[ "${1:-}" == --data-dir ]]; then
		[[ $# -ge 2 && -n "$2" && "$2" != -* ]] || {
			echo "Manca la cartella dopo --data-dir" >&2
			return 1
		}
		selected="$2"
	fi
	if [[ -z "$selected" ]]; then
		saved="${XDG_CONFIG_HOME:-$HOME/.config}/engramma/archive"
		if [[ -f "$saved" ]]; then
			IFS= read -r selected <"$saved" || true
		fi
	fi
	if [[ -z "$selected" && -n "${ENGRAMMA_DIR:-}" ]]; then
		selected="$ENGRAMMA_DIR"
		ARCHIVE_LEGACY=true
	fi
	if [[ -z "$selected" ]]; then
		# Not an error of the command line: the caller shows it and still runs the
		# steps that need no archive.
		ARCHIVE_ERROR="Archivio non configurato: eng init ne crea uno nuovo, eng setup <indirizzo o cartella> ne collega uno esistente"
		ENGRAMMA_DIR=""
		return 2
	fi
	ENGRAMMA_DIR="$(realpath -m -- "$selected")" || return 1
}

validate_archive() {
	local root
	if [[ ! -d "$ENGRAMMA_DIR/workspaces" ]]; then
		ARCHIVE_ERROR="Archivio non valido: $ENGRAMMA_DIR (manca workspaces/)"
		return 1
	fi
	# Preserve the legacy directory-only usage; the separated archive is Git.
	$ARCHIVE_LEGACY && return 0
	root="$(git -C "$ENGRAMMA_DIR" rev-parse --show-toplevel 2>/dev/null)" || root=""
	if [[ -z "$root" || "$(realpath -- "$root")" != "$(realpath -- "$ENGRAMMA_DIR")" ]]; then
		ARCHIVE_ERROR="Archivio non valido: $ENGRAMMA_DIR (serve la radice di un repository Git)"
		return 1
	fi
}

# Lock the archive directory itself. No file is added to the user's repository,
# and alternate spellings of the same directory share the same lock.
lock_archive() {
	local archive_fd
	if ! exec {archive_fd}<"$ENGRAMMA_DIR" || ! flock -x -w 5 "$archive_fd"; then
		echo "Archivio occupato o inaccessibile: $ENGRAMMA_DIR. Riprova tra poco." >&2
		return 1
	fi
}

# The workstation selection and paths are shared even across distinct archives.
lock_config() {
	local config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/engramma" config_fd
	mkdir -p -- "$config_dir" &&
		exec {config_fd}<"$config_dir" &&
		flock -x -w 5 "$config_fd"
}
