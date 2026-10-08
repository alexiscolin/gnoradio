// The same calls Adena signs, as a `gnokey maketx call` to paste in a terminal
// (gnoweb's $help and gno.golf use the same command). gnokey does not simulate
// first, so the gas is a fixed ceiling per function, measured on a devnet with
// ~2x headroom; the fee is that gas at the chain's price (auth/gasprice: 1 ugnot
// per 1,000 gas on onyx and mainnet).

import type { Call } from "./gno";

const HEAVY: Readonly<Record<string, number>> = {
  // radio.Sync(20), the safety net anyone may call: simulated on the v1 devnet (2026-10-08, 5,000
  // tracks) at 62.8M with nothing new to import; 20 new tracks add about 22M (filetest).
  Sync: 100_000_000,
  // Measured on the v1 devnet (2026-10-08, 5,000 tracks): publish 24M, register 21-25M. radio.PublishTrack
  // also puts the track on its stations: +7.0M at 5,000 tracks, +7.3M at 20,000 (radio z_gas_publish
  // filetests), so about 32M on chain, under 60M.
  // Refresh measured 29.2M on the v1 devnet (global chain test, 2026-10-08).
  Refresh: 60_000_000,
  PublishTrack: 60_000_000,
  PublishPlaylist: 60_000_000,
  RegisterArtist: 60_000_000,
  // Picks: 32-36M (a listener's first 36M); a dedication or a sponsored pick adds ~4M (filetests). ~2x margin.
  Queue: 70_000_000,
  QueueAt: 70_000_000,
  QueueSponsored: 80_000_000,
  QueueSponsoredAt: 80_000_000,
  QueueWithNote: 80_000_000,
  QueueWithNoteAt: 80_000_000,
  // RestoreSlot runs the same refresh as Refresh (measured 39M on v1); TipOnAir 36.8M before the
  // picker-paid path, the plain tips less: kept well above.
  RestoreSlot: 100_000_000,
  TipOnAir: 80_000_000,
  Tip: 60_000_000,
  TipWithSupport: 60_000_000,
  // tickets.Present (the holder at the door): one timestamp, estimated like CheckIn (default 40M). Re-measure once live.
  Present: 40_000_000,
  // Not measured yet (re-measure once live): radio.EditTrack rewrites a track record like PublishTrack
  // (24M) and, for a new genre or duration, runs Refresh (29.2M) in the same transaction: 100M, as
  // RestoreSlot. UpdatePlaylist rewrites a playlist like PublishPlaylist, TransferTicket moves an NFT and two
  // holder lists like BuyTicket (30M); CancelEvent and HideOwn write one record each, like the moderator's hide.
  EditTrack: 100_000_000,
  UpdatePlaylist: 60_000_000,
  TransferTicket: 50_000_000,
  CancelEvent: 40_000_000,
  HideOwn: 40_000_000,
  // The full gas-wanted is charged, so small calls get tight limits (measured on the v1 devnet,
  // global chain test 2026-10-08): a paid ticket 30M, a vault withdrawal 7.5M, the fee 8.9M, the goal 11.7M.
  BuyTicket: 50_000_000,
  VaultWithdraw: 15_000_000,
  SetServiceFee: 18_000_000,
  SetMonthlyGoal: 24_000_000,
};

const ADDRESS_KEY = "gnoradio.gnokeyAddress";
/** gnokeyAddress is the address of the gnokey key the listener signs with, if they gave it (dedications are certified for it). */
export const gnokeyAddress = (): string => { try { return localStorage.getItem(ADDRESS_KEY) ?? ""; } catch { return ""; } };
export const setGnokeyAddress = (a: string): void => { try { localStorage.setItem(ADDRESS_KEY, a.trim()); } catch { /* this visit only */ } };

/** gasFor is the gas a call may burn: 40M for a listener action (a like 19M, a ticket 25M on v1), more for the heavy ones. */
export const gasFor = (func: string): number => HEAVY[func] ?? 40_000_000;

/** feeFor is the fee (ugnot) for that gas at 1 ugnot per 1,000 gas. */
export const feeFor = (gas: number): number => Math.ceil(gas / 1000);

/** shellQuote wraps a value in single quotes for bash or zsh; a quote inside becomes '\''. */
export const shellQuote = (s: string): string => `'${s.replaceAll("'", `'\\''`)}'`;

/** KEY_HOLDER stands in for the key name until the user types theirs. */
const KEY_HOLDER = "YOUR_KEY_NAME";

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
