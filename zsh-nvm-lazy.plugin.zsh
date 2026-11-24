() {
emulate -L zsh
setopt local_options extended_glob

(( $+functions[nvm] )) && return 0

if [[ -z $NVM_DIR ]]; then
  if [[ -d $HOME/.nvm ]]; then
    NVM_DIR=$HOME/.nvm
  elif [[ -d ${XDG_CONFIG_HOME:-$HOME/.config}/nvm ]]; then
    NVM_DIR=${XDG_CONFIG_HOME:-$HOME/.config}/nvm
  else
    return 0
  fi
  export NVM_DIR
else
  NVM_DIR=${NVM_DIR%/}
fi

local -a hbroots
hbroots=(${NVM_HOMEBREW:+$NVM_HOMEBREW} ${HOMEBREW_PREFIX:+$HOMEBREW_PREFIX/opt/nvm} /opt/homebrew/opt/nvm /usr/local/opt/nvm)
local nvmsh="$NVM_DIR/nvm.sh" _r
if [[ ! -f $nvmsh ]]; then
  nvmsh=""
  for _r in "${hbroots[@]}"; do [[ -f "$_r/nvm.sh" ]] && { nvmsh="$_r/nvm.sh"; break }; done
fi
[[ -n $nvmsh ]] || return 0

local fellback=0 target_version=""

[[ $NVM_DIR == *[][\\*^\$+?\(\){}\|\#]* ]] && fellback=1

local _d nodebin=""
for _d in $path; do
  if [[ -f "$_d/node" && -x "$_d/node" ]]; then nodebin="$_d/node"; break; fi
done
if [[ -n $nodebin && $nodebin == "$NVM_DIR"/versions/node/v[0-9]##.[0-9]##.[0-9]##/bin/node ]]; then
  target_version=${nodebin#"$NVM_DIR"/versions/node/}
  target_version=${target_version%/bin/node}
elif [[ -n $nodebin && $nodebin == "$NVM_DIR"/* ]]; then
  fellback=1
fi

if [[ -z $target_version && $fellback == 0 ]]; then
  local -A seen
  local cur=default resolved="" hop=0
  seen[$cur]=1
  while (( hop++ < 64 )); do
    local afile="$NVM_DIR/alias/$cur" line="" got=0 raw=""
    [[ -f $afile ]] || break
    while IFS= read -r raw; do
      raw=${raw%%\#*}
      raw=${raw%%[[:space:]]#}
      [[ -n $raw ]] || continue
      line=$raw; got=1; break
    done < "$afile"
    (( got )) || break
    if (( $+seen[$line] )); then fellback=1; break; fi
    seen[$line]=1
    cur=$line
  done
  [[ $cur != default ]] && resolved=$cur

  if [[ -z $resolved && $fellback == 0 ]]; then
    local dir=$PWD nvmrc=""
    while [[ -n $dir && $dir != . && ! -f "$dir/.nvmrc" ]]; do
      dir=${dir%/*}
    done
    if [[ -f "$dir/.nvmrc" ]]; then nvmrc="$dir/.nvmrc"
    elif [[ -e "$dir/.nvmrc" ]]; then fellback=1
    fi
    if [[ -n $nvmrc ]]; then
      local -a kept rlines
      local content raw2
      content=$(<$nvmrc)
      rlines=(${(f)content})
      for raw2 in "${rlines[@]}"; do
        raw2=${raw2%%\#*}
        raw2=${raw2##[[:space:]]#}
        raw2=${raw2%%[[:space:]]#}
        [[ -n $raw2 ]] && kept+=("$raw2")
      done
      if (( ${#kept} == 1 )) && [[ ${kept[1]} != *=* ]]; then
        resolved=${kept[1]}
      elif (( ${#kept} > 1 )); then
        fellback=1
      fi
    fi
  fi

  if [[ -n $resolved && $fellback == 0 ]]; then
    local p=$resolved
    [[ $p == [0-9]* ]] && p="v$p"
    if [[ $p != v[0-9]* ]]; then
      fellback=1
    else
      local core=${p#v}
      local -a segs; segs=(${(s:.:)core})
      local seg bad=0
      for seg in "${segs[@]}"; do [[ $seg == [0-9]## ]] || bad=1; done
      if (( bad )) || (( ${#segs} < 1 || ${#segs} > 3 )); then
        fellback=1
      elif (( ${#segs} == 3 )); then
        [[ -d "$NVM_DIR/versions/node/$p" ]] && target_version=$p
      else
        local -a instdirs
        instdirs=("$NVM_DIR"/versions/node/v[0-9]##.[0-9]##.[0-9]##(N/))
        local cand bmaj=-1 bmin=-1 bpat=-1
        for cand in "${instdirs[@]}"; do
          local name=${cand:t}
          [[ $name == v${core}.* ]] || continue
          local -a parts; parts=(${(s:.:)${name#v}})
          if (( parts[1] > bmaj || (parts[1] == bmaj && parts[2] > bmin) \
                || (parts[1] == bmaj && parts[2] == bmin && parts[3] > bpat) )); then
            bmaj=${parts[1]} bmin=${parts[2]} bpat=${parts[3]} target_version=$name
          fi
        done
      fi
    fi
  fi
fi

if (( fellback )); then
  source "$nvmsh"
else
  if [[ -n $target_version ]]; then
    local verdir="$NVM_DIR/versions/node/$target_version"

    local haveman=0
    whence -p manpath >/dev/null 2>&1 && haveman=1

    if (( haveman )) && [[ -z $MANPATH ]]; then
      MANPATH=
    fi

    local -a comps; comps=(${(s.:.)PATH})
    local _i nvmidx=-1 sysidx=-1 c rest
    local -a rp
    for (( _i = 1; _i <= ${#comps}; _i++ )); do
      c=${comps[_i]}
      if (( nvmidx == -1 )) && [[ $c == "$NVM_DIR"/* ]]; then
        rest=${c#"$NVM_DIR"/}
        rp=(${(s:/:)rest})
        if { (( ${#rp} == 2 )) && [[ ${rp[2]} == bin ]] } \
            || { (( ${#rp} == 4 )) && [[ ${rp[1]} == versions && ${rp[4]} == bin ]] }; then
          nvmidx=$_i
        fi
      fi
      if (( sysidx == -1 )) && { [[ $c == /bin ]] || [[ $c == /usr/bin ]] || [[ $c == /usr/local/bin ]] }; then
        sysidx=$_i
      fi
    done
    if (( nvmidx == -1 || (sysidx != -1 && sysidx < nvmidx) )); then
      PATH="$verdir/bin:$PATH"
    else
      comps[nvmidx]="$verdir/bin"
      PATH=${(j.:.)comps}
    fi
    export PATH

    if (( haveman )) && [[ -n $MANPATH ]]; then
      local -a mcomps; mcomps=(${(s.:.)MANPATH})
      local mnvmidx=-1 msysidx=-1
      for (( _i = 1; _i <= ${#mcomps}; _i++ )); do
        c=${mcomps[_i]}
        if (( mnvmidx == -1 )) && [[ $c == "$NVM_DIR"/* ]]; then
          rest=${c#"$NVM_DIR"/}
          rp=(${(s:/:)rest})
          if { (( ${#rp} == 3 )) && [[ ${rp[2]} == share && ${rp[3]} == man ]] } \
              || { (( ${#rp} == 5 )) && [[ ${rp[1]} == versions && ${rp[4]} == share && ${rp[5]} == man ]] }; then
            mnvmidx=$_i
          fi
        fi
        if (( msysidx == -1 )) && { [[ $c == /share/man ]] || [[ $c == /usr/share/man ]] || [[ $c == /usr/local/share/man ]] }; then
          msysidx=$_i
        fi
      done
      if (( mnvmidx == -1 || (msysidx != -1 && msysidx < mnvmidx) )); then
        MANPATH="$verdir/share/man:$MANPATH"
      else
        mcomps[mnvmidx]="$verdir/share/man"
        MANPATH=${(j.:.)mcomps}
      fi
      export MANPATH
    fi

    export NVM_BIN="$verdir/bin" NVM_INC="$verdir/include/node"
  fi

  nvm() {
    emulate -L zsh
    nvm_lazy_load || return $?
    nvm "$@"
  }
fi

nvm_lazy_load() {
  emulate -L zsh
  local -a hbroots
  hbroots=(${NVM_HOMEBREW:+$NVM_HOMEBREW} ${HOMEBREW_PREFIX:+$HOMEBREW_PREFIX/opt/nvm} /opt/homebrew/opt/nvm /usr/local/opt/nvm)
  if (( ! $+functions[nvm_ls_current] )); then
    local nvmsh="$NVM_DIR/nvm.sh" r=""
    if [[ ! -f $nvmsh ]]; then
      nvmsh=""
      for r in "${hbroots[@]}"; do [[ -f "$r/nvm.sh" ]] && { nvmsh="$r/nvm.sh"; break }; done
    fi
    [[ -n $nvmsh ]] || return 1
    source "$nvmsh" --no-use || return $?
  fi
  (( $+functions[compdef] )) || return 0
  [[ ${_comps[nvm]-} == '_bash_complete -o default -F __nvm' ]] && return 0
  local compfile="$NVM_DIR/bash_completion" r=""
  if [[ ! -f $compfile ]]; then
    compfile=""
    for r in "${hbroots[@]}"; do [[ -f "$r/etc/bash_completion.d/nvm" ]] && { compfile="$r/etc/bash_completion.d/nvm"; break }; done
  fi
  [[ -n $compfile ]] || return 0
  autoload -U +X bashcompinit && bashcompinit
  local ZSH_VERSION=
  source "$compfile"
}

if (( $+functions[compdef] )); then
  _nvm_lazy_completion() {
    emulate -L zsh
    nvm_lazy_load
    local -a reply=(${(z)${_comps[nvm]-}})
    (( $#reply )) && "${reply[@]}" "$@"
  }
  compdef _nvm_lazy_completion nvm
fi
}
