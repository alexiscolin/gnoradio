// Get started on GnoRadio: one list that drives the /features page and its
// static, crawlable copy (prerender.ts). Every line states what the app and the
// realms do (docs/FEATURES.md); numbers come from the constants that enforce them.
import type { Glyph } from "../components/Shapes";
import { CHECK_IN } from "./concerts";
import { COSTS, NO_FEE, TREASURY_USE } from "./legal";
import { gnot, UGNOT } from "./format";
import { MAX_PROMO, PICK_PAY, promoSplit } from "./incentives";
import { realmPage, txURL } from "./links";
import { DAYS } from "./session";
import { BOOK_MAX, BOOK_MIN, MAX_OPEN_REPORTS, MAX_SPLITS } from "./rules";
import type { View } from "./types";

/** Go is where a feature is done: a screen (and a spot on it), the pick sheet, or a page on gnoweb. */
export type Go =
  | { readonly view: View; readonly hash?: string }
  | { readonly pick: true }
  | { readonly href: string };

export interface Feature {
  readonly g: Glyph;
  readonly title: string;
  readonly line: string;
  readonly cta: string;
  readonly go: Go;
}

/** A smaller feature, listed under the cards. */
export interface Minor {
  readonly title: string;
  readonly line: string;
  readonly go: Go;
}

export interface Audience {
  readonly id: "listeners" | "artists";
  readonly title: string;
  readonly lead: string;
  readonly cards: readonly Feature[];
  readonly more: readonly Minor[];
}

const PICK: Go = { pick: true };
const ME_MUSIC: Go = { view: { k: "me" }, hash: "me-make-music" };
const ME_TICKETS: Go = { view: { k: "me" }, hash: "me-tickets" };
/** TIP_LINE: where a tip goes, as the realm splits it (catalog social.gno). */
export const TIP_LINE = "Straight to the artist and their collaborators in one transaction, minus the promo share they chose. 0% to GnoRadio.";

export const PICK_WINDOW = `${String(BOOK_MIN / 60)} minutes to ${String(BOOK_MAX / 3600)} hours ahead`;
/** REPORTS: what a report does (catalog.Report): public, on-chain, a few open per wallet. */
export const REPORTS = `Report a track, album, artist or playlist on-chain, in public; up to ${String(MAX_OPEN_REPORTS)} open reports per wallet.`;
/** IMPORTED: a profile GnoRadio imported from Audius can be verified by its artist. */
export const IMPORTED = "Already on Audius? Your profile may be here: verify it and it is yours.";
/** PROMO_ASK: asked of a verified artist whose promo share is still 0; the share stays their choice. */
export const PROMO_ASK = `Set a promo share (0 to ${String(MAX_PROMO)}%): listeners who put your track on air or share it get part of each tip. You can change it any time.`;
/** PHONE_SIGN: said on a phone before a pick, not after it (Adena runs in Chrome on a computer; its phone app is not out). */
export const PHONE_SIGN = "Picking needs Adena on a computer. Listening works here.";
/** SHARE_TEXT: what a shared /features link says. */
export const SHARE_TEXT = "A community radio where listeners pick what plays next. Tips go to artists, 0% to GnoRadio.";
/** ARTIST_NEEDS: what publishing takes, said before the first step. */
export const ARTIST_NEEDS = "You need Adena in Chrome on a computer, a little GNOT for the deposits, and a link to your file on IPFS, Arweave or an allowed https host.";
const REFUND = `${String(PICK_PAY.min)} to ${String(PICK_PAY.max)} GNOT per aired pick (${String(PICK_PAY.def)} by default)`;

export const HERO = {
  kicker: "Community radio · open music · on-chain",
  title: "Your song. On air. For everyone.",
  lead: "A free community radio and music player. Pick what plays next for everyone; tip artists directly, 0% to GnoRadio. Listening needs no wallet. Its rules live on gno.land.",
} as const;

export const VIDEO = {
  src: "/promo.mp4",
  poster: "/promo-poster.jpg",
  seconds: 57,
  caption: "GnoRadio in a minute: tune in, pick what plays next, tip the artist.",
  music: { title: "New Again", artist: "Josh Woodward", site: "https://www.joshwoodward.com", license: "CC-BY-4.0" },
} as const;

