#!/usr/bin/env bash
set -uo pipefail

PROGRAM_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
CLAUDE_HOME="${ENGRAMMA_CLAUDE_HOME:-$HOME/.claude}"
LIB_DIR="$PROGRAM_DIR/lib"

# shellcheck source=../lib/archive.sh
source "$LIB_DIR/archive.sh"
case "${1:-}" in
	--version)
		printf 'Engramma %s\n' "$(cat "$PROGRAM_DIR/VERSION")"
		exit 0
		;;
	-h | --help | help) ENGRAMMA_DIR="" ;;
	*)
		select_archive "$@" || exit 1
		if [[ "${1:-}" == --data-dir ]]; then shift 2; fi
		case "${1:-}" in
			-h | --help | help) ;;
			*) validate_archive || exit 1 ;;
		esac
		if [[ "${1:-}" == --print-data-dir ]]; then
			printf '%s\n' "$ENGRAMMA_DIR"
			exit 0
		fi
		;;
esac

# shellcheck source=../lib/ui.sh
source "$LIB_DIR/ui.sh"
# shellcheck source=../lib/workspace.sh
source "$LIB_DIR/workspace.sh"
# shellcheck source=../lib/links.sh
source "$LIB_DIR/links.sh"
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
# shellcheck source=../lib/engramma.sh
source "$LIB_DIR/engramma.sh"
# shellcheck source=../lib/commands.sh
source "$LIB_DIR/commands.sh"
# shellcheck source=../lib/tools.sh
source "$LIB_DIR/tools.sh"
# shellcheck source=../lib/integrations.sh
source "$LIB_DIR/integrations.sh"

# Names a workspace cannot take: eng <name> would run the command instead.
RESERVED_NAMES="check sync setup list tools integrations save new add log detach help session-start global all"


usage() {
	cat <<EOF
eng: tiene note, memoria e configurazione degli agenti in un archivio Git privato
e le collega ai tuoi progetti, su ogni computer.

Uso: eng [--data-dir <archivio>] [comando] [workspace | global] [opzioni]

Comandi
  check [ws | global]      controlla senza cambiare niente: collegamenti, repo mancanti,
                           modifiche da salvare o da inviare. È il comando di default:
                           eng da solo controlla il computer e i workspace presenti,
                           eng <ws> solo quel workspace, eng global solo il computer
  sync [ws | global]       scarica l'archivio, sistema il computer, clona e aggiorna i repo,
                           poi salva e invia note e memoria dei workspace
                           (senza nome: i workspace già presenti su questo computer;
                           global: solo la configurazione del computer)
  setup                    primo avvio su un computer nuovo: uguale a sync global
  save <ws | global>       salva e invia subito le modifiche di un workspace o di global,
                           con un commit dedicato, senza scaricare né toccare i repo
  list [ws]                i workspace dell'archivio, con cartella e repo
  tools [ws | global]      i programmi di mise e di requires.txt: installati e mancanti
  tools install [ws|global]  mise installa i programmi mancanti, alla versione richiesta
  integrations             le integrazioni degli agenti attive in global/integrations.txt
                           (boost, caveman, code-review-graph, repomix) e cosa manca
  new <ws> [cartella]      crea un workspace vuoto; cartella sotto ~/workspace (default: il nome)
  add <ws> <url> [branch]  aggiunge un repo al workspace; eng sync lo clona
  log                      mostra il log dell'ultima esecuzione
  detach <ws|global|all>   sostituisce i collegamenti con copie indipendenti;
                           dopo detach all l'archivio si può cancellare

Opzioni
  --data-dir <dir>     prima del comando: usa un altro archivio solo per questa volta
  --version            versione del programma, senza leggere l'archivio
  -n, --dry-run        mostra cosa farebbe senza farlo (sync, setup, detach)
  -v, --verbose        mostra anche i controlli andati bene
  --path <dir>         con sync di un solo workspace: dove stanno i suoi repo su questo
                       computer (salvato in ~/.config/engramma/paths)
  -j, --jobs <n>       con sync: quanti repo clonare o aggiornare insieme
                       (default da ~/.config/engramma/config, altrimenti 3)
  --prune              con sync: cancella senza chiedere i branch locali già mergiati
                       o rimossi dal remoto, anche con commit solo locali

Uscita: 0 se tutto è a posto, 1 se resta qualcosa da sistemare.

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
	[[ -n "$1" && -d "$ENGRAMMA_DIR/workspaces/$1" ]]
}

