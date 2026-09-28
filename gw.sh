# shellcheck shell=sh
# gw: cd into a worktree for a GitHub PR.
#
# Usage: gw https://github.com/owner/repo/pull/123
#
# Must be sourced, not executed - only sourcing lets the final cd
# affect the caller: . /path/to/gw.sh
#
# Requirements:
#   Hard: sh, git, gh (https://cli.github.com/).
#     Without gh gw runs in limited mode: pr-N branch, no status,
#     no rename-following, private repos via git credential helper only.
#   Assumed standard Unix (unchecked): find, rm.
#     find needs -maxdepth and -prune (both BSD and GNU find have them).
#   Soft (silent feature detection, never a fatal dep error):
#     git-wt (native git worktree fallback otherwise; hooks/copy
#     configs are git-wt-only extras), zoxide (checkout discovery
#     speedup), ssh (only ssh -G to resolve Host aliases; a missing
#     ssh means the host is taken literally).

_gw_tolower() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

gw() {
  case $# in
  1) ;;
  *)
    printf 'Usage: gw <github PR URL>\n' >&2
    return 1
    ;;
  esac
  _gw_url=$1

  _gw_url_lc=$(_gw_tolower "$_gw_url")
  case "$_gw_url_lc" in
  *github.com/*/*/pull/*) ;;
  *)
    printf 'gw: not a GitHub PR URL: %s\n' "$_gw_url" >&2
    return 1
    ;;
  esac
  _gw_rest=${_gw_url_lc#*github.com/}
  _gw_owner=${_gw_rest%%/*}
  _gw_rest=${_gw_rest#*/}
  case "$_gw_rest" in
  */*) ;;
  *)
    printf 'gw: not a GitHub PR URL: %s\n' "$_gw_url" >&2
    return 1
    ;;
  esac
  _gw_repo=${_gw_rest%%/*}
  _gw_rest=${_gw_rest#*/}
  case "$_gw_rest" in
  pull/[0-9]*) ;;
  *)
    printf 'gw: not a GitHub PR URL: %s\n' "$_gw_url" >&2
    return 1
    ;;
  esac
  _gw_num=${_gw_rest#pull/}
  _gw_num=${_gw_num%%/*}
  _gw_num=${_gw_num%%\?*}
  _gw_num=${_gw_num%%\#*}
  case "$_gw_num" in
  '' | *[!0-9]*)
    printf 'gw: not a GitHub PR URL: %s\n' "$_gw_url" >&2
    return 1
    ;;
  esac
  _gw_repo=${_gw_repo%.git}
  if [ -z "$_gw_owner" ] || [ -z "$_gw_repo" ]; then
    printf 'gw: not a GitHub PR URL: %s\n' "$_gw_url" >&2
    return 1
  fi

  if command -v gh >/dev/null 2>&1; then
    _gw_no_gh=""
  else
    printf 'gw: gh not found, limited mode (pr-%s branch, no status); install gh: https://cli.github.com/\n' "$_gw_num" >&2
    _gw_no_gh=1
  fi

  _gw_base=$_gw_owner/$_gw_repo
  if [ -n "$_gw_no_gh" ]; then
    # Limited mode: owner/repo + N straight from the URL (no
    # rename-following), every PR treated as a fork. Private repos work
    # only via the git credential helper.
    _gw_branch="pr-$_gw_num"
    _gw_is_cross="true"
    _gw_state=""
    _gw_pr_url=""
  else
    _gw_out=$(gh pr view "$_gw_num" -R "$_gw_base" --json headRefName,isCrossRepository,state,url --jq '.headRefName, .isCrossRepository, .state, .url') || {
      printf 'gw: could not load PR #%s in %s\n' "$_gw_num" "$_gw_base" >&2
      return 1
    }
    {
      IFS= read -r _gw_branch || _gw_branch=""
      IFS= read -r _gw_is_cross || _gw_is_cross=""
      IFS= read -r _gw_state || _gw_state=""
      IFS= read -r _gw_pr_url || _gw_pr_url=""
    } <<_GW_PR_EOF
$_gw_out
_GW_PR_EOF
    if [ -z "$_gw_branch" ]; then
      printf 'gw: could not load PR #%s in %s\n' "$_gw_num" "$_gw_base" >&2
      return 1
    fi
    if [ -n "$_gw_state" ] && [ "$_gw_state" != "OPEN" ]; then
      printf 'gw: PR #%s is %s\n' "$_gw_num" "$_gw_state" >&2
    fi
  fi

  # Canonical owner/repo from gh (follows renames) for discovery and clone.
  # Skipped in limited mode: the URL values stay literal.
  if [ -z "$_gw_no_gh" ]; then
    case "$_gw_pr_url" in
    *github.com/*/*/pull/*)
      _gw_canon=${_gw_pr_url#*github.com/}
      _gw_owner=${_gw_canon%%/*}
      _gw_canon=${_gw_canon#*/}
      _gw_repo=${_gw_canon%%/*}
      _gw_repo=${_gw_repo%.git}
      _gw_base=$_gw_owner/$_gw_repo
      ;;
    esac
  fi

  _gw_want="github.com/$(_gw_tolower "$_gw_base")"
  _gw_found=""
  if _gw_found=$(_gw_find_checkout "$_gw_want"); then
    :
  else
    _gw_found=""
    _gw_root=${GW_CLONE_ROOT:-$HOME/GitHub}
    # "~" is a literal match.
    # shellcheck disable=SC2088
    case "$_gw_root" in
    "~") _gw_root=$HOME ;;
    "~/"*) _gw_root=$HOME/${_gw_root#\~/} ;;
    esac
    _gw_tab=$(printf '\t')
    for _gw_target in "$_gw_root/$_gw_repo" "$_gw_root/$_gw_owner/$_gw_repo"; do
      if [ ! -e "$_gw_target" ]; then
        printf 'gw: no local checkout of %s, cloning into %s\n' "$_gw_base" "$_gw_target"
        if [ -n "$_gw_no_gh" ]; then
          _gw_clone_url="https://github.com/$_gw_base.git"
          if ! git clone "$_gw_clone_url" "$_gw_target"; then
            rm -rf -- "$_gw_target"
            return 1
          fi
        elif ! gh repo clone "$_gw_base" "$_gw_target"; then
          rm -rf -- "$_gw_target"
          return 1
        fi
        _gw_found=${_gw_target}${_gw_tab}origin
        break
      fi
      if _gw_found=$(_gw_dir_matches "$_gw_target" "$_gw_want"); then
        break
      fi
      _gw_found=""
    done
    if [ -z "$_gw_found" ]; then
      printf 'gw: %s and %s exist but neither is %s\n' "$_gw_root/$_gw_repo" "$_gw_root/$_gw_owner/$_gw_repo" "$_gw_base" >&2
      return 1
    fi
  fi
  _gw_tab=$(printf '\t')
  _gw_checkout=${_gw_found%%"${_gw_tab}"*}
  _gw_remote=${_gw_found#*"${_gw_tab}"}

  _gw_wt_branch=$_gw_branch
  _gw_pr_ref="refs/gw/pr-$_gw_num"
  if [ -n "$_gw_no_gh" ] || [ "$_gw_is_cross" = "true" ]; then
    _gw_wt_branch="pr-$_gw_num"
    _gw_sync "$_gw_checkout" "$_gw_remote" "pull/$_gw_num/head" "$_gw_pr_ref" "$_gw_wt_branch" || return 1
  elif ! _gw_sync "$_gw_checkout" "$_gw_remote" "refs/heads/$_gw_branch" "refs/remotes/$_gw_remote/$_gw_branch" "$_gw_wt_branch"; then
    printf 'gw: %s not fetchable from %s, using pull/%s/head\n' "$_gw_branch" "$_gw_remote" "$_gw_num" >&2
    _gw_sync "$_gw_checkout" "$_gw_remote" "pull/$_gw_num/head" "$_gw_pr_ref" "$_gw_wt_branch" || return 1
  fi

  # Never cd before the worktree path is known; failures must leave the
  # caller where they were.
  _gw_wt_path=""
  if command -v git-wt >/dev/null 2>&1; then
    # git-wt prints the path on its last stdout line.
    _gw_wt_out=$(git -C "$_gw_checkout" wt --nocd "$_gw_wt_branch")
    _gw_nl=$(printf '\nX')
    _gw_nl=${_gw_nl%X}
    case "$_gw_wt_out" in
    *"$_gw_nl"*) _gw_wt_path=${_gw_wt_out##*"$_gw_nl"} ;;
    *) _gw_wt_path=$_gw_wt_out ;;
    esac
  elif _gw_wt_path=$(_gw_branch_worktree "$_gw_checkout" "$_gw_wt_branch" 2>/dev/null); then
    :
  else
    # Native fallback: plain git worktree under .wt.
    _gw_wt_top=$(git -C "$_gw_checkout" rev-parse --show-toplevel 2>/dev/null) || {
      printf 'gw: could not resolve worktree path for %s\n' "$_gw_wt_branch" >&2
      return 1
    }
    _gw_wt_safe=$(_gw_sanitize_branch "$_gw_wt_branch") || {
      printf 'gw: could not resolve worktree path for %s\n' "$_gw_wt_branch" >&2
      return 1
    }
    _gw_wt_path=$_gw_wt_top/.wt/$_gw_wt_safe
    if _gw_wt_err=$(git -C "$_gw_checkout" worktree add -- "$_gw_wt_path" "$_gw_wt_branch" 2>&1); then
      _gw_wt_err=""
    else
      printf 'gw: could not create worktree at %s for %s: %s\n' "$_gw_wt_path" "$_gw_wt_branch" "$_gw_wt_err" >&2
      return 1
    fi
  fi
  if ! command -v git-wt >/dev/null 2>&1 && [ -n "$_gw_wt_path" ] && [ -d "$_gw_wt_path" ]; then
    # Keep a native .wt/ out of git status on both creation and reuse.
    _gw_wt_info=$(git -C "$_gw_checkout" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || _gw_wt_info=""
    if [ -n "$_gw_wt_info" ]; then
      _gw_wt_exclude=$_gw_wt_info/info/exclude
      if ! grep -qxF '.wt/' "$_gw_wt_exclude" 2>/dev/null; then
        printf '\n.wt/\n' >>"$_gw_wt_exclude" 2>/dev/null || true
      fi
    fi
  fi
  if [ -z "$_gw_wt_path" ] || [ ! -d "$_gw_wt_path" ]; then
    printf 'gw: could not resolve worktree path for %s\n' "$_gw_wt_branch" >&2
    if [ -z "$_gw_wt_path" ] && command -v git-wt >/dev/null 2>&1; then
      printf 'gw: git-wt did not report a worktree path (needs --nocd support)\n' >&2
    fi
    return 1
  fi
  command cd "$_gw_wt_path" || return 1
}

_gw_sanitize_branch() {
  # Print branch $1 sanitized for use as a worktree path. / is preserved
  # as directory hierarchy; anything outside [A-Za-z0-9._-/] becomes _;
  # empty, . and .. segments become _ so the result cannot escape the base.
  _gw_sb_rest=$(printf '%s' "$1" | tr -c 'A-Za-z0-9._/-' '_')
  _gw_sb_out=""
  while :; do
    case "$_gw_sb_rest" in
    */*)
      _gw_sb_seg=${_gw_sb_rest%%/*}
      _gw_sb_rest=${_gw_sb_rest#*/}
      ;;
    *)
      _gw_sb_seg=$_gw_sb_rest
      _gw_sb_rest=""
      ;;
    esac
    case "$_gw_sb_seg" in
    "" | "." | "..") _gw_sb_seg="_" ;;
    esac
    if [ -z "$_gw_sb_out" ]; then
      _gw_sb_out=$_gw_sb_seg
    else
      _gw_sb_out=$_gw_sb_out/$_gw_sb_seg
    fi
    [ -n "$_gw_sb_rest" ] || break
  done
  printf '%s\n' "$_gw_sb_out"
}

