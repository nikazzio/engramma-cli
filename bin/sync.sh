#!/usr/bin/env bash
set -uo pipefail

PROGRAM_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
CLAUDE_HOME="${ENGRAMMA_CLAUDE_HOME:-$HOME/.claude}"
LIB_DIR="$PROGRAM_DIR/lib"

# shellcheck source=../lib/archive.sh
source "$LIB_DIR/archive.sh"
for argument in "$@"; do
	if [[ "$argument" == --version ]]; then
		printf 'Engramma %s\n' "$(cat "$PROGRAM_DIR/VERSION")"
		exit 0
	fi
done

HAS_ARCHIVE=true
ARCHIVE_PATH=""
select_archive "$@"
case $? in
	0) ;;
	2) HAS_ARCHIVE=false ;;
	*) exit 2 ;;
esac
EXPLICIT_ARCHIVE=false
if [[ "${1:-}" == --data-dir ]]; then
	EXPLICIT_ARCHIVE=true
	shift 2
fi
if $HAS_ARCHIVE && ! validate_archive; then
	HAS_ARCHIVE=false
	ARCHIVE_PATH="$ENGRAMMA_DIR"
	ENGRAMMA_DIR=""
fi
if [[ "${1:-}" == --print-data-dir ]]; then
	$HAS_ARCHIVE || { echo "$ARCHIVE_ERROR" >&2; exit 1; }
	(($# == 1)) || { echo "Uso: eng --print-data-dir" >&2; exit 2; }
	printf '%s\n' "$ENGRAMMA_DIR"
	exit 0
fi

PLAIN=false
NON_INTERACTIVE=false
for argument in "$@"; do
	case "$argument" in
		--plain) PLAIN=true ;;
		--non-interactive) NON_INTERACTIVE=true ;;
	esac
done

# shellcheck source=../lib/ui.sh
source "$LIB_DIR/ui.sh"
# shellcheck source=../lib/agents.sh
source "$LIB_DIR/agents.sh"
# shellcheck source=../lib/workspace.sh
source "$LIB_DIR/workspace.sh"
# shellcheck source=../lib/links.sh
source "$LIB_DIR/links.sh"
# shellcheck source=../lib/memory.sh
source "$LIB_DIR/memory.sh"
# shellcheck source=../lib/environment.sh
source "$LIB_DIR/environment.sh"
# shellcheck source=../lib/repos.sh
source "$LIB_DIR/repos.sh"
# shellcheck source=../lib/detach.sh
source "$LIB_DIR/detach.sh"
# shellcheck source=../lib/global.sh
source "$LIB_DIR/global.sh"
# shellcheck source=../lib/codex.sh
source "$LIB_DIR/codex.sh"
# shellcheck source=../lib/copilot.sh
source "$LIB_DIR/copilot.sh"
# shellcheck source=../lib/engramma.sh
source "$LIB_DIR/engramma.sh"
# shellcheck source=../lib/commands.sh
source "$LIB_DIR/commands.sh"
# shellcheck source=../lib/standalone.sh
source "$LIB_DIR/standalone.sh"
# shellcheck source=../lib/wizard.sh
source "$LIB_DIR/wizard.sh"
# shellcheck source=../lib/tools.sh
source "$LIB_DIR/tools.sh"
# shellcheck source=../lib/integrations.sh
source "$LIB_DIR/integrations.sh"

# Names a workspace cannot take: eng <name> would run the command instead.
RESERVED_NAMES="check sync setup init list tools integrations agents save new add log detach help session-start global all"


