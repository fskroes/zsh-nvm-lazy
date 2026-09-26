#!/usr/bin/env zsh
# Parity test: after the plugin loads, the shell must be the same as after
# `source nvm.sh`. Each case builds a fake NVM_DIR (node binaries are small
# scripts that print their version) and runs two clean shells, one with real
# nvm.sh and one with the plugin, then compares PATH, NVM_BIN, NVM_INC,
# MANPATH and `node --version`. It then runs nvm commands in both shells
# and compares that output as well.
#
# Needs a real nvm.sh: $NVM_SH, else ~/.nvm/nvm.sh. No network.
emulate zsh
setopt extended_glob no_unset pipe_fail

here=${0:A:h}
plugin=${PLUGIN:-${here:h}/zsh-nvm-lazy.plugin.zsh}
nvm_sh=${NVM_SH:-$HOME/.nvm/nvm.sh}
[[ -r $nvm_sh ]] || { print "SKIP: parity: no nvm.sh found (set NVM_SH)"; exit 0 }
[[ -r $plugin ]] || { print "FAIL: parity: no plugin at $plugin"; exit 1 }
nvm_comp=${nvm_sh:h}/bash_completion
nvm_version=$(sed -n "s/^ *nvm_echo '\([0-9.]*\)'$/\1/p" $nvm_sh | head -1)

tmp=$(mktemp -d "${TMPDIR:-/tmp}/nvm-lazy-parity.XXXXXX")
trap 'rm -rf -- $tmp' EXIT
sys=/usr/bin:/bin   # sed, awk, grep and manpath for nvm.sh

# mk DIR VERSION... : a fake NVM_DIR with these node versions installed.
mk() {
  local d=$1 v; shift
  mkdir -p $d/alias
  ln -s $nvm_sh $d/nvm.sh
  [[ -r $nvm_comp ]] && ln -s $nvm_comp $d/bash_completion
  for v in $@; do
    mkdir -p $d/versions/node/$v/{bin,include/node,share/man/man1}
    print -r -- "#!/bin/sh
echo $v" > $d/versions/node/$v/bin/node
    chmod +x $d/versions/node/$v/bin/node
  done
}
# al DIR NAME CONTENT : write alias NAME (for example default or lts/krypton).
al() { mkdir -p ${1}/alias/${2:h}; print -r -- $3 > $1/alias/$2 }
bin() { print -r -- $1/versions/node/$2/bin }

# The probe runs in each clean shell. MODE is eager or plugin.
cat > $tmp/probe.zsh <<'EOF'
if [[ $MODE == eager ]]; then source $NVM_DIR/nvm.sh; else source $PLUGIN; fi
print -r -- "PATH=$PATH"
print -r -- "NVM_BIN=${NVM_BIN-<unset>}"
print -r -- "NVM_INC=${NVM_INC-<unset>}"
print -r -- "MANPATH=${MANPATH-<unset>}"
# The type shows export and the zsh MANPATH/manpath tie; ${#manpath} shows () vs ('').
print -r -- "types=${(t)PATH-} ${(t)NVM_BIN-} ${(t)NVM_INC-} ${(t)MANPATH-} manpath=${#manpath}"
print -r -- "node=$(whence -p node) $(node --version 2>&1)"
print -r -- "nvm-is=$(whence -w nvm)"
print -r -- "LOADED=$+functions[nvm_ls_current]"
[[ -n ${AFTER-} ]] && eval "$AFTER"
EOF

# After startup: nvm must work in the same way in both shells.
after_std='print -- "--- after"
nvm current; print "rc=$?"
nvm bogus-command >/dev/null 2>&1; print "rc=$?"
nvm ls --no-colors --no-alias 2>&1
print -r -- "PATH=$PATH"
print -r -- "nvm-is=$(whence -w nvm)"'

typeset -a names
typeset -A dir cpath cman cwd expect after
# add NAME DIR PATH MANPATH(or -) EXPECT(fast|any) [AFTER]
add() {
  names+=$1; dir[$1]=$2; cpath[$1]=$3; cman[$1]=$4; expect[$1]=$5
  after[$1]=${6-$after_std}; cwd[$1]=$tmp
}

n() { print -r -- $tmp/$1/nvm }   # fixture dir for a case

