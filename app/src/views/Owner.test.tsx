import { act, cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import type { Artist, Catalog, ConcertEvent, Playlist, Track } from "../lib/types";
import type { Actions } from "../player/useActions";
import type { Player } from "../player/usePlayer";
import { CancelConcert, PlaylistView, TrackView } from "./Detail";
import { Me } from "./Community";

// What an owner can do on their own things: cancel a concert, give a ticket, edit a track or a playlist, hide a track.

const ME = "g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5";
const OTHER = "g1y2tswmrtlany2ffmpyc0uyunk4gt4gv8gtf736";

vi.mock("../lib/community", async (orig) => ({
  ...(await orig<object>()),
  loadUser: () => Promise.resolve({ address: ME, likes: 0, follows: 0, tipped: 0, playlists: [], artist: 0 }),
  loadTicketsOf: () => Promise.resolve([{ id: 7, event: 2, serial: 1, attended: false }]),
  hostAllowed: () => Promise.resolve(true),
}));
vi.mock("../lib/incentives", async (orig) => ({
  ...(await orig<object>()),
  loadCurator: () => Promise.reject(new Error("none")),
  useSponsored: () => null,
}));
vi.mock("../lib/names", () => ({ useNames: () => () => "@alice" }));

afterEach(cleanup);

const fakeActions = (owner: string) => ({
  pending: "", liked: new Set(), following: new Set(),
  wallet: { state: { status: "connected", address: owner }, connectWallet: vi.fn() },
  cancelEvent: vi.fn(), giveTicket: vi.fn(), editTrack: vi.fn(), updatePlaylist: vi.fn(), hideOwn: vi.fn(),
}) as unknown as Actions & Record<"cancelEvent" | "giveTicket" | "editTrack" | "updatePlaylist" | "hideOwn", ReturnType<typeof vi.fn>>;

const track = {
  id: 3, artist: 1, artistName: "Lea", claimed: true, origin: "artist", title: "Air", genre: 2, duration: 222, license: "CC-BY-4.0", cmo: "none",
  credits: "", audio: "ipfs://bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi", audioSha256: "", cover: "", coverSha256: "", source: "", attribution: "", album: 0,
  created: 0, likes: 0, tips: 0, supporters: 0, splits: [],
} as Track;
const artist = { id: 1, name: "Lea", kind: "artist", owner: ME, verified: false, tracks: [3], albums: [], proofHost: "" } as unknown as Artist;
const event = { id: 2, artist: 1, title: "Release Party", venue: "La Station", link: "", start: 2_000_000_000, price: 0, capacity: 50, sold: 3, cancelled: false } as ConcertEvent;
const playlist: Playlist = { id: 9, owner: ME, title: "Late Night", updated: 0, tracks: [3] };
const cat = {
  tracks: [track], byId: new Map([[3, track]]), artists: new Map([[1, artist]]), albums: [], playlists: [playlist],
  genres: [{ id: 1, name: "Ambient" }, { id: 2, name: "Techno" }], stations: [], pending: 0, newFloor: 0, events: [event], admin: "",
} as unknown as Catalog;
const player = { playList: vi.fn() } as unknown as Player;

describe("CancelConcert", () => {
  it("asks before cancelling, then signs", () => {
    const a = fakeActions(ME);
    render(<CancelConcert e={event} actions={a} />);
    fireEvent.click(screen.getByRole("button", { name: "Cancel concert" }));
    expect(screen.getByText(/3 tickets sold/)).toBeTruthy();
    expect(a.cancelEvent).not.toHaveBeenCalled();
    fireEvent.click(screen.getByRole("button", { name: "Yes, cancel concert" }));
    expect(a.cancelEvent).toHaveBeenCalledWith(event);
  });
});

describe("TrackView for its artist", () => {
  it("edits the fields EditTrack takes and hides after a confirm", () => {
    const a = fakeActions(ME);
    render(<TrackView cat={cat} player={player} go={() => undefined} id={3} actions={a} openSupport={() => undefined} openPick={() => undefined} />);
    fireEvent.click(screen.getByRole("button", { name: "Edit" }));
    fireEvent.change(screen.getByLabelText("Title"), { target: { value: "Air, edit" } });
    fireEvent.click(screen.getByRole("button", { name: "Save changes" }));
    expect(a.editTrack).toHaveBeenCalledWith(track, expect.objectContaining({ title: "Air, edit", genre: 2, duration: "3:42", audio: "ipfs://bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi" }), expect.any(Function));
    fireEvent.click(screen.getByRole("button", { name: "Hide track" }));
    fireEvent.click(screen.getByRole("button", { name: "Yes, hide track" }));
    expect(a.hideOwn).toHaveBeenCalledWith("track", 3, true);
  });

  it("shows no owner controls to someone else", () => {
    render(<TrackView cat={cat} player={player} go={() => undefined} id={3} actions={fakeActions(OTHER)} openSupport={() => undefined} openPick={() => undefined} />);
    expect(screen.queryByRole("button", { name: "Edit" })).toBeNull();
    expect(screen.queryByRole("button", { name: "Hide track" })).toBeNull();
  });

  it("links the track's page on gnoweb, in a new tab", () => {
    render(<TrackView cat={cat} player={player} go={() => undefined} id={3} actions={fakeActions(OTHER)} openSupport={() => undefined} openPick={() => undefined} />);
    const link = screen.getByRole("link", { name: /on gno\.land, opens a new tab/ });
    expect(link.getAttribute("href")).toMatch(/\/home\/v1:track\/3$/);
    expect(link.getAttribute("target")).toBe("_blank");
  });
});

describe("PlaylistView for its owner", () => {
  it("updates title and tracks with UpdatePlaylist", () => {
    const a = fakeActions(ME);
    render(<PlaylistView cat={cat} player={player} go={() => undefined} id={9} actions={a} saved={{ has: () => false, toggle: vi.fn() }} />);
    fireEvent.click(screen.getByRole("button", { name: "Edit" }));
    fireEvent.change(screen.getByLabelText("Title"), { target: { value: "Later Night" } });
    fireEvent.click(screen.getByRole("button", { name: "Save playlist" }));
    expect(a.updatePlaylist).toHaveBeenCalledWith(9, "Later Night", [3], expect.any(Function));
  });
});

describe("Me tickets", () => {
  it("gives a ticket only to a canonical address", async () => {
    const a = fakeActions(ME);
    render(<Me cat={cat} go={() => undefined} actions={a} saved={{ ids: [] } as never} openPick={() => undefined} />);
    await act(async () => { await Promise.resolve(); });
    fireEvent.click(await screen.findByRole("button", { name: "Give" }));
    const input = screen.getByLabelText("Give to");
    fireEvent.change(input, { target: { value: OTHER.toUpperCase() } });
    expect(screen.getByRole("alert").textContent).toMatch(/lower case/);
    expect(screen.getByRole<HTMLButtonElement>("button", { name: "Give ticket" }).disabled).toBe(true);
    fireEvent.change(input, { target: { value: OTHER } });
    fireEvent.click(screen.getByRole("button", { name: "Give ticket" }));
    expect(a.giveTicket).toHaveBeenCalledWith(7, OTHER, expect.any(Function));
  });
});
