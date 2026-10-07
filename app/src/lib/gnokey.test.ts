import { describe, expect, it } from "vitest";
import { REALMS } from "./gno";
import { feeFor, gasFor, gnokeyCommand, shellQuote } from "./gnokey";

const ON = ["onyx-1", "https://rpc.onyx.testnets.gno.land:443"] as const;

describe("gnokeyCommand", () => {
  it("writes the gnoweb-style call for a listener action", () => {
    expect(gnokeyCommand({ pkg: REALMS.catalog, func: "Like", args: ["12"] }, ...ON, "alice")).toBe(
      "gnokey maketx call -pkgpath gno.land/r/gnoradio/catalog/v0 -func Like -args '12' -gas-fee 40000ugnot -gas-wanted 40000000 -broadcast -chainid 'onyx-1' -remote 'https://rpc.onyx.testnets.gno.land:443' 'alice'",
    );
  });
  it("sends coins only when the call is payable", () => {
    const tip = gnokeyCommand({ pkg: REALMS.catalog, func: "TipWithSupport", args: ["3", "10"], send: 2_500_000 }, ...ON, "alice");
    expect(tip).toContain("-args '3' -args '10' -send 2500000ugnot -gas-fee");
    expect(gnokeyCommand({ pkg: REALMS.catalog, func: "Like", args: ["1"], send: 0 }, ...ON, "alice")).not.toContain("-send");
  });
  it("quotes arguments so the shell passes them through untouched", () => {
    const bio = `It's "live" $HOME; rm -rf / \`x\` & more\nline two`;
    const cmd = gnokeyCommand({ pkg: REALMS.catalog, func: "RegisterArtist", args: ["Léa", bio] }, ...ON, "my key");
    expect(cmd).toContain(`-args 'Léa' -args 'It'\\''s "live" $HOME; rm -rf / \`x\` & more\nline two'`);
    expect(cmd.endsWith(" 'my key'")).toBe(true);
    expect(gnokeyCommand({ pkg: REALMS.catalog, func: "Report", args: ["track", "1", ""] }, ...ON, "k")).toContain("-args '1' -args '' -gas-fee");
  });
  it("names the chain and the node, and holds a place for the key", () => {
    const cmd = gnokeyCommand({ pkg: REALMS.radio, func: "Sync", args: ["20"] }, "gnoland-1", "https://rpc.gno.land:443", "  ");
    expect(cmd).toContain("-chainid 'gnoland-1' -remote 'https://rpc.gno.land:443' 'YOUR_KEY_NAME'");
    expect(cmd).toContain(`-gas-fee ${String(feeFor(gasFor("Sync")))}ugnot -gas-wanted 500000000`);
  });
});

describe("shellQuote", () => {
  it("closes, escapes and reopens around a single quote", () => {
    expect(shellQuote("a'b")).toBe(`'a'\\''b'`);
  });
});
