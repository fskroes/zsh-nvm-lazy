# zsh-nvm-lazy

Load [nvm](https://github.com/nvm-sh/nvm) on first use in zsh. Your default `node` is on `PATH` at once, the same one nvm itself would put there.

`source nvm.sh` costs about 270 ms in every new shell. This plugin costs 0.6 ms.

## The problem

Most lazy loaders for nvm do not put `node` on `PATH` until nvm loads. Until you type `nvm` or `node` one time, these things break:

- global npm tools (`eslint`, `tsc`, ...): `command not found`
- scripts and editors that look for `node` on `PATH`
- tools that start `node` from a shell hook or a key binding

The usual fix is a wrapper function for each global tool (oh-my-zsh `lazy-cmd`). You must keep that list up to date by hand.

## What this plugin does

At startup it reads the files that nvm reads, with zsh builtins only. It starts no process, and it does not source `nvm.sh`. It finds the version the same way nvm does (the nvm function names are in brackets):

1. The `node` already on `PATH`, if nvm installed it (`nvm_ls_current`).
2. Else the `default` alias and the alias chain behind it, for example `default` → `lts/*` → `lts/krypton` → `v24.x` (`nvm_resolve_alias`).
3. Else the `.nvmrc` in the current directory or a parent (`nvm_find_nvmrc`, `nvm_rc_version`).
4. Then the installed version that matches: the newest one for `22` or `22.11` (`nvm_version`).

It then changes `PATH` and `MANPATH` the same way `nvm use` does (`nvm_change_path`), and exports `NVM_BIN` and `NVM_INC`.

`nvm` itself is a small stub. The first `nvm` call sources `nvm.sh --no-use` one time and runs your command. After that, `nvm` is nvm's own function.

If the plugin is not sure that it gets the same result as nvm, it sources `nvm.sh` at startup, as nvm's own install lines do. A wrong `node` is worse than a slow shell. This happens when:

| Setup | Why |
|---|---|
| `default` is `node`, `stable`, `iojs`, `unstable` or `system` | nvm resolves these names with its own logic |
| `default` is `lts/-1` or a similar offset | nvm resolves these names with its own logic |
| an alias loop, for example `default` → `a` → `default` | nvm shows `∞`; the plugin lets nvm handle it |
| no `default` alias, and `.nvmrc` holds a name (`lts/*`, `node`), not a version | nvm resolves these names with its own logic |
| an `.nvmrc` with more than one value line (`node=...` format) | nvm's key/value `.nvmrc` format |
| a node from the old layout (`$NVM_DIR/v0.10.0/bin`) or io.js already on `PATH` | a directory layout the plugin does not read |
| `NVM_DIR` holds one of `[ ] * ^ $ + ? ( ) { } \| \ #` | nvm puts `NVM_DIR` into `grep` and `sed` patterns, and the match changes |

## Speed

`zsh tests/bench.zsh 30` on an Apple Silicon Mac, zsh 5.9, nvm 0.40.5, one installed node. Each run is a new clean shell.

| What | Median |
|---|---|
| `source nvm.sh` | 263.8 ms |
| this plugin | 0.6 ms |
| `source nvm.sh`, then `node --version` | 275.9 ms |
| this plugin, then `node --version` | 9.8 ms |
| this plugin, then the first `nvm` call | 37.9 ms |

The first `nvm` call is fast too, because `--no-use` skips the version lookup that the plugin already did.

## Install

First remove the other nvm loaders from your `~/.zshrc`:

- the lines that the nvm installer added: `export NVM_DIR=...`, `[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"` and the `bash_completion` line
- `nvm` in the oh-my-zsh `plugins=(...)` list

If nvm is in `~/.nvm` or `${XDG_CONFIG_HOME:-~/.config}/nvm`, you need no settings. Else set `NVM_DIR` before the plugin loads.

For Homebrew's nvm, set `NVM_DIR` to your versions directory (usually `~/.nvm`). The plugin looks for `nvm.sh` in `$NVM_DIR`, `$NVM_HOMEBREW`, `$HOMEBREW_PREFIX/opt/nvm`, `/opt/homebrew/opt/nvm` and `/usr/local/opt/nvm`. It never runs `brew`.

For tab completion of `nvm`, load the plugin after `compinit`. oh-my-zsh, antidote and zinit do this for you.

### oh-my-zsh

```sh
git clone https://github.com/fskroes/zsh-nvm-lazy ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-nvm-lazy
```

Then add it to the plugin list in `~/.zshrc`:

```zsh
plugins=(... zsh-nvm-lazy)
```

### Plain zsh

```sh
git clone https://github.com/fskroes/zsh-nvm-lazy ~/.zsh/zsh-nvm-lazy
```

Then in `~/.zshrc`, after `compinit`:

```zsh
source ~/.zsh/zsh-nvm-lazy/zsh-nvm-lazy.plugin.zsh
```

### antidote

Add this line to `~/.zsh_plugins.txt`:

```text
fskroes/zsh-nvm-lazy
```

### zinit

```zsh
zinit light fskroes/zsh-nvm-lazy
```

## Differences from `source nvm.sh`

`PATH`, `MANPATH`, `NVM_BIN` and `NVM_INC` are the same, including which ones are exported. The test compares them after each case. Two things differ:

- Before the first call, `nvm` is the stub function, not nvm's function.
- `nvm_lazy_load` loads nvm now, without running a command. Call it before you use nvm's internal `nvm_*` functions in your own code.

## Other options

| Option | `node` on `PATH` at startup | Notes |
|---|---|---|
| `source nvm.sh` | yes | the reference; about 270 ms |
| oh-my-zsh `nvm` plugin, `lazy yes` | no, only after first use | global tools need `lazy-cmd` entries |
| [lukechilds/zsh-nvm](https://github.com/lukechilds/zsh-nvm), `NVM_LAZY_LOAD` | no, only after first use | makes a wrapper for each global tool it finds |
| [fnm](https://github.com/Schniz/fnm) | yes | a different tool, not nvm; it reads `.nvmrc` |
| this plugin | yes | nvm itself, loaded on the first `nvm` call |

If you can change tools, fnm is a good choice. This plugin is for people who keep nvm.

## Tests

There is no CI. The checks run on your machine, in git hooks:

```sh
git config core.hooksPath .githooks   # one time, after clone
sh tests/check.sh                     # all parity cases (pre-push)
sh tests/check.sh --quick             # 2 cases and the extra checks, under 2 s (pre-commit)
zsh tests/bench.zsh 30                # the speed table above
```

`tests/parity.zsh` needs a real `nvm.sh` (`~/.nvm/nvm.sh`, or set `NVM_SH`). For each case it makes a fake `NVM_DIR`, with small scripts as `node` binaries. It then starts two clean shells: one runs `source nvm.sh`, one loads the plugin. It compares `PATH`, `NVM_BIN`, `NVM_INC`, `MANPATH` and which `node` runs. It also compares the output and exit status of `nvm current`, `nvm ls` and a wrong `nvm` command. Cases marked `fast` must not source `nvm.sh` at startup.

Other checks: nvm is not installed, `setopt no_unset`, nvm is already loaded, and tab completion.

`PARITY_CASES="exact lts" zsh tests/parity.zsh` runs only the cases you name.

## License

MIT
