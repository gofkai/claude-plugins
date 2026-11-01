#!/usr/bin/env bash
# PreToolUse(Bash): block pushes to protected branches (main/master/develop by default).
# This is a client-side guard. Branch protection on the server is still the real control.
#
# How it works: split the command using shell syntax (quotes, escapes, $(...), backticks, heredocs,
# redirects), find push invocations (direct, via alias, subtree, sh -c, eval, xargs,
# submodule foreach, rebase -x), then look at the target branch:
#   - certainly a protected branch    → block (exit 2)
#   - cannot be known by reading it   → ask the user (permissionDecision: ask)
#     unknown variables / $(...) in the target, -c remote.*|push.*|branch.*, GIT_CONFIG*,
#     push.default=matching, xargs/find, shell aliases containing push
#   - everything else                 → allow
# Not blocked: data strings (echo/grep/commit messages/heredocs not fed to a shell).
#
# Protected branches: set GIT_GUARD_PROTECTED to a space-separated list to override the
# default, e.g. GIT_GUARD_PROTECTED="main release".

export LC_ALL=C
read -ra PROTECTED <<< "${GIT_GUARD_PROTECTED:-main master develop}"
SHELLS_RE='^(ba|z|da|k)?sh$'
# Lines with a heredoc whose body is fed to a shell to run
EXEC_RE='(^|[[:space:];|&(])((/[^[:space:]]*/)?(ba|z|da|k)?sh|eval|source)([[:space:]]|$)'
# $(...) that certainly returns the current branch → treat it as HEAD
HEAD_RE='^[[:space:]]*git[[:space:]]+(branch[[:space:]]+--show-current|rev-parse[[:space:]]+--abbrev-ref[[:space:]]+HEAD|symbolic-ref[[:space:]]+(-q[[:space:]]+)?--short([[:space:]]+-q)?[[:space:]]+HEAD)[[:space:]]*$'
DYN=$'\x1e'   # marks an argument containing a variable / $(...)
GLOB=$'\x1d'  # marks an argument with an unquoted glob

ASK=""
block() { echo "git-guard: $1 Create a branch and open a PR/MR instead." >&2; exit 2; }
ask()   { [[ -n $ASK ]] || ASK=$1; }
# Ask only when the command contains a push. Decide at the end, because the word push may only
# appear after unquoting / decoding a later word (c="git pu""sh ..."; env -S "$c")
PENDING=""
ask_push() { [[ -n $PENDING ]] || PENDING=$1; }

input=$(cat)

# Without jq the input cannot be parsed: fail closed for any command containing push
if ! command -v jq >/dev/null 2>&1; then
  [[ $input == *push* ]] && block "jq is required to check push commands (install: brew install jq)."
  exit 0
fi

cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // ""')
DIR=$(printf '%s' "$input" | jq -r '.cwd // ""')
[[ -n $DIR ]] || DIR=$PWD
DIR_DYN=0

