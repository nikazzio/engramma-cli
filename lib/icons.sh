# shellcheck shell=bash
# shellcheck disable=SC2034 # the icons are used by lib/ui.sh

# The symbols of the outcomes, in three sets: nerd (Nerd Font glyphs, codes in
# the Font Awesome range of the font), unicode (ordinary symbols) and ascii.
# ENGRAMMA_ICONS or the line "icons = <set>" of ~/.config/engramma/config picks
# one. Without a choice: unicode in a terminal, ascii in a pipe or a log, where a
# private glyph would be a stray character. Every icon takes one column.

# The set named in the configuration file, empty when there is none.
configured_icons() {
	local file="${XDG_CONFIG_HOME:-$HOME/.config}/engramma/config"
	[[ -f "$file" ]] || return 0
	sed -nE 's/^[[:space:]]*icons[[:space:]]*=[[:space:]]*([a-z]*).*/\1/p' "$file" | tail -n 1
}

load_icons() {
	local set="${ENGRAMMA_ICONS:-}"
	[[ -n "$set" ]] || set="$(configured_icons)"
	case "$set" in
		nerd | unicode | ascii) ;;
		*) if [[ -t 1 ]] && ! $PLAIN; then set=unicode; else set=ascii; fi ;;
	esac
	ICON_SET="$set"
	case "$set" in
		nerd)
			ICON_OK=$'\xef\x80\x8c'   # U+F00C check
			ICON_DONE=$'\xef\x81\xa7' # U+F067 plus
			ICON_INFO=$'\xef\x81\x9a' # U+F05A info
			ICON_DRY=$'\xef\x81\xae'  # U+F06E eye
			ICON_WARN=$'\xef\x81\xb1' # U+F071 warning triangle
			ICON_ERR=$'\xef\x80\x8d'  # U+F00D cross
			ICON_SKIP=$'\xef\x81\xa8' # U+F068 minus
			ICON_FIX=$'\xef\x81\x94'  # U+F054 chevron
			;;
		unicode)
			ICON_OK="✔" ICON_DONE="✚" ICON_INFO="•" ICON_DRY="◇"
			ICON_WARN="▲" ICON_ERR="✖" ICON_SKIP="–" ICON_FIX="↳"
			;;
		*)
			ICON_OK="o" ICON_DONE="+" ICON_INFO="i" ICON_DRY="~"
			ICON_WARN="!" ICON_ERR="x" ICON_SKIP="-" ICON_FIX=">"
			;;
	esac
}
