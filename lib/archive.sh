# shellcheck shell=bash

# Select data without evaluating configuration as shell code. This module is
# also used before the workstation modules, which depend on the selected root.
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
		echo "Archivio non configurato: usa eng --data-dir <cartella> oppure salva il percorso in ~/.config/engramma/archive" >&2
		return 1
	fi
	ENGRAMMA_DIR="$(realpath -m -- "$selected")" || return 1
}

validate_archive() {
	local root
	if [[ ! -d "$ENGRAMMA_DIR/workspaces" ]]; then
		echo "Archivio non valido: $ENGRAMMA_DIR (manca workspaces/)" >&2
		return 1
	fi
	# Preserve the legacy directory-only usage; the separated archive is Git.
	$ARCHIVE_LEGACY && return 0
	root="$(git -C "$ENGRAMMA_DIR" rev-parse --show-toplevel 2>/dev/null)" || root=""
	if [[ -z "$root" || "$(realpath -- "$root")" != "$(realpath -- "$ENGRAMMA_DIR")" ]]; then
		echo "Archivio non valido: $ENGRAMMA_DIR (serve la radice di un repository Git)" >&2
		return 1
	fi
}