usage() {
	cat <<EOF
eng: tiene note, memoria e configurazione degli agenti in un archivio Git privato
e le collega ai tuoi progetti, su ogni computer.

Uso: eng [--data-dir <archivio>] [comando] [workspace | global] [opzioni]

Comandi
  check [ws | global]      controlla lo stato locale: collegamenti, repo mancanti,
                           modifiche da salvare o da inviare. È il comando di default:
                           eng da solo controlla il computer e i workspace presenti,
                           eng <ws> solo quel workspace, eng global solo il computer
  sync [ws | global]       scarica l'archivio, sistema il computer, clona e aggiorna i repo,
                           poi salva e invia note e memoria dei workspace
                           (senza nome: i workspace già presenti su questo computer;
                           global: solo la configurazione del computer)
  init [cartella]          crea un archivio nuovo (default ~/engramma-dati): Git, primo
                           commit e percorso ricordato. Poi collega un repository privato
  setup [archivio]         primo avvio su un computer nuovo: uguale a sync global. Con
                           l'indirizzo Git o la cartella di un archivio esistente lo
                           collega (un indirizzo viene clonato in ~/engramma-dati)
  save <ws | global>       salva e invia subito le modifiche di un workspace o di global,
                           con un commit dedicato, senza scaricare né toccare i repo
  list [ws]                i workspace dell'archivio, con cartella e repo
  tools [ws | global]      i programmi di mise e di requires.txt: installati e mancanti
  tools install [ws|global]  mise installa i programmi mancanti, alla versione richiesta
  agents                   mostra agenti selezionati e stato della memoria
  integrations             le integrazioni degli agenti attive in global/integrations.txt
                           (boost, caveman, code-review-graph, repomix) e cosa manca
  new <ws> [cartella]      crea un workspace vuoto; cartella sotto ~/workspace (default: il nome)
  add <ws> <url> [branch]  aggiunge un repo al workspace; eng sync lo clona
  log                      mostra il log dell'ultima esecuzione
  detach <ws|global|all>   sostituisce i collegamenti con copie indipendenti;
                           dopo detach all l'archivio si può cancellare

Opzioni
  --data-dir <dir>     prima del comando: usa un altro archivio solo per questa volta
  -h, --help           aiuto generale o del singolo comando
  --version            versione del programma, senza leggere l'archivio
  --refresh            con check: aggiorna lo stato remoto e verifica SSH
  --wizard             con setup: apre la configurazione guidata nel terminale
  --agents <elenco>    con setup: claude, codex, copilot (separati da virgole) o none
  --claude-memory on|off  con setup: abilita o disabilita la sincronizzazione della memoria
  --plain              output statico senza colori
  --non-interactive    evita domande interattive
  -n, --dry-run        mostra cosa farebbe senza farlo (init, sync, setup, detach)
  -v, --verbose        mostra anche i controlli andati bene
  --path <dir>         con sync di un solo workspace: dove stanno i suoi repo su questo
                       computer (salvato in ~/.config/engramma/paths)
  -j, --jobs <n>       con sync: quanti repo clonare o aggiornare insieme
                       (default da ~/.config/engramma/config, altrimenti 3)
  --prune              con sync: cancella senza chiedere i branch conclusi
                       i cui commit sono presenti sul remoto

Uscita: 0 se il comando è riuscito, 1 se c’è un problema, 2 per errori d’uso.

Workspace: $(available_workspaces)
EOF
}