# --- default alias forms -------------------------------------------------
d=$(n exact);   mk $d v20.5.0 v22.1.0;  al $d default v22.1.0
add exact $d "$sys" - fast "$after_std
nvm use --silent v20.5.0; print -r -- \"PATH=\$PATH\"; print -r -- \"NVM_BIN=\$NVM_BIN\""
d=$(n major);   mk $d v20.0.0 v22.1.0 v22.10.0 v22.9.3; al $d default 22
add major $d "$sys" - fast
d=$(n vmajor);  mk $d v22.1.0 v22.10.0; al $d default v22
add vmajor $d "$sys" - fast
d=$(n minor);   mk $d v22.1.0 v22.1.5 v22.10.0; al $d default 22.1
add minor $d "$sys" - fast
d=$(n boundary); mk $d v2.0.0 v22.0.0; al $d default 2
add boundary $d "$sys" - fast
d=$(n comment); mk $d v20.0.0 v22.1.0
print -r -- $'\n22   # pinned by me   \n20\n' > $d/alias/default
add comment $d "$sys" - fast
d=$(n lts);     mk $d v22.1.0 v24.1.0; al $d default 'lts/*'; al $d 'lts/*' lts/krypton
al $d lts/krypton v24.1.0; al $d lts/jod v22.1.0
add lts $d "$sys" - fast
d=$(n ltsname); mk $d v22.1.0 v24.1.0; al $d default lts/jod; al $d lts/jod v22.1.0
add ltsname $d "$sys" - fast
d=$(n chain);   mk $d v20.0.0 v22.1.0; al $d default mine; al $d mine 20
add chain $d "$sys" - fast
d=$(n node);    mk $d v20.0.0 v24.1.0 v22.1.0; al $d default node
add node $d "$sys" - any
d=$(n stable);  mk $d v20.0.0 v24.1.0; al $d default stable
add stable $d "$sys" - any
d=$(n system);  mk $d v20.0.0; al $d default system
add system $d "$sys" - any
d=$(n loop);    mk $d v20.0.0; al $d default a; al $d a default
add loop $d "$sys" - any
d=$(n missing); mk $d v20.0.0; al $d default v18.0.0
add missing $d "$sys" - fast
d=$(n nodefault); mk $d v20.0.0
add nodefault $d "$sys" - fast
d=$(n nvmrc);   mk $d v20.0.0 v22.1.0; mkdir -p $tmp/nvmrc/proj/sub; print 20 > $tmp/nvmrc/proj/.nvmrc
add nvmrc $d "$sys" - fast; cwd[nvmrc]=$tmp/nvmrc/proj/sub
d=$(n empty);   mk $d v20.0.0; : > $d/alias/default
add empty $d "$sys" - fast

# --- PATH already holds node ---------------------------------------------
d=$(n inherit); mk $d v20.0.0 v22.1.0; al $d default 22
add inherit $d "$(bin $d v20.0.0):$sys" - fast
d=$(n sysfirst); mk $d v20.0.0 v22.1.0; al $d default 22
add sysfirst $d "/usr/bin:/bin:$(bin $d v20.0.0)" - fast
d=$(n stale2);  mk $d v22.1.0; al $d default 22
add stale2 $d "$(bin $d v19.0.0):/opt/x/bin:$(bin $d v18.0.0):$sys" - fast
d=$(n sysnode); mk $d v22.1.0; al $d default 22; mkdir -p $tmp/sysnode/bin
print '#!/bin/sh\necho v99.0.0-system' > $tmp/sysnode/bin/node; chmod +x $tmp/sysnode/bin/node
add sysnode $d "$tmp/sysnode/bin:$sys" - fast
d=$(n legacy);  mk $d v22.1.0; al $d default 22; mkdir -p $d/v0.10.0/bin
add legacy $d "$d/v0.10.0/bin:$sys" - fast
# The same, with a node in the old layout: that node is current, so nvm.sh decides.
d=$(n legacynode); mk $d v22.1.0; al $d default 22; mkdir -p $d/v0.10.0/bin
print '#!/bin/sh\necho v0.10.0' > $d/v0.10.0/bin/node; chmod +x $d/v0.10.0/bin/node
add legacynode $d "$d/v0.10.0/bin:$sys" - any

# --- MANPATH -------------------------------------------------------------
d=$(n man);     mk $d v20.0.0 v22.1.0; al $d default 22
add man $d "$sys" "/usr/share/man:/opt/x/share/man" fast
d=$(n manold);  mk $d v20.0.0 v22.1.0; al $d default 22
add manold $d "$sys" "$d/versions/node/v20.0.0/share/man:/usr/share/man" fast
d=$(n manempty); mk $d v22.1.0; al $d default 22
add manempty $d "$sys" "" fast   # exported, but empty

# --- odd places ----------------------------------------------------------
d="$tmp/space dir/nvm"; mk $d v22.1.0; al $d default 22
add space $d "$sys" - fast
# nvm puts NVM_DIR into grep and sed patterns unescaped: [ ] change its match.
d="$tmp/br[16]/nvm"; mk $d v22.1.0; al $d default 22
add brackets $d "$sys" - any
d="$tmp/br2[16]/nvm"; mk $d v20.5.0 v22.1.0; al $d default 22
add brackets-inherit $d "$(bin $d v20.5.0):$sys" - any

