#!/usr/bin/env zsh
# Startup cost of nvm, measured against your real nvm install:
#   `source nvm.sh`  vs  this plugin, and the time to the first `node --version`.
# Usage: zsh tests/bench.zsh [runs]   (default 30)
emulate zsh
zmodload zsh/datetime

plugin=${PLUGIN:-${0:A:h:h}/zsh-nvm-lazy.plugin.zsh}
nvm_dir=${NVM_DIR:-$HOME/.nvm}
runs=${1:-30}
[[ -r $nvm_dir/nvm.sh ]] || { print "no nvm.sh in $nvm_dir"; exit 1 }

# Each run is a clean shell. It prints its own time in microseconds.
measure() {  # measure LABEL CODE
  local -a t; local i
  for i in {1..$runs}; do
    t+=$(env -i HOME=$HOME PATH=/usr/bin:/bin NVM_DIR=$nvm_dir /bin/zsh -f -c "
      zmodload zsh/datetime; s=\$EPOCHREALTIME
      $2
      integer us=\$(( (EPOCHREALTIME - s) * 1000000 )); print \$us")
  done
  t=(${(on)t})
  printf '%-34s median %7.1f ms   min %7.1f ms\n' $1 $(( t[(${#t} + 1) / 2] / 1000.0 )) $(( t[1] / 1000.0 ))
}

print "nvm in $nvm_dir, $runs runs each, zsh $ZSH_VERSION"
measure 'source nvm.sh'                  'source $NVM_DIR/nvm.sh'
measure 'plugin'                         "source ${(q)plugin}"
measure 'source nvm.sh + node --version' 'source $NVM_DIR/nvm.sh; node --version >/dev/null'
measure 'plugin + node --version'        "source ${(q)plugin}; node --version >/dev/null"
measure 'plugin + first nvm call'        "source ${(q)plugin}; nvm --version >/dev/null"