_gw_sync() {
  # Fetch $3 from remote $2 into ref $4 in repo $1, then create or move local
  # branch $5 to it. A branch with commits of its own is left alone.
  _gw_s_dir=$1
  _gw_s_remote=$2
  _gw_s_src=$3
  _gw_s_ref=$4
  _gw_s_lb=$5
  _gw_s_old=$(git -C "$_gw_s_dir" rev-parse --verify --quiet "$_gw_s_ref" 2>/dev/null) || _gw_s_old=""
  git -C "$_gw_s_dir" fetch "$_gw_s_remote" "+${_gw_s_src}:${_gw_s_ref}" || return 1
  _gw_s_new=$(git -C "$_gw_s_dir" rev-parse --verify --quiet "$_gw_s_ref") || return 1

  if ! _gw_s_cur=$(git -C "$_gw_s_dir" rev-parse --verify --quiet "refs/heads/$_gw_s_lb" 2>/dev/null); then
    git -C "$_gw_s_dir" branch "$_gw_s_lb" "$_gw_s_ref" >/dev/null
    return
  fi
  if [ "$_gw_s_cur" = "$_gw_s_new" ]; then
    return 0
  fi
  # Move when the branch only holds fetched commits: behind the new head, or
  # at/behind the previous one (the PR was force-pushed).
  if git -C "$_gw_s_dir" merge-base --is-ancestor "$_gw_s_cur" "$_gw_s_new" 2>/dev/null; then
    :
  elif [ -n "$_gw_s_old" ] && git -C "$_gw_s_dir" merge-base --is-ancestor "$_gw_s_cur" "$_gw_s_old" 2>/dev/null; then
    :
  else
    printf 'gw: %s has local commits, not updated\n' "$_gw_s_lb" >&2
    return 0
  fi
  if _gw_s_wt=$(_gw_branch_worktree "$_gw_s_dir" "$_gw_s_lb"); then
    git -C "$_gw_s_wt" reset --keep "$_gw_s_new" ||
      printf 'gw: could not update %s in %s, leaving it as is\n' "$_gw_s_lb" "$_gw_s_wt" >&2
  else
    git -C "$_gw_s_dir" branch -f "$_gw_s_lb" "$_gw_s_new"
  fi
  return 0
}

