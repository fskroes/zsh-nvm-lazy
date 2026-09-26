# zsh-nvm-lazy: put the right node on PATH at shell startup, the way
# `source nvm.sh` would, without paying nvm.sh's startup cost.
#
# nvm.sh itself is only sourced (with --no-use, exactly once) the first time
# `nvm` is actually called; from then on `nvm` is nvm's own function, this
# stub is gone. `node`, `npm`, `npx` and global npm tools need no stub at
# all: PATH already points at the right bin dir from startup.
#
# On startup this plugin re-derives, without forking a single process, what
# `nvm_auto use` (nvm.sh) would have put on PATH: it walks the default alias
# chain (nvm_resolve_alias) or an .nvmrc (nvm_rc_version), matches it against
# installed versions the way nvm_ls does, and edits PATH/MANPATH the way
# `nvm use` (nvm_change_path) does. Whenever that walk hits something it
# cannot resolve with full confidence (an implicit alias, an alias loop, an
# multi-key .nvmrc, an old-style/io.js install, ...) it falls back to
# sourcing nvm.sh in full, exactly what plain `source nvm.sh` would do:
# wrong node is far worse than slow.
#
# Public functions:
#   nvm                    lazy stub; loads nvm on first call, then IS nvm.
#   nvm_lazy_load          load nvm right now, without running a command.
#   _nvm_lazy_completion   completion stub, registered only if compinit
#                          already ran; loads nvm's own bash completion on
#                          first Tab, then hands the completion off to it.
() {
emulate -L zsh
setopt local_options extended_glob

(( $+functions[nvm] )) && return 0   # nvm already loaded: change nothing

# NVM_DIR discovery, same order as nvm's own oh-my-zsh plugin.
if [[ -z $NVM_DIR ]]; then
  if [[ -d $HOME/.nvm ]]; then
    NVM_DIR=$HOME/.nvm
  elif [[ -d ${XDG_CONFIG_HOME:-$HOME/.config}/nvm ]]; then
    NVM_DIR=${XDG_CONFIG_HOME:-$HOME/.config}/nvm
  else
    return 0                         # no nvm anywhere: stay silent
  fi
  export NVM_DIR
else
  NVM_DIR=${NVM_DIR%/}               # nvm.sh itself strips a trailing slash
fi

# Homebrew's nvm formula keeps nvm.sh outside NVM_DIR (its own caveats say
# so); check the well-known spots, never by running `brew`.
local -a hbroots
hbroots=(${NVM_HOMEBREW:+$NVM_HOMEBREW} ${HOMEBREW_PREFIX:+$HOMEBREW_PREFIX/opt/nvm} /opt/homebrew/opt/nvm /usr/local/opt/nvm)
local nvmsh="$NVM_DIR/nvm.sh" _r
if [[ ! -f $nvmsh ]]; then
  nvmsh=""
  for _r in "${hbroots[@]}"; do [[ -f "$_r/nvm.sh" ]] && { nvmsh="$_r/nvm.sh"; break }; done
fi
[[ -n $nvmsh ]] || return 0           # nvm not installed: stay silent

local fellback=0 target_version=""

# nvm_change_path and nvm_ls put $NVM_DIR into grep and sed patterns
# unescaped. With a regex character (or sed's `#` delimiter) in it, nvm.sh
# matches differently from a literal path compare: let nvm.sh decide.
[[ $NVM_DIR == *[][\\*^\$+?\(\){}\|\#]* ]] && fellback=1

# nvm_ls_current: is a node already on PATH, and does nvm manage it? A
# `versions/node/vX.Y.Z/bin/node` path IS its own version number, so unlike
# nvm_ls_current we don't need to exec node to learn it.
local _d nodebin=""
for _d in $path; do
  if [[ -f "$_d/node" && -x "$_d/node" ]]; then nodebin="$_d/node"; break; fi
done
if [[ -n $nodebin && $nodebin == "$NVM_DIR"/versions/node/v[0-9]##.[0-9]##.[0-9]##/bin/node ]]; then
  target_version=${nodebin#"$NVM_DIR"/versions/node/}
  target_version=${target_version%/bin/node}
elif [[ -n $nodebin && $nodebin == "$NVM_DIR"/* ]]; then
  fellback=1                          # old-style/io.js layout: not confident
fi

if [[ -z $target_version && $fellback == 0 ]]; then
  # current is "none" or "system": nvm_auto falls back to the default alias.
  # Walk it exactly like nvm_resolve_alias: one file per hop, first non-blank
  # line (comment and trailing whitespace stripped, like nvm_alias), cycle
  # detected against every name already seen.
  local -A seen
  local cur=default resolved="" hop=0
  seen[$cur]=1
  while (( hop++ < 64 )); do
    local afile="$NVM_DIR/alias/$cur" line="" got=0 raw=""
    [[ -f $afile ]] || break
    while IFS= read -r raw; do
      raw=${raw%%\#*}                 # nvm_alias: sed 's/#.*//'
      raw=${raw%%[[:space:]]#}        # nvm_alias: sed 's/[[:space:]]*$//'
      [[ -n $raw ]] || continue       # nvm_alias: awk 'NF'
      line=$raw; got=1; break
    done < "$afile"
    (( got )) || break
    if (( $+seen[$line] )); then fellback=1; break; fi   # alias loop
    seen[$line]=1
    cur=$line
  done
  [[ $cur != default ]] && resolved=$cur

  if [[ -z $resolved && $fellback == 0 ]]; then
    # No default alias resolved to anything: nvm_rc_version. The walk up
    # from $PWD is nvm_find_up plus nvm_find_nvmrc, line for line: the loop
    # stops at "", and the final test then checks "/.nvmrc".
    local dir=$PWD nvmrc=""
    while [[ -n $dir && $dir != . && ! -f "$dir/.nvmrc" ]]; do
      dir=${dir%/*}
    done
    if [[ -f "$dir/.nvmrc" ]]; then nvmrc="$dir/.nvmrc"
    elif [[ -e "$dir/.nvmrc" ]]; then fellback=1   # "/.nvmrc" is not a file
    fi
    if [[ -n $nvmrc ]]; then
      # nvm_process_nvmrc: comments and blank lines dropped, both ends
      # trimmed; only the common "one bare version line" shape is handled
      # here, a multi-key .nvmrc (engines=...) defers to nvm.sh itself.
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
    [[ $p == [0-9]* ]] && p="v$p"     # nvm_ensure_version_prefix
    if [[ $p != v[0-9]* ]]; then
      fellback=1                     # an implicit alias (node/stable/...),
    else                             # lts/-N, or "∞": nvm_resolve_alias
                                      # territory, defer to nvm.sh.
      local core=${p#v}
      local -a segs; segs=(${(s:.:)core})
      local seg bad=0
      for seg in "${segs[@]}"; do [[ $seg == [0-9]## ]] || bad=1; done
      if (( bad )) || (( ${#segs} < 1 || ${#segs} > 3 )); then
        fellback=1
      elif (( ${#segs} == 3 )); then
        # nvm_ls: an explicit version has to already be installed.
        [[ -d "$NVM_DIR/versions/node/$p" ]] && target_version=$p
      else
        # nvm_ls: partial version (major, or major.minor). Newest installed
        # version whose name starts "v<pattern>." — the boundary dot is
        # what keeps "2" from matching "v22.0.0" the way nvm_ls avoids it.
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
  source "$nvmsh"                    # same as plain `source nvm.sh`
else
  if [[ -n $target_version ]]; then
    local verdir="$NVM_DIR/versions/node/$target_version"

    # nvm_has manpath, without forking it and without `$+commands[...]`, which
    # hashes every directory on PATH on first use (milliseconds on a long
    # PATH); `whence -p` stops at the first match instead.
    local haveman=0
    whence -p manpath >/dev/null 2>&1 && haveman=1

    # nvm use: with MANPATH empty, nvm runs `local MANPATH; MANPATH=$(manpath)`,
    # so its change stays inside the function. What remains is an empty,
    # assigned MANPATH (zsh: manpath=('')), exported only if it already was.
    # A plain assignment leaves the same state, without the `manpath` fork.
    if (( haveman )) && [[ -z $MANPATH ]]; then
      MANPATH=
    fi

    # nvm use / nvm_change_path: replace the first nvm bin dir already on
    # PATH, or prepend if there is none, or prepend anyway (keeping the old
    # one) when a plain system bin dir precedes it (nvm.sh issue #1652).
    # Classified by a prefix-strip + split, not a glob match per component:
    # over a real, ~30-entry PATH the repeated [^/]## pattern compile was
    # the dominant startup cost.
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

    # nvm use / nvm_change_path again, for MANPATH under /share/man — only
    # when it already held something (the empty case was handled above).
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
    nvm "$@"                          # nvm_lazy_load just made this the real nvm
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
  # oh-my-zsh's own recipe (nvm.plugin.zsh): load bashcompinit, then source
  # nvm's bash completion with ZSH_VERSION hidden so it doesn't call compinit
  # itself again.
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
