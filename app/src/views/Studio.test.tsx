import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import type { Catalog } from "../lib/types";
import type { Actions } from "../player/useActions";
import { Studio } from "./Community";

vi.mock("../lib/names", () => ({ useNames: () => () => "@alice" }));

afterEach(cleanup);

const cat = { tracks: [], albums: [], playlists: [], artists: new Map(), stations: [{ id: 0, name: "Main" }], pending: 0 } as unknown as Catalog;

describe("Studio", () => {
  it("refreshes a long discography batch by batch, each click from where the last ended", () => {
    const refreshArtist = vi.fn();
    render(<Studio cat={cat} go={() => undefined} actions={{ refreshArtist } as unknown as Actions} />);
    fireEvent.change(screen.getByLabelText("Type"), { target: { value: "artist" } });
    fireEvent.change(screen.getByLabelText(/^Number/), { target: { value: "4" } });
    const btn = () => screen.getByRole("button", { name: /Refresh its tracks' station slots/ });
    fireEvent.click(btn());
    fireEvent.click(btn());
    expect(refreshArtist.mock.calls).toEqual([[4, 0], [4, 50]]);
    fireEvent.change(screen.getByLabelText(/^Number/), { target: { value: "5" } }); // another artist starts over
    fireEvent.click(btn());
    expect(refreshArtist).toHaveBeenLastCalledWith(5, 0);
  });
});