_gw_branch_worktree() {
  # Print the worktree path with branch $2 checked out in repo $1.
  _gw_bw_dir=$1
  _gw_bw_lb=$2
  _gw_bw_want="branch refs/heads/$_gw_bw_lb"
  _gw_bw_wt=""
  _gw_bw_out=$(git -C "$_gw_bw_dir" worktree list --porcelain 2>/dev/null) || return 1
  while IFS= read -r _gw_bw_line || [ -n "$_gw_bw_line" ]; do
    case "$_gw_bw_line" in
    "worktree "*) _gw_bw_wt=${_gw_bw_line#worktree } ;;
    esac
    if [ "$_gw_bw_line" = "$_gw_bw_want" ] && [ -n "$_gw_bw_wt" ]; then
      printf '%s\n' "$_gw_bw_wt"
      return 0
    fi
  done <<_GW_BW_EOF
$_gw_bw_out
_GW_BW_EOF
  return 1
}

_gw_main_checkout() {
  # Print the main checkout containing $1. Fails for bare repos.
  _gw_mc_arg=$1
  _gw_mc_common=$(git -C "$_gw_mc_arg" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 1
  _gw_mc_base=${_gw_mc_common##*/}
  if [ "$_gw_mc_base" = ".git" ]; then
    _gw_mc_main=${_gw_mc_common%/*}
    printf '%s\n' "$_gw_mc_main"
    return 0
  fi
  # Submodules keep their git dir under the parent's .git/modules.
  if [ "$(git -C "$_gw_mc_arg" rev-parse --is-bare-repository 2>/dev/null)" != "false" ]; then
    return 1
  fi
  git -C "$_gw_mc_arg" rev-parse --show-toplevel 2>/dev/null
}

_gw_find_checkout() {
  # Print "<main checkout><tab><matching remote>" for host/owner/repo ($1).
  _gw_fc_want=$1
  _gw_fc_dir=$(git rev-parse --show-toplevel 2>/dev/null) || _gw_fc_dir=""
  if [ -n "$_gw_fc_dir" ]; then
    if _gw_dir_matches "$_gw_fc_dir" "$_gw_fc_want"; then
      return 0
    fi
  fi

  if command -v zoxide >/dev/null 2>&1; then
    _gw_fc_repo=${_gw_fc_want##*/}
    _gw_fc_out=$(zoxide query -l "$_gw_fc_repo" 2>/dev/null) || _gw_fc_out=""
    while IFS= read -r _gw_fc_line || [ -n "$_gw_fc_line" ]; do
      [ -n "$_gw_fc_line" ] || continue
      [ -e "$_gw_fc_line/.git" ] || continue
      _gw_fc_base=${_gw_fc_line##*/}
      if [ "$(_gw_tolower "$_gw_fc_base")" != "$_gw_fc_repo" ]; then
        continue
      fi
      if _gw_dir_matches "$_gw_fc_line" "$_gw_fc_want"; then
        return 0
      fi
    done <<_GW_FC_ZOX_EOF
$_gw_fc_out
_GW_FC_ZOX_EOF
  fi

  _gw_fc_gwr=${GW_ROOTS:-"$HOME/GitHub $HOME/code $HOME/src $HOME/repos $HOME/workspace $HOME/projects"}
  _gw_fc_lf=$(printf '\nX')
  _gw_fc_lf=${_gw_fc_lf%X}
  _gw_fc_seen=$_gw_fc_lf
  case $- in
  *f*) _gw_fc_had_f=1 ;;
  *) _gw_fc_had_f=0 ;;
  esac
  set -f
  # Word-splitting GW_ROOTS on spaces is intentional.
  # shellcheck disable=SC2086
  # "~" is a literal match.
  # shellcheck disable=SC2088
  for _gw_fc_root in $_gw_fc_gwr; do
    case "$_gw_fc_root" in
    "~") _gw_fc_root=$HOME ;;
    "~/"*) _gw_fc_root=$HOME/${_gw_fc_root#\~/} ;;
    esac
    [ -d "$_gw_fc_root" ] || continue
    _gw_fc_out=$(find -L "$_gw_fc_root" -maxdepth 5 \( -name node_modules -prune \) -o \( -name .git -prune -print \) 2>/dev/null) || _gw_fc_out=""
    while IFS= read -r _gw_fc_gitdir || [ -n "$_gw_fc_gitdir" ]; do
      [ -n "$_gw_fc_gitdir" ] || continue
      _gw_fc_dir=${_gw_fc_gitdir%/.git}
      _gw_fc_dir=$(_gw_main_checkout "$_gw_fc_dir") || continue
      case "$_gw_fc_seen" in
      *"$_gw_fc_lf$_gw_fc_dir$_gw_fc_lf"*) continue ;;
      esac
      _gw_fc_seen=$_gw_fc_seen$_gw_fc_dir$_gw_fc_lf
      if _gw_dir_matches "$_gw_fc_dir" "$_gw_fc_want"; then
        if [ "$_gw_fc_had_f" = 0 ]; then
          set +f
        fi
        return 0
      fi
    done <<_GW_FC_FIND_EOF