fail_usage() {
	echo "$1" >&2
	echo "Aiuto: eng --help" >&2
	exit 1
}

COMMAND=check
MODE=check
REQUESTED_PATH=""
REQUESTED_JOBS=""
PRUNE=false
TOOLS_INSTALL=false
TOOLS_GLOBAL=false
WORKSPACES=()
BACKUP_STAMP="$(date +%Y-%m-%d-%H%M%S)"
# Copies kept before replacing a file: on this computer, outside the archive and its Git.
BACKUP_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/engramma/backup"

# save, new and add take only names and values: an option would end up as data.
if [[ "${1:-}" =~ ^(save|new|add)$ ]]; then
	for arg in "${@:2}"; do
		[[ "$arg" != -* ]] || fail_usage "eng $1 non accetta opzioni: $arg"
	done
fi

case "${1:-}" in
	sync | setup | check | detach | list | session-start)
		COMMAND="$1"
		shift
		;;
	tools)
		COMMAND=tools
		shift
		[[ "${1:-}" == install ]] && TOOLS_INSTALL=true && shift
		;;
	-h | --help | help)
		usage
		exit 0
		;;
save) echo "Archivio: $ENGRAMMA_DIR"; save_engramma "${@:2}"; exit ;;
	new) echo "Archivio: $ENGRAMMA_DIR"; new_workspace "${@:2}"; exit ;;
	add) echo "Archivio: $ENGRAMMA_DIR"; add_repo "${@:2}"; exit ;;
	log) show_last_log; exit ;;
	integrations) integrations_command; exit ;;
esac

while [[ $# -gt 0 ]]; do
	case "$1" in
		-n | --dry-run) MODE=dry ;;
		-v | --verbose) VERBOSE=true ;;
		--path)
			[[ $# -ge 2 && "$2" != -* ]] || fail_usage "Manca la cartella dopo --path"
			REQUESTED_PATH="$2"
			shift
			;;
		-j | --jobs)
			[[ $# -ge 2 && "$2" =~ ^[1-9][0-9]*$ ]] || fail_usage "Manca il numero dopo $1 (es. $1 4)"
			REQUESTED_JOBS="$2"
			shift
			;;
		--prune) PRUNE=true ;;
		-*) fail_usage "Opzione sconosciuta: $1" ;;
		# A name alone, as in "eng demo", is a check: only sync changes things.
		*) WORKSPACES+=("$1") ;;
	esac
	shift
done

case "$COMMAND" in
	sync | setup | detach) [[ "$MODE" == dry ]] || MODE=run ;;
	check | list | session-start | tools)
		[[ "$MODE" == check ]] || fail_usage "--dry-run vale solo con sync, setup e detach"
		;;
esac

# global is the configuration of the computer, named like a workspace.
HEADER="$COMMAND"
if [[ " ${WORKSPACES[*]} " == *" global "* ]]; then
	((${#WORKSPACES[@]} == 1)) || fail_usage "global va da solo: eng $COMMAND global"
	HEADER="$COMMAND global"
	case "$COMMAND" in
		sync | check) COMMAND=setup ;;
		detach) COMMAND=detach-global ;;
		tools) TOOLS_GLOBAL=true ;;
		*) fail_usage "eng $COMMAND non accetta global" ;;
	esac
	WORKSPACES=()
fi

