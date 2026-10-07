import AxeBuilder from "@axe-core/playwright";
import type { Page } from "@playwright/test";
import { expect, open, openPick, test } from "./fixtures";

/** scan runs axe, attaches every violation to the report and fails on critical ones (color-contrast aside for now). */
async function scan(page: Page, what: string, include?: string) {
  let axe = new AxeBuilder({ page });
  if (include) axe = axe.include(include);
  const { violations } = await axe.analyze();
  const lines = violations.map((v) => `[${v.impact ?? "?"}] ${v.id}: ${v.help} (${String(v.nodes.length)}) ${v.nodes.slice(0, 3).map((n) => n.target.join(" ")).join(" | ")}`);
  await test.info().attach(`axe ${what}`, { body: lines.join("\n") || "no violation", contentType: "text/plain" });
  for (const l of lines) console.log(`axe ${what} (${test.info().project.name}) ${l}`);
  const critical = violations.filter((v) => v.impact === "critical" && v.id !== "color-contrast");
  expect(critical.map((v) => `${v.id}: ${v.help}`), `critical axe violations on ${what}`).toEqual([]);
}

test("8. axe: Listen", async ({ page }) => { await open(page); await scan(page, "Listen"); });
test("8. axe: Stations", async ({ page }) => { await open(page, "/stations"); await scan(page, "Stations"); });
test("8. axe: Library", async ({ page }) => { await open(page, "/library"); await scan(page, "Library"); });
test("8. axe: Pick sheet", async ({ page, mobile }) => {
  await openPick(page, mobile);
  await scan(page, "Pick sheet", "dialog[open]");
});
