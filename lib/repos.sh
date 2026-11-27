# shellcheck shell=bash
# shellcheck disable=SC2153 # FILE, REF, CMD and the other colors come from lib/theme.sh

FETCH_TIMEOUT_SECONDS=120
CLONE_TIMEOUT_SECONDS=600
# A repo whose clone, fetch and alignment take longer is named in the summary.
SLOW_REPO_SECONDS="${ENGRAMMA_SLOW_REPO_SECONDS:-30}"

# Runs git without ever asking for a password (a prompt hidden behind the live
# zone would wait forever). Its stderr goes to the log, the last lines also to
# the lines of the repo when it fails.
quiet_git() {
	local label="$1" errors status line
	shift
	activity "$BLOCK_TITLE › ${REPO_NAME:-$BLOCK_TITLE} › $label"
	errors="$(mktemp)"
	GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh -o BatchMode=yes -o ConnectTimeout=15}" GIT_TERMINAL_PROMPT=0 \
		"$@" 2>"$errors" </dev/null
	status=$?
	((status == 124)) && echo "timeout: interrotto dopo il tempo massimo" >>"$errors"
	while IFS= read -r line; do
		log_line "     │ $line"
	done <"$errors"
	if ((status)); then
		while IFS= read -r line; do
			say "  ${DIM}│ $line${RESET}"
		done < <(grep -v '^[[:space:]]*$' "$errors" | tail -n 3)
	fi
	rm -f "$errors"
	return "$status"
}

default_branch_of() {
	if [[ -n "${2:-}" ]]; then
		echo "$2"
	elif git -C "$1" rev-parse --verify --quiet origin/develop >/dev/null; then
		echo develop
	else
		echo main
	fi
}

is_upstream_gone() {
	local track
	track="$(git -C "$1" for-each-ref --format='%(upstream:track)' "refs/heads/$2")"
	[[ "$track" == "[gone]" ]]
}

is_merged_into() {
	git -C "$1" merge-base --is-ancestor "refs/heads/$2" "origin/$3"
}

is_branch_finished() {
	is_upstream_gone "$1" "$2" || is_merged_into "$1" "$2" "$3"
}

stale_branches_of() {
	local repo="$1" default_branch="$2" branch
	while read -r branch; do
		[[ "$branch" == "$default_branch" || "$branch" == main || "$branch" == develop ]] && continue
		is_branch_finished "$repo" "$branch" "$default_branch" && echo "$branch"
	done < <(git -C "$repo" for-each-ref --format='%(refname:short)' refs/heads/)
}

# A branch whose commits are all on the remote: merged into the main branch, or
# contained in a branch of origin. A branch removed on origin after a squash
# merge can still hold commits never pushed.
is_branch_pushed() {
	is_merged_into "$1" "$2" "$3" ||
		[[ -n "$(git -C "$1" for-each-ref --count=1 --contains "refs/heads/$2" refs/remotes/)" ]]
}

# Lists the branches already merged or removed on origin, with the date and the
# subject of their last commit, and leaves them in JOB_STALE ("<branch> pushed"
# or "<branch> local" per line): deleting them is asked once at the end of the
# workspace (prune_stale_branches).
list_stale_branches() {
	local repo="$1" default_branch="$2" branch stale where note
	stale="$(stale_branches_of "$repo" "$default_branch")"
	[[ -n "$stale" ]] || return 0
	info "branch locali mergiati in $default_branch o rimossi dal remoto:"
	while read -r branch; do
		where=pushed note=""
		if ! is_branch_pushed "$repo" "$branch" "$default_branch"; then
			where=local note=" ${YELLOW}· commit non presenti sul remoto${RESET}"
		fi
		JOB_STALE+="$branch $where"$'\n'
		say "    ${MAGENTA}•${RESET} ${REF}$branch${RESET} ${DIM}$(git -C "$repo" log -1 --format='%ad %s' --date=short "refs/heads/$branch")${RESET}$note"
	done <<<"$stale"
}