available_workspaces() {
	local dir names=()
	for dir in "$ENGRAMMA_DIR"/workspaces/*/; do
		[[ -d "$dir" ]] && names+=("$(basename "$dir")")
	done
	echo "${names[*]:-nessuno}"
}

is_workspace() {
	[[ "$1" =~ ^[a-z0-9][a-z0-9._-]*$ && -d "$ENGRAMMA_DIR/workspaces/$1" ]]
}

command_help() {
	local syntax example
	case "$1" in
		check) syntax='check [workspace ... | global] [--refresh] [-v]'; example='eng check demo' ;;
		sync) syntax='sync [workspace ... | global] [-n] [-v] [--path <cartella>] [-j <numero>] [--prune]'; example='eng sync demo --dry-run' ;;
		setup) syntax='setup [<archivio> [<destinazione>]] [--agents <elenco>] [--claude-memory on|off] [-n] [-v] oppure setup --wizard [-n]'; example='eng setup --wizard' ;;
		init) syntax='init [<cartella>] [-n]'; example='eng init ~/engramma-dati' ;;
		detach) syntax='detach <workspace | global | all> [-n] [-v]'; example='eng detach all --dry-run' ;;
		list) syntax='list [workspace ...]'; example='eng list demo' ;;
		tools) syntax='tools [install] [workspace ... | global]'; example='eng tools install global' ;;
		agents) syntax='agents'; example='eng agents' ;;
		integrations) syntax='integrations'; example='eng integrations' ;;
		save) syntax='save <workspace | global> [<messaggio>]'; example='eng save demo "Aggiorna gli appunti"' ;;
		new) syntax='new <workspace> [<cartella>]'; example='eng new demo clienti/demo' ;;
		add) syntax='add <workspace> <url Git> [<branch>]'; example='eng add demo git@example.org:team/app.git' ;;
		log) syntax='log'; example='eng log' ;;
		session-start) syntax='session-start'; example='eng session-start' ;;
		*) fail_usage "Comando sconosciuto: $1" ;;
	esac
	printf 'Uso: eng %s\nEsempio: %s\n\nOpzioni comuni: --plain, --non-interactive, --version. Aiuto generale: eng --help\n' "$syntax" "$example"
}

fail_usage() {
	echo "$1" >&2
	if [[ -n "${EXPLICIT_COMMAND:-}" ]]; then
		echo "Aiuto: eng $EXPLICIT_COMMAND --help" >&2
	else
		echo "Aiuto: eng --help" >&2
	fi
	exit 2
}

COMMAND=check
EXPLICIT_COMMAND=""
MODE=check
REQUESTED_WIZARD=false
REQUESTED_AGENTS=""
REQUESTED_CLAUDE_MEMORY=""
REQUESTED_PATH=""
REQUESTED_JOBS=""
PRUNE=false
REFRESH=false
TOOLS_INSTALL=false
TOOLS_GLOBAL=false
WORKSPACES=()
BACKUP_STAMP="$(date +%Y-%m-%d-%H%M%S)"
BACKUP_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/engramma/backup"

while [[ "${1:-}" == --plain || "${1:-}" == --non-interactive ]]; do shift; done
case "${1:-}" in
	help)
		case $# in
			1) usage ;;
			2) command_help "$2" ;;
			*) fail_usage 'Uso: eng help [comando]' ;;
		esac
		exit 0
		;;
	check | sync | setup | init | detach | list | session-start | tools | save | new | add | log | integrations | agents)
		COMMAND="$1"
		EXPLICIT_COMMAND="$1"
		shift
		;;
esac
for argument in "$@"; do
	case "$argument" in
		-h | --help)
			if [[ -n "$EXPLICIT_COMMAND" ]]; then command_help "$EXPLICIT_COMMAND"; else usage; fi
			exit 0
			;;
	esac
done

while [[ $# -gt 0 ]]; do
	case "$1" in
		--plain | --non-interactive) ;;
		-n | --dry-run) MODE=dry ;;
		-v | --verbose)
			case "$COMMAND" in
				check | sync | setup | detach) VERBOSE=true ;;
				*) fail_usage "eng $COMMAND non accetta opzioni: $1" ;;
			esac
			;;
		--refresh) REFRESH=true ;;
		--wizard)
			[[ "$COMMAND" == setup ]] || fail_usage "--wizard vale solo con setup"
			REQUESTED_WIZARD=true
			;;
		--agents)
			[[ "$COMMAND" == setup ]] || fail_usage "--agents vale solo con setup"
			valid_agent_list "${2:-}" || fail_usage "Scegli claude, codex, copilot (separati da virgole) oppure none"
			REQUESTED_AGENTS="$2"
			shift
			;;
		--claude-memory)
			[[ "$COMMAND" == setup ]] || fail_usage "--claude-memory vale solo con setup"
			[[ "${2:-}" =~ ^(on|off)$ ]] || fail_usage "--claude-memory vuole on oppure off"
			REQUESTED_CLAUDE_MEMORY="$2"
			shift
			;;
		--path)
			[[ $# -ge 2 && -n "$2" && "$2" != -* ]] || fail_usage "Manca la cartella dopo --path"
			REQUESTED_PATH="$2"
			shift
			;;
		-j | --jobs)
			[[ $# -ge 2 && "$2" =~ ^[1-9][0-9]*$ ]] || fail_usage "Manca il numero dopo $1 (es. $1 4)"
			REQUESTED_JOBS="$2"
			shift
			;;
		--prune) PRUNE=true ;;
		-*)
			case "$COMMAND" in
				save | new | add | init | log | integrations | agents | session-start)
					fail_usage "eng $COMMAND non accetta opzioni: $1"
					;;
				*) fail_usage "Opzione sconosciuta: $1" ;;
			esac
			;;
		*) WORKSPACES+=("$1") ;;
		esac
	shift
done
use_output_style

case "$COMMAND" in
	sync | setup | detach) [[ "$MODE" == dry ]] || MODE=run ;;
	init) ;;
	*) [[ "$MODE" != dry ]] || fail_usage "--dry-run vale solo con init, sync, setup e detach" ;;
esac
if $REFRESH && [[ "$COMMAND" != check ]]; then
	fail_usage "--refresh vale solo con check"
fi
if [[ -n "$REQUESTED_JOBS" ]] || $PRUNE; then
	[[ "$COMMAND" == sync && "${WORKSPACES[0]:-}" != global ]] || fail_usage "--jobs e --prune valgono solo con sync"
fi
if [[ -n "$REQUESTED_PATH" ]]; then
	[[ "$COMMAND" == sync && ${#WORKSPACES[@]} -eq 1 && "${WORKSPACES[0]}" != global ]] || fail_usage "--path vale solo con sync di un solo workspace"
	[[ ! "$REQUESTED_PATH" =~ [[:space:]] ]] || fail_usage "La cartella non può contenere spazi: '$REQUESTED_PATH'"
fi

if $NON_INTERACTIVE; then export GIT_TERMINAL_PROMPT=0; fi
NETWORK_CHECKS=false
if [[ "$MODE" == run ]] || $REFRESH; then NETWORK_CHECKS=true; fi
if [[ "$MODE" == dry || "$COMMAND" == check ]]; then
	export GIT_OPTIONAL_LOCKS=0 MISE_OFFLINE=1
fi

if [[ "$REQUESTED_CLAUDE_MEMORY" == on && -n "$REQUESTED_AGENTS" ]] &&
	! agent_in_list "$REQUESTED_AGENTS" claude; then
	fail_usage "Per sincronizzare la memoria seleziona anche Claude"
fi

case "$COMMAND" in
	init)
		((${#WORKSPACES[@]} <= 1)) || fail_usage "Uso: eng init [cartella]"
		init_archive "${WORKSPACES[0]:-}"
		exit $?
		;;
	setup)
		((${#WORKSPACES[@]} <= 2)) || fail_usage "Uso: eng setup [<indirizzo o cartella> [destinazione]]"
		if $REQUESTED_WIZARD; then
			$IS_INTERACTIVE || fail_usage "--wizard richiede un terminale interattivo"
			[[ -z "$REQUESTED_AGENTS$REQUESTED_CLAUDE_MEMORY" && ${#WORKSPACES[@]} -eq 0 ]] ||
				fail_usage "Con --wizard scegli archivio e agenti durante la guida"
		fi
		if $REQUESTED_WIZARD || automatic_setup_wizard; then run_setup_wizard; exit $?; fi
		if ((${#WORKSPACES[@]})); then
			attach_archive "${WORKSPACES[@]}"
			exit $?
		fi
		;;
	log | integrations | agents | session-start)
		((${#WORKSPACES[@]} == 0)) || fail_usage "eng $COMMAND non accetta argomenti"
		;;
	save | new | add)
		case "$COMMAND:${#WORKSPACES[@]}" in
			save:1 | save:2 | new:1 | new:2 | add:2 | add:3) ;;
			*) fail_usage "Numero di argomenti non valido per eng $COMMAND" ;;
		esac
		;;
	tools)
		if [[ "${WORKSPACES[0]:-}" == install ]]; then
			TOOLS_INSTALL=true
			WORKSPACES=("${WORKSPACES[@]:1}")
		fi
		;;
	detach)
		((${#WORKSPACES[@]} == 1)) || fail_usage "eng detach vuole un workspace, oppure global o all"
		;;
esac

if [[ "$COMMAND" == log ]]; then show_last_log; exit $?; fi
if ! $HAS_ARCHIVE; then
	if [[ -n "$REQUESTED_AGENTS$REQUESTED_CLAUDE_MEMORY" ]]; then
		say_fail "$ARCHIVE_ERROR"
		exit 1
	fi
	run_without_archive
fi

case "$COMMAND" in
	save | new | add | session-start) lock_archive || exit 1 ;;
	sync | setup | detach) [[ "$MODE" == dry ]] || lock_archive || exit 1 ;;
	check) ! $REFRESH || lock_archive || exit 1 ;;
esac

case "$COMMAND" in
	detach | list | new | add) ;;
	*) load_agent_profile || exit 1 ;;
esac
if [[ -n "$REQUESTED_AGENTS$REQUESTED_CLAUDE_MEMORY" ]]; then resolve_agent_request; fi

case "$COMMAND" in
	agents) agents_command; exit $? ;;
	save | new | add)
		echo "Archivio: $ENGRAMMA_DIR"
		case "$COMMAND" in
			save)
				start_log
				log_line "Engramma · save ${WORKSPACES[0]}"
				save_engramma "${WORKSPACES[@]}"
				save_status=$?
				log_line "Engramma · save · esito $save_status"
				print_memory_inventory
				exit "$save_status"
				;;
			new) new_workspace "${WORKSPACES[@]}" ;;
			add) add_repo "${WORKSPACES[@]}" ;;
		esac
		exit $?
		;;
	integrations) integrations_command; exit $? ;;
esac

# global is the configuration of the computer, named like a workspace.
HEADER="$COMMAND"
for name in "${WORKSPACES[@]}"; do
	[[ "$name" == global ]] || continue
	((${#WORKSPACES[@]} == 1)) || fail_usage "global va da solo: eng $COMMAND global"
	HEADER="$COMMAND global"
	case "$COMMAND" in
		sync | check) COMMAND=setup ;;
		detach) COMMAND=detach-global ;;
		tools) TOOLS_GLOBAL=true ;;
		*) fail_usage "eng $COMMAND non accetta global" ;;
	esac
	WORKSPACES=()
	break
done

if [[ "$COMMAND" == detach && "${WORKSPACES[0]}" == all ]]; then
	COMMAND=detach-all
	WORKSPACES=()
fi

for name in "${WORKSPACES[@]}"; do
	is_workspace "$name" || fail_usage "Workspace sconosciuto: '$name' (ci sono: $(available_workspaces))"
done
REPO_JOBS="${REQUESTED_JOBS:-$(configured_repo_jobs)}"

load_workspace() {
	WORKSPACE_NAME="$1"
	WORKSPACE_NOTES_DIR="$ENGRAMMA_DIR/workspaces/$WORKSPACE_NAME"
	resolve_workspace_dir
}

# Each workspace with its folder and its repos, read from engramma only: no
# network, nothing changed.
list_workspaces() {
	local names=("$@") name entry folder url branch shown where repo_dir mark
	if ((${#names[@]} == 0)); then
		read -ra names <<<"$(available_workspaces)"
	fi
	for name in "${names[@]}"; do
		load_workspace "$name"
		if [[ -d "$WORKSPACE_DIR" ]]; then
			where="$(path "$WORKSPACE_DIR")"
		else
			where="${DIM}$(tilde "$WORKSPACE_DIR") · non su questo computer${RESET}"
		fi
		echo ""
		echo " ${REPO}$name${RESET}  $where"
		local entries=() width=0
		mapfile -t entries < <(repo_entries)
		for entry in "${entries[@]}"; do
			read -r folder _ <<<"$entry"
			((${#folder} > width)) && width=${#folder}
		done
		for entry in "${entries[@]}"; do
			read -r folder url branch <<<"$entry"
			[[ -n "$folder" ]] || continue
			shown="${url#*@}" shown="${shown#*://}" shown="${shown/://}" shown="${shown%.git}"
			repo_dir="$WORKSPACE_DIR/$folder"
			if [[ -d "$repo_dir/.git" ]]; then
				mark="${GREEN}●${RESET}"
			else
				mark="${DIM}○${RESET}"
			fi
			printf '   %s %s%-*s%s  %s%-8s%s %s%s%s\n' "$mark" "$TEXT" "$width" "$folder" "$RESET" \
				"$REF" "${branch:-auto}" "$RESET" "$DIM" "$shown" "$RESET"
		done
	done
	echo ""
	echo "   ${GREEN}●${RESET} ${DIM}clonato su questo computer   ${RESET}${DIM}○ non ancora clonato · auto = develop se esiste, altrimenti main${RESET}"
}

# The workspaces already set up on this computer: their folder exists.
present_workspaces() {
	local notes_dir
	for notes_dir in "$ENGRAMMA_DIR"/workspaces/*/; do
		[[ -d "$notes_dir" ]] || continue
		load_workspace "$(basename "$notes_dir")"
		[[ -d "$WORKSPACE_DIR" ]] && echo "$WORKSPACE_NAME"
	done
	return 0
}

