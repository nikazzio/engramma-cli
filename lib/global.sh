# shellcheck shell=bash
# shellcheck disable=SC2153 # FILE, REF, CMD and the other colors come from lib/theme.sh

GLOBAL_DIR="$ENGRAMMA_DIR/global"
GLOBAL_LINKS_FILE="$GLOBAL_DIR/links.txt"
GLOBAL_REQUIRES_FILE="$GLOBAL_DIR/requires.txt"

has_global_config() {
	[[ -f "$GLOBAL_LINKS_FILE" ]]
}

# Expands only the placeholders documented in the README, never arbitrary shell.
expand_global_destination() {
	local destination="$1" config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
	local remaining="${destination//\$\{HOME\}/}"
	remaining="${remaining//\$\{CLAUDE_HOME\}/}"
	remaining="${remaining//\$\{XDG_CONFIG_HOME\}/}"
	[[ "$remaining" != *'$'* ]] || return 1

	destination="${destination//\$\{CLAUDE_HOME\}/$CLAUDE_HOME}"
	destination="${destination//\$\{XDG_CONFIG_HOME\}/$config_home}"
	echo "${destination//\$\{HOME\}/$HOME}"
}

global_entries() {
	read_list_entries "$GLOBAL_LINKS_FILE"
}

link_global() {
	has_global_config || return 0
	section "file globali"

	local source destination how
	while read -r source destination how _; do
		[[ -n "$destination" ]] || continue
		if ! destination="$(expand_global_destination "$destination")"; then
			problem "${FILE}$source${RESET}: segnaposto non ammesso nella destinazione ${DIM}(solo \${HOME}, \${CLAUDE_HOME}, \${XDG_CONFIG_HOME})${RESET}"
			continue
		fi
		if [[ ! -f "$GLOBAL_DIR/$source" ]]; then
			problem "${FILE}$source${RESET}: elencato in global/links.txt ma assente in global/"
		elif [[ "$how" == unisci ]]; then
			merge_global_file "$source" "$destination"
		else
			ensure_global_link "$source" "$destination"
		fi
	done < <(global_entries)
	check_claude_hooks
}

ensure_global_link() {
	local name="$1" link="$2"
	local target="$GLOBAL_DIR/$name"

	if [[ -L "$link" ]]; then
		if [[ "$(readlink "$link")" == "$target" ]]; then
			fine "${FILE}$name${RESET} → symlink ok"
		else
			problem "${FILE}$name${RESET}: symlink verso $(path "$(readlink "$link")"), non verso engramma: non lo tocco"
		fi
		return
	fi

	if [[ ! -e "$link" ]]; then
		link_global_file "$name" "$target" "$link" "symlink"
	elif cmp -s "$target" "$link"; then
		link_global_file "$name" "$target" "$link" "copia identica → symlink"
	else
		resolve_global_difference "$name" "$target" "$link"
	fi
}

link_global_file() {
	local name="$1" target="$2" link="$3" dry_message="$4"
	case "$MODE" in
		dry) would "${FILE}$name${RESET}: $dry_message ${DIM}($(path "$link"))${RESET}" ;;
		check) problem "${FILE}$name${RESET}: symlink mancante ${DIM}($(path "$link"))${RESET}" ;;
		*)
			mkdir -p "$(dirname "$link")"
			ln -sfn "$target" "$link"
			ok "${FILE}$name${RESET} → symlink creato ${DIM}($(path "$link"))${RESET}"
			;;
	esac
}