# Counts a problem whose only trace is the outcome of the repo.
repo_problem() {
	PROBLEM_COUNT=$((PROBLEM_COUNT + 1))
	BLOCK_ISSUES=$((BLOCK_ISSUES + 1))
	repo_status "$@"
	note problem "$2"
}

# A lock left by a git that stopped halfway (editors that run git in the
# background leave it): until it goes, every commit and checkout fails. Older than
# a minute and with no git running, nobody is using it.
check_git_lock() {
	local repo="$1" lock="$1/.git/index.lock"
	[[ -f "$lock" ]] || return 0
	if [[ -z "$(find "$lock" -mmin +1 2>/dev/null)" ]] || git_running_in "$repo"; then
		info "git al lavoro in questo momento ${DIM}($(path "$lock"))${RESET}"
		return 0
	fi
	case "$MODE" in
		dry) would "blocco di git rimasto da un'operazione interrotta: toglierei $(path "$lock")" ;;
		check)
			problem "blocco di git rimasto da un'operazione interrotta: commit e checkout falliscono ${DIM}(eng sync lo toglie)${RESET}"
			fix_with 46 "${CMD}rm $(tilde "$lock")${RESET}"
			;;
		*)
			rm -f "$lock"
			ok "blocco di git rimasto da un'operazione interrotta: tolto ${DIM}($(path "$lock"))${RESET}"
			;;
	esac
}

# A git whose working folder is the repo (git -C moves there): read from /proc,
# so on systems without it only the age of the lock counts.
git_running_in() {
	local pid
	for pid in $(pgrep -x git 2>/dev/null); do
		[[ "$(readlink "/proc/$pid/cwd" 2>/dev/null)" == "$1"* ]] && return 0
	done
	return 1
}

short_head() {
	git -C "$1" rev-parse --short=7 HEAD 2>/dev/null
}

clone_repo() {
	local repo="$1" url="$2" branch="$3"

	if [[ "$MODE" == dry ]]; then
		repo_status dry "git clone ${url}"
		return
	fi

	if ! ssh_url_authenticated "$url"; then
		repo_problem err "clone saltato: SSH verso $(ssh_host_of_url "$url") non autenticato"
		return
	fi

	if ! quiet_git "git clone" timeout "$CLONE_TIMEOUT_SECONDS" git clone --quiet "$url" "$repo"; then
		repo_problem err "git clone fallito ${DIM}($url)${RESET}"
		rmdir "$repo" 2>/dev/null
		return
	fi

	local default_branch
	default_branch="$(default_branch_of "$repo" "$branch")"
	if ! git -C "$repo" checkout --quiet "$default_branch" 2>/dev/null; then
		repo_problem warn "clonato, ma git checkout $default_branch fallito"
		return
	fi
	repo_status ok "clonato · $default_branch @ $(short_head "$repo")"
}

# Read-only: where the repo stands, and the work that exists only here.
check_repo() {
	local repo="$1" current_branch unsaved item
	check_git_lock "$repo"
	current_branch="$(git -C "$repo" branch --show-current)"
	unsaved="$(repo_unsaved_work "$repo")"
	if [[ -z "$unsaved" ]]; then
		repo_status fine "${current_branch:-HEAD staccato}"
		return
	fi
	while IFS= read -r item; do
		local_work "$item"
	done <<<"$unsaved"
	repo_status warn "${current_branch:-HEAD staccato} · lavoro solo su questo computer"
}