# Quick filter on text with quotes/backslashes removed (g""it, pu\sh); $'...' can encode text → always check
norm=${cmd//[\"\'\\]/}
[[ $norm == *git* || $norm == *push* || $cmd == *"\$'"* ]] || exit 0
HAS_PUSH=0; [[ $norm == *push* ]] && HAS_PUSH=1   # also set later while splitting words (end_word)
ENV_CFG=0;  [[ $cmd =~ GIT_(CONFIG|DIR|WORK_TREE) ]] && ENV_CFG=1
APPEND=0    # git command after xargs/find: arguments may be appended

enqueue() {  # $1 = sub-command to analyze later, run in the current directory
  QUEUE+=("$1"); QDIR+=("$DIR"); QDYN+=("$DIR_DYN")
}

resolve_dir() {  # $1 = path, $2 = base directory → RD
  local p=$1
  [[ $p == '~' || $p == '~/'* ]] && p=$HOME${p#\~}
  [[ $p == /* ]] || p=$2/$p
  RD=$p
}

# ---------- Target branch checks ----------

check_name() {  # $1 = target ref (may be a glob refspec)
  local name=${1#refs/heads/} p
  [[ -n $name ]] || return 0
  for p in "${PROTECTED[@]}"; do
    if [[ $1 == *'*'* ]]; then
      [[ $p == $name || refs/heads/$p == $1 ]] && block "refspec '$1' also matches protected branch '$p'."
    elif [[ $name == "$p" ]]; then
      block "pushing to protected branch '$p' is blocked."
    fi
  done
  return 0
}

check_refspec() {  # $1 = refspec, $2 = repo dir, $3 = repo unknown
  local spec=${1#+} src dst
  if [[ $spec == *:* ]]; then
    src=${spec%%:*}; dst=${spec#*:}
    [[ -n $dst ]] || dst=$src
  else
    dst=$spec
  fi
  if [[ $dst == HEAD || $dst == @ ]]; then
    (( $3 )) && { ask "cannot determine the current branch"; return; }
    dst=$(git -C "$2" symbolic-ref --short -q HEAD 2>/dev/null)
  fi
  check_name "$dst"
}

bare_push() {  # push without a refspec. $1 = dir, $2 = dir unknown, $3 = remote, $4 = dynamic remote
  local b r specs mode line p
  (( $2 )) && { ask "cannot determine the current repo / branch"; return; }
  b=$(git -C "$1" symbolic-ref --short -q HEAD 2>/dev/null) || return 0
  r=$3
  if [[ -z $r ]]; then
    r=$(git -C "$1" config "branch.$b.pushRemote" || git -C "$1" config remote.pushDefault ||
        git -C "$1" config "branch.$b.remote") 2>/dev/null
    [[ -n $r ]] || r=origin
  fi
  if (( !$4 )); then
    specs=$(git -C "$1" config --get-all "remote.$r.push" 2>/dev/null)
    if [[ -n $specs ]]; then
      while IFS= read -r line; do check_refspec "$line" "$1" 0; done <<< "$specs"
      return
    fi
  fi
  mode=$(git -C "$1" config push.default 2>/dev/null)
  case $mode in
    nothing) return ;;
    matching)
      for p in "${PROTECTED[@]}"; do
        git -C "$1" show-ref --verify -q "refs/heads/$p" &&
          { ask "push.default=matching would also push branch '$p'"; return; }
      done
      return ;;
  esac
  check_name "$b"
  check_name "$(git -C "$1" config "branch.$b.merge" 2>/dev/null)"
}

check_push() {  # $1 = dir, $2 = dir unknown, $3 = risky -c present, $4 = subtree, rest = arguments
  local gdir=$1 gdyn=$2 cfg=$3 subtree=$4 remote="" rset=0 rdyn=0 skip=0 endopt=0 t dyn
  local -a refs=()
  shift 4
  for t in "$@"; do
    dyn=0
    if [[ $t == "$DYN"* ]]; then dyn=1; t=${t#?}
    elif [[ $t == "$GLOB"* ]]; then dyn=2; t=${t#?}; fi
    if (( skip )); then skip=0; continue; fi
    if (( !endopt )); then
      case $t in
        --) endopt=1; continue ;;
        --all|--mirror|--branches) block "push '$t' (includes protected branches) is blocked." ;;
        -o|--push-option|--receive-pack|--exec|--repo|-P|--prefix) skip=1; continue ;;
        -*) (( dyn )) && ask "push option uses a variable: '$t'"; continue ;;
      esac
    fi
    if (( !rset )); then remote=$t; rset=1; rdyn=$dyn; continue; fi
    (( dyn == 1 )) && { ask "target branch uses a variable or \$(...): '$t'"; continue; }
    (( dyn == 2 )) && ask "target branch has an unquoted glob the shell may expand from files: '$t'"
    refs+=("$t")
  done
  (( cfg || ENV_CFG )) && ask "push with git config (-c / GIT_CONFIG*) may change the target branch"
  (( APPEND )) && ask "push arguments are appended by xargs/find"
  if (( ${#refs[@]} )); then
    for t in "${refs[@]}"; do check_refspec "$t" "$gdir" "$gdyn"; done
  elif (( !subtree )); then
    (( rdyn )) && ask "remote uses a variable"
    bare_push "$gdir" "$gdyn" "$remote" "$rdyn"
  fi
}

# ---------- Analyze a single command (W = words, D = dynamic flags) ----------

git_cfg() {  # $1 = key=value of -c, $2 = dynamic. Sets the cfg variable of git_call
  local key=${1%%=*} val=${1#*=}
  (( $2 )) && { cfg=1; return; }
  shopt -s nocasematch
  case $key in
    remote.*|push.*|branch.*) cfg=1 ;;
    alias.*) [[ $val == *push* ]] && cfg=1 ;;
  esac
  shopt -u nocasematch
}

git_call() {  # $1 = index of the word "git" in W
  local n=${#W[@]} k gdir=$DIR gdyn=$DIR_DYN cfg=0 sub val j sub_i
  local -a args=() av=()
  for (( k = $1 + 1; k < n; k++ )); do
    case ${W[k]} in
      -C) (( k++ ))
          if (( D[k] )); then gdyn=1; else resolve_dir "${W[k]}" "$gdir"; gdir=$RD; fi ;;
      -c|--config-env) (( k++ )); git_cfg "${W[k]}" "${D[k]:-0}" ;;
      --config-env=*) git_cfg "${W[k]#--config-env=}" "${D[k]}" ;;
      --git-dir|--work-tree) (( k++ )); gdyn=1 ;;
      --git-dir=*|--work-tree=*) gdyn=1 ;;
      --namespace|--super-prefix) (( k++ )) ;;
      -*) ;;
      *) break ;;
    esac
  done
  (( k < n )) || return
  sub=${W[k]}
  (( D[k] )) && { ask_push "dynamic git command with push"; return; }
  sub_i=$k
  for (( j = k + 1; j < n; j++ )); do
    case ${D[j]} in
      1) args+=("$DYN${W[j]}") ;;
      2) args+=("$GLOB${W[j]}") ;;
      *) args+=("${W[j]}") ;;
    esac
  done

  case $sub in
    push|send-pack) check_push "$gdir" "$gdyn" "$cfg" 0 "${args[@]}" ;;
    subtree)
      for (( j = sub_i + 1; j < n; j++ )); do
        [[ ${W[j]} == push ]] && { check_push "$gdir" "$gdyn" "$cfg" 1 "${args[@]:j-sub_i}"; return; }
      done ;;
    submodule)  # git submodule foreach <command>
      for (( j = sub_i + 1; j < n; j++ )); do
        [[ ${W[j]} == foreach ]] && { enqueue "${W[*]:j+1}"; return; }
      done ;;
    rebase)     # git rebase -x/--exec <command>
      for (( j = sub_i + 1; j < n; j++ )); do
        case ${W[j]} in
          -x|--exec) enqueue "${W[j+1]}" ;;
          --exec=*) enqueue "${W[j]#--exec=}" ;;
        esac
      done ;;
    bisect) [[ ${W[sub_i+1]} == run ]] && enqueue "${W[*]:sub_i+2}" ;;
    add|am|apply|archive|blame|branch|bundle|cat-file|checkout|cherry|cherry-pick|clean|clone|\
    commit|config|describe|diff|difftool|fetch|for-each-ref|format-patch|fsck|gc|grep|help|init|\
    log|ls-files|ls-remote|ls-tree|merge|merge-base|mergetool|mv|notes|pull|range-diff|reflog|\
    remote|reset|restore|revert|rev-list|rev-parse|rm|shortlog|show|show-ref|sparse-checkout|\
    stash|status|switch|symbolic-ref|tag|update-ref|version|whatchanged|worktree) ;;
    *)  # alias (git does not let an alias override the built-in commands listed above)
      (( cfg )) && { ask "git command '$sub' with -c alias/remote/push"; return; }
      val=$(git -C "$gdir" config --get "alias.$sub" 2>/dev/null) || return
      if [[ $val == '!'* ]]; then
        [[ $val == *push* ]] && ask "shell alias '$sub' contains push: $val"
        return
      fi
      read -ra av <<< "$val"
      if [[ ${av[0]} == push ]]; then
        check_push "$gdir" "$gdyn" 0 0 "${av[@]:1}" "${args[@]}"
      elif [[ $val == *push* ]]; then
        ask "alias '$sub' contains push: $val"
      fi ;;
  esac
}

wrapper_scan() {  # wrapper command at index $1: find the real command after it; none found but push present → ask
  local j n=${#W[@]}
  for (( j = $1 + 1; j < n; j++ )); do
    (( D[j] )) && continue
    case ${W[j]##*/} in
      git|eval|env|watch|flock|sh|bash|zsh|dash|ksh) dispatch "$j"; return ;;
    esac
  done
  for (( j = $1 + 1; j < n; j++ )); do
    [[ ${W[j]} == *push* ]] && { ask "command '${W[$1]##*/}' contains push but cannot be analyzed"; return; }
  done
}

env_chdir() {  # $1 = directory, $2 = dynamic
  if (( $2 )); then DIR_DYN=1; else resolve_dir "$1" "$DIR"; DIR=$RD; fi
}

ENV_LONGOPTS=(split-string chdir unset argv0 ignore-environment null debug default-signal
              ignore-signal block-signal list-signal-handling help version)

env_long() {  # $1 = --name[=value] → LO = full name (getopt_long accepts a unique prefix), "" if unknown/ambiguous
  local o=${1%%=*} x m=0
  o=${o#--}; LO=""
  for x in "${ENV_LONGOPTS[@]}"; do
    [[ $x == "$o" ]] && { LO=$x; return; }
    [[ $x == "$o"* ]] && { LO=$x; (( m++ )); }
  done
  (( m == 1 )) || LO=""
}

env_cmd() {  # command string of env -S / --split-string. $1 = string, $2 = dynamic
  if (( $2 )); then ask_push "env -S / --split-string with a dynamic command"
  else enqueue "$1"; fi
}

later_has_push() {  # does any word after index $1 in W contain "push"
  local k
  for (( k = $1 + 1; k < ${#W[@]}; k++ )); do [[ ${W[k]} == *push* ]] && return 0; done
  return 1
}

runs_dynamic() {  # dynamic word at index $1 may be a push command: it is last (split, then run) or push follows it
  (( $1 + 1 >= ${#W[@]} )) || later_has_push "$1"
}

env_short() {  # short flag cluster of env at W[$1]. Returns 0 on -S (command handled); R = index of the last word used
  local w=${W[$1]} k c rest wdyn=${D[$1]:-0}
  R=$1
  for (( k = 1; k < ${#w}; k++ )); do
    c=${w:k:1}; rest=${w:k+1}
    # A dynamic part ($, glob, brace) in a flag position may expand to -S → don't guess
    if (( wdyn )) && [[ $c == [\$\?\[\*\{] ]]; then
      ask_push "env has a dynamic flag cluster: '$w'"
      return 1
    fi
    case $c in
      S) if [[ -n $rest ]]; then env_cmd "$rest" "$wdyn"; else env_cmd "${W[$1+1]}" "${D[$1+1]:-0}"; fi
         return 0 ;;
      C) if [[ -n $rest ]]; then env_chdir "$rest" "$wdyn"
         else R=$(( $1 + 1 )); env_chdir "${W[R]}" "${D[R]}"; fi
         return 1 ;;
      u|P|a) [[ -n $rest ]] || R=$(( $1 + 1 )); return 1 ;;   # flags with a value: the rest is the value
    esac
  done
  return 1
}

dispatch() {  # $1 = index of the command in W
  local i=$1 n=${#W[@]} b j k w joined dynany saved_dir saved_dyn endopt
  if (( D[i] == 1 )); then   # the command name is a variable ($c, $GIT push ...): cannot be guessed
    runs_dynamic "$i" && ask_push "dynamic command '${W[i]}' may be a push"
    return
  elif (( D[i] )); then      # the command name is a glob
    later_has_push "$i" && ask_push "glob command '${W[i]}' contains push"
    return
  fi
  b=${W[i]##*/}
  if [[ $b == git ]]; then git_call "$i"; return; fi
  if [[ $b =~ $SHELLS_RE ]]; then   # sh -c '<command>'
    dynany=0
    for (( j = i + 1; j < n; j++ )); do
      if (( !D[j] )) && [[ ${W[j]} == -*c* && ${W[j]} != --* ]]; then
        if (( D[j+1] )); then ask_push "sh -c with a dynamic command"
        else enqueue "${W[j+1]}"; fi
        return
      fi
      (( D[j] )) && dynany=1
    done
    # A dynamic argument may be "-c" (bash $X '<command>') → ask if push follows
    (( dynany )) && later_has_push "$i" && ask_push "shell with dynamic arguments contains push"
    return
  fi
  if [[ $b == eval ]]; then
    joined=""; dynany=0
    for (( j = i + 1; j < n; j++ )); do joined+="${W[j]} "; (( D[j] )) && dynany=1; done
    (( dynany )) && ask_push "eval with variables"
    enqueue "$joined"
    return
  fi
  case $b in
    env)  # env [-i] [-u X] [-C dir] [-S '<command>'] [VAR=x] <command>
      saved_dir=$DIR; saved_dyn=$DIR_DYN; endopt=0
      for (( j = i + 1; j < n; j++ )); do
        w=${W[j]}
        if (( !endopt )); then
          case $w in
            --) endopt=1; continue ;;   # after "--" there may still be VAR=x before the command
            --?*)
              env_long "$w"
              case $LO in
                split-string)
                  if [[ $w == *=* ]]; then env_cmd "${w#*=}" "${D[j]}"
                  else env_cmd "${W[j+1]}" "${D[j+1]:-0}"; fi
                  break ;;
                chdir) if [[ $w == *=* ]]; then env_chdir "${w#*=}" "${D[j]}"
                       else (( j++ )); env_chdir "${W[j]}" "${D[j]}"; fi ;;
                unset|argv0) [[ $w == *=* ]] || (( j++ )) ;;
                '') ask_push "env has an unknown or ambiguous abbreviated option: '$w'" ;;
              esac   # the remaining options take no value from the next word
              continue ;;
            -[!-]*) env_short "$j" && break; j=$R; continue ;;   # short flag cluster: -iS '<command>', -iC dir, -u X
          esac
        fi
        # A dynamic word that is not VAR=...: may be an option (-S), an assignment or the command → ask, then continue
        if (( D[j] )) && ! [[ $w =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
          runs_dynamic "$j" && ask_push "env has a dynamic argument: '$w'"
          continue
        fi
        [[ $w == *=* ]] && continue
        dispatch "$j"; break
      done
      DIR=$saved_dir; DIR_DYN=$saved_dyn ;;
    watch)  # watch runs its arguments via sh -c
      for (( j = i + 1; j < n; j++ )); do
        case ${W[j]} in
          -n|--interval|-q|--equexit) (( j++ )) ;;
          -*) ;;
          *) enqueue "${W[*]:j}"; break ;;
        esac
      done ;;
    flock)  # flock [opts] <file> -c '<command>' | flock [opts] <file> <command> ...
      for (( j = i + 1; j < n; j++ )); do
        case ${W[j]} in
          -c|--command) enqueue "${W[j+1]}"; return ;;
          --command=*) enqueue "${W[j]#*=}"; return ;;
        esac
      done
      wrapper_scan "$i" ;;
    sudo|doas|timeout|nice|ionice|nohup|stdbuf|caffeinate|unbuffer|xargs|parallel|find)
      [[ $b == xargs || $b == parallel || $b == find ]] && APPEND=1
      wrapper_scan "$i"
      APPEND=0 ;;
    # Commands that treat their arguments as data
    echo|printf|grep|egrep|fgrep|rg|ag|cat|head|tail|less|more|sed|awk|tee|wc|sort|uniq|tr|cut|\
    jq|yq|column|diff|test|'['|'[['|true|false|:|read|export|local|declare|set|unset|alias|\
    type|which|man|gh|glab) ;;
    *)  # unknown command followed by "git ... push": it may run it for us (ssh, script runners...) → ask
      for (( j = i + 1; j < n; j++ )); do
        [[ ${W[j]##*/} == git ]] || continue
        for (( k = j + 1; k < n; k++ )); do
          [[ ${W[k]} == push ]] && { ask "command '$b' may run git push"; return; }
        done
        return
      done ;;
  esac
}

analyze() {
  local n=${#W[@]} i=0 j=1
  (( n )) || return
  case ${W[0]} in
    cd|pushd)   # inside a pipeline, cd runs in a subshell and does not change the directory
      (( SEG_PIPE )) && return
      while [[ ${W[j]} == -[PLen@]* ]]; do (( j++ )); done
      if (( j >= n )); then
        if [[ ${W[0]} == cd ]]; then DIR=$HOME; DIR_DYN=0; else DIR_DYN=1; fi
      elif (( D[j] )) || [[ ${W[j]} == - || ${W[j]} == [+-][0-9]* ]]; then
        DIR_DYN=1   # cd -, pushd +N, variable: the new directory is unknown
      else
        resolve_dir "${W[j]}" "$DIR"; DIR=$RD
      fi
      return ;;
    popd) (( SEG_PIPE )) || DIR_DYN=1; return ;;
  esac
  # Skip variable assignments and shell keywords before the command
  while (( i < n )); do
    if [[ ${W[i]} =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then (( i++ )); continue; fi
    case ${W[i]} in
      if|then|else|elif|do|while|until|'!'|'{'|'}'|time|command|builtin|exec) (( i++ )); continue ;;
    esac
    break
  done
  (( i < n )) && dispatch "$i"
}

# ---------- Split the command using shell syntax ----------
# Uses the variables of tokenize (s, n, word, dyn, inword) through bash dynamic scoping.

end_word() {
  if (( inword )); then
    if (( hs )); then    # here-string: runs only when fed to a shell
      local w
      for w in "${W[@]}"; do [[ ${w##*/} =~ $SHELLS_RE ]] && { enqueue "$word"; break; }; done
      hs=0
    elif (( skipnext )); then
      skipnext=0         # redirect target, not an argument
    else
      # unquoted glob (?, [, *) → 2: still check the literal, but ask; "[" / "[[" is the test command
      (( glob && !dyn )) && [[ $word != '[' && $word != '[[' ]] && dyn=2
      # case ... esac: the ")" of a pattern is not a subshell. It is a keyword only when unquoted/unescaped
      # and in command position (start of a command or after then/do/{...)
      if (( !quoted && !dyn )) && at_command_pos; then
        if [[ $word == case ]]; then ds_kind+=(c); ds_dir+=(""); ds_dyn+=(0); case_wait_in=1
        elif [[ $word == esac ]] && (( ${#ds_kind[@]} )) && [[ ${ds_kind[${#ds_kind[@]}-1]} == c ]]; then
          ds_pop; in_pat=0
        fi
      elif (( case_wait_in && !quoted && !dyn )) && [[ $word == in ]]; then
        case_wait_in=0; in_pat=1   # the first pattern starts: "|" means "or", not a pipe
      fi
      W+=("$word"); D+=("$dyn"); Q+=("$quoted")
      [[ $word == *push* ]] && HAS_PUSH=1   # after unquoting: pu""sh, pu\sh
    fi
  fi
  word=""; inword=0; dyn=0; glob=0; quoted=0
}

at_command_pos() {  # every earlier word is a real shell keyword (unquoted, not dynamic)
  local k
  for k in "${!W[@]}"; do
    (( Q[k] || D[k] )) && return 1
    case ${W[k]} in if|then|else|elif|do|while|until|'!'|'{'|time) ;; *) return 1 ;; esac
  done
  return 0
}

ds_pop() {  # pop the top of the parenthesis / case stack
  local top=$(( ${#ds_kind[@]} - 1 ))
  unset "ds_kind[top]" "ds_dir[top]" "ds_dyn[top]"
}

end_seg() {  # $1 = 1 if the command ends with "|"
  end_word
  SEG_PIPE=$(( ${1:-0} || pipe_prev )); pipe_prev=${1:-0}
  analyze
  W=(); D=(); Q=(); skipnext=0; hs=0
}

hd_delim_at() {  # $1 = index right after "<<" → HD = delimiter, HD_STRIP, R = end index
  local j=$1 c
  HD=""; HD_STRIP=0
  [[ ${s:j:1} == '-' ]] && { HD_STRIP=1; (( j++ )); }
  while [[ ${s:j:1} == [' '$'\t'] ]]; do (( j++ )); done
  while (( j < n )); do
    c=${s:j:1}
    case $c in
      ' '|$'\t'|$'\n'|';'|'&'|'|'|'<'|'>'|'('|')') break ;;
      \'|\"|\\) ;;
      *) HD+=$c ;;
    esac
    (( j++ ))
  done
  R=$j
}

hd_body_at() {  # $1 = start of the body, $2 = delimiter, $3 = strip tabs → HB = body, R = index after the delimiter
  local pos=$1 r l cmpl
  HB=""
  while (( pos < n )); do
    r=${s:pos}; l=${r%%$'\n'*}; (( pos += ${#l} + 1 ))
    cmpl=$l; (( $3 )) && cmpl=${cmpl#"${cmpl%%[!$'\t']*}"}
    [[ $cmpl == "$2" ]] && break
    HB+=$l$'\n'
  done
  R=$pos
}

match_paren() {  # $1 = index right after "(" → R = index of the matching ")" (skipping quotes and heredoc bodies)
  local j=$1 depth=1 c r k
  local -a hds=() hdstrip=()
  while (( j < n )); do
    c=${s:j:1}
    case $c in
      '<') if [[ ${s:j+1:1} == '<' && ${s:j+2:1} != '<' ]]; then
             hd_delim_at $((j + 2)); hds+=("$HD"); hdstrip+=("$HD_STRIP"); j=$R; continue
           fi ;;
      $'\n') if (( ${#hds[@]} )); then
               R=$((j + 1))
               for k in "${!hds[@]}"; do hd_body_at "$R" "${hds[k]}" "${hdstrip[k]}"; done
               j=$((R - 1)); hds=(); hdstrip=()
             fi ;;
      \\) (( j++ )) ;;
      \') r=${s:j+1}; [[ $r == *\'* ]] || { R=$n; return; }; r=${r%%\'*}; (( j += ${#r} + 1 )) ;;
      \") (( j++ ))
          while (( j < n )) && [[ ${s:j:1} != \" ]]; do [[ ${s:j:1} == \\ ]] && (( j++ )); (( j++ )); done ;;
      \() (( depth++ )) ;;
      \)) (( --depth == 0 )) && { R=$j; return; } ;;
    esac
    (( j++ ))
  done
  R=$n
}

scan_backtick() {  # $1 = index right after "`" → R = index of the closing "`"
  local j=$1
  while (( j < n )) && [[ ${s:j:1} != '`' ]]; do [[ ${s:j:1} == \\ ]] && (( j++ )); (( j++ )); done
  enqueue "${s:$1:j-$1}"; dyn=1; word+='$'; inword=1; R=$j
}

scan_dollar() {  # $1 = index of "$" → R = last character handled
  local j=$1 nx=${s:$1+1:1} inner r
  inword=1
  case $nx in
    \()
      match_paren $((j + 2)); inner=${s:j+2:R-j-2}
      if [[ $inner =~ $HEAD_RE ]]; then word+=HEAD
      else enqueue "$inner"; dyn=1; word+='$'; fi ;;
    \{)
      r=${s:j+2}; r=${r%%\}*}; enqueue "$r"; dyn=1; word+='$'; R=$((j + 2 + ${#r})) ;;
    \")  # $"..." (locale-translated string): same as a double-quoted string
      scan_dquote $((j + 2)) ;;
    \')  # $'...': still treated as dynamic, but decode escapes to see whether it spells push
      dyn=1; word+='$'; (( j += 2 ))
      while (( j < n )) && [[ ${s:j:1} != \' ]]; do [[ ${s:j:1} == \\ ]] && (( j++ )); (( j++ )); done
      r=${s:$1+2:j-$1-2}; printf -v r '%b' "$r" 2>/dev/null
      [[ $r == *push* ]] && HAS_PUSH=1
      R=$j ;;
    [A-Za-z0-9_@*#?\$!-])
      dyn=1; word+='$'; R=$j ;;
    *) word+='$'; R=$j ;;
  esac
}

scan_dquote() {  # $1 = index right after '"' → R = index of the closing '"'
  local j=$1 c nx
  inword=1; quoted=1
  while (( j < n )); do
    c=${s:j:1}
    case $c in
      \") R=$j; return ;;
      \\) nx=${s:j+1:1}
          case $nx in '$'|'`'|\"|\\) word+=$nx; (( j++ )) ;; $'\n') (( j++ )) ;; *) word+=$c ;; esac ;;
      '$') scan_dollar "$j"; j=$R ;;
      '`') scan_backtick $((j + 1)); j=$R ;;
      *) word+=$c ;;
    esac
    (( j++ ))
  done
  R=$n
}

tokenize() {
  local s=$1 n=${#1} i=0 c nx r line_start=0 k exec pipe_prev=0 top glob=0 quoted=0 in_pat=0 case_wait_in=0
  local -a hd_delim=() hd_strip=() ds_kind=() ds_dir=() ds_dyn=()
  W=(); D=(); Q=(); word=""; inword=0; dyn=0; skipnext=0; hs=0
  while (( i < n )); do
    c=${s:i:1}
    case $c in
      ' '|$'\t') end_word ;;
      $'\n')
        end_seg
        if (( ${#hd_delim[@]} )); then   # read the heredoc bodies
          exec=0; [[ ${s:line_start:i-line_start} =~ $EXEC_RE ]] && exec=1
          R=$((i + 1))
          for k in "${!hd_delim[@]}"; do
            hd_body_at "$R" "${hd_delim[k]}" "${hd_strip[k]}"
            (( exec )) && enqueue "$HB"
          done
          hd_delim=(); hd_strip=(); i=$((R - 1))
        fi
        line_start=$((i + 1)) ;;
      ';') end_seg
           if [[ ${s:i+1:1} == [\;\&] ]]; then   # ;; ;& ;;& end a case branch → a pattern follows
             (( i++ )); [[ ${s:i+1:1} == '&' ]] && (( i++ ))
             (( ${#ds_kind[@]} )) && [[ ${ds_kind[${#ds_kind[@]}-1]} == c ]] && in_pat=1
           fi ;;
      '(') if (( in_pat )); then end_word     # "(" opening a pattern: case x in (a|b) ...
           else end_seg; ds_kind+=(p); ds_dir+=("$DIR"); ds_dyn+=("$DIR_DYN"); fi ;;   # subshell: a cd inside does not leak out
      ')') end_word
           top=$(( ${#ds_kind[@]} - 1 ))
           if (( top >= 0 )) && [[ ${ds_kind[top]} == c ]]; then
             # ")" ends a case pattern: the pattern is not a command
             W=(); D=(); Q=(); skipnext=0; hs=0; in_pat=0; pipe_prev=0
           else
             end_seg
             if (( top < 0 )); then DIR_DYN=1       # unbalanced parenthesis: stop trusting the directory
             else DIR=${ds_dir[top]}; DIR_DYN=${ds_dyn[top]}; ds_pop; fi
           fi ;;
      '&')
        nx=${s:i+1:1}
        if [[ $nx == '>' ]]; then   # &> file
          end_word; skipnext=1; (( i++ )); [[ ${s:i+1:1} == '>' ]] && (( i++ ))
        else
          end_seg; [[ $nx == '&' ]] && (( i++ ))
        fi ;;
      '|') nx=${s:i+1:1}
           if (( in_pat )); then end_word   # "a|b)" inside case: "or"
           elif [[ $nx == '|' ]]; then end_seg; (( i++ ))
           else end_seg 1; [[ $nx == '&' ]] && (( i++ )); fi ;;
      '<'|'>')
        nx=${s:i+1:1}
        if [[ $nx == '(' ]]; then   # process substitution
          match_paren $((i + 2)); enqueue "${s:i+2:R-i-2}"; inword=1; dyn=1; word+='$'; i=$R
        elif [[ $c$nx == '<<' && ${s:i+2:1} == '<' ]]; then   # here-string
          end_word; hs=1; (( i += 2 ))
        elif [[ $c$nx == '<<' ]]; then   # heredoc: record the delimiter; the body is read at the end of the line
          end_word; hd_delim_at $((i + 2))
          hd_delim+=("$HD"); hd_strip+=("$HD_STRIP"); i=$R
          continue
        else   # redirect: drop the fd number before it and the target after it
          [[ $word =~ ^[0-9]+$ ]] && (( !dyn )) && { word=""; inword=0; }
          end_word
          while [[ ${s:i+1:1} == [\<\>\&\|] ]]; do (( i++ )); done
          skipnext=1
        fi ;;
      \\) nx=${s:i+1:1}; (( i++ )); [[ $nx == $'\n' ]] || { word+=$nx; inword=1; quoted=1; } ;;
      \')
        r=${s:i+1}; [[ $r == *\'* ]] && r=${r%%\'*}
        word+=$r; inword=1; quoted=1; (( i += ${#r} + 1 )) ;;
      \") scan_dquote $((i + 1)); i=$R ;;
      '$') scan_dollar "$i"; i=$R ;;
      '`') scan_backtick $((i + 1)); i=$R ;;
      '#') if (( inword )); then word+=$c
           else r=${s:i}; r=${r%%$'\n'*}; (( i += ${#r} - 1 )); fi ;;
      '?'|'['|'*')   # unquoted glob: the shell may expand it from files in the directory
        glob=1; word+=$c; inword=1 ;;
      '{')       # brace expansion {a,b} / {a..b}
        r=${s:i+1}; r=${r%%\}*}
        [[ $r != *[[:space:]]* && ( $r == *,* || $r == *..* ) ]] && dyn=1
        word+=$c; inword=1 ;;
      *) word+=$c; inword=1 ;;
    esac
    (( i++ ))
  done
  end_seg
}

QUEUE=(); QDIR=(); QDYN=()
enqueue "$cmd"
for (( qi = 0; qi < ${#QUEUE[@]} && qi < 64; qi++ )); do
  DIR=${QDIR[qi]}; DIR_DYN=${QDYN[qi]}
  tokenize "${QUEUE[qi]}"
done
# Limit reached with sub-commands still unchecked → don't let it through silently
(( qi < ${#QUEUE[@]} )) && ask_push "command has too many nested levels to check"
(( HAS_PUSH )) && [[ -n $PENDING ]] && ask "$PENDING"

if [[ -n $ASK ]]; then
  jq -cn --arg r "git-guard: $ASK — please confirm this push command." \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"ask",permissionDecisionReason:$r}}'
fi
exit 0