setup_workstation() {
	heading "POSTAZIONE"
	block "engramma" "$(tilde "$ENGRAMMA_DIR")"
	report_engramma
	use_mise_tools
	block "programmi" "mise · global/requires.txt" "programmi"
	ensure_mise
	check_global_commands
	block "configurazione" "global/ · skills/" "file"
	if agent_enabled claude; then link_skills; fi
	link_global
	section "percorsi assoluti"
	check_absolute_paths "$GLOBAL_DIR" "$ENGRAMMA_DIR/skills"
	heading "AGENTI"
	if agent_enabled claude; then
		block "claude code" "memoria: $CLAUDE_MEMORY" "controlli"
		check_selected_agent claude
		check_claude_marketplaces
		check_claude_plugins
	fi
	if ! $EXPLICIT_AGENTS || agent_enabled codex; then
		block "codex" "$(tilde "$CODEX_HOME_DIR") · ~/.agents"
		check_selected_agent codex
		setup_codex
	fi
	if agent_enabled copilot; then
		block "copilot" "$(tilde "$COPILOT_HOME_DIR") · memoria su GitHub"
		check_selected_agent copilot
		setup_copilot
	fi
	if $EXPLICIT_AGENTS && [[ "$ACTIVE_AGENTS" == none ]]; then
		block "agenti" "nessuno selezionato"
		info "Scegli con eng setup --agents claude,codex,copilot"
	fi
	block_end
}