# A repo already cloned: fetch, then, once its personal files are linked, back
# on the main branch with a fast-forward.
update_repo() {
	local repo="$1" branch="$2"
	check_git_lock "$repo"

	if ! ssh_url_authenticated "$(git -C "$repo" remote get-url origin 2>/dev/null)"; then
		repo_problem err "fetch saltato: SSH verso origin non autenticato"
		return
	fi

	if ! quiet_git "git fetch" timeout "$FETCH_TIMEOUT_SECONDS" git -C "$repo" fetch --prune --quiet origin; then
		repo_problem err "git fetch fallito: non lo tocco"
		return
	fi

	# The network part is over: the slot goes to the next job while this one
	# waits, and the wait does not count in the time of the repo.
	touch "$JOB_ID.fetched"
	local waiting=$SECONDS
	wait_for_file "$JOB_ID.linked"
	JOB_WAITED=$((SECONDS - waiting))
	align_repo "$repo" "$branch"
}

align_repo() {
	local repo="$1" branch="$2"

	if [[ -n "$(git -C "$repo" status --porcelain 2>/dev/null)" ]]; then
		repo_status skip "file con modifiche non committate: aggiornamento saltato"
		note local "file con modifiche non committate: aggiornamento saltato"
		return
	fi

	local default_branch current_branch before
	default_branch="$(default_branch_of "$repo" "$branch")"
	current_branch="$(git -C "$repo" branch --show-current)"
	before="$(short_head "$repo")"

	if [[ -n "$current_branch" && "$current_branch" != "$default_branch" ]] &&
		! is_branch_finished "$repo" "$current_branch" "$default_branch"; then
		repo_status skip "branch ${REF}$current_branch${RESET} ancora in corso: aggiornamento saltato"
		note local "branch ${REF}$current_branch${RESET} ancora in corso: aggiornamento saltato"
		return
	fi

	if [[ "$MODE" == dry ]]; then
		list_stale_branches "$repo" "$default_branch"
		repo_status dry "checkout $default_branch + merge --ff-only origin/$default_branch"
		return
	fi

	activity "$BLOCK_TITLE › $REPO_NAME › git merge --ff-only"
	if ! git -C "$repo" checkout --quiet "$default_branch" 2>/dev/null; then
		repo_problem err "git checkout $default_branch fallito"
		return
	fi

	if ! git -C "$repo" merge --ff-only --quiet "origin/$default_branch" 2>/dev/null; then
		repo_problem warn "$default_branch locale e remoto hanno commit diversi: aggiornamento automatico impossibile"
		return
	fi

	list_stale_branches "$repo" "$default_branch"
	if [[ "$current_branch $before" == "$default_branch $(short_head "$repo")" ]]; then
		repo_status fine "$default_branch, già aggiornato"
	elif [[ "$current_branch" == "$default_branch" ]]; then
		repo_status ok "$default_branch ${DIM}$before → $(short_head "$repo")${RESET}"
	else
		repo_status ok "${current_branch:-HEAD staccato} → $default_branch @ $(short_head "$repo")"
	fi
}

# Waits for a file written by the main process, as long as it is running.
wait_for_file() {
	until [[ -e "$1" ]]; do
		kill -0 "$$" 2>/dev/null || exit 1
		sleep 0.05
	done
}

link_repo_personal_files() {
	ensure_repo_note "$1" "$2"
	ensure_repo_files "$1" "$2"
	ensure_repo_excludes "$1" "$2"
	check_codex_repo_instructions "$1" "$2"
	check_repo_env_vars "$1" "$2"
}

# The folders of the workspace that hold its notes: a repo cannot be cloned there.
RESERVED_REPO_FOLDERS=(.claude docs AGENTS.md)

is_reserved_repo_folder() {
	local reserved
	for reserved in "${RESERVED_REPO_FOLDERS[@]}"; do
		[[ "$1" == "$reserved" ]] && return 0
	done
	return 1
}

# A folder name that says what the repo is: <owner>-<repo> from its URL, or just
# <repo> when it already starts with the owner (example/example-api).
suggested_repo_folder() {
	local path="${1%.git}" repo owner
	path="${path##*:}"
	path="${path#//*/}"
	repo="${path##*/}"
	owner="${path%/*}"
	owner="${owner##*/}"
	if [[ -z "$owner" || "$owner" == "$repo" || "$repo" == "$owner"* ]]; then
		echo "$repo"
	else
		echo "$owner-$repo"
	fi
}