# PARITY_CASES="exact lts" runs only those cases (the pre-commit hook uses this).
if [[ -n ${PARITY_CASES-} ]]; then
  for c in ${(s: :)PARITY_CASES}; do
    (( ${names[(Ie)$c]} )) || { print "FAIL: PARITY_CASES: no case named $c"; exit 1 }
  done
  names=(${(s: :)PARITY_CASES})
fi

# Run every case twice (eager, plugin), all in parallel.
run() {  # run CASE MODE
  local c=$1 m=$2 o=$tmp/out/$1.$2
  local -a e=(HOME=$tmp/home PATH=${cpath[$c]} NVM_DIR=${dir[$c]} PLUGIN=$plugin
              MODE=$m AFTER=${after[$c]} TERM=dumb)
  [[ ${cman[$c]} != - ]] && e+=(MANPATH=${cman[$c]})
  ( cd ${cwd[$c]} && env -i $e /bin/zsh -f $tmp/probe.zsh >$o.out 2>$o.err )
}
mkdir -p $tmp/out $tmp/home $tmp/nonvm
# Extra checks, one clean shell each: xtra NAME NVM_DIR CODE
xtra() { env -i HOME=$tmp/home PATH=$sys NVM_DIR=$2 /bin/zsh -f -c $3 >$tmp/out/x.$1 2>&1 }
d=$(n major)
xtra nonvm $tmp/nonvm "source ${(q)plugin}; print -r -- \"\$PATH|\$+functions[nvm]\"" &
xtra nounset $d "setopt no_unset; source ${(q)plugin} && print ok" &
xtra loaded $d "source \$NVM_DIR/nvm.sh; p=\$PATH; source ${(q)plugin}; [[ \$PATH == \$p ]] && print -r -- \$+functions[nvm_ls_current]" &
[[ -r $nvm_comp ]] && xtra comp $d "
  autoload -U compinit; compinit -u -D
  source ${(q)plugin}; print -r -- \"before=\${+_comps[nvm]}\"
  nvm --version >/dev/null; print -r -- \"after=\$_comps[nvm]\"" &
# Homebrew: nvm.sh and its completion live outside NVM_DIR, in $NVM_HOMEBREW.
if [[ -r $nvm_comp ]]; then
  hb=$tmp/brew/opt/nvm; mkdir -p $hb/etc/bash_completion.d $tmp/brewdir/alias
  ln -s $nvm_sh $hb/nvm.sh; ln -s $nvm_comp $hb/etc/bash_completion.d/nvm
  xtra brew $tmp/brewdir "export NVM_HOMEBREW=$hb
    autoload -U compinit; compinit -u -D
    source ${(q)plugin}; print -r -- \"before=\${+_comps[nvm]}\"
    nvm --version >/dev/null; print -r -- \"rc=\$? after=\$_comps[nvm]\"" &
fi
for c in $names; do run $c eager & run $c plugin & done
wait

fail=0 fast=0
for c in $names; do
  o=$tmp/out/$c
  if [[ -s $o.plugin.err ]]; then
    print "FAIL: $c: plugin wrote to stderr:"; sed 's/^/    /' $o.plugin.err; fail=1; continue
  fi
  loaded=${${(M)${(f)"$(<$o.plugin.out)"}:#LOADED=*}#LOADED=}
  a=("${(@f)$(grep -v '^LOADED=' $o.eager.out)}")
  b=("${(@f)$(grep -v '^LOADED=' $o.plugin.out)}")
  if [[ ${(F)a} != ${(F)b} ]]; then
    print "FAIL: $c: plugin differs from nvm.sh (loaded=$loaded)"
    diff <(print -rl -- $a) <(print -rl -- $b) | sed 's/^/    /'; fail=1; continue
  fi
  if [[ ${expect[$c]} == fast && $loaded != 0 ]]; then
    print "FAIL: $c: plugin loaded nvm.sh at startup, the fast path must handle this case"; fail=1; continue
  fi
  (( loaded == 0 )) && (( fast++ ))
  print "ok: $c (${${loaded:#0}:+nvm.sh loaded at startup}${${loaded:#1}:+fast path})"
done

# check NAME EXPECTED MESSAGE
check() {
  local out=$(<$tmp/out/x.$1)
  [[ $out == $2 ]] && print "ok: $3" || { print "FAIL: $3: got:"; print -r -- $out | sed 's/^/    /'; fail=1 }
}
check nonvm "$sys|0" "no nvm installed: silent, nothing defined"
check nounset ok "works with setopt no_unset"
check loaded 1 "nvm already loaded: plugin changes nothing"
[[ -r $nvm_comp ]] && check comp $'before=1\nafter=_bash_complete -o default -F __nvm' \
  "completion: stub at startup, nvm's own after first use"
[[ -r $nvm_comp ]] && check brew $'before=1\nrc=0 after=_bash_complete -o default -F __nvm' \
  "Homebrew nvm: nvm.sh and completion found in NVM_HOMEBREW"

print "parity: ${#names} cases against nvm $nvm_version, $fast on the fast path"
exit $fail