workspace_steps() {
	load_workspace "$1"
	block "$WORKSPACE_NAME" "$(tilde "$WORKSPACE_DIR")"
	check_environment
	link_workspace_notes
	link_memories
	section "percorsi assoluti"
	check_absolute_paths "$WORKSPACE_NOTES_DIR"
	process_repos
	block_end
}

# Workspaces in engramma whose folder is not on this computer yet.
report_absent_workspaces() {
	local notes_dir absent=()
	for notes_dir in "$ENGRAMMA_DIR"/workspaces/*/; do
		[[ -d "$notes_dir" ]] || continue
		load_workspace "$(basename "$notes_dir")"
		[[ -d "$WORKSPACE_DIR" ]] || absent+=("$WORKSPACE_NAME")
	done
	((${#absent[@]})) || return 0
	block "non ancora su questo computer" "" ""
	BLOCK_EXPANDED=true
	local name
	for name in "${absent[@]}"; do
		info "${BOLD}$name${RESET}  ${DIM}→ eng sync $name${RESET}"
	done
	block_end
}

finish() {
	print_summary
	((PROBLEM_COUNT)) && exit 1
	exit 0
}

if [[ "$COMMAND" == list ]]; then
	list_workspaces "${WORKSPACES[@]}"
	exit 0
fi

if [[ "$COMMAND" == tools ]]; then
	tools_command "$TOOLS_INSTALL" "$TOOLS_GLOBAL" "${WORKSPACES[@]}"
	exit $?
fi

[[ "$COMMAND" == session-start ]] || start_log

case "$COMMAND" in
	session-start)
		if agent_enabled claude; then session_start_report; fi
		exit 0
		;;
	detach-all)
		print_header "detach all"
		block "engramma" "comando, skill, configurazione"
		detach_skills
		detach_global
		for notes_dir in "$ENGRAMMA_DIR"/workspaces/*/; do
			[[ -d "$notes_dir" ]] || continue
			load_workspace "$(basename "$notes_dir")"
			block "$WORKSPACE_NAME" "$(tilde "$WORKSPACE_DIR")" "collegamenti"
			detach_workspace
		done
		block "engramma" "comando e scelta dell’archivio"
		if ((PROBLEM_COUNT == 0)) && ! has_other_saved_archive; then
			detach_engramma_command
			((PROBLEM_COUNT)) || forget_archive
		fi
		finish
		;;
	detach-global)
		print_header "detach global"
		block "global" "skill e configurazione"
		detach_skills
		detach_global
		finish
		;;
	detach)
		load_workspace "${WORKSPACES[0]}"
		print_header "detach $WORKSPACE_NAME"
		block "$WORKSPACE_NAME" "$(tilde "$WORKSPACE_DIR")" "collegamenti"
		detach_workspace
		finish
		;;