if [[ "$COMMAND" == detach && ${#WORKSPACES[@]} -eq 1 && "${WORKSPACES[0]}" == all ]]; then
	COMMAND=detach-all
	WORKSPACES=()
fi

for name in "${WORKSPACES[@]}"; do
	is_workspace "$name" || fail_usage "Workspace sconosciuto: '$name' (ci sono: $(available_workspaces))"
done

case "$COMMAND" in
	setup | session-start | detach-all | detach-global)
		((${#WORKSPACES[@]} == 0)) || fail_usage "eng $HEADER non accetta workspace"
		;;
	detach)
		((${#WORKSPACES[@]} == 1)) || fail_usage "eng detach vuole un workspace, oppure all"
		;;
esac

if [[ -n "$REQUESTED_JOBS" ]] || $PRUNE; then
	[[ "$COMMAND" == sync ]] || fail_usage "--jobs e --prune valgono solo con sync"
fi
REPO_JOBS="${REQUESTED_JOBS:-$(configured_repo_jobs)}"

if [[ -n "$REQUESTED_PATH" ]]; then
	[[ "$COMMAND" == sync && ${#WORKSPACES[@]} -eq 1 ]] || fail_usage "--path vale solo con sync di un solo workspace"
	[[ ! "$REQUESTED_PATH" =~ [[:space:]] ]] || fail_usage "La cartella non può contenere spazi: '$REQUESTED_PATH'"
fi

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
	load_ssh_agent
	block "programmi" "mise · global/requires.txt" "programmi"
	ensure_mise
	check_global_commands
	block "configurazione" "global/ · skills/" "file"
	link_skills
	link_global
	section "percorsi assoluti"
	check_absolute_paths "$GLOBAL_DIR" "$ENGRAMMA_DIR/skills"
	heading "AGENTI"
	block "claude code" "plugin e marketplace in settings.json" "controlli"
	check_claude_marketplaces
	check_claude_plugins
	block "codex" "$(tilde "$CODEX_HOME_DIR") · ~/.agents"
	setup_codex
	block_end
}

workspace_steps() {
	load_workspace "$1"
	block "$WORKSPACE_NAME" "$(tilde "$WORKSPACE_DIR")"
	remember_workspace_path
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
		session_start_report
		exit 0
		;;
	detach-all)
		print_header "detach all"
		block "engramma" "comando, skill, configurazione"
		detach_engramma_command
		detach_skills
		detach_global
		for notes_dir in "$ENGRAMMA_DIR"/workspaces/*/; do
			[[ -d "$notes_dir" ]] || continue
			load_workspace "$(basename "$notes_dir")"
			block "$WORKSPACE_NAME" "$(tilde "$WORKSPACE_DIR")" "collegamenti"
			detach_workspace
		done
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

[[ "$MODE" == run ]] && { load_ssh_agent; pull_engramma; }

print_header "$HEADER"

ALL_WORKSPACES=false
if [[ "$COMMAND" != setup ]] && ((${#WORKSPACES[@]} == 0)); then
	ALL_WORKSPACES=true
	mapfile -t WORKSPACES < <(present_workspaces)
fi

# The SSH servers of all the workspaces are probed together, in the background,
# while the workstation is checked.
load_ssh_agent
for name in "${WORKSPACES[@]}"; do
	load_workspace "$name"
	mapfile -t hosts < <(ssh_hosts_of_repos)
	prefetch_ssh "${hosts[@]}"
done
[[ "$COMMAND" == sync ]] && start_repo_jobs "${WORKSPACES[@]}"

# A check of named workspaces looks at them only; "eng check global" covers the computer.
if [[ "$COMMAND" != check ]] || $ALL_WORKSPACES; then
	setup_workstation
fi
[[ "$COMMAND" == setup ]] && finish

$ALL_WORKSPACES || EXPAND_BLOCKS=true
((${#WORKSPACES[@]})) && heading "WORKSPACE"
for name in "${WORKSPACES[@]}"; do
	workspace_steps "$name"
done
if [[ "$COMMAND" == sync && "$MODE" == run ]]; then
	send_workspace_updates "${WORKSPACES[@]}"
fi
$ALL_WORKSPACES && report_absent_workspaces
finish
