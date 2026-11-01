#!/usr/bin/env bash
# Tests for hooks/guard-protected-push.sh.
# Each case feeds a PreToolUse(Bash) payload to the hook and checks the decision:
#   block = exit 2 · ask = permissionDecision "ask" · allow = exit 0 with no output
# Usage: tests/run.sh [path/to/hook]
set -uo pipefail
export LC_ALL=C

HOOK=${1:-"$(cd "$(dirname "$0")/.." && pwd)/hooks/guard-protected-push.sh"}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

make_repo() {  # $1 = dir, $2 = current branch
  git init -q -b main "$1"
  git -C "$1" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  git -C "$1" branch -q develop
  [[ $2 == main ]] || git -C "$1" checkout -q -b "$2"
  git -C "$1" remote add origin https://example.invalid/repo.git
}
make_repo "$TMP/on-main" main
make_repo "$TMP/on-feature" feature/42-login

decide() {  # $1 = command, $2 = cwd → prints block | ask | allow
  local out code
  out=$(jq -cn --arg c "$1" --arg d "$2" '{tool_input:{command:$c},cwd:$d}' | bash "$HOOK" 2>/dev/null)
  code=$?
  if (( code == 2 )); then echo block
  elif [[ $out == *'"permissionDecision":"ask"'* ]]; then echo ask
  elif (( code == 0 )) && [[ -z $out ]]; then echo allow
  else echo "unexpected(exit=$code,out=$out)"; fi
}

PASS=0 FAIL=0
check() {  # $1 = expected, $2 = cwd, $3 = command
  local got
  got=$(decide "$3" "$2")
  if [[ $got == "$1" ]]; then (( PASS++ ))
  else (( FAIL++ )); printf 'FAIL  expected %-5s got %-5s  [%s] %s\n' "$1" "$got" "${2##*/}" "$3"; fi
}

M=$TMP/on-main F=$TMP/on-feature

# Direct pushes to a protected branch
check block "$F" 'git push origin main'
check block "$F" 'git push origin master'
check block "$F" 'git push origin develop'
check block "$F" 'git push origin +main'
check block "$F" 'git push origin HEAD:main'
check block "$F" 'git push origin feature/42-login:refs/heads/main'
check block "$F" 'git push --all'
check block "$F" 'git push --mirror origin'
check block "$F" "git push origin 'refs/heads/*'"

# Bare push resolves the current branch
check block "$M" 'git push'
check block "$M" 'git push origin'
check block "$M" 'git push origin HEAD'
check allow "$F" 'git push'
check allow "$F" 'git push -u origin feature/42-login'
check allow "$F" 'git push origin HEAD'

# Directory changes
check block "$F" "cd $M && git push"
check block "$F" "git -C $M push"
check allow "$M" "cd $F && git push"
check allow "$F" "(cd $M) && git push"

# Obfuscation and indirection
check block "$F" 'git pu""sh origin main'
check block "$F" 'git pu\sh origin main'
check block "$F" "sh -c 'git push origin main'"
check block "$F" 'bash -c "git push origin develop"'
check block "$F" 'eval "git push origin main"'
check block "$F" 'env git push origin main'
check block "$F" 'git status; git push origin main'
check block "$F" 'git add . && git commit -m wip && git push origin main'
check block "$F" 'echo $(git push origin main)'

# Unknown at read time → ask the user
check ask "$F" 'git push origin $BRANCH'
check ask "$F" 'git push origin "$(pick-branch)"'
check ask "$F" 'git -c remote.origin.push=refs/heads/main push'
check ask "$F" 'GIT_CONFIG_GLOBAL=/tmp/x git push'
check ask "$F" 'git branch | xargs git push origin'
check ask "$F" '$GIT push origin feature/42-login'

# Data, not commands
check allow "$F" 'echo "git push origin main"'
check allow "$F" 'git commit -m "push to main later"'
check allow "$F" 'grep -r "git push origin main" docs/'
check allow "$F" "cat <<'EOF' > notes.md
git push origin main
EOF"
check allow "$F" 'git log --oneline main'
check allow "$F" 'git checkout main'
check allow "$F" 'git pull origin main'
check allow "$F" 'ls -la'

if [[ ${GIT_GUARD_TEST_CONFIG:-1} == 1 ]] && grep -q GIT_GUARD_PROTECTED "$HOOK"; then
  # Custom protected-branch list
  export GIT_GUARD_PROTECTED="release production"
  check block "$F" 'git push origin release'
  check block "$F" 'git push origin production'
  check allow "$F" 'git push origin main'
  unset GIT_GUARD_PROTECTED
fi

echo "passed: $PASS  failed: $FAIL"
(( FAIL == 0 ))
