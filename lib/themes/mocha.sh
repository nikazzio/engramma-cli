# shellcheck shell=bash
# shellcheck disable=SC2034 # read by lib/theme.sh and the output functions
# Catppuccin Mocha (https://catppuccin.com/palette), truecolor. The brand gradient
# is neon on purpose: it is the only thing on screen not taken from the palette.

THEME_TRUECOLOR=true

# Status
THEME_OK="166;227;161"      # green: already in place
THEME_DONE="148;226;213"    # teal: done in this run
THEME_WARN="249;226;175"    # yellow
THEME_ERROR="243;139;168"   # red
THEME_DRY="137;220;235"     # sky
THEME_INFO="137;180;250"    # blue

# Text
THEME_TEXT="205;214;244"    # text
THEME_MUTED="127;132;156"   # overlay1
THEME_RULE="108;112;134"    # overlay0
THEME_TITLE="180;190;254"   # lavender

# Things named in the messages
THEME_REPO="203;166;247"    # mauve: repo and workspace names
THEME_FILE="250;179;135"    # peach: files, folders, paths
THEME_CMD="148;226;213"     # teal: commands to run
THEME_REF="245;194;231"     # pink: branches, plugins, settings keys, skills

# Neon gradient for the name, one stop per letter.
THEME_BRAND=("255;60;200" "255;90;230" "225;120;255" "180;150;255" "130;180;255" "80;210;255" "40;235;255" "60;255;220")