# A program replaced the link with a file of its own (boost does it when it
# installs): in a terminal engramma asks which copy to keep, otherwise it says so.
resolve_global_difference() {
	local name="$1" target="$2" link="$3" answer=""

	problem "${FILE}$name${RESET}: un programma ha sostituito il symlink con un file diverso ${DIM}($(path "$link"))${RESET}"
	if [[ "$MODE" == run ]] && $IS_INTERACTIVE; then
		while true; do
			ask "tengo [c] il file del computer (copiato in engramma) · [e] quello di engramma (backup del locale) · [d] diff · [s] salto?"
			answer="$ASK_ANSWER"
			[[ "$answer" == d ]] || break
			local line
			while IFS= read -r line; do
				put "     $line"
			done < <(diff -u --label "engramma/$name" --label "$(tilde "$link")" "$target" "$link")
		done
	fi

	case "$answer" in
		c)
			if ! cp "$link" "$target" 2>/dev/null; then
				problem "${FILE}$name${RESET}: copia in engramma non riuscita, file del computer lasciato com'è ${DIM}($(path "$link"))${RESET}"
				return
			fi
			ok "${FILE}$name${RESET}: file del computer copiato in engramma"
			;;
		e)
			local backup="$BACKUP_DIR/global/$BACKUP_STAMP/$name"
			if ! { mkdir -p "$(dirname "$backup")" && cp -a "$link" "$backup"; } 2>/dev/null; then
				problem "${FILE}$name${RESET}: backup non riuscito, file del computer lasciato com'è ${DIM}($(path "$link"))${RESET}"
				return
			fi
			ok "${FILE}$name${RESET}: tenuto engramma, backup del locale in $(path "$backup")"
			;;
		*)
			next_step 30 "${CMD}eng setup${RESET} in un terminale interattivo: diff di $name e scelta della copia da tenere"
			return
			;;
	esac
	PROBLEM_COUNT=$((PROBLEM_COUNT - 1))
	rm "$link"
	link_global_file "$name" "$target" "$link" ""
}

ENGRAMMA_STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/engramma"

# A settings file that its program rewrites at every change (Claude Code does it
# with settings.json) cannot stay a link: engramma keeps the shared copy and
# merges it with the file of the computer, in both directions (lib/json_merge.py).
merge_global_file() {
	local name="$1" destination="$2"
	local target="$GLOBAL_DIR/$name" base="$ENGRAMMA_STATE_DIR/global/$name"

	if [[ -z "$PYTHON" ]]; then
		problem "${FILE}$name${RESET}: merge impossibile senza python3 ${DIM}(sudo apt install python3)${RESET}"
		return
	fi

	if [[ -L "$destination" ]]; then
		if [[ "$(readlink "$destination")" != "$target" ]]; then
			problem "${FILE}$name${RESET}: symlink verso $(path "$(readlink "$destination")"), non verso engramma: non lo tocco"
			return
		fi
		case "$MODE" in
			dry) would "${FILE}$name${RESET}: symlink → copia con merge a 3 vie ${DIM}($(path "$destination"))${RESET}" ;;
			check) problem "${FILE}$name${RESET} è ancora un symlink: Claude Code lo riscrive e lo spezza ${DIM}(eng setup passa al merge a 3 vie)${RESET}" ;;
			*)
				rm "$destination"
				cp "$target" "$destination"
				mkdir -p "$(dirname "$base")"
				cp "$target" "$base"
				ok "${FILE}$name${RESET}: symlink → copia con merge a 3 vie ${DIM}($(path "$destination"))${RESET}"
				;;
		esac
		return
	fi

	local merge_mode=dry choices=() conflicts=()
	[[ "$MODE" == run ]] && merge_mode=run
	mkdir -p "$(dirname "$base")"
	local kind path detail
	while IFS=$'\t' read -r kind path detail; do
		[[ "$kind" == conflict ]] && conflicts+=("$path"$'\t'"$detail")
	done < <("$PYTHON" "$LIB_DIR/json_merge.py" "$target" "$destination" "$base" dry)

	if ((${#conflicts[@]})) && [[ "$MODE" == run ]] && $IS_INTERACTIVE; then
		local conflict key answer
		for conflict in "${conflicts[@]}"; do
			key="${conflict%%$'\t'*}"
			warn "${FILE}$name${RESET} ${REF}$key${RESET}: modificato su entrambi i lati ${DIM}${conflict#*$'\t'}${RESET}"
			ask "tengo [c] computer · [e] engramma · [s] salto?"
			answer="$ASK_ANSWER"
			# By key, not by position: the file may change while the user answers.
			[[ "$answer" == c ]] && choices+=(--choose "$key=computer")
			[[ "$answer" == e ]] && choices+=(--choose "$key=engramma")
		done
	fi

	local changes=0
	while IFS=$'\t' read -r kind path detail; do
		changes=$((changes + 1))
		case "$kind:$MODE" in
			invalid:*) problem "${FILE}$name${RESET}: JSON non valido, merge saltato ${DIM}($detail)${RESET}" ;;
			conflict:*)
				problem "${FILE}$name${RESET} ${REF}$path${RESET}: conflitto, modificato su entrambi i lati$($VERBOSE && echo " ${DIM}$detail${RESET}")"
				fix_with 30 "${CMD}eng setup${RESET} in un terminale interattivo: risolvi i conflitti di $name"
				;;
			applied:run) ok "${FILE}$name${RESET} ${REF}$path${RESET} ← engramma ${DIM}$detail${RESET}" ;;
			adopted:run) ok "${FILE}$name${RESET} ${REF}$path${RESET} → engramma ${DIM}$detail${RESET}" ;;
			applied:dry) would "${FILE}$name${RESET} ${REF}$path${RESET} ← engramma ${DIM}$detail${RESET}" ;;
			adopted:dry) would "${FILE}$name${RESET} ${REF}$path${RESET} → engramma ${DIM}$detail${RESET}" ;;
			applied:*) problem "${FILE}$name${RESET} ${REF}$path${RESET} ← engramma, da applicare ${DIM}$detail${RESET}" ;;
			adopted:*) problem "${FILE}$name${RESET} ${REF}$path${RESET} → engramma, da adottare ${DIM}$detail${RESET}" ;;
		esac
	done < <("$PYTHON" "$LIB_DIR/json_merge.py" "$target" "$destination" "$base" "$merge_mode" "${choices[@]}")
	((changes)) || fine "${FILE}$name${RESET}: merge a 3 vie, nessuna differenza"
}

