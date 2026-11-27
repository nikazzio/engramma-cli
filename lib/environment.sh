# shellcheck shell=bash
# shellcheck disable=SC2153 # FILE, REF, CMD and the other colors come from lib/theme.sh

SSH_CHECK_TIMEOUT_SECONDS=15

is_wsl() {
	grep -qi microsoft /proc/version 2>/dev/null
}

hosts_files_to_check() {
	if [[ -n "${ENGRAMMA_HOSTS_FILE:-}" ]]; then
		echo "$ENGRAMMA_HOSTS_FILE"
	elif is_wsl; then
		echo "/mnt/c/Windows/System32/drivers/etc/hosts"
	else
		echo "/etc/hosts"
	fi
}

required_commands() {
	{
		echo git
		read_list_file "$WORKSPACE_NOTES_DIR/requires.txt" | awk '{ print $1, ($2 == "facoltativo" ? "facoltativo" : "") }'
	} | awk '!seen[$1]++'
}

check_commands() {
	local command optional
	while read -r command optional; do
		if command -v "$command" >/dev/null; then
			fine "${REF}$command${RESET}"
		elif [[ "$optional" == facoltativo ]]; then
			fine "${REF}$command${RESET} assente, facoltativo"
		else
			problem "${REF}$command${RESET} non installato"
		fi
	done < <(required_commands)
}

check_node_version() {
	local name repo required version installed mise=""
	[[ -z "${ENGRAMMA_NO_MISE:-}" ]] && mise="$(command -v mise || true)"
	while read -r name _; do
		repo="$WORKSPACE_DIR/$name"
		[[ -f "$repo/.nvmrc" ]] || continue
		required="$(sed -nE 's/^[[:space:]]*v?([0-9]+).*/\1/p' "$repo/.nvmrc" | head -n 1)"
		[[ -n "$required" ]] || continue
		if [[ -n "$mise" ]]; then
			version="$(cd "$repo" && "$mise" exec -- node --version 2>/dev/null)" || version=""
		else
			version="$(cd "$repo" && node --version 2>/dev/null)" || version=""
		fi
		installed="$(sed -nE 's/^v([0-9]+).*/\1/p' <<<"$version")"
		if [[ "$required" == "$installed" ]]; then
			fine "$name: Node $installed richiesto e disponibile nel progetto"
		elif [[ -z "$installed" ]]; then
			warn "$name richiede Node $required; impossibile verificare la versione nel progetto"
			[[ -n "$mise" ]] && next_step 20 "verifica Node in $name: ${CMD}cd $(tilde "$repo") && mise exec -- node --version${RESET}"
		else
			warn "$name richiede Node $required, ma nel progetto risulta Node $installed"
			if [[ -n "$mise" ]]; then
				next_step 20 "verifica la versione Node configurata per $name: ${CMD}cd $(tilde "$repo") && mise ls node${RESET}"
			else
				next_step 20 "attiva Node $required per $name e verifica con ${CMD}cd $(tilde "$repo") && node --version${RESET}"
			fi
		fi
	done < <(repo_entries)
}

ssh_hosts_of_repos() {
	local url
	while read -r _ url; do
		[[ "$url" =~ ^([^@/]+@[^:/]+): ]] && echo "${BASH_REMATCH[1]}"
	done < <(repo_entries) | sort -u
}

SSH_PROBE_DIR=""

# The answer of a server to "ssh -T", one file per host. Every host is asked once
# per run, and all of them at the same time: prefetch_ssh starts the probes in the
# background, ssh_probe waits for the one it needs.
prefetch_ssh() {
	local host
	[[ -n "$SSH_PROBE_DIR" ]] || SSH_PROBE_DIR="$(mktemp -d)"
	for host in "$@"; do
		[[ -n "$host" && ! -e "$SSH_PROBE_DIR/$host.pid" ]] || continue
		(
			timeout "$SSH_CHECK_TIMEOUT_SECONDS" ssh -T -o BatchMode=yes -o ConnectTimeout=10 "$host" >"$SSH_PROBE_DIR/$host.out" 2>&1 </dev/null
			echo $? >"$SSH_PROBE_DIR/$host.done"
		) &
		echo $! >"$SSH_PROBE_DIR/$host.pid"
	done
}