/** audiences is the feature list; fees says whether the operator takes any (a ticket service fee). */
export const audiences = (fees: boolean): readonly Audience[] => [
  {
    id: "listeners",
    title: "For listeners",
    lead: "Free online radio you program.",
    cards: [
      { g: "circle", title: "Tune in", line: "Main, 20 genre stations, New this week and Listeners' choice. Everyone hears the same second. No wallet.", cta: "Tune in", go: { view: { k: "stations", live: 0 } } },
      { g: "square", title: "Play anything", line: "Search the library and play any track, album or playlist, just for you.", cta: "Open the Library", go: { view: { k: "library", genre: 0 } } },
      { g: "quarter", title: "Be the DJ", line: `Pick a track and it airs for everyone tuned in, next or at a time you choose, ${PICK_WINDOW}. One pick per station per hour. Add a dedication: it scrolls on air, checked automatically before you sign.`, cta: "Pick a track", go: PICK },
      { g: "quarter", title: "Free picks", line: `Some artists refund your pick once it has played in full: look for "free pick" when you choose. For wallets with some pick history, a few a day; collect it within 7 days.`, cta: "Find one", go: PICK },
      { g: "square", title: "A share of tips", line: `When an artist sets a promo share (0 to ${String(MAX_PROMO)}%, off by default), part of each tip made while your pick plays goes to you, and to whoever's link brought the tipper. It is shown before anyone signs.`, cta: "Top curators", go: { view: { k: "community" } } },
      { g: "square", title: "Tip an artist", line: TIP_LINE, cta: "Support an artist", go: { view: { k: "community" } } },
      { g: "circle", title: "Keep what you love", line: "Save tracks in your browser for free; like, follow artists and publish public playlists on-chain.", cta: "Make a playlist", go: { view: { k: "contribute", path: "listener" } } },
      { g: "triangle", title: "Go to the concert", line: `Find concerts by city, day or price. Free or paid tickets; a paid ticket's price goes 100% to the artist${fees ? ", plus a service fee" : ""}.`, cta: "Concerts", go: { view: { k: "concerts" } } },
    ],
    more: [
      { title: "Your pick on air", line: "When your pick starts, the browser can tell you (if you allow it); when it ends, you see the likes and tips it gained.", go: PICK },
      { title: "Your public page", line: "Your picks, curator rank and playlists, on one page you can share.", go: { view: { k: "me" } } },
      { title: "Your tickets", line: "Show a ticket's QR code at the door, or give it to another wallet.", go: ME_TICKETS },
      { title: "Station jingles", line: "A short jingle when you tune in and at the top of each hour, matched to the genre on Main.", go: { view: { k: "stations", live: 0 } } },
      { title: "Media keys", line: "Play, pause and skip from the keyboard or the lock screen: next station on the radio, next track in the library.", go: { view: { k: "stations", live: 0 } } },
      { title: "Quick actions", line: `Turn on quick actions in the wallet card: a session signs for you until it expires (${String(DAYS)} days) or you turn it off; a daily cap limits its fees and deposits.`, go: { view: { k: "me" } } },
      { title: "No browser wallet", line: "Sign with gnokey instead: the app gives you the command to copy.", go: { view: { k: "me" } } },
      { title: "Report content", line: REPORTS, go: { view: { k: "contribute", path: "report" } } },
      { title: "Weekly top per station", line: "Each station's top curators of the week, rendered by the chain on gnoweb.", go: { href: realmPage("radio") } },
      { title: "Check it on gnoweb", line: "The same radio, rendered by gno.land from the realms, with their source code.", go: { href: realmPage("home") } },
    ],
  },
  {
    id: "artists",
    title: "For artists",
    lead: "Publish once. Get heard. Get tipped.",
    cards: [
      { g: "triangle", title: "In rotation when you publish", line: "Host your file on IPFS, Arweave or an allowed https host and add its link. Your track joins its genre station in the same transaction.", cta: "Publish a track", go: { view: { k: "contribute", path: "artist" } } },
      { g: "triangle", title: "Split with your band", line: `Up to ${String(MAX_SPLITS)} collaborators get their share of every tip; you keep at least 10%.`, cta: "Publish a track", go: { view: { k: "contribute", path: "artist" } } },
      { g: "circle", title: "Verify, then tips open", line: "A short code on your Audius bio or your own domain, a robot check, then a public 72-hour wait. No paperwork, no email.", cta: "Verify your profile", go: { view: { k: "contribute", path: "claim" } } },
      { g: "square", title: "0% to GnoRadio", line: "Tips reach you and your collaborators in the same transaction. GnoRadio never holds them.", cta: "How tips work", go: { view: { k: "about" } } },
      { g: "quarter", title: "Reward your curators", line: `Choose a promo share from 0 to ${String(MAX_PROMO)}%: it goes to listeners who put your track on air and to whoever shared the link. Once you are verified.`, cta: "Set it in Me", go: ME_MUSIC },
      { g: "quarter", title: "Sponsor picks", line: `Fund a budget that refunds listeners who pick your tracks, ${REFUND}. A daily cap; withdraw what isn't reserved at any time. Once you are verified.`, cta: "Set it in Me", go: ME_MUSIC },
      { g: "square", title: "Sell tickets", line: "Free or paid NFT tickets. The price goes 100% to you; fans check in at the door with a QR code.", cta: "Concerts", go: { view: { k: "concerts" } } },
      { g: "triangle", title: "Stay in control", line: "Edit your tracks; hide and show again your tracks, albums or profile. Every moderation removal carries a public reason.", cta: "Your music", go: ME_MUSIC },
    ],
    more: [
      { title: "Announce a concert", line: "Set the venue, date, price and seats in a form on gno.land.", go: { href: txURL("tickets", "CreateEvent") } },
      { title: "Make an album", line: "Group your tracks into an album, in a form on gno.land.", go: { href: txURL("catalog", "CreateAlbum") } },
      { title: "Check in at the door", line: CHECK_IN, go: { view: { k: "concerts" } } },
      { title: "Imported already?", line: IMPORTED, go: { view: { k: "contribute", path: "claim" } } },
    ],
  },
];