# Makes the tools installed with mise visible even when the shell running the
# script has not activated mise (for example a command launched by Claude Code).
# ENGRAMMA_NO_MISE skips it where the tools are already on PATH (the tests).
use_mise_tools() {
	[[ -z "${ENGRAMMA_NO_MISE:-}" ]] || return 0
	local mise mise_path
	mise="$(command -v mise)"
	[[ -z "$mise" && -x "$HOME/.local/bin/mise" ]] && mise="$HOME/.local/bin/mise"
	[[ -n "$mise" ]] || return 0
	mise_path="$(cd "$HOME" && "$mise" env -s bash 2>/dev/null | sed -nE "s/^export PATH='(.*)'$/\1/p")"
	[[ -n "$mise_path" ]] && PATH="$mise_path"
	return 0
}

global_required_commands() {
	read_list_file "$GLOBAL_REQUIRES_FILE" | sed 's/#.*//' | awk '{ print $1 }'
}

is_global_requirement() {
	global_required_commands | grep -qxF "$1"
}

global_requirement_hint() {
	read_list_file "$GLOBAL_REQUIRES_FILE" | awk -v command="$1" '$1 == command' | head -n 1 |
		sed -nE 's/^[^#]*#[[:space:]]*//p'
}

check_global_commands() {
	[[ -f "$GLOBAL_REQUIRES_FILE" ]] || return 0

	# Missing commands grouped by how to install them, in the order of requires.txt.
	MISSING_HINTS=()
	MISSING_COMMANDS=()

	local line command optional hint
	while IFS= read -r line; do
		hint=""
		[[ "$line" == *'#'* ]] && hint="$(echo "${line#*#}" | sed -E 's/^[[:space:]]+//')"
		read -r command optional _ <<<"${line%%#*}"
		[[ -n "$command" ]] || continue
		report_global_command "$command" "$optional" "$hint"
	done < <(read_list_file "$GLOBAL_REQUIRES_FILE")

	local index
	for index in "${!MISSING_HINTS[@]}"; do
		if [[ -n "${MISSING_HINTS[index]}" ]]; then
			next_step 10 "${CMD}${MISSING_HINTS[index]}${RESET} ${DIM}(installa ${MISSING_COMMANDS[index]})${RESET}"
		else
			next_step 10 "installa ${MISSING_COMMANDS[index]} ${DIM}(global/requires.txt non dice come)${RESET}"
		fi
	done

	check_zoxide_init
	check_code_graph_servers
}

report_global_command() {
	local command="$1" optional="$2" hint="$3" how=""
	[[ -n "$hint" ]] && how=" ${DIM}($hint)${RESET}"

	if command -v "$command" >/dev/null; then
		fine "${REF}$command${RESET}"
		report_global_copies "$command" "$hint"
	elif [[ "$optional" == facoltativo ]]; then
		fine "${REF}$command${RESET} assente, facoltativo$how"
	else
		problem "${REF}$command${RESET} non installato$how"
		remember_missing_command "$command" "$hint"
	fi
}

remember_missing_command() {
	local command="$1" hint="$2" index
	for index in "${!MISSING_HINTS[@]}"; do
		if [[ "${MISSING_HINTS[index]}" == "$hint" ]]; then
			MISSING_COMMANDS[index]+=", $command"
			return
		fi
	done
	MISSING_HINTS+=("$hint")
	MISSING_COMMANDS+=("$command")
}

# Debian and Ubuntu install some programs under another name (the fd-find package
# gives fdfind): that file is a copy of the same program.
debian_command_name() {
	[[ "$1" == fd ]] && echo fdfind
	return 0
}

# Lists the distinct copies of a command on PATH. mise shims only redirect to the
# installed version, so they are not counted as copies.
command_copies() {
	local debian_name
	debian_name="$(debian_command_name "$1")"
	type -ap "$1" ${debian_name:+"$debian_name"} | grep -v '/shims/' | while read -r path; do
		realpath "$path"
	done | awk '!seen[$0]++'
}

# The copy to keep is the one installed the way requires.txt says: with mise when
# the hint names mise, otherwise the one that runs now.
copy_to_keep() {
	local copies="$1" hint="$2" keep=""
	[[ "$hint" == *mise* ]] && keep="$(grep -m 1 '/mise/installs/' <<<"$copies")"
	echo "${keep:-$(head -n 1 <<<"$copies")}"
}

report_global_copies() {
	local command="$1" hint="$2" copies keep path
	copies="$(command_copies "$command")"
	(($(wc -l <<<"$copies") > 1)) || return 0
	keep="$(copy_to_keep "$copies" "$hint")"

	if [[ "$keep" == "$(head -n 1 <<<"$copies")" ]]; then
		warn "${REF}$command${RESET}: $(wc -l <<<"$copies") installazioni trovate; quella prevista è la prima rilevata"
	else
		problem "${REF}$command${RESET}: $(wc -l <<<"$copies") installazioni trovate; quella prevista non è la prima rilevata"
	fi
	while read -r path; do
		if [[ "$path" == "$keep" ]]; then
			info "${DIM}$(path "$path")${RESET} ${GREEN}copia prevista${RESET}"
		else
			info "${DIM}$(path "$path")${RESET} ${YELLOW}altra copia${RESET}"
			next_step 40 "facoltativo, rimuovi la copia aggiuntiva di $command: $(removal_command "$path")"
			suggest_credential_fix "$command" "$path"
		fi
	done <<<"$copies"
}

# How to remove a copy, from the place it was installed in.
removal_command() {
	local path="$1" package prefix
	case "$path" in
		"$HOME"/.nvm/*)
			echo "${CMD}rm -rf ~/.nvm${RESET} ${DIM}(tutto nvm, con le sue node e i pacchetti installati lì; togli anche le sue righe dalla configurazione della shell, se ci sono)${RESET}"
			;;
		*/lib/node_modules/*)
			prefix="${path%%/lib/node_modules/*}"
			package="${path#*/lib/node_modules/}"
			if [[ "$package" == @* ]]; then
				package="$(cut -d/ -f1-2 <<<"$package")"
			else
				package="${package%%/*}"
			fi
			echo "${CMD}$(tilde "$prefix")/bin/npm uninstall -g $package${RESET}"
			;;
		*/mise/installs/npm-*)
			package="${path#*/mise/installs/npm-}"
			package="npm:${package%%/*}"
			echo "${CMD}mise unuse -g $package && mise uninstall --all $package${RESET}"
			;;
		*/mise/installs/*)
			package="${path#*/mise/installs/}"
			package="${package%%/*}"
			echo "${CMD}mise unuse -g $package && mise uninstall --all $package${RESET}"
			;;
		/usr/* | /bin/* | /sbin/* | /opt/*)
			package="$(system_package_of "$path")"
			if [[ -n "$package" ]]; then
				echo "${CMD}sudo apt remove $package${RESET}"
			else
				echo "togli ${CMD}$path${RESET} con lo strumento che l'ha installato"
			fi
			;;
		"$HOME"/*)
			echo "${CMD}rm $(tilde "$path")${RESET}"
			;;
		*)
			echo "togli ${CMD}$path${RESET} con lo strumento che l'ha installato"
			;;
	esac
}

system_package_of() {
	command -v dpkg >/dev/null || return 0
	{ dpkg -S "$1" 2>/dev/null || dpkg -S "${1#/usr}" 2>/dev/null; } | head -n 1 | cut -d: -f1
}

# git can call a copy by its full path to log in (for example gh): after removing
# that copy, git must call the one that stays.
suggest_credential_fix() {
	local command="$1" path="$2" key value
	while read -r key value; do
		[[ -n "$key" && "$value" == *"$path"* ]] || continue
		next_step 41 "${CMD}git config --global --replace-all $key '${value//$path/$command}' '$path'${RESET} ${DIM}(il credential helper deve puntare al $command che resta)${RESET}"
	done < <(git config --global --get-regexp '^credential\..*helper$' 2>/dev/null)
}

# The rc file of the interactive shell, empty for a shell engramma does not know.
interactive_rc_file() {
	case "$(basename "${SHELL:-bash}")" in
		zsh) echo "$HOME/.zshrc" ;;
		bash) echo "$HOME/.bashrc" ;;
	esac
}

# Login shells get mise from shell/zprofile, interactive ones need it in their rc file.
check_mise_activation() {
	local shell_name rc
	shell_name="$(basename "${SHELL:-bash}")"
	rc="$(interactive_rc_file)"
	[[ -n "$rc" ]] || return 0

	if grep -qs 'mise activate' "$rc"; then
		fine "mise activate in $(path "$rc")"
	else
		problem "mise non attivato in $(path "$rc"): la shell potrebbe non usare la versione richiesta dal progetto"
		fix_with 20 "${CMD}echo 'eval \"\$(~/.local/bin/mise activate $shell_name)\"' >> $(tilde "$rc")${RESET}, poi apri un terminale nuovo"
	fi
}

# The z command of zoxide exists only once its init line runs in the interactive shell.
check_zoxide_init() {
	is_global_requirement zoxide && command -v zoxide >/dev/null || return 0
	local shell_name rc
	shell_name="$(basename "${SHELL:-bash}")"
	rc="$(interactive_rc_file)"
	[[ -n "$rc" ]] || return 0

	if grep -qs 'zoxide init' "$rc"; then
		fine "zoxide init in $(path "$rc")"
	else
		problem "zoxide non attivato in $(path "$rc"): il comando z per cambiare cartella non è disponibile"
		fix_with 21 "${CMD}echo 'eval \"\$(zoxide init $shell_name)\"' >> $(tilde "$rc")${RESET}, poi apri un terminale nuovo"
	fi
}

# code-review-graph answers Claude Code through an MCP server registered in the
# configuration of this computer (not linked: it holds machine data).
check_code_graph_servers() {
	integration_enabled code-review-graph && command -v code-review-graph >/dev/null || return 0
	if grep -qs '"code-review-graph"' "$HOME/.claude.json"; then
		fine "MCP code-review-graph registrato in Claude Code"
	else
		problem "MCP code-review-graph non registrato in Claude Code"
		# shellcheck disable=SC2088 # shown to the user, who runs it in a shell
		fix_with 50 "${CMD}claude mcp add -s user code-review-graph -- ~/.local/share/mise/shims/code-review-graph serve --auto-watch${RESET}"
	fi
}

# Claude Code installs the plugins of its settings at the start of a session;
# engramma installs them at once and shows the errors Claude Code reports.
check_claude_plugins() {
	is_global_requirement claude && command -v claude >/dev/null && [[ -n "$PYTHON" ]] || return 0
	[[ -f "$CLAUDE_HOME/settings.json" ]] || return 0

	local kind plugin detail
	while IFS=$'\t' read -r kind plugin detail; do
		case "$kind:$MODE" in
			missing:dry) would "claude plugin install $plugin" ;;
			missing:check) problem "${REF}$plugin${RESET}: abilitato in settings.json, non installato ${DIM}(eng setup lo installa)${RESET}" ;;
			missing:run) install_claude_plugin "$plugin" ;;
			error:*) problem "${REF}$plugin${RESET}: ${DIM}$detail${RESET}" ;;
			fine:*) fine "${REF}$plugin${RESET}" ;;
		esac
	done < <(timeout 60 claude plugin list --json 2>/dev/null </dev/null | "$PYTHON" -c '
import json, sys
settings = json.load(open(sys.argv[1], encoding="utf-8"))
try:
    installed = {item["id"]: item for item in json.load(sys.stdin)}
except ValueError:
    installed = {}
for plugin, enabled in settings.get("enabledPlugins", {}).items():
    if enabled is not True:
        continue
    item = installed.get(plugin)
    if item is None:
        print(f"missing\t{plugin}\t")
    elif item.get("errors"):
        first = item["errors"][0] if isinstance(item["errors"], list) else item["errors"]
        print("error", plugin, first.get("message", first) if isinstance(first, dict) else first, sep="\t")
    else:
        print(f"fine\t{plugin}\t")
' "$CLAUDE_HOME/settings.json")
}

install_claude_plugin() {
	local plugin="$1" output
	add_claude_marketplace "${plugin#*@}" || return 0
	if output="$(GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ConnectTimeout=10" timeout 300 claude plugin install "$plugin" 2>&1 </dev/null)"; then
		log_output "$output"
		ok "${REF}$plugin${RESET} installato ${DIM}(attivo con /reload-plugins o alla prossima sessione)${RESET}"
	else
		log_output "$output"
		problem "claude plugin install $plugin fallito: ${DIM}$(grep -v '^[[:space:]]*$' <<<"$output" | tail -n 1)${RESET}"
		ssh_agent_has_keys || next_step 15 "carica la chiave nell'agent SSH: apri un terminale (keychain chiede la passphrase), poi rilancia"
	fi
}

# The marketplaces declared in settings.json: registered in Claude Code, and with
# their automatic update (off by default for any marketplace not by Anthropic).
check_claude_marketplaces() {
	is_global_requirement claude && command -v claude >/dev/null && [[ -n "$PYTHON" ]] || return 0
	[[ -f "$CLAUDE_HOME/settings.json" ]] || return 0
	local registered name auto
	registered="$(timeout 60 claude plugin marketplace list --json 2>/dev/null </dev/null |
		"$PYTHON" -c 'import json, sys; print(" ".join(m.get("name", "") for m in json.load(sys.stdin)))' 2>/dev/null)"
	while IFS=$'\t' read -r name auto; do
		[[ -n "$name" ]] || continue
		if [[ " $registered " != *" $name "* ]]; then
			case "$MODE" in
				dry) would "marketplace ${REF}$name${RESET}: lo registrerei in Claude Code" ;;
				check) problem "marketplace ${REF}$name${RESET} dichiarato in settings.json ma non registrato in Claude Code ${DIM}(eng setup lo registra)${RESET}" ;;
				*) add_claude_marketplace "$name" ;;
			esac
		elif [[ "$auto" == true ]]; then
			fine "marketplace ${REF}$name${RESET} · aggiornamento automatico"
		else
			info "marketplace ${REF}$name${RESET}: aggiornamento automatico spento ${DIM}(si aggiorna solo con /plugin marketplace update $name)${RESET}"
		fi
	done < <("$PYTHON" -c '
import json, sys
for name, entry in json.load(open(sys.argv[1], encoding="utf-8")).get("extraKnownMarketplaces", {}).items():
    print(name, "true" if entry.get("autoUpdate") is True else "false", sep="\t")
' "$CLAUDE_HOME/settings.json")
}

# Claude Code registers the marketplaces of its settings only when a session starts,
# so plugin install does not find a plugin of a marketplace added since. `marketplace
# add` also rewrites the settings entry (autoUpdate is lost): the declared one is put back.
add_claude_marketplace() {
	local name="$1" source entry output
	timeout 60 claude plugin marketplace list --json 2>/dev/null </dev/null |
		"$PYTHON" -c 'import json, sys; sys.exit(0 if any(m.get("name") == sys.argv[1] for m in json.load(sys.stdin)) else 1)' "$name" &&
		return 0
	source="$("$PYTHON" -c '
import json, sys
source = json.load(open(sys.argv[1], encoding="utf-8")).get("extraKnownMarketplaces", {}).get(sys.argv[2], {}).get("source", {})
print(source.get("url") or source.get("repo") or source.get("path") or "")
' "$CLAUDE_HOME/settings.json" "$name")"
	[[ -n "$source" ]] || return 0
	entry="$("$PYTHON" -c 'import json, sys; print(json.dumps(json.load(open(sys.argv[1], encoding="utf-8"))["extraKnownMarketplaces"][sys.argv[2]]))' "$CLAUDE_HOME/settings.json" "$name")"
	if output="$(GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ConnectTimeout=10" timeout 300 claude plugin marketplace add "$source" 2>&1 </dev/null)"; then
		log_output "$output"
		ok "marketplace ${REF}$name${RESET} registrato in Claude Code"
		restore_claude_marketplace_entry "$name" "$entry"
	else
		log_output "$output"
		problem "claude plugin marketplace add $source fallito: ${DIM}$(grep -v '^[[:space:]]*$' <<<"$output" | tail -n 1)${RESET}"
		ssh_agent_has_keys || next_step 15 "carica la chiave nell'agent SSH: apri un terminale (keychain chiede la passphrase), poi rilancia"
		return 1
	fi
}

restore_claude_marketplace_entry() {
	"$PYTHON" -c '
import json, sys
settings_path, name, declared = sys.argv[1], sys.argv[2], json.loads(sys.argv[3])
settings = json.load(open(settings_path, encoding="utf-8"))
if settings.get("extraKnownMarketplaces", {}).get(name) == declared:
    sys.exit(0)
settings.setdefault("extraKnownMarketplaces", {})[name] = declared
with open(settings_path, "w", encoding="utf-8") as output:
    json.dump(settings, output, ensure_ascii=False, indent=2)
    output.write("\n")
' "$CLAUDE_HOME/settings.json" "$1" "$2"
}

# Claude Code runs the hooks of its settings at every event: a script that does not
# exist makes each of them fail.
check_claude_hooks() {
	local path owner
	while read -r path; do
		[[ -n "$path" && ! -e "$path" ]] || continue
		owner="$(hook_owner "$path")"
		if [[ -z "$owner" ]]; then
			problem "hook di Claude Code verso $(path "$path"): file inesistente, ogni evento darà errore"
			fix_with 35 "$(path "$path") mancante: installa ciò che lo fornisce, oppure togli l'hook con ${CMD}/hooks${RESET} in Claude Code"
		elif command -v "$owner" >/dev/null; then
			problem "hook di Claude Code verso $(path "$path"): file inesistente, lo installa $owner"
			fix_with 35 "reinstalla gli hook di $owner: ${CMD}$(global_requirement_hint "$owner")${RESET}"
		else
			problem "hook di Claude Code verso $(path "$path"): file inesistente, arriva con $owner"
		fi
	done < <(claude_settings_files | while read -r settings; do claude_hook_paths "$settings"; done | sort -u)
}

# The settings Claude Code reads now, and the ones engramma links in their place.
claude_settings_files() {
	[[ -f "$CLAUDE_HOME/settings.json" ]] && echo "$CLAUDE_HOME/settings.json"
	# shellcheck disable=SC2016 # the placeholder is compared as written in links.txt
	global_source_for '${CLAUDE_HOME}/settings.json'
}

# Paths under the home folder named by the commands of the settings, written as
# the home path, ~ or $HOME.
claude_hook_paths() {
	grep '"command"' "$1" | grep -oE "(\\\$HOME|~|$HOME)/[^\"' :\\\\]+" |
		sed -E "s#^(\\\$HOME|~)#$HOME#"
}

# The program of requires.txt that a path belongs to: a file named after it
# (boost-hook-claude.sh) or a folder with its name (mise/shims).
hook_owner() {
	local name folder command
	name="$(basename "$1")"
	folder="/$(dirname "${1#"$HOME"/}")/"
	while read -r command; do
		if [[ "$name" == "$command"[-_.]* || "$folder" == */"$command"/* ]]; then
			echo "$command"
			return
		fi
	done < <(global_required_commands)
}

detach_global() {
	has_global_config || return 0
	section "file globali"

	local source destination
	while read -r source destination _; do
		destination="$(expand_global_destination "$destination")" || continue
		detach_link "$destination" "$source"
	done < <(global_entries)
}