ssh_probe() {
	local host="$1"
	prefetch_ssh "$host"
	while [[ ! -e "$SSH_PROBE_DIR/$host.done" ]]; do
		sleep 0.05
	done
	cat "$SSH_PROBE_DIR/$host.out"
}

# ssh exits with 255 when it cannot connect or authenticate, timeout with 124.
# Any other code means the server accepted the key: GitHub exits with 1, other
# servers with 0 or with the code of their git shell, each with its own message.
ssh_probe_accepted() {
	local host="$1" code
	ssh_probe "$host" >/dev/null
	code="$(cat "$SSH_PROBE_DIR/$host.done" 2>/dev/null)"
	[[ -n "$code" && "$code" != 255 && "$code" != 124 ]]
}

check_ssh() {
	local host output
	while read -r host; do
		[[ -n "$host" ]] || continue
		activity "$BLOCK_TITLE › ssh -T ${host#*@}"
		output="$(ssh_probe "$host")"
		if ssh_probe_accepted "$host"; then
			fine "ssh ${host#*@} autenticato"
		else
			problem "ssh ${REF}${host#*@}${RESET} non autenticato ${DIM}($(tail -n 1 <<<"${output:-nessuna risposta}"))${RESET}: clone e fetch dei suoi repo saltati"
			ssh_agent_has_keys || next_step 15 "carica la chiave nell'agent SSH: apri un terminale (keychain chiede la passphrase), poi rilancia"
		fi
	done < <(ssh_hosts_of_repos)
}

ssh_host_of_url() {
	[[ "$1" =~ ^([^@/]+@[^:/]+): ]] && echo "${BASH_REMATCH[1]}"
}

# Whether git can reach the server of a URL: always for local and HTTPS remotes,
# for SSH remotes only when the server answered the probe.
ssh_url_authenticated() {
	local host
	host="$(ssh_host_of_url "$1")"
	[[ -z "$host" ]] || ssh_probe_accepted "$host"
}

ssh_agent_has_keys() {
	[[ -n "${SSH_AUTH_SOCK:-}" ]] && ssh-add -l >/dev/null 2>&1
}

# A shell started by Claude Code or by a hook has no SSH agent: the agent of
# keychain (or of the desktop keyring) is used when it is running.
load_ssh_agent() {
	ssh_agent_has_keys && return 0
	local keychain keyring
	keychain="$HOME/.keychain/$(hostname)-sh"
	keyring="/run/user/$(id -u)/gcr/ssh"
	if [[ -f "$keychain" ]]; then
		# shellcheck disable=SC1090 # written by keychain on this computer
		source "$keychain" >/dev/null
		ssh_agent_has_keys && return 0
	fi
	if [[ -S "$keyring" ]]; then
		export SSH_AUTH_SOCK="$keyring"
		ssh_agent_has_keys && return 0
	fi
	return 0
}

check_hosts() {
	local hosts_file hostname
	hosts_file="$(hosts_files_to_check)"
	while read -r hostname; do
		if [[ -r "$hosts_file" ]] && grep -qE "^[^#]*[[:space:]]$hostname([[:space:]]|$)" "$hosts_file"; then
			fine "$hostname nel file hosts"
		else
			problem "$hostname non è nel file hosts ${DIM}($hosts_file)${RESET}: aggiungi ${REF}127.0.0.1 $hostname${RESET} da amministratore"
		fi
	done < <(read_list_entries "$WORKSPACE_NOTES_DIR/hosts.txt")
}

check_environment() {
	section "ambiente"
	check_commands
	check_node_version
	if $NETWORK_CHECKS; then check_ssh; fi
	check_hosts
}
