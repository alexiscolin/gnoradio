#!/bin/sh
# Deploy GnoRadio's packages to a public chain under your namespace, signed by
# your own gnokey key (this script never sees the key, gnokey asks for it).
#
#   tools/deploy/deploy.sh [--dry-run] [--resubmit] [--release v2] <onyx|mainnet> <gnokey key name> <namespace>
#
# e.g. tools/deploy/deploy.sh onyx mykey nym-alexiscolin000 puts them at
# gno.land/{p,r}/nym-alexiscolin000/gnoradio/..., next to gnogolf.
#
# Both chains park a submitted package ("inert") until an approver enables it,
# and enabling type-checks its imports, so the packages go one by one in
# dependency order (stage.py), each waiting to be "live" before the next. On
# onyx an automatic approver enables a good package in seconds; on mainnet a
# person does (docs/DEPLOY.md), so the wait can take days: stop with Ctrl-C and
# run the same command again later, it skips what is live and waits on what is
# parked. --resubmit sends a parked package again (after fixing it) instead of
# waiting. --dry-run checks and prints everything, signs nothing. --release v2
# deploys only the four rules realms of a new release, at that version: the
# rest is on chain already (docs/DEPLOY.md, Upgrading the rules later).
#
# Whoever deploys becomes the data realm's owner and guardian and the admin of
# catalog, radio and tickets (docs/DEPLOY.md: hand the guardian role to a
# separate key before any public use).
set -eu
DRY= RESUBMIT= RELEASE=
while [ $# -gt 0 ]; do
  case $1 in
    --dry-run) DRY=1 ;;
    --resubmit) RESUBMIT=1 ;;
    --release) RELEASE=$2; shift ;;
    *) break ;;
  esac
  shift
done
[ $# -eq 3 ] || { sed -n '2,23p' "$0"; exit 2; }
NET=$1 KEY=$2 NS=$3/gnoradio
case $NET in
  onyx) CHAIN=onyx-1 REMOTE=https://rpc.onyx.testnets.gno.land:443 WEB=https://onyx.testnets.gno.land POLL=5 TRIES=36 ;;
  mainnet) CHAIN=gnoland-1 REMOTE=https://rpc.gno.land:443 WEB=https://gno.land POLL=30 TRIES=0 ;;
  *) echo "network: onyx or mainnet" >&2; exit 2 ;;
esac
# The chains run gno v1.5.0 (commit e75fef82c): lint with the same release.
GNO=${GNO:-$HOME/.cache/gno-toolchains/onyx-v1.5.0/gno}
# Lint's module cache only: gnokey keeps reading your own GNOHOME, where your
# keys are.
LINTHOME=${LINTHOME:-$HOME/.cache/gno-toolchains/onyx-v1.5.0/gnohome}
# Sign with gnokey from the same release: an older one rejects package paths
# the chains accept. Built once from the release's source next to gno.
GNOKEY=${GNOKEY:-$HOME/.cache/gno-toolchains/onyx-v1.5.0/gnokey}
GNOROOT_SRC=${GNOROOT_SRC:-$HOME/.cache/gno-toolchains/onyx-v1.5.0/gnoroot}
if [ ! -x "$GNOKEY" ]; then
  [ -f "$GNOROOT_SRC/gno.land/cmd/gnokey/main.go" ] ||
    { echo "no $GNOKEY and no gno v1.5.0 source in $GNOROOT_SRC to build it" >&2; exit 1; }
  echo "building $GNOKEY (gno v1.5.0)"
  go -C "$GNOROOT_SRC" build -o "$GNOKEY" ./gno.land/cmd/gnokey
fi
FEE=200000 # ugnot per submission: 200M gas at 1ugnot/1000gas
CAP=100000000 # ugnot, the most one package's storage deposit may take (vm default_deposit)
OUT=build/$NET
cd "$(dirname "$0")/../.."

DIRS=$(python3 tools/deploy/stage.py "$NS" "$OUT" $RELEASE)
touch "$OUT/gnowork.toml" # the staged packages resolve each other locally
echo "lint ($GNO)"
(cd "$OUT" && GNOHOME=$LINTHOME "$GNO" lint ./...) || { echo "lint failed: nothing submitted" >&2; exit 1; }

