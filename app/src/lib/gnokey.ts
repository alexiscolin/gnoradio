// The same calls Adena signs, as a `gnokey maketx call` to paste in a terminal
// (gnoweb's $help and gno.golf use the same command). gnokey does not simulate
// first, so the gas is a fixed ceiling per function, measured on a devnet with
// ~2x headroom; the fee is that gas at the chain's price (auth/gasprice: 1 ugnot
// per 1,000 gas on onyx and mainnet).

import type { Call } from "./gno";

const HEAVY: Readonly<Record<string, number>> = {
  Sync: 500_000_000,
  Refresh: 100_000_000,
  PublishTrack: 100_000_000,
  PublishPlaylist: 100_000_000,
  RegisterArtist: 100_000_000,
};

/** gasFor is the gas a call may burn: 40M for a listener action, more for the heavy ones. */
export const gasFor = (func: string): number => HEAVY[func] ?? 40_000_000;

/** feeFor is the fee (ugnot) for that gas at 1 ugnot per 1,000 gas. */
export const feeFor = (gas: number): number => Math.ceil(gas / 1000);

/** shellQuote wraps a value in single quotes for bash or zsh; a quote inside becomes '\''. */
export const shellQuote = (s: string): string => `'${s.replaceAll("'", `'\\''`)}'`;

/** KEY_HOLDER stands in for the key name until the user types theirs. */
export const KEY_HOLDER = "YOUR_KEY_NAME";

/** gnokeyCommand is the one-line `gnokey maketx call` for c, signed by the key named key. */
export function gnokeyCommand(c: Call, chainId: string, remote: string, key: string): string {
  const gas = gasFor(c.func);
  return [
    "gnokey maketx call",
    `-pkgpath ${c.pkg}`,
    `-func ${c.func}`,
    ...c.args.map((a) => `-args ${shellQuote(a)}`),
    ...(c.send ? [`-send ${String(c.send)}ugnot`] : []),
    `-gas-fee ${String(feeFor(gas))}ugnot`,
    `-gas-wanted ${String(gas)}`,
    "-broadcast",
    `-chainid ${shellQuote(chainId)}`,
    `-remote ${shellQuote(remote)}`,
    shellQuote(key.trim() || KEY_HOLDER),
  ].join(" ");
}
