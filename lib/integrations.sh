# shellcheck shell=bash
# shellcheck disable=SC2153 # FILE, REF, CMD and the other colors come from lib/theme.sh

# Tools that change how the agents work, active only when global/integrations.txt
# names them, one per line with an optional "# how to install it". engramma knows
# how each one shows up in the program, in Claude Code and in Codex; the rest of
# the program skips the work of an integration that is not active.

INTEGRATIONS_FILE="$GLOBAL_DIR/integrations.txt"
KNOWN_INTEGRATIONS=(boost caveman code-review-graph repomix)

integration_enabled() {
	read_list_file "$INTEGRATIONS_FILE" 2>/dev/null | sed 's/#.*//' | awk 'NF { print $1 }' | grep -qxF "$1"
}

# The state of one part of an integration: ok, missing, or none when the part
# does not exist for that integration (or the agent is not installed).
integration_part() {
	local name="$1" part="$2"
	case "$part" in
		program)
			case "$name" in
				boost | code-review-graph) command -v "$name" >/dev/null && echo ok || echo missing ;;
				*) echo none ;;
			esac
			;;
		claude)
			local settings="$CLAUDE_HOME/settings.json"
			case "$name" in
				boost) grep -qs 'boost-hook-claude' "$settings" && echo ok || echo missing ;;
				caveman) grep -qs '"caveman@' "$settings" && echo ok || echo missing ;;
				code-review-graph) grep -qs '"code-review-graph"' "$HOME/.claude.json" && echo ok || echo missing ;;
				repomix) grep -qs '@repomix"' "$settings" && echo ok || echo missing ;;
			esac
			;;
		codex)
			command -v codex >/dev/null || { echo none; return; }
			case "$name" in
				boost) [[ -f "$CODEX_HOME_DIR/BOOST.md" ]] && echo ok || echo missing ;;
				caveman) [[ -d "$CODEX_HOME_DIR/caveman" ]] && echo ok || echo missing ;;
				code-review-graph) grep -qs '^\[mcp_servers\.code-review-graph\]' "$CODEX_CONFIG" && echo ok || echo missing ;;
				repomix) [[ -d "$CODEX_SKILLS_DIR/repomix-explorer" || -d "$CODEX_HOME_DIR/skills/repomix-explorer" ]] && echo ok || echo missing ;;
			esac
			;;
	esac
}

integration_mark() {
	case "$1" in
		ok) printf '%s' "${GREEN}●${RESET}" ;;
		missing) printf '%s' "${RED}○${RESET}" ;;
		*) printf '%s' "${DIM}–${RESET}" ;;
	esac
}

# eng integrations: the active integrations, with the state of the program and of
# each agent, the command to install what is missing, and the ones available.
integrations_command() {
	local name hint part state marks incomplete=0 active=() available=()
	echo ""
	echo " ${REPO}integrazioni degli agenti${RESET}  ${DIM}$(tilde "$INTEGRATIONS_FILE")${RESET}"

	while IFS= read -r name; do
		[[ -n "$name" ]] && active+=("$name")
	done < <(read_list_file "$INTEGRATIONS_FILE" 2>/dev/null | sed 's/#.*//' | awk 'NF { print $1 }')

	if ((${#active[@]} == 0)); then
		echo "   ${DIM}nessuna integrazione attiva${RESET}"
	else
		printf '   %-20s %-10s %-8s %s\n' "" "programma" "claude" "codex"
	fi
	for name in "${active[@]}"; do
		if [[ " ${KNOWN_INTEGRATIONS[*]} " != *" $name "* ]]; then
			printf '   %s%-20s%s %s\n' "$TEXT" "$name" "$RESET" "${RED}sconosciuta${RESET} ${DIM}(conosciute: ${KNOWN_INTEGRATIONS[*]})${RESET}"
			incomplete=$((incomplete + 1))
			continue
		fi
		marks=() state=ok
		for part in program claude codex; do
			marks+=("$(integration_part "$name" "$part")")
			[[ "${marks[-1]}" == missing ]] && state=missing
		done
		printf '   %s%-20s%s %s%9s%s%7s%s\n' "$TEXT" "$name" "$RESET" \
			"$(integration_mark "${marks[0]}")" "" "$(integration_mark "${marks[1]}")" "" "$(integration_mark "${marks[2]}")"
		if [[ "$state" == missing ]]; then
			incomplete=$((incomplete + 1))
			hint="$(read_list_file "$INTEGRATIONS_FILE" | awk -v n="$name" '$1 == n' | head -n 1 | sed -nE 's/^[^#]*#[[:space:]]*//p')"
			echo "     ${CMD}${hint:-vedi docs/agents.md per installarla}${RESET}"
		fi
	done

	for name in "${KNOWN_INTEGRATIONS[@]}"; do
		[[ " ${active[*]} " == *" $name "* ]] || available+=("$name")
	done
	if ((${#available[@]})); then
		local joined="${available[*]}"
		echo ""
		echo " ${DIM}disponibili, non attive: ${joined// /, }${RESET}"
	fi
	echo ""
	echo "   ${GREEN}●${RESET} ${DIM}a posto   ${RESET}${RED}○${RESET} ${DIM}manca   – non previsto o agente non installato${RESET}"
	((incomplete == 0))
}
