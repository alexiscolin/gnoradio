import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { track } from "../lib/analytics";
import { EMPTY_SUPPORT } from "../lib/community";
import { AUDIENCES, VIDEO } from "../lib/features";
import type { Catalog } from "../lib/types";
import { Features } from "./Features";

vi.mock("../lib/analytics", () => ({ track: vi.fn() }));

afterEach(cleanup);

const first = (text: string): HTMLElement => {
  const [el] = screen.getAllByText(text);
  if (!el) throw new Error(text);
  return el;
};

const cat = { tracks: [{ id: 1 }, { id: 2 }], artists: new Map([[1, {}]]), stations: [{ id: 0, tracks: 2 }], playlists: [{ id: 1 }] } as unknown as Catalog;

describe("Features", () => {
  const setup = () => {
    const go = vi.fn(), openPick = vi.fn();
    const r = render(<Features cat={cat} support={EMPTY_SUPPORT} go={go} openPick={openPick} me="" />);
    return { go, openPick, ...r };
  };
  it("shows every feature, each with a real link", () => {
    const { container } = setup();
    const h3 = [...container.querySelectorAll("h3")].map((h) => h.textContent);
    for (const f of AUDIENCES.flatMap((a) => [...a.cards, ...a.more])) expect(h3.some((t) => t.startsWith(f.title))).toBe(true);
    expect(container.querySelectorAll("h1")).toHaveLength(1);
    for (const a of container.querySelectorAll("a")) expect(a.getAttribute("href")).toMatch(/^(\/|https?:)/);
  });
  it("follows a card inside the app, to its spot, and opens the pick sheet", () => {
    const { go, openPick, container } = setup();
    fireEvent.click(first("Set it in Me"));
    expect(go).toHaveBeenCalledWith({ k: "me" });
    expect(container.querySelector('a[href="/me#me-make-music"]')).not.toBeNull();
    expect(track).toHaveBeenCalledWith("cta", { page: "features", at: "card", to: "me" });
    fireEvent.click(first("Pick a track"));
    expect(openPick).toHaveBeenCalledWith(0);
  });
  it("is short: 8 cards per audience, minor features folded, the 3 strongest counts", () => {
    const { container } = setup();
    for (const a of AUDIENCES) expect(a.cards).toHaveLength(8);
    const folds = container.querySelectorAll("details.feat-more-box");
    expect(folds).toHaveLength(2);
    for (const d of folds) expect(d.hasAttribute("open")).toBe(false);
    expect(container.querySelectorAll(".about-facts li")).toHaveLength(3);
    // Be the DJ and Make music come right after the video and counts, before the feature lists.
    const order = [...container.querySelectorAll(".feat-final, #listeners")].map((e) => e.className || e.id);
    expect(order[0]).toContain("feat-final");
  });
  it("plays the promo only on demand, with its caption and credit", () => {
    const { container } = setup();
    const v = container.querySelector("video");
    expect(v?.hasAttribute("autoplay")).toBe(false);
    expect(v?.getAttribute("preload")).toBe("none");
    expect(v?.getAttribute("aria-label")).toBe(VIDEO.caption);
    expect(screen.getByRole("link", { name: "Josh Woodward" }).getAttribute("href")).toBe(VIDEO.music.site);
    expect(screen.getByRole("link", { name: "CC BY 4.0" }).getAttribute("href")).toBe("https://creativecommons.org/licenses/by/4.0/");
  });
});
