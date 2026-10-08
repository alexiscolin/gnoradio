import { afterEach, describe, expect, it, vi } from "vitest";

afterEach(() => { vi.unstubAllEnvs(); vi.resetModules(); });

describe("rulesVersion", () => {
  it("is v1 with no release set", async () => {
    const { REALMS } = await import("./realms");
    expect(REALMS.radio).toMatch(/\/radio\/v1$/);
  });
  it("switches to the release at its takeover time, not before", async () => {
    vi.stubEnv("VITE_RULES_VERSION", "v2");
    vi.stubEnv("VITE_RULES_FROM", "1791762213");
    const { rulesVersion } = await import("./realms");
    expect(rulesVersion(1791762212)).toBe("v1");
    expect(rulesVersion(1791762213)).toBe("v2");
  });
  it("is the release at once with no takeover time", async () => {
    vi.stubEnv("VITE_RULES_VERSION", "v2");
    const { REALMS } = await import("./realms");
    expect(REALMS.catalog).toMatch(/\/catalog\/v2$/);
    expect(REALMS.data).toMatch(/\/data$/);
  });
});