reserved_repo_folder_problem() {
	local name="$1" url="$2"
	repo_begin "$name"
	repo_problem err "cartella riservata agli appunti del workspace, repo non toccato ${DIM}($url)${RESET}"
	fix_with 44 "in $(path "$WORKSPACE_NOTES_DIR/repos.txt") rinomina la cartella del repo: ${CMD}$(suggested_repo_folder "$url") $url${RESET}"
}

# ── repos in background jobs ──────────────────────────────────────────────────

# Clone, fetch and alignment run in background jobs, at most REPO_JOBS at a time,
# for the repos of every workspace and from the start of the run, while the
# workstation is checked. A job keeps the lines and the outcome of its repo in a
# file; the block of the workspace reads them in the order of repos.txt, so the
# output does not depend on which job ends first. Questions cannot come from a
# job. Links and the other local checks stay in the main process: the job of a
# repo already cloned waits for them before aligning it, otherwise the files
# linked into the repo would look like uncommitted changes.
REPO_JOBS=3
REPO_JOBS_DIR=""
REPO_JOBS_PID=""
REPO_JOBS_TOTAL=0
declare -A REPO_JOB_KIND=()
STALE_BRANCHES=() UNPUSHED_BRANCHES=()

repo_job_id() {
	echo "$REPO_JOBS_DIR/$1--$2"
}

