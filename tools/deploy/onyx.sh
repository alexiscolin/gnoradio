#!/bin/sh
# Deploy GnoRadio's packages to onyx under your namespace, with your gnokey key.
#
#   tools/deploy/onyx.sh <gnokey key name> <your gno.land name or g1 address>
#
# e.g. tools/deploy/onyx.sh mykey nym-alexiscolin000 puts them at
# gno.land/{p,r}/nym-alexiscolin000/gnoradio/..., next to gnogolf.
#
# Each package is submitted, then the script waits for onyx's approver to
# enable it (status "live") before the next one, since each imports the earlier
# ones. Whoever deploys catalog, radio and tickets becomes their admin.
set -eu
KEY=$1
NS=$2/gnoradio
REMOTE=https://rpc.onyx.testnets.gno.land:443
cd "$(dirname "$0")/../.."
python3 tools/deploy/stage.py "$NS" build/onyx >/dev/null
for pkg in p/text p/svg p/store p/safe p/blocks r/catalog r/radio r/tickets r/home; do
  kind=${pkg%%/*}
  name=${pkg#*/}
  path=gno.land/$kind/$NS/$name/v0
  dir=build/onyx/$kind/$NS/$name/v0
  # The storage deposit is charged when the package is enabled, about 100 ugnot per byte: allow twice that.
  deposit=$(( $(cat "$dir"/*.gno | wc -c) * 200 + 2000000 ))
  echo "submitting $path (max deposit ${deposit}ugnot)"
  gnokey maketx addpkg -pkgdir "$dir" -pkgpath "$path" \
    -gas-fee 200000ugnot -gas-wanted 200000000 -max-deposit "${deposit}ugnot" \
    -chainid onyx-1 -remote "$REMOTE" -broadcast "$KEY"
  tries=0
  until gnokey query vm/qpkgmeta_json -data "$path" -remote "$REMOTE" 2>/dev/null | grep -q '"live"'; do
    tries=$((tries + 1))
    if [ "$tries" -gt 36 ]; then
      echo "still not live after 3 minutes: $path (check: gnokey query vm/qpkgmeta_json -data $path -remote $REMOTE)" >&2
      exit 1
    fi
    sleep 5
  done
  echo "live: $path"
done
echo "done: https://onyx.testnets.gno.land/r/$NS/home/v0"
