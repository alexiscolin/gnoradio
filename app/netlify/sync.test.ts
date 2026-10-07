// @vitest-environment node
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import sync from "./functions/sync.mjs";
import { REALMS } from "../src/lib/realms";

const chain = vi.hoisted(() => ({ connects: 0, needs: "(false bool)", evals: [] as string[], sent: [] as unknown[][] }));
vi.mock("@gnolang/gno-js-client", () => ({
  GnoJSONRPCProvider: {
    create: () => {
      chain.connects++;
      return Promise.resolve({
        evaluateExpression: (pkg: string, expr: string) => {
          chain.evals.push(`${pkg}.${expr}`);
          return Promise.resolve(chain.needs);
        },
      });
    },
  },
  GnoWallet: {
    fromMnemonic: () => Promise.resolve({ connect: () => undefined, callMethod: (...args: unknown[]) => Promise.resolve(chain.sent.push(args)) }),
  },
}));

beforeEach(() => {
  Object.assign(chain, { connects: 0, needs: "(false bool)", evals: [], sent: [] });
  vi.stubEnv("BOT_MNEMONIC", "test mnemonic");
});
afterEach(() => {
  vi.unstubAllEnvs();
});

describe("sync", () => {
  it("stays off unless SYNC_ROBOT=on", async () => {
    vi.stubEnv("SYNC_ROBOT", "");
    expect(await (await sync()).json()).toEqual({ sent: false, enabled: false });
    vi.stubEnv("SYNC_ROBOT", "true");
    expect(await (await sync()).json()).toEqual({ sent: false, enabled: false });
    expect(chain.connects).toBe(0);
  });

  it("pays nothing when NeedsSync is false", async () => {
    vi.stubEnv("SYNC_ROBOT", "on");
    expect(await (await sync()).json()).toEqual({ sent: false, needed: false });
    expect(chain.evals).toEqual([`${REALMS.radio}.NeedsSync()`]);
    expect(chain.sent).toEqual([]);
  });

  it("sends one Sync when NeedsSync is true", async () => {
    vi.stubEnv("SYNC_ROBOT", "on");
    chain.needs = "(true bool)";
    expect(await (await sync()).json()).toEqual({ sent: true, needed: true });
    expect(chain.sent).toHaveLength(1);
    expect(chain.sent[0]?.slice(0, 3)).toEqual([REALMS.radio, "Sync", ["20"]]);
  });

  it("reports not sent without a robot key", async () => {
    vi.stubEnv("SYNC_ROBOT", "on");
    vi.stubEnv("BOT_MNEMONIC", "");
    chain.needs = "(true bool)";
    expect(await (await sync()).json()).toEqual({ sent: false, needed: true });
    expect(chain.sent).toEqual([]);
  });
});
