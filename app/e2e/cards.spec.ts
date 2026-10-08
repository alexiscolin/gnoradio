import { expect, test } from "@playwright/test";
import { cardOf } from "../netlify/cards";

// The link-preview expressions (netlify/cards.ts) run against the devnet's real realms:
// the unit tests answer by expression prefix and never compile them.
const RPC = "http://127.0.0.1:27157";

test("link previews compile on-chain: concert and door cards", async () => {
  const concert = await cardOf(RPC, "/concerts/1");
  expect(concert?.title).toBeTruthy();
  expect(concert?.path).toBe("/concerts/1");
  const res = await fetch(RPC, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ jsonrpc: "2.0", id: 1, method: "abci_query", params: { path: "vm/qeval", data: Buffer.from("gno.land/r/gnoradio/tickets/v1.TicketOwner(1)").toString("base64") } }),
  });
  const data = ((await res.json()) as { result: { response: { ResponseBase: { Data: string } } } }).result.response.ResponseBase.Data;
  const holder = /g1[a-z0-9]{38}/.exec(Buffer.from(data, "base64").toString())?.[0] ?? "";
  const door = await cardOf(RPC, `/door/1-${holder}`);
  expect(door?.title).toBeTruthy();
  expect(door?.path).toMatch(/^\/concerts\/\d+$/);
  expect((await cardOf(RPC, "/artist/1"))?.kicker).toMatch(/^Artist · /);
});
