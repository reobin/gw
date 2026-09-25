# gw: cd into a worktree for a GitHub PR.
#
# Usage: gw https://github.com/owner/repo/pull/123
#
# Resolves the PR's head branch, finds your local checkout of the repo by
# remote URL (never by path), asks `git wt` to create the worktree when
# needed, and cds into it. Works from any directory.
#
# Fork PRs are checked out read-only as a local `pr-<num>` branch from
# pull/<num>/head; there is no fork remote to push back to.
#
# Requirements: zsh, git, gh, git-wt (https://github.com/k1LoW/git-wt).
# No git-wt shell integration needed; gw cds itself via `wt --nocd`.
# zoxide is optional and speeds up checkout discovery.
#
# Configuration:
#   GW_ROOTS       space-separated dirs scanned for checkouts
#                  (default: ~/GitHub ~/code ~/src ~/repos ~/workspace ~/projects)
#   GW_CLONE_ROOT  where to clone when no checkout exists (default: ~/GitHub)
# GW_ROOTS entries with spaces are not supported. The scan looks two grouping
# levels deep (e.g. <root>/<group>/<org>/<repo>), skips node_modules, and
# ignores bare repos.
gw() {
  emulate -L zsh

  if [[ $# -ne 1 ]]; then
    printf 'Usage: gw <github PR URL>\n' >&2
    return 1
  fi
  local url="$1" owner repo num

  if [[ "${url:l}" =~ github\.com/([^/?#[:space:]]+)/([^/?#[:space:]]+)/pull/([0-9]+)([/?#]|$) ]]; then
    owner="${match[1]}"
    repo="${match[2]%.git}"
    num="${match[3]}"
  else
    printf 'gw: not a GitHub PR URL: %s\n' "$url" >&2
    return 1
  fi

  if ! command -v gh >/dev/null 2>&1; then
    printf 'gw: gh CLI is not installed\n' >&2
    return 1
  fi
  if ! command -v git-wt >/dev/null 2>&1; then
    printf 'gw: git-wt is not installed\n' >&2
    return 1
  fi

  local base="$owner/$repo" out branch is_cross state pr_url
  local -a pr
  out="$(gh pr view "$num" -R "$base" --json headRefName,isCrossRepository,state,url --jq '.headRefName, .isCrossRepository, .state, .url')" || {
    printf 'gw: could not load PR #%s in %s\n' "$num" "$base" >&2
    return 1
  }
  pr=("${(@f)out}")
  branch="${pr[1]}" is_cross="${pr[2]}" state="${pr[3]}" pr_url="${pr[4]}"
  if [[ -z "$branch" ]]; then
    printf 'gw: could not load PR #%s in %s\n' "$num" "$base" >&2
    return 1
  fi
  if [[ -n "$state" && "$state" != "OPEN" ]]; then
    printf 'gw: PR #%s is %s\n' "$num" "$state" >&2
  fi

  # Canonical owner/repo from gh (follows renames) for discovery and clone.
  if [[ "$pr_url" =~ github\.com/([^/?#[:space:]]+)/([^/?#[:space:]]+)/pull/ ]]; then
    owner="${match[1]}"
    repo="${match[2]%.git}"
    base="$owner/$repo"
  fi

  local want="github.com/${base:l}" found="" checkout remote
  if ! found="$(_gw_find_checkout "$want")"; then
    found=""
    local root="${GW_CLONE_ROOT:-$HOME/GitHub}" target
    [[ "$root" == "~" || "$root" == "~/"* ]] && root="$HOME${root#\~}"
    for target in "$root/$repo" "$root/$owner/$repo"; do
      if [[ ! -e "$target" ]]; then
        printf 'gw: no local checkout of %s, cloning into %s\n' "$base" "$target"
        if ! gh repo clone "$base" "$target"; then
          rm -rf -- "$target"
          return 1
        fi
        found="$target"$'\t'"origin"
        break
      fi
      found="$(_gw_dir_matches "$target" "$want")" && break
      found=""
    done
    if [[ -z "$found" ]]; then
      printf 'gw: %s and %s exist but neither is %s\n' "$root/$repo" "$root/$owner/$repo" "$base" >&2
      return 1
    fi
  fi
  checkout="${found%%$'\t'*}" remote="${found#*$'\t'}"

  local wt_branch="$branch" pr_ref="refs/gw/pr-$num"
  if [[ "$is_cross" == "true" ]]; then
    wt_branch="pr-$num"
    _gw_sync "$checkout" "$remote" "pull/$num/head" "$pr_ref" "$wt_branch" || return 1
  elif ! _gw_sync "$checkout" "$remote" "refs/heads/$branch" "refs/remotes/$remote/$branch" "$wt_branch"; then
    printf 'gw: %s not fetchable from %s, using pull/%s/head\n' "$branch" "$remote" "$num" >&2
    _gw_sync "$checkout" "$remote" "pull/$num/head" "$pr_ref" "$wt_branch" || return 1
  fi

  # Never cd before the worktree path is known; failures must leave the
  # caller where they were. git-wt prints the path on its last stdout line.
  local wt_path
  wt_path="$(git -C "$checkout" wt --nocd "$wt_branch" | tail -n 1)"
  [[ -n "$wt_path" && -d "$wt_path" ]] || {
    printf 'gw: could not resolve worktree path for %s\n' "$wt_branch" >&2
    [[ -z "$wt_path" ]] && printf 'gw: expected k1LoW/git-wt (needs --nocd)\n' >&2
    return 1
  }
  builtin cd "$wt_path" || return 1
}

_gw_sync() {
  # Fetch $3 from remote $2 into ref $4 in repo $1, then create or move local
  # branch $5 to it. A branch with commits of its own is left alone.
  emulate -L zsh
  local dir="$1" remote="$2" src="$3" ref="$4" lb="$5" old new cur wt
  old="$(git -C "$dir" rev-parse --verify --quiet "$ref")"
  git -C "$dir" fetch "$remote" "+${src}:${ref}" || return 1
  new="$(git -C "$dir" rev-parse --verify --quiet "$ref")" || return 1

  if ! cur="$(git -C "$dir" rev-parse --verify --quiet "refs/heads/$lb")"; then
    git -C "$dir" branch "$lb" "$ref" >/dev/null
    return
  fi
  [[ "$cur" == "$new" ]] && return 0
  # Move when the branch only holds fetched commits: behind the new head, or
  # at/behind the previous one (the PR was force-pushed).
  if ! git -C "$dir" merge-base --is-ancestor "$cur" "$new" \
    && ! { [[ -n "$old" ]] && git -C "$dir" merge-base --is-ancestor "$cur" "$old"; }; then
    printf 'gw: %s has local commits, not updated\n' "$lb" >&2
    return 0
  fi
  if wt="$(_gw_branch_worktree "$dir" "$lb")"; then
    git -C "$wt" reset --keep "$new" \
      || printf 'gw: could not update %s in %s, leaving it as is\n' "$lb" "$wt" >&2
  else
    git -C "$dir" branch -f "$lb" "$new"
  fi
  return 0
}

_gw_branch_worktree() {
  # Print the worktree path with branch $2 checked out in repo $1.
  emulate -L zsh
  local wt="" line want="branch refs/heads/$2"
  while IFS= read -r line; do
    [[ "$line" == "worktree "* ]] && wt="${line#worktree }"
    if [[ "$line" == "$want" && -n "$wt" ]]; then
      printf '%s\n' "$wt"
      return 0
    fi
  done < <(git -C "$1" worktree list --porcelain 2>/dev/null)
  return 1
}

_gw_main_checkout() {
  # Print the main checkout containing $1. Fails for bare repos.
  emulate -L zsh
  local common
  common="$(git -C "${1:?}" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || return 1
  if [[ "${common:t}" == .git ]]; then
    printf '%s\n' "${common:h}"
    return 0
  fi
  # Submodules keep their git dir under the parent's .git/modules.
  [[ "$(git -C "$1" rev-parse --is-bare-repository 2>/dev/null)" == false ]] || return 1
  git -C "$1" rev-parse --show-toplevel 2>/dev/null
}

_gw_find_checkout() {
  # Print "<main checkout><tab><matching remote>" for host/owner/repo ($1).
  emulate -L zsh
  local want="${1:?}" dir gitdir root repo
  local -a roots
  typeset -A seen

  dir="$(git rev-parse --show-toplevel 2>/dev/null)" \
    && _gw_dir_matches "$dir" "$want" && return 0

  if command -v zoxide >/dev/null 2>&1; then
    repo="${want##*/}"
    while IFS= read -r dir; do
      [[ -e "$dir/.git" ]] || continue
      [[ "${dir:t:l}" == "$repo" ]] || continue
      _gw_dir_matches "$dir" "$want" && return 0
    done < <(zoxide query -l "$repo" 2>/dev/null)
  fi

  local gwr="${GW_ROOTS:-$HOME/GitHub $HOME/code $HOME/src $HOME/repos $HOME/workspace $HOME/projects}"
  roots=(${=gwr})
  for root in $roots; do
    [[ "$root" == "~" || "$root" == "~/"* ]] && root="$HOME${root#\~}"
    [[ -d "$root" ]] || continue
    while IFS= read -r gitdir; do
      dir="$(_gw_main_checkout "${gitdir%/.git}")" || continue
      [[ -n "${seen[$dir]:-}" ]] && continue
      seen[$dir]=1
      _gw_dir_matches "$dir" "$want" && return 0
    done < <(find -L "$root" -maxdepth 5 \( -name node_modules -prune \) -o \( -name .git -prune -print \) 2>/dev/null)
  done
  return 1
}

_gw_dir_matches() {
  # Print "<main checkout><tab><remote>" when a remote of $1 matches $2.
  # Checks every configured URL, then each remote's get-url, since insteadOf
  # rewriting can hide the github URL on either side.
  emulate -L zsh
  local dir="${1:?}" want="${2:?}" line key rname url hit="" main
  for line in ${(f)"$(git -C "$dir" config --get-regexp '^remote\..*\.url$' 2>/dev/null)"}; do
    key="${line%% *}" url="${line#* }"
    rname="${${key#remote.}%.url}"
    if [[ "$(_gw_github_id "$url")" == "$want" ]]; then
      hit="$rname"
      break
    fi
  done
  if [[ -z "$hit" ]]; then
    for rname in ${(f)"$(git -C "$dir" remote 2>/dev/null)"}; do
      url="$(git -C "$dir" remote get-url "$rname" 2>/dev/null)" || continue
      if [[ "$(_gw_github_id "$url")" == "$want" ]]; then
        hit="$rname"
        break
      fi
    done
  fi
  [[ -n "$hit" ]] || return 1
  main="$(_gw_main_checkout "$dir")" || return 1
  printf '%s\t%s\n' "$main" "$hit"
}

_gw_github_id() {
  # Normalize a remote URL to host/owner/repo (lowercase, no .git suffix).
  emulate -L zsh
  local url="$1" host slug scheme ssh_like=0 prev resolved
  [[ -n "$url" ]] || return 1
  prev=""
  while [[ "$url" != "$prev" ]]; do
    prev="$url"
    url="${url%.git}"
    while [[ "$url" == */ ]]; do url="${url%/}"; done
  done
  if [[ "$url" =~ ^[^/@]+@([^:]+):(.+)$ ]]; then
    host="${match[1]}" slug="${match[2]}" ssh_like=1
  elif [[ "$url" =~ ^([a-zA-Z][a-zA-Z0-9+.-]*)://([^/]+)/(.+)$ ]]; then
    scheme="${match[1]}" host="${match[2]}" slug="${match[3]}"
    [[ "${scheme:l}" == *ssh* ]] && ssh_like=1
  else
    return 1
  fi
  host="${host##*@}" host="${host%%:*}"
  if (( ssh_like )) && [[ "${host:l}" != github.com ]]; then
    resolved="$(ssh -G "$host" 2>/dev/null | awk '/^hostname /{print $2; exit}')"
    [[ -n "$resolved" ]] && host="$resolved"
  fi
  printf '%s\n' "${host:l}/${slug:l}"
}
