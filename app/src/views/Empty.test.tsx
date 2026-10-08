import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { EMPTY_SUPPORT } from "../lib/community";
import { FeesContext } from "../lib/fees";
import type { Catalog } from "../lib/types";
import type { Actions } from "../player/useActions";
import type { Player } from "../player/usePlayer";
import { liveFacts } from "./About";
import { Library, Listen, Stations } from "./Browse";
import { CollectionView } from "./Collection";
import { Concerts } from "./Detail";

// A fresh chain at launch: the realms are there, nothing else. Every screen says so and offers the way in.

afterEach(cleanup);

const empty = {
  tracks: [], byId: new Map(), artists: new Map(), albums: [], playlists: [], genres: [{ id: 1, name: "Ambient" }],
  stations: [{ id: 0, name: "Main", genre: 0, tracks: 0, now: { track: 0, offset: 0 } }], pending: 0, newFloor: 0, events: [], admin: "",
} as unknown as Catalog;
const player = { playList: vi.fn(), goLive: vi.fn(), mode: "live", station: 0 } as unknown as Player;
const actions = { pending: "", liked: new Set(), following: new Set(), wallet: { state: { status: "none" }, connectWallet: vi.fn() } } as unknown as Actions;
const saved = { ids: [], has: () => false, toggle: vi.fn() } as never;
const noBadText = () => { expect(document.body.textContent).not.toMatch(/\bNaN\b|undefined|Infinity|\b0 GNOT\b/); };

describe("empty states", () => {
  it("Listen leads to publishing, hides the zero numbers and the DJ block", () => {
    const go = vi.fn();
    render(<FeesContext.Provider value><Listen cat={empty} player={player} go={go} activity={[]} support={EMPTY_SUPPORT} now={0} openSupport={vi.fn()} openPick={vi.fn()} /></FeesContext.Provider>);
    expect(screen.getByText("Be the first")).toBeTruthy();
    expect(screen.queryByText("Be the DJ")).toBeNull();
    expect(screen.getByText("No track yet: publish the first one.")).toBeTruthy();
    const [first] = screen.getAllByRole("button", { name: /Make music/ });
    if (first) fireEvent.click(first);
    expect(go).toHaveBeenCalledWith({ k: "contribute", path: "artist" });
    noBadText();
  });

  it("Listen offers no support block while GnoRadio takes no fee", () => {
    render(<Listen cat={empty} player={player} go={vi.fn()} activity={[]} support={EMPTY_SUPPORT} now={0} openSupport={vi.fn()} openPick={vi.fn()} />);
    expect(screen.queryByText("Given to GnoRadio by listeners")).toBeNull();
    noBadText();
  });

  it("Library and Stations offer Make music", () => {
    render(<Library cat={empty} player={player} go={vi.fn()} genre={0} actions={actions} saved={saved} />);
    expect(screen.getByPlaceholderText("Search the library")).toBeTruthy();
    expect(screen.getByRole("button", { name: /Make music/ })).toBeTruthy();
    cleanup();
    render(<Stations cat={empty} player={player} go={vi.fn()} />);
    expect(screen.getByText("Nothing on air yet: publish the first track.")).toBeTruthy();
    noBadText();
  });

  it("Concerts asks artists to announce one", () => {
    render(<Concerts cat={empty} go={vi.fn()} player={player} actions={actions} />);
    expect(screen.getByText("No concert announced yet.")).toBeTruthy();
    expect(screen.getByRole("link", { name: /Announce yours/ }).getAttribute("href")).toMatch(/CreateEvent/);
  });

  it("Your library leads back to the Library", () => {
    const go = vi.fn();
    render(<CollectionView cat={empty} player={player} go={go} actions={actions} saved={saved} list="saved" />);
    fireEvent.click(screen.getByRole("button", { name: /Open the Library/ }));
    expect(go).toHaveBeenCalledWith({ k: "library", genre: 0 });
  });

  it("live facts leave the zeros out", () => {
    expect(liveFacts(empty, EMPTY_SUPPORT)).toEqual([]);
  });
});
