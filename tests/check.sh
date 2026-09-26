#!/bin/sh
# Local gate. No CI: run it by hand, or let the git hooks run it.
#   sh tests/check.sh          all parity cases (about 10 s)
#   sh tests/check.sh --quick  a few parity cases (pre-commit)
cd "$(dirname "$0")/.." || exit 1
fail=0
for f in zsh-nvm-lazy.plugin.zsh tests/parity.zsh tests/bench.zsh; do
  zsh -n "$f" || { echo "FAIL: zsh -n $f"; fail=1; }
done
[ $fail = 0 ] && echo "ok: all zsh files parse"
if [ "${1-}" = --quick ]; then
  PARITY_CASES="exact nvmrc" zsh tests/parity.zsh || fail=1
else
  zsh tests/parity.zsh || fail=1
fi
exit $fail
