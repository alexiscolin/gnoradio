import { describe, expect, it } from "vitest";
import { hasProof, isSharedHost, privateIP, proofLine, proofPage } from "./proof";

const W = "g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5";
const X = "g1hplnue27uazg4pa7vfhzga64na9skvglqatedj";

describe("proof", () => {
  it("finds the line in a bio", () => {
    expect(hasProof(`Producer from Lyon. ${proofLine(12, W)} thanks!`, 12, W)).toBe(true);
  });
  it("refuses another artist, another wallet, or a page naming two wallets", () => {
    expect(hasProof(proofLine(13, W), 12, W)).toBe(false);
    expect(hasProof(proofLine(12, X), 12, W)).toBe(false);
    expect(hasProof(`${proofLine(12, W)} ${proofLine(12, X)}`, 12, W)).toBe(false);
    expect(hasProof("gnoradio:12:" + W.slice(0, 20), 12, W)).toBe(false);
  });
  it("only reads public https pages", () => {
    expect(proofPage("https://lea.bandcamp.com")?.hostname).toBe("lea.bandcamp.com");
    for (const bad of ["http://a.com", "https://127.0.0.1/x", "https://localhost/x", "https://a.com:8443/x", "https://x.tail8cf12f.ts.net/", "nope"]) expect(proofPage(bad)).toBeNull();
  });
  it("ignores pages anyone can write on", () => {
    expect(isSharedHost("archive.org")).toBe(true);
    expect(isSharedHost("ia800.us.archive.org")).toBe(true);
    expect(isSharedHost("lea.bandcamp.com")).toBe(true);
    expect(isSharedHost("lea.com")).toBe(false);
  });
  it("never fetches internal addresses", () => {
    for (const ip of ["127.0.0.1", "10.1.2.3", "172.20.0.1", "192.168.1.1", "169.254.169.254", "100.100.1.1", "0.0.0.0", "::1", "fd00::1", "fe80::1", "::ffff:10.0.0.1", "198.18.0.1", "192.0.0.8", "64:ff9b::a00:1", "2002:a00:1::1"]) expect(privateIP(ip)).toBe(true);
    for (const ip of ["93.184.216.34", "172.32.0.1", "2606:4700::1111"]) expect(privateIP(ip)).toBe(false);
  });
});