esac

if [[ -n "$REQUESTED_AGENTS$REQUESTED_CLAUDE_MEMORY" ]]; then
	print_header "$HEADER"
	apply_agent_request || finish
	if [[ "$MODE" == run ]]; then load_ssh_agent; pull_engramma; fi
else
	if [[ "$MODE" == run ]]; then load_ssh_agent; pull_engramma; fi
	print_header "$HEADER"
fi

ALL_WORKSPACES=false
if [[ "$COMMAND" != setup ]] && ((${#WORKSPACES[@]} == 0)); then
	ALL_WORKSPACES=true
	mapfile -t WORKSPACES < <(present_workspaces)
fi

if [[ -n "$REQUESTED_PATH" ]]; then
	load_workspace "${WORKSPACES[0]}"
	remember_workspace_path || finish
fi

# The SSH servers of all the workspaces are probed together, in the background,
# while the workstation is checked.
if $NETWORK_CHECKS; then
	load_ssh_agent
	for name in "${WORKSPACES[@]}"; do
		load_workspace "$name"
		mapfile -t hosts < <(ssh_hosts_of_repos)
		prefetch_ssh "${hosts[@]}"
	done
fi
[[ "$COMMAND" == sync ]] && start_repo_jobs "${WORKSPACES[@]}"

# A check of named workspaces looks at them only; "eng check global" covers the computer.
if [[ "$COMMAND" != check ]] || $ALL_WORKSPACES; then
	setup_workstation
elif $REFRESH; then
	block "archivio" "$(tilde "$ENGRAMMA_DIR")"
	report_engramma_updates
fi
[[ "$COMMAND" == setup ]] && finish

$ALL_WORKSPACES || EXPAND_BLOCKS=true
((${#WORKSPACES[@]})) && heading "WORKSPACE"
for name in "${WORKSPACES[@]}"; do
	workspace_steps "$name"
done
if [[ "$COMMAND" == sync ]]; then
	if [[ "$MODE" == run ]]; then
		send_workspace_updates "${WORKSPACES[@]}"
	else
		preview_memory_transfers "${WORKSPACES[@]}"
	fi
fi
$ALL_WORKSPACES && report_absent_workspaces
finish