/** moneyRows: where each payment goes, as [what, where, note]; the fee rows only while fees are on. */
export const moneyRows = (fees: boolean): readonly (readonly [string, string, string])[] => [
  ["Tip to an artist", "0% to GnoRadio", `Split with collaborators as the artist declared it. The artist's promo share (0 to ${String(MAX_PROMO)}%, off until the artist sets it) goes to the listener who picked it on air and whoever shared the link.`],
  ["Free pick", "Paid by the artist", `The artist's budget refunds your pick once it has played in full (${String(PICK_PAY.def)} GNOT by default, enough that it costs you nothing). Collect it within 7 days. For wallets with some pick history, a few a day.`],
  ...(fees ? [["Optional, on top of a tip", "+10% to the treasury", `Off by default. ${TREASURY_USE}`] as const] : []),
  ["Paid concert ticket", "Price to the artist", `The ticket price goes 100% to the artist${fees ? "; a service fee is added, for the treasury" : ""}. The artist runs the concert: if it is cancelled, ask them for a refund.`],
  fees ? ["Direct support", "To the treasury", `${TREASURY_USE} ${COSTS}`] : ["GnoRadio fee", "None", NO_FEE],
  ["Storage deposit", "Locked by gno.land", "Returned to whoever's transaction frees the data, e.g. your own Unlike."],
];

/**
 * CANNOT: what nobody can do, whatever their role, and the one admin power that touches
 * future tips (catalog ResetOwner + AssignArtist on an imported profile), said plainly.
 */
export const CANNOT = "Take back a tip once sent: it reaches the artist in the same transaction. Touch an artist's promo budget. Change an artist's split, edit someone else's track or move anyone's ticket. One admin power to know: the admin can give a claimed imported profile to another wallet, and its later tips with it; it is public on chain.";

/** EXAMPLE: a tip on a picked track, worked out with the split the realm applies. */
const tip = 10 * UGNOT, pct = 10;
const { toPicker } = promoSplit(tip, pct, { picker: "picker", ref: "", tipper: "tipper", owner: "artist" });
export const EXAMPLE = `A ${gnot(tip)} tip on a track a listener picked on air, with a ${String(pct)}% promo share: ${gnot(tip - toPicker)} to the artist and their collaborators, ${gnot(toPicker)} to the listener who picked it, 0 to GnoRadio.`;

/** TRUST: why GnoRadio can be checked rather than believed. */
export const TRUST = [
  ["GnoRadio never holds your money", "Tips, tickets and support are paid out in the same transaction; promo budgets can be withdrawn by their funder at any time, even while GnoRadio is paused."],
  ["Check it yourself", "Every action is a transaction, and gnoweb renders every page from the chain."],
  ["What it costs to run", COSTS],
] as const;

/** hrefOf is a feature's link as a plain URL (the pick sheet opens from the live radio). */
export const hrefOf = (go: Go, path: (v: View) => string): string =>
  "href" in go ? go.href : "pick" in go ? path({ k: "stations", live: 0 }) : `${path(go.view)}${go.hash ? `#${go.hash}` : ""}`;

/** AUDIENCES is the feature list with no fee: the static copy (prerender) and the default. */
export const AUDIENCES = audiences(false);