n=$(echo "$DIRS" | wc -l | tr -d ' ')
bytes=$(cat $(for d in $DIRS; do echo "$d"/*.gno; done) | wc -c | tr -d ' ')
echo "$n packages, $bytes bytes of source, to $CHAIN as $NS"
echo "fees: $((n * FEE / 1000000)).$((n * FEE % 1000000 / 100000)) GNOT at most ($FEE ugnot each)"
echo "storage deposit: 100 ugnot per stored byte, charged when a package is enabled;"
if [ -n "$RELEASE" ]; then echo "  about 60 GNOT for the four rules realms (the code without p/ and data)."
else echo "  about 100 GNOT for this release (a devnet measured 91 GNOT for the code, safe/v0's word list alone 30)."; fi
echo "  Each submission allows up to $((CAP / 1000000)) GNOT; only what is stored is taken."

# live | inert (parked) | absent, read straight from the node (no key needed)
status() {
  curl -s -m 20 "$REMOTE/abci_query?path=%22vm/qpkgmeta_json%22&data=$(printf %s "$1" | base64 | tr -d '\n')" |
    python3 -c 'import sys,json,base64; print(json.loads(base64.b64decode(json.load(sys.stdin)["result"]["response"]["ResponseBase"]["Data"] or "e30=") or "{}").get("status", ""))' 2>/dev/null || true
}
# status_sure retries a read that failed (no answer, bad JSON): only an explicit
# answer from the node decides whether to submit.
status_sure() {
  for _ in 1 2 3 4 5; do
    st=$(status "$1")
    [ -n "$st" ] && { echo "$st"; return; }
    sleep 3
  done
  echo "cannot read the status of $1 from $REMOTE: nothing submitted, try again later" >&2
  exit 1
}
submit() {
  set -- "$GNOKEY" maketx addpkg -pkgdir "$1" -pkgpath "$2" -gas-fee "${FEE}ugnot" -gas-wanted 200000000 \
    -max-deposit "${CAP}ugnot" -chainid "$CHAIN" -remote "$REMOTE" -broadcast "$KEY"
  if [ -n "$DRY" ]; then echo "  would run: $*"; else "$@"; fi
}

for dir in $DIRS; do
  path=gno.land/${dir#"$OUT"/}
  st=$(status_sure "$path")
  case $st in
    live) echo "live already: $path"; continue ;;
    inert) if [ -n "$RESUBMIT" ]; then echo "resubmitting $path"; submit "$dir" "$path"; else echo "parked already: $path"; fi ;;
    absent) echo "submitting $path"; submit "$dir" "$path" ;;
    *) echo "unexpected status '$st' for $path: nothing submitted" >&2; exit 1 ;;
  esac
  [ -n "$DRY" ] && continue
  tries=0
  until [ "$(status "$path")" = live ]; do
    tries=$((tries + 1))
    if [ "$TRIES" -gt 0 ] && [ "$tries" -gt "$TRIES" ]; then
      echo "still not live after $((TRIES * POLL / 60)) minutes: $path. A package that fails its checks stays parked." >&2
      echo "  fix it, then run again with --resubmit" >&2
      exit 1
    fi
    if [ $((tries % 20)) -eq 1 ]; then
      echo "  parked, waiting for an approver to enable $path (Ctrl-C and rerun later is fine)"
      echo "  check: gnokey query vm/qpkgmeta_json -data $path -remote $REMOTE"
      echo "  queue: gnokey query 'vm/qinertpaths?limit=100' -data gno.land/r/ -remote $REMOTE"
    fi
    sleep "$POLL"
  done
  echo "live: $path"
done
[ -n "$DRY" ] && echo "dry run: nothing was signed" && exit 0
if [ -n "$RELEASE" ]; then
  echo "done. Now, as owner, propose them (each takes over once all are Ready, after the data realm's delay):"
  for r in catalog radio tickets home; do
    echo "  gnokey maketx call -pkgpath gno.land/r/$NS/data -func Propose -args $r -args gno.land/r/$NS/$r/$RELEASE -gas-fee 30000ugnot -gas-wanted 20000000 -chainid $CHAIN -remote $REMOTE -broadcast $KEY"
  done
else echo "done: $WEB/r/$NS/home/v1"; fi
