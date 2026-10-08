// @vitest-environment node
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { readBody, refuse, signCertificate } from "./bot";
import { keyPair, verifies } from "./testing";

let n = 0;
const req = (init: { method?: string; origin?: string; length?: number; ip?: string } = {}) => {
  const headers = new Headers({ "x-nf-client-connection-ip": init.ip ?? `10.0.0.${String(++n)}` });
  if (init.origin !== undefined) headers.set("origin", init.origin);
  if (init.length !== undefined) headers.set("content-length", String(init.length));
  return new Request("https://radio.example/api/x", { method: init.method ?? "POST", headers });
};

beforeEach(() => { vi.stubEnv("VITE_GNORADIO_NS", "gnoradio"); });
afterEach(() => {
  vi.unstubAllEnvs();
});

describe("refuse", () => {
  it("accepts POST only", () => {
    vi.stubEnv("URL", "https://radio.example");
    expect(refuse(req({ method: "GET", origin: "https://radio.example" }), 5)?.status).toBe(405);
  });

  it("accepts this site's Origin only when URL is set", () => {
    vi.stubEnv("URL", "https://radio.example");
    vi.stubEnv("NETLIFY_DEV", "true"); // ignored once URL is set
    expect(refuse(req({ origin: "https://radio.example" }), 5)).toBeNull();
    expect(refuse(req({ origin: "https://evil.example" }), 5)?.status).toBe(403);
    expect(refuse(req({ origin: "null" }), 5)?.status).toBe(403);
    expect(refuse(req(), 5)?.status).toBe(403);
  });

  it("lets a call without URL through under netlify dev only", () => {
    vi.stubEnv("URL", "");
    vi.stubEnv("NETLIFY_DEV", "");
    expect(refuse(req(), 5)?.status).toBe(403);
    vi.stubEnv("NETLIFY_DEV", "true");
    expect(refuse(req(), 5)).toBeNull();
  });

  it("accepts a deploy preview's own origin, and refuses to run without its namespace", () => {
    vi.stubEnv("URL", "https://radio.example");
    vi.stubEnv("DEPLOY_PRIME_URL", "https://deploy-preview-3--radio.netlify.app");
    expect(refuse(req({ origin: "https://deploy-preview-3--radio.netlify.app" }), 5)).toBeNull();
    vi.stubEnv("VITE_GNORADIO_NS", "");
    vi.stubEnv("NETLIFY_DEV", "");
    expect(refuse(req({ origin: "https://radio.example" }), 5)?.status).toBe(503);
  });

  it("counts an IPv6 client by its /64", () => {
    vi.stubEnv("URL", "https://radio.example");
    const call = (ip: string) => refuse(req({ origin: "https://radio.example", ip }), 1)?.status;
    expect(call("2001:db8:1:2::1")).toBeUndefined();
    expect(call("2001:db8:1:2::ffff")).toBe(429);
  });

  it("caps the body at 4 KB", () => {
    vi.stubEnv("URL", "https://radio.example");
    expect(refuse(req({ origin: "https://radio.example", length: 4096 }), 5)).toBeNull();
    expect(refuse(req({ origin: "https://radio.example", length: 4097 }), 5)?.status).toBe(413);
  });

  it("limits calls per client IP per minute", () => {
    vi.stubEnv("URL", "https://radio.example");
    const call = (ip: string) => refuse(req({ origin: "https://radio.example", ip }), 2)?.status;
    expect(call("1.1.1.1")).toBeUndefined();
    expect(call("1.1.1.1")).toBeUndefined();
    expect(call("1.1.1.1")).toBe(429);
    expect(call("2.2.2.2")).toBeUndefined();
  });

  it("forgets calls older than a minute", () => {
    vi.useFakeTimers();
    try {
      vi.stubEnv("URL", "https://radio.example");
      const call = () => refuse(req({ origin: "https://radio.example", ip: "3.3.3.3" }), 1)?.status;
      expect(call()).toBeUndefined();
      expect(call()).toBe(429);
      vi.advanceTimersByTime(61_000);
      expect(call()).toBeUndefined();
    } finally {
      vi.useRealTimers();
    }
  });
});

describe("signCertificate", () => {
  it("signs with BOT_SIGNING_KEY a signature the public key verifies", async () => {
    const { seed, publicKey } = await keyPair();
    vi.stubEnv("BOT_SIGNING_KEY", seed);
    const sig = await signCertificate("gnoradio claim 1");
    expect(sig).toMatch(/^[0-9a-f]{128}$/);
    expect(await verifies(publicKey, sig, "gnoradio claim 1")).toBe(true);
    expect(await verifies(publicKey, sig, "gnoradio claim 2")).toBe(false);
  });

  it("signs nothing without a well-formed key", async () => {
    vi.stubEnv("BOT_SIGNING_KEY", "");
    expect(await signCertificate("m")).toBe("");
    vi.stubEnv("BOT_SIGNING_KEY", "zz".repeat(32));
    expect(await signCertificate("m")).toBe("");
    vi.stubEnv("BOT_SIGNING_KEY", "ab".repeat(31));
    expect(await signCertificate("m")).toBe("");
  });
});

describe("readBody", () => {
  const chunked = (s: string) => new Request("https://x/api", { method: "POST", body: new ReadableStream({ start(c) { c.enqueue(new TextEncoder().encode(s)); c.close(); } }), duplex: "half" } as RequestInit);
  it("parses a small JSON body without a content-length", async () => {
    expect(await readBody(chunked('{"note":"hi"}'))).toEqual({ note: "hi" });
  });
  it("refuses a body over 4 KB even when no content-length announces it", async () => {
    expect(await readBody(chunked(JSON.stringify({ note: "x".repeat(5000) })))).toBeNull();
  });
  it("refuses a body that is not JSON", async () => {
    expect(await readBody(chunked("not json"))).toBeNull();
  });
});
