#!/bin/sh
# Tests for the gw.sh string functions: _gw_tolower, _gw_sanitize_branch,
# _gw_github_id. Plain POSIX sh, no dependencies, runnable under dash:
# dash tests/test-gw.sh (also sh, bash --posix).

_t_script_dir=$(dirname -- "$0")
CDPATH=''
_t_root=$(cd -- "$_t_script_dir/.." && pwd) || exit 1
# shellcheck disable=SC1091
. "$_t_root/gw.sh" || exit 1

_t_pass=0
_t_fail=0

_t_assert_eq() {
  _t_ae_want=$1
  _t_ae_got=$2
  _t_ae_label=$3
  if [ "$_t_ae_want" = "$_t_ae_got" ]; then
    _t_pass=$((_t_pass + 1))
    printf 'ok - %s\n' "$_t_ae_label"
  else
    _t_fail=$((_t_fail + 1))
    printf 'not ok - %s: want <%s> got <%s>\n' "$_t_ae_label" "$_t_ae_want" "$_t_ae_got"
  fi
  unset _t_ae_want _t_ae_got _t_ae_label
}

_t_assert_status() {
  _t_as_want=$1
  _t_as_got=$2
  _t_as_label=$3
  if [ "$_t_as_want" = "$_t_as_got" ]; then
    _t_pass=$((_t_pass + 1))
    printf 'ok - %s\n' "$_t_as_label"
  else
    _t_fail=$((_t_fail + 1))
    printf 'not ok - %s: want status <%s> got <%s>\n' "$_t_as_label" "$_t_as_want" "$_t_as_got"
  fi
  unset _t_as_want _t_as_got _t_as_label
}

# _gw_tolower
_t_got=$(_gw_tolower "ABC")
_t_assert_eq "abc" "$_t_got" "tolower upper"
_t_got=$(_gw_tolower "abc")
_t_assert_eq "abc" "$_t_got" "tolower already lower"
_t_got=$(_gw_tolower "")
_t_assert_eq "" "$_t_got" "tolower empty"
_t_got=$(_gw_tolower "AbC123-_.x")
_t_assert_eq "abc123-_.x" "$_t_got" "tolower mixed with digits and punctuation"
_t_got=$(_gw_tolower "HELLO WORLD")
_t_assert_eq "hello world" "$_t_got" "tolower with space"

# _gw_sanitize_branch
_t_got=$(_gw_sanitize_branch "feature/foo")
_t_assert_eq "feature/foo" "$_t_got" "sanitize keeps slash hierarchy"
_t_got=$(_gw_sanitize_branch "Feature/Bar Baz!")
_t_assert_eq "Feature/Bar_Baz_" "$_t_got" "sanitize maps outside set, keeps case"
_t_got=$(_gw_sanitize_branch "a//b")
_t_assert_eq "a/_/b" "$_t_got" "sanitize empty segment"
_t_got=$(_gw_sanitize_branch "/leading")
_t_assert_eq "_/leading" "$_t_got" "sanitize leading slash"
_t_got=$(_gw_sanitize_branch "trailing/")
_t_assert_eq "trailing" "$_t_got" "sanitize trailing slash dropped"
_t_got=$(_gw_sanitize_branch ".")
_t_assert_eq "_" "$_t_got" "sanitize dot"
_t_got=$(_gw_sanitize_branch "..")
_t_assert_eq "_" "$_t_got" "sanitize dotdot"
_t_got=$(_gw_sanitize_branch "a/./b")
_t_assert_eq "a/_/b" "$_t_got" "sanitize dot segment"
_t_got=$(_gw_sanitize_branch "a/../b")
_t_assert_eq "a/_/b" "$_t_got" "sanitize dotdot segment"
_t_got=$(_gw_sanitize_branch "")
_t_assert_eq "_" "$_t_got" "sanitize empty"
_t_got=$(_gw_sanitize_branch "a:b")
_t_assert_eq "a_b" "$_t_got" "sanitize colon"

# _gw_github_id without ssh
_t_got=$(_gw_github_id "https://github.com/Owner/Repo")
_t_assert_eq "github.com/owner/repo" "$_t_got" "github_id https"
_t_got=$(_gw_github_id "https://github.com/Owner/Repo.git")
_t_assert_eq "github.com/owner/repo" "$_t_got" "github_id https .git"
_t_got=$(_gw_github_id "https://github.com/Owner/Repo/")
_t_assert_eq "github.com/owner/repo" "$_t_got" "github_id https trailing slash"
_t_got=$(_gw_github_id "https://github.com/Owner/Repo.git/")
_t_assert_eq "github.com/owner/repo" "$_t_got" "github_id https .git trailing slash"
_t_got=$(_gw_github_id "HTTPS://GITHUB.COM/Owner/Repo")
_t_assert_eq "github.com/owner/repo" "$_t_got" "github_id uppercase scheme and host"
_t_got=$(_gw_github_id "git@github.com:Owner/Repo.git")
_t_assert_eq "github.com/owner/repo" "$_t_got" "github_id scp-like .git"
_t_got=$(_gw_github_id "git@github.com:Owner/Repo/")
_t_assert_eq "github.com/owner/repo" "$_t_got" "github_id scp-like trailing slash"
_t_got=$(_gw_github_id "ssh://git@github.com/Owner/Repo.git")
_t_assert_eq "github.com/owner/repo" "$_t_got" "github_id ssh url .git"

