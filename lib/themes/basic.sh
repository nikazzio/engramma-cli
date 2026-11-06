# shellcheck shell=bash
# shellcheck disable=SC2034 # read by lib/theme.sh and the output functions
# The 16 ANSI colors, for terminals without truecolor: each value is an SGR code.
# Bright variants (90-97) only: the dark ones are unreadable on a black background.

THEME_TRUECOLOR=false

THEME_OK="92"
THEME_DONE="36"
THEME_WARN="93"
THEME_ERROR="91"
THEME_DRY="96"
THEME_INFO="94"

THEME_TEXT="39"
THEME_MUTED="37"
THEME_RULE="90"
THEME_TITLE="97"

THEME_REPO="95"
THEME_FILE="93"
THEME_CMD="96"
THEME_REF="95"

THEME_BRAND=("1;95" "1;95" "1;94" "1;96")