$_gw_fc_out
_GW_FC_FIND_EOF
  done
  if [ "$_gw_fc_had_f" = 0 ]; then
    set +f
  fi
  return 1
}

_gw_dir_matches() {
  # Print "<main checkout><tab><remote>" when a remote of $1 matches $2.
  # Checks every configured URL, then each remote's get-url, since insteadOf
  # rewriting can hide the github URL on either side.
  _gw_dm_dir=$1
  _gw_dm_want=$2
  _gw_dm_hit=""
  _gw_dm_out=$(git -C "$_gw_dm_dir" config --get-regexp '^remote\..*\.url$' 2>/dev/null) || _gw_dm_out=""
  while IFS= read -r _gw_dm_line || [ -n "$_gw_dm_line" ]; do
    [ -n "$_gw_dm_line" ] || continue
    case "$_gw_dm_line" in
    *" "*) ;;
    *) continue ;;
    esac
    _gw_dm_key=${_gw_dm_line%% *}
    _gw_dm_url=${_gw_dm_line#* }
    _gw_dm_rname=${_gw_dm_key#remote.}
    _gw_dm_rname=${_gw_dm_rname%.url}
    _gw_dm_id=$(_gw_github_id "$_gw_dm_url" 2>/dev/null) || continue
    if [ "$_gw_dm_id" = "$_gw_dm_want" ]; then
      _gw_dm_hit=$_gw_dm_rname
      break
    fi
  done <<_GW_DM_CFG_EOF
$_gw_dm_out
_GW_DM_CFG_EOF
  if [ -z "$_gw_dm_hit" ]; then
    _gw_dm_out=$(git -C "$_gw_dm_dir" remote 2>/dev/null) || _gw_dm_out=""
    while IFS= read -r _gw_dm_remote || [ -n "$_gw_dm_remote" ]; do
      [ -n "$_gw_dm_remote" ] || continue
      _gw_dm_url=$(git -C "$_gw_dm_dir" remote get-url "$_gw_dm_remote" 2>/dev/null) || continue
      _gw_dm_id=$(_gw_github_id "$_gw_dm_url" 2>/dev/null) || continue
      if [ "$_gw_dm_id" = "$_gw_dm_want" ]; then
        _gw_dm_hit=$_gw_dm_remote
        break
      fi
    done <<_GW_DM_REMOTE_EOF
$_gw_dm_out
_GW_DM_REMOTE_EOF
  fi
  [ -n "$_gw_dm_hit" ] || return 1
  _gw_dm_main=$(_gw_main_checkout "$_gw_dm_dir") || return 1
  printf '%s\t%s\n' "$_gw_dm_main" "$_gw_dm_hit"
}

_gw_github_id() {
  # Normalize a remote URL to host/owner/repo (lowercase, no .git suffix).
  _gw_gid_url=$1
  [ -n "$_gw_gid_url" ] || return 1
  _gw_gid_prev=""
  while [ "$_gw_gid_url" != "$_gw_gid_prev" ]; do
    _gw_gid_prev=$_gw_gid_url
    case "$_gw_gid_url" in
    *.git) _gw_gid_url=${_gw_gid_url%.git} ;;
    esac
    while :; do
      case "$_gw_gid_url" in
      */) _gw_gid_url=${_gw_gid_url%/} ;;
      *) break ;;
      esac
    done
  done
  _gw_gid_ssh_like=0
  case "$_gw_gid_url" in
  *://*)
    _gw_gid_scheme=${_gw_gid_url%%://*}
    _gw_gid_rest=${_gw_gid_url#*://}
    case "$_gw_gid_scheme" in
    [a-zA-Z]*)
      case "$_gw_gid_scheme" in
      *[!a-zA-Z0-9+.-]*) return 1 ;;
      esac
      ;;
    *) return 1 ;;
    esac
    case "$_gw_gid_rest" in
    */?*)
      _gw_gid_host=${_gw_gid_rest%%/*}
      _gw_gid_slug=${_gw_gid_rest#*/}
      ;;
    *) return 1 ;;
    esac
    case "$(_gw_tolower "$_gw_gid_scheme")" in
    *ssh*) _gw_gid_ssh_like=1 ;;
    esac
    ;;
  *@*:*)
    _gw_gid_user=${_gw_gid_url%%@*}
    case "$_gw_gid_user" in
    */* | *@*) return 1 ;;
    esac
    _gw_gid_after_at=${_gw_gid_url#*@}
    case "$_gw_gid_after_at" in
    *:*) ;;
    *) return 1 ;;
    esac
    _gw_gid_host=${_gw_gid_after_at%%:*}
    _gw_gid_slug=${_gw_gid_after_at#*:}
    _gw_gid_ssh_like=1
    ;;
  *) return 1 ;;
  esac
  _gw_gid_host=${_gw_gid_host##*@}
  _gw_gid_host=${_gw_gid_host%%:*}
  [ -n "$_gw_gid_host" ] && [ -n "$_gw_gid_slug" ] || return 1
  if [ "$_gw_gid_ssh_like" = 1 ]; then
    if [ "$(_gw_tolower "$_gw_gid_host")" != "github.com" ] && command -v ssh >/dev/null 2>&1; then
      _gw_gid_out=$(ssh -G "$_gw_gid_host" 2>/dev/null) || _gw_gid_out=""
      _gw_gid_resolved=""
      while IFS= read -r _gw_gid_line || [ -n "$_gw_gid_line" ]; do
        case "$_gw_gid_line" in
        "hostname "*)
          _gw_gid_resolved=${_gw_gid_line#hostname }
          _gw_gid_resolved=${_gw_gid_resolved%% *}
          if [ -n "$_gw_gid_resolved" ]; then
            break
          fi
          ;;
        esac
      done <<_GW_GID_SSH_EOF
$_gw_gid_out
_GW_GID_SSH_EOF
      if [ -n "$_gw_gid_resolved" ]; then
        _gw_gid_host=$_gw_gid_resolved
      fi
    fi
  fi
  printf '%s\n' "$(_gw_tolower "$_gw_gid_host")/$(_gw_tolower "$_gw_gid_slug")"
}