# _gw_github_id rejects invalid input
if _gw_github_id "not a url" >/dev/null 2>&1; then _t_got=0; else _t_got=$?; fi
_t_assert_status 1 "$_t_got" "github_id rejects non-url"
if _gw_github_id "" >/dev/null 2>&1; then _t_got=0; else _t_got=$?; fi
_t_assert_status 1 "$_t_got" "github_id rejects empty"
if _gw_github_id "https://github.com/" >/dev/null 2>&1; then _t_got=0; else _t_got=$?; fi
_t_assert_status 1 "$_t_got" "github_id rejects bare host"

# _gw_github_id via a stub ssh on PATH (alias branch)
_t_tmp=$(mktemp -d) || exit 1
trap 'rm -rf -- "$_t_tmp"' EXIT INT TERM
mkdir -p "$_t_tmp/bin"
cat >"$_t_tmp/bin/ssh" <<'_SSH_EOF'
#!/bin/sh
if [ "$1" = "-G" ]; then
  case "$2" in
    myalias) printf 'hostname github.com\n' ;;
    *) printf 'hostname %s\n' "$2" ;;
  esac
  exit 0
fi
printf 'stub ssh: unexpected args\n' >&2
exit 1
_SSH_EOF
chmod +x "$_t_tmp/bin/ssh"
PATH="$_t_tmp/bin:$PATH"
export PATH

_t_got=$(_gw_github_id "ssh://git@myalias/Owner/Repo.git")
_t_assert_eq "github.com/owner/repo" "$_t_got" "github_id ssh alias url"
_t_got=$(_gw_github_id "git@myalias:Owner/Repo.git")
_t_assert_eq "github.com/owner/repo" "$_t_got" "github_id ssh alias scp-like"

# github.com URLs must not depend on ssh: a failing stub still passes
cat >"$_t_tmp/bin/ssh" <<'_SSH_EOF'
#!/bin/sh
printf 'stub ssh: must not be called\n' >&2
exit 1
_SSH_EOF
chmod +x "$_t_tmp/bin/ssh"
_t_got=$(_gw_github_id "https://github.com/Owner/Repo.git")
_t_assert_eq "github.com/owner/repo" "$_t_got" "github_id https ignores ssh"
_t_got=$(_gw_github_id "git@github.com:Owner/Repo.git")
_t_assert_eq "github.com/owner/repo" "$_t_got" "github_id scp-like ignores ssh"

_t_assert_contains() {
  _t_ac_hay=$1
  _t_ac_needle=$2
  _t_ac_label=$3
  case "$_t_ac_hay" in
  *"$_t_ac_needle"*)
    _t_pass=$((_t_pass + 1))
    printf 'ok - %s\n' "$_t_ac_label"
    ;;
  *)
    _t_fail=$((_t_fail + 1))
    printf 'not ok - %s: missing <%s>\n' "$_t_ac_label" "$_t_ac_needle"
    ;;
  esac
  unset _t_ac_hay _t_ac_needle _t_ac_label
}

# gw --help / -h print usage to stdout, status 0
_t_got=$(gw --help 2>&1)
_t_st=$?
_t_assert_status 0 "$_t_st" "gw --help status"
_t_assert_contains "$_t_got" "Usage:" "gw --help prints usage"
_t_assert_contains "$_t_got" "GW_ROOTS" "gw --help documents GW_ROOTS"
_t_assert_contains "$_t_got" "GW_CLONE_ROOT" "gw --help documents GW_CLONE_ROOT"
_t_assert_contains "$_t_got" "git-wt" "gw --help lists soft deps"
_t_assert_contains "$_t_got" "README" "gw --help points at README"

_t_got=$(gw -h 2>&1)
_t_st=$?
_t_assert_status 0 "$_t_st" "gw -h status"
_t_assert_contains "$_t_got" "Usage:" "gw -h prints usage"

# bare gw, unknown flags, extra args, bad URLs: status 1 + full help
_t_got=$(gw 2>&1)
_t_st=$?
_t_assert_status 1 "$_t_st" "bare gw status"
_t_assert_contains "$_t_got" "try gw --help" "bare gw suggests --help"
_t_assert_contains "$_t_got" "Usage:" "bare gw prints full help"

_t_got=$(gw --bogus 2>&1)
_t_st=$?
_t_assert_status 1 "$_t_st" "gw unknown flag status"
_t_assert_contains "$_t_got" "unknown option" "gw unknown flag names the flag"
_t_assert_contains "$_t_got" "Usage:" "gw unknown flag prints full help"

_t_got=$(gw a b 2>&1)
_t_st=$?
_t_assert_status 1 "$_t_st" "gw extra args status"
_t_assert_contains "$_t_got" "try gw --help" "gw extra args suggests --help"
_t_assert_contains "$_t_got" "Usage:" "gw extra args prints full help"

_t_got=$(gw not-a-url 2>&1)
_t_st=$?
_t_assert_status 1 "$_t_st" "gw bad url status"
_t_assert_contains "$_t_got" "not a GitHub PR URL" "gw bad url reason"
_t_assert_contains "$_t_got" "try gw --help" "gw bad url suggests --help"
_t_assert_contains "$_t_got" "Usage:" "gw bad url prints full help"

printf '%d passed, %d failed\n' "$_t_pass" "$_t_fail"
[ "$_t_fail" -eq 0 ]