start_repo_jobs() {
	local specs=() workspace name url branch
	for workspace in "$@"; do
		load_workspace "$workspace"
		while read -r name url branch; do
			is_reserved_repo_folder "$name" && continue
			[[ -z "${REPO_JOB_KIND[$workspace/$name]:-}" ]] || continue
			if [[ -e "$WORKSPACE_DIR/$name/.git" ]]; then
				REPO_JOB_KIND["$workspace/$name"]=update
			else
				REPO_JOB_KIND["$workspace/$name"]=clone
			fi
			specs+=("$workspace"$'\x1f'"$name"$'\x1f'"$url"$'\x1f'"$branch"$'\x1f'"$WORKSPACE_DIR"$'\x1f'"${REPO_JOB_KIND[$workspace/$name]}")
		done < <(repo_entries)
	done
	((${#specs[@]})) || return 0
	REPO_JOBS_DIR="$(mktemp -d)"
	REPO_JOBS_TOTAL=${#specs[@]}
	live_progress "$REPO_JOBS_DIR" "${#specs[@]}" repo
	run_repo_jobs "${specs[@]}" &
	REPO_JOBS_PID=$!
}

# At most REPO_JOBS jobs clone or fetch at the same time; a job that has fetched
# and waits for the links of its repo leaves its slot (the alignment is local).
run_repo_jobs() {
	local spec fields launched=() id busy
	for spec in "$@"; do
		IFS=$'\x1f' read -r -a fields <<<"$spec"
		while :; do
			busy=0
			for id in "${launched[@]}"; do
				[[ -e "$id.fetched" || -e "$id.done" ]] || busy=$((busy + 1))
			done
			((busy < REPO_JOBS)) && break
			sleep 0.05
		done
		repo_job "${fields[@]}" &
		launched+=("$(repo_job_id "${fields[0]}" "${fields[1]}")")
	done
	wait
}

repo_job() {
	local workspace="$1" name="$2" url="$3" branch="$4" dir="$5" kind="$6" started=$SECONDS
	JOB_WAITED=0
	JOB_ID="$(repo_job_id "$workspace" "$name")"
	JOB_STALE=""
	echo "$BASHPID" >"$JOB_ID.pid"
	exec {LOG_FD}>"$JOB_ID.log"
	# shellcheck disable=SC2034 # the state of lib/ui.sh, as for a block of its own
	BLOCK_OPEN=true BLOCK_FLUSHED=false BLOCK_TITLE="$workspace" GROUP_TITLE="" BLOCK_LEVEL=0
	PROBLEM_COUNT=0 BLOCK_ISSUES=0 BLOCK_WARNINGS=0 BLOCK_FINE=0
	REPO_NAME="$name" REPO_STATUS=fine REPO_MESSAGE="" REPO_LINES=() REPO_LEVEL=0
	NOTES=() LAST_NOTE=-1
	if [[ "$kind" == clone ]]; then
		clone_repo "$dir/$name" "$url" "$branch"
	else
		update_repo "$dir/$name" "$branch"
	fi
	{
		printf 'JOB_STATUS=%q JOB_MESSAGE=%q JOB_LEVEL=%q JOB_SECONDS=%q\n' \
			"$REPO_STATUS" "$REPO_MESSAGE" "$REPO_LEVEL" $((SECONDS - started - JOB_WAITED))
		printf 'JOB_PROBLEMS=%q JOB_ISSUES=%q JOB_WARNINGS=%q JOB_FINE=%q JOB_STALE=%q\n' \
			"$PROBLEM_COUNT" "$BLOCK_ISSUES" "$BLOCK_WARNINGS" "$BLOCK_FINE" "$JOB_STALE"
		printf 'JOB_LINES=('
		((${#REPO_LINES[@]})) && printf '%q ' "${REPO_LINES[@]}"
		printf ')\n'
		printf 'JOB_NOTES=('
		((${#NOTES[@]})) && printf '%q ' "${NOTES[@]}"
		printf ')\n'
	} >"$JOB_ID.result"
	touch "$JOB_ID.done"
}

# Ctrl+C does not reach the jobs (a command started with & in a script ignores
# it): on exit the jobs still running are stopped, with the git they started.
stop_repo_jobs() {
	[[ -n "$REPO_JOBS_DIR" ]] || return 0
	local pid_file running=false
	for pid_file in "$REPO_JOBS_DIR"/*.pid; do
		[[ -e "$pid_file" && ! -e "${pid_file%.pid}.done" ]] || continue
		running=true
		pkill -TERM -P "$(<"$pid_file")" 2>/dev/null
		kill "$(<"$pid_file")" 2>/dev/null
	done
	# The dispatcher is stopped only while it still has jobs to start.
	$running || [[ "$(find "$REPO_JOBS_DIR" -name '*.done' | wc -l)" -lt "$REPO_JOBS_TOTAL" ]] &&
		kill "$REPO_JOBS_PID" 2>/dev/null
	rm -rf "$REPO_JOBS_DIR"
	REPO_JOBS_PID="" REPO_JOBS_DIR=""
}

# Adds the outcome of the job to the repo open in the block.
collect_repo_job() {
	local name="$1" id branch where
	id="$(repo_job_id "$WORKSPACE_NAME" "$name")"
	activity "$BLOCK_TITLE › $name"
	until [[ -e "$id.done" ]]; do
		kill -0 "$REPO_JOBS_PID" 2>/dev/null || [[ -e "$id.done" ]] || break
		sleep 0.05
	done
	[[ -f "$id.log" && -n "$LOG_FD" ]] && cat "$id.log" >&"$LOG_FD"
	if [[ ! -f "$id.result" ]]; then
		repo_problem err "job interrotto prima della fine"
		FAILED_REPOS+=("$WORKSPACE_NAME/$name")
		return
	fi

	local JOB_STATUS JOB_MESSAGE JOB_LEVEL JOB_SECONDS JOB_PROBLEMS JOB_ISSUES JOB_WARNINGS JOB_FINE JOB_STALE JOB_LINES=() JOB_NOTES=()
	# shellcheck source=/dev/null # written by repo_job
	source "$id.result"
	REPO_STATUS="$JOB_STATUS" REPO_MESSAGE="$JOB_MESSAGE"
	REPO_LINES+=("${JOB_LINES[@]}")
	# shellcheck disable=SC2034 # read by fix_with in lib/ui.sh
	((${#JOB_NOTES[@]})) && NOTES+=("${JOB_NOTES[@]}") && LAST_NOTE=$((${#NOTES[@]} - 1))
	raise_level "$JOB_LEVEL"
	PROBLEM_COUNT=$((PROBLEM_COUNT + JOB_PROBLEMS))
	BLOCK_ISSUES=$((BLOCK_ISSUES + JOB_ISSUES))
	BLOCK_WARNINGS=$((BLOCK_WARNINGS + JOB_WARNINGS))
	BLOCK_FINE=$((BLOCK_FINE + JOB_FINE))

	local elapsed
	elapsed_label elapsed "$JOB_SECONDS"
	((JOB_SECONDS > SLOW_REPO_SECONDS)) && SLOW_REPOS+=("$WORKSPACE_NAME/$name $elapsed")
	[[ "$JOB_STATUS" == err ]] && FAILED_REPOS+=("$WORKSPACE_NAME/$name")
	while read -r branch where; do
		[[ -n "$branch" ]] || continue
		STALE_BRANCHES+=("$name $branch")
		[[ "$where" == local ]] && UNPUSHED_BRANCHES+=("$name $branch")
	done <<<"$JOB_STALE"
}

# The repos of the workspace with their jobs: first the links of the repos already
# cloned, one after the other, then the outcomes in the order of repos.txt.
process_repos() {
	if [[ "$MODE" == check ]]; then
		check_repos
		return
	fi
	local name url branch kind
	local -A parked_lines=() parked_levels=()
	STALE_BRANCHES=() UNPUSHED_BRANCHES=()
	while read -r name url branch <&3; do
		[[ "${REPO_JOB_KIND[$WORKSPACE_NAME/$name]:-}" == update ]] || continue
		repo_begin "$name"
		link_repo_personal_files "$WORKSPACE_DIR/$name" "$name"
		((${#REPO_LINES[@]})) && parked_lines[$name]="$(printf '%s\x1e' "${REPO_LINES[@]}")"
		parked_levels[$name]=$REPO_LEVEL
		REPO_NAME=""
		touch "$(repo_job_id "$WORKSPACE_NAME" "$name").linked"
	done 3< <(repo_entries)

	while read -r name url branch <&3; do
		if is_reserved_repo_folder "$name"; then
			reserved_repo_folder_problem "$name" "$url"
			continue
		fi
		kind="${REPO_JOB_KIND[$WORKSPACE_NAME/$name]:-}"
		repo_begin "$name"
		if [[ -n "${parked_lines[$name]:-}" ]]; then
			mapfile -t -d $'\x1e' REPO_LINES <<<"${parked_lines[$name]}"
			unset 'REPO_LINES[-1]'
		fi
		REPO_LEVEL="${parked_levels[$name]:-0}"
		collect_repo_job "$name"
		if [[ "$kind" == clone && -e "$WORKSPACE_DIR/$name/.git" ]]; then
			link_repo_personal_files "$WORKSPACE_DIR/$name" "$name"
		fi
	done 3< <(repo_entries)
	repo_end
	prune_stale_branches
}

# Read-only, without jobs: what eng would clone, and the work not saved or not sent.
check_repos() {
	local name url branch repo
	while read -r name url branch <&3; do
		if is_reserved_repo_folder "$name"; then
			reserved_repo_folder_problem "$name" "$url"
			continue
		fi
		repo="$WORKSPACE_DIR/$name"
		repo_begin "$name"
		if [[ ! -e "$repo/.git" ]]; then
			repo_problem err "non clonato ${DIM}· eng sync lo clona${RESET}"
			continue
		fi
		link_repo_personal_files "$repo" "$name"
		check_repo "$repo"
	done 3< <(repo_entries)
	repo_end
}

# One question for the branches already merged of every repo of the workspace:
# all, none, or repo by repo. A branch whose commits are not on the remote (never
# pushed, or merged with a squash: engramma cannot tell) is left out of the
# question and only listed. --prune deletes all of them without asking.
prune_stale_branches() {
	((${#STALE_BRANCHES[@]})) && [[ "$MODE" == run ]] || return 0
	local entry name branch repos=() candidates=() chosen=() kept=""
	for entry in "${STALE_BRANCHES[@]}"; do
		if [[ " ${UNPUSHED_BRANCHES[*]/%/ |} " == *" $entry |"* ]]; then
			kept+="$entry"$'\n'
		else
			candidates+=("$entry")
			name="${entry%% *}"
			[[ " ${repos[*]} " == *" $name "* ]] || repos+=("$name")
		fi
	done
	close_repos
	section "branch mergiati o rimossi dal remoto"
	if $PRUNE; then
		chosen=("${STALE_BRANCHES[@]}")
	elif report_unpushed_branches "$kept" && ((${#candidates[@]} == 0)); then
		return 0
	elif ! $IS_INTERACTIVE; then
		if ((${#candidates[@]} == 1)); then
			info "1 branch lasciato: eng sync $WORKSPACE_NAME --prune lo cancella ${DIM}(cancella anche quelli con commit solo locali)${RESET}"
		else
			info "${#candidates[@]} branch lasciati: eng sync $WORKSPACE_NAME --prune li cancella ${DIM}(cancella anche quelli con commit solo locali)${RESET}"
		fi
		return 0
	else
		ask "Cancello i ${#candidates[@]} branch locali elencati con commit presenti sul remoto (${#repos[@]} repo)? [s] sì · [n] no · [c] scelgo per repo"
		case "$ASK_ANSWER" in
			s | si | sì) chosen=("${candidates[@]}") ;;
			c)
				for name in "${repos[@]}"; do
					local branches=()
					for entry in "${candidates[@]}"; do
						[[ "${entry%% *}" == "$name" ]] && branches+=("${entry#* }")
					done
				ask "$name: cancello i branch locali ${branches[*]}? [s/N]"
					[[ "$ASK_ANSWER" == s ]] || continue
					for branch in "${branches[@]}"; do
						chosen+=("$name $branch")
					done
				done
				;;
		esac
	fi
	if ((${#chosen[@]} == 0)); then
		info "branch locali lasciati"
		return 0
	fi
	for entry in "${chosen[@]}"; do
		name="${entry%% *}" branch="${entry#* }"
		if git -C "$WORKSPACE_DIR/$name" branch -D "$branch" >/dev/null 2>&1; then
			ok "${TEXT}$name${RESET}: branch locale ${REF}$branch${RESET} eliminato"
		else
			warn "${TEXT}$name${RESET} git branch -D $branch fallito ${DIM}(checkout in un altro worktree?)${RESET}"
		fi
	done
}

# The branches with commits that are not on the remote, one line per repo, and
# --prune among the next steps.
report_unpushed_branches() {
	[[ -n "$1" ]] || return 0
	next_step 50 "${CMD}eng sync $WORKSPACE_NAME --prune${RESET}: cancella senza chiedere i branch locali mergiati o rimossi dal remoto, anche quelli con commit solo locali"
	local name branch names=() branches
	while read -r name _; do
		[[ -n "$name" && " ${names[*]} " != *" $name "* ]] && names+=("$name")
	done <<<"$1"
	for name in "${names[@]}"; do
		branches="$(awk -v name="$name" '$1 == name { printf "%s ", $2 }' <<<"$1")"
		branches="${branches% }"
		info "${TEXT}$name${RESET} lasciati ${REF}$branches${RESET}: commit non presenti sul remoto"
	done
}
