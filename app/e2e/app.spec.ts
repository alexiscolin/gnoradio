import { TEST1, dialTime, expect, genreStation, nav, open, openPick, player, rpc, test } from "./fixtures";

const esc = (s: string) => s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
const hhmm = (d: Date) => `${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`;

test("1. first load: splash, then Listen with the on-air tile and a ticking dial", async ({ page, mobile }) => {
  await page.goto("/");
  await expect(page.getByText("Community radio · open music · on-chain")).toBeVisible(); // the splash
  await open(page);
  await expect(page).toHaveTitle("Community radio, open music · GnoRadio");
  await expect(page.getByRole("button", { name: /On air · Main/ })).toBeVisible();

  const p = await player(page, mobile);
  const dial = p.getByRole("img", { name: /^\d+:\d\d · of \d+:\d\d · live$/ }); // tuned: a track and its length
  await expect(dial).toBeVisible();
  const t0 = await dialTime(dial);
  await page.waitForTimeout(2_200);
  expect(await dialTime(dial)).not.toBe(t0);
  await expect(p.getByRole("button", { name: "Listen live" })).toContainText("Listen");
});

test("2. navigation: every entry, back/forward", async ({ page }) => {
  const sections: [string, string, string][] = [
    ["Stations", "/stations", "Stations · GnoRadio"],
    ["Library", "/library", "Library · GnoRadio"],
    ["Community", "/community", "Community · GnoRadio"],
    ["Concerts", "/concerts", "Concerts · GnoRadio"],
    ["Contribute", "/contribute", "Contribute · GnoRadio"],
    ["Me", "/me", "Me · GnoRadio"],
    ["Listen", "/", "Community radio, open music · GnoRadio"],
  ];
  await open(page);
  const visited: [string, string][] = [["/", "Community radio, open music · GnoRadio"]];
  for (const [label, path, title] of sections) {
    const entry = nav(page).getByRole("button", { name: label, exact: true });
    if ((await entry.count()) === 0) continue; // the phone tab bar has five entries
    await entry.click();
    await expect(page).toHaveURL(path);
    await expect(page).toHaveTitle(title);
    await expect(entry).toHaveAttribute("aria-current", "page");
    visited.push([path, title]);
  }
  expect(visited.length).toBeGreaterThanOrEqual(6);
  const [prevPath, prevTitle] = visited.at(-2) ?? ["", ""];
  await page.goBack();
  await expect(page).toHaveURL(prevPath);
  await expect(page).toHaveTitle(prevTitle);
  await page.goForward();
  await expect(page).toHaveURL("/");
  await expect(page).toHaveTitle("Community radio, open music · GnoRadio");
});

test("2b. deep links render", async ({ page }) => {
  test.setTimeout(180_000); // ten cold loads; detail pages wait for the whole catalog
  const [genre] = await rpc.genres();
  const track = await rpc.track(1);
  const artist = await rpc.named("Artist", 1);
  const album = await rpc.named("Album", 1);
  const playlist = await rpc.named("Playlist", 1);
  const links: [string, RegExp, string][] = [
    ["/stations", /\/stations$/, "Stations · GnoRadio"],
    ["/library", /\/library$/, "Library · GnoRadio"],
    [`/library/${String(genre?.id)}`, new RegExp(`/library/[a-z0-9-]*${String(genre?.id)}$`), `${genre?.name ?? ""} · GnoRadio`],
    ["/artist/1", /\/artist\/[a-z0-9-]+-1$/, `${artist.name ?? ""} · GnoRadio`],
    ["/track/1", /\/track\/[a-z0-9-]+-1$/, `${track.title} · GnoRadio`],
    ["/album/1", /\/album\/[a-z0-9-]+-1$/, `${album.title ?? ""} · GnoRadio`],
    ["/playlist/1", /\/playlist\/[a-z0-9-]+-1$/, `${playlist.title ?? ""} · GnoRadio`],
    [`/listener/${TEST1}`, new RegExp(`/listener/([a-z0-9-]+-)?${TEST1}$`), ""],
    ["/legal", /\/legal$/, "Legal · GnoRadio"],
    ["/about", /\/about$/, "About · GnoRadio"],
  ];
  await open(page, "/legal");
  for (const [path, url, title] of links) {
    await page.goto(path);
    await expect(nav(page)).toBeVisible({ timeout: 30_000 });
    await expect(page).toHaveURL(url);
    if (title) await expect(page).toHaveTitle(title);
    else await expect(page).toHaveTitle(/ · GnoRadio$/);
    await expect(page.getByRole("main")).not.toContainText(/This (track|artist|album|playlist) is not available\./); // the app's own missing-page line, not a track title
    await expect(page.getByRole("main")).not.toBeEmpty();
  }
});

test("2c. an unknown path says so, with a way home; the phone tab bar shows all seven tabs", async ({ page, mobile }) => {
  await open(page, "/nowhere-here");
  await expect(page).toHaveURL(/\/nowhere-here$/);
  await expect(page).toHaveTitle("Not found · GnoRadio");
  await page.getByRole("button", { name: "Back to Listen" }).click();
  await expect(page).toHaveURL("/");
  if (!mobile) return;
  const width = page.viewportSize()?.width ?? 0;
  for (const label of ["Listen", "Stations", "Library", "Community", "Concerts", "Contribute", "Me"]) {
    const box = await nav(page).getByRole("button", { name: label, exact: true }).boundingBox();
    expect(box && box.x >= 0 && box.x + box.width <= width + 0.5, `${label} fits`).toBe(true);
  }
});

test("3. radio: Listen tunes in with the jingle, stations switch, media session follows", async ({ page, mobile, jingles }) => {
  await open(page);
  let p = await player(page, mobile);
  await expect(p.getByRole("img", { name: /^\d+:\d\d · of / })).toBeVisible();
  expect(jingles, "no jingle on page load").toEqual([]);

  await p.getByRole("button", { name: "Listen live" }).click();
  const stop = p.getByRole("button", { name: "Stop listening" });
  await expect(stop).toContainText("Stop");
  await expect(p.getByRole("button", { name: "Live" })).toHaveAttribute("aria-pressed", "true");
  await expect.poll(() => jingles.length).toBe(1);
  expect(jingles[0]).toMatch(/\/gnoradio-jingles\/main(-\d)?\.mp3$/);

  // The OS media session names what is on air: the player's title, and a track of Main's schedule now.
  const meta = await page.evaluate(() => navigator.mediaSession.metadata?.title ?? "");
  expect(meta).not.toBe("");
  await expect(p.getByRole("button", { name: meta, exact: true })).toBeVisible();
  const sched = await rpc.schedule(0, 900);
  const around = sched.entries.filter((e) => e.start <= sched.now + 10 && e.end >= sched.now - 30);
  const titles = await Promise.all(around.map(async (e) => (await rpc.track(e.track)).title));
  expect(titles).toContain(meta);
  await expect(page).toHaveTitle(new RegExp(`^● ${esc(meta)} · .* — Main live$`));

  // Change station from Stations: the chip follows and the station's jingle plays.
  const st = await genreStation();
  if (mobile) await p.getByRole("button", { name: "Close player" }).click();
  await nav(page).getByRole("button", { name: "Stations", exact: true }).click();
  await page.getByRole("main").getByRole("button", { name: new RegExp(`^${esc(st.name)}`) }).click();
  p = await player(page, mobile);
  await expect(p.getByRole("button", { name: st.name, exact: true })).toBeVisible();
  await expect.poll(() => jingles.length).toBe(2);
  expect(jingles[1]).toMatch(/\/gnoradio-jingles\/[a-z0-9-]+\.mp3$/);
  await expect.poll(() => page.evaluate(() => navigator.mediaSession.metadata?.album ?? "")).toBe(`${st.name} · live on GnoRadio`);
});

test("4. library: search, play (no jingle), drag the dial", async ({ page, mobile, jingles }) => {
  const track = await rpc.track(1);
  await open(page, "/library");
  await page.getByRole("textbox", { name: /Search tracks, artists/ }).fill(`${track.title} ${track.artistName}`);
  // the row whose name ends with the title: "Air", not "Air Pocket"
  const row = page.getByRole("main").getByRole("button", { name: new RegExp(`${esc(track.title)}$`) }).first();
  await expect(row).toBeVisible();
  await row.click();

  const p = await player(page, mobile);
  await expect(p.getByRole("button", { name: "Pause" })).toContainText("Pause");
  await expect(p.getByRole("button", { name: "Lib", exact: true })).toHaveAttribute("aria-pressed", "true");
  await expect(p.getByRole("button", { name: track.title, exact: true })).toBeVisible();
  expect(jingles, "no jingle in the library").toEqual([]);

  const dial = p.getByRole("slider", { name: "Position" });
  await expect(dial).toBeVisible();
  const before = await dialTime(dial);
  const box = await dial.boundingBox();
  if (!box) throw new Error("dial has no box");
  const cx = box.x + box.width / 2, cy = box.y + box.height / 2, r = box.width * 0.42;
  await page.mouse.move(cx, cy - r); // 12 o'clock
  await page.mouse.down();
  await page.mouse.move(cx + r, cy, { steps: 5 }); // 3 o'clock
  await page.mouse.move(cx, cy + r, { steps: 5 }); // 6 o'clock: half the track
  await page.mouse.up();
  await expect.poll(() => dialTime(dial)).toBeGreaterThan(before + 20);
});

test("5. pick next sheet: genre list, step 2, dedication check, time, wallet ask", async ({ page, mobile }) => {
  const { st, sheet } = await openPick(page, mobile);
  const inGenre = await rpc.tracks((t) => t.genre === st.genre);
  // A pointer shows its placeholder name (/api/meta answers nothing under test).
  const titles = inGenre.map((t) => t.title || (t.audio.startsWith("jamendo:") ? "Jamendo track" : "Audius track"));

  // Step 1: only the station's genre.
  const rows = sheet.locator("button[aria-pressed]"); // the track rows
  await expect(rows.first()).toBeVisible();
  // The title is the row's last <b> (the cover draws an empty one first).
  const names = await rows.evaluateAll((els) => els.map((e) => [...e.querySelectorAll("b")].at(-1)?.textContent ?? ""));
  expect(names.length).toBeGreaterThan(0);
  for (const n of names) expect(titles, `"${n}" is a ${st.name} track`).toContain(n);

  // Selecting enables "Next · <title>".
  const push = sheet.getByRole("button", { name: /^(Choose a track|Next · )/ });
  await expect(push).toBeDisabled();
  const row = rows.and(sheet.locator(":enabled")).first();
  const title = (await row.locator("b").last().textContent()) ?? "";
  await row.click();
  await expect(row).toHaveAttribute("aria-pressed", "true");
  await expect(push).toHaveText(`Next · ${title}`);
  await expect(push).toBeEnabled();
  await push.click();

  // Step 2.
  await expect(sheet.getByText(/^Would air at \d\d:\d\d/)).toBeVisible();
  await expect(sheet.getByText(/Costs about [\d.]+ GNOT/)).toBeVisible();
  await expect(sheet.getByText(/about [\d.]+ GNOT locked for storage/)).toBeVisible();
  // An artist's free pick takes no dedication: take the paid pick to check the field.
  const free = sheet.getByRole("checkbox", { name: /^Free pick/ });
  if (await free.isVisible()) await free.uncheck();
  const note = sheet.getByRole("textbox", { name: /Dedication/ });
  for (const bad of ["for you 🎉", "see https://example.com"]) {
    await note.fill(bad);
    await expect(note).toHaveAttribute("aria-invalid", "true");
    await expect(sheet.getByText(/^Dedication: /)).toBeVisible();
  }
  await note.fill("to the night shift");
  await expect(note).toHaveAttribute("aria-invalid", "false");

  await sheet.getByRole("button", { name: "At a time" }).click();
  const time = sheet.getByLabel("Time, in your time zone");
  const [h = 0, m = 0] = (await time.inputValue()).split(":").map(Number);
  const later = new Date();
  later.setHours(h + 1, m, 0, 0);
  await time.fill(hhmm(later));
  await expect(sheet.getByText(`Would air at ${hhmm(later)}`)).toBeVisible();
  await sheet.getByRole("button", { name: "Right away" }).click();

  // No wallet: pushing asks for one, never a terminal command. Nothing is signed.
  await sheet.getByRole("button", { name: "Push on air" }).click();
  await expect(page.getByRole("dialog", { name: "To like, pick or tip, you need a gno.land wallet" })).toBeVisible();
  await expect(page.getByRole("dialog", { name: /with gnokey/ })).toHaveCount(0);
});

test("6. a dedication on air shows as a ticker in the player", async ({ page, mobile }) => {
  const stations = await rpc.stations();
  const scheds = await Promise.all(stations.map((s) => rpc.schedule(s.id)));
  const withNote = scheds.flatMap((s) => s.entries.filter((e) => e.note).map((e) => ({ station: s.station, now: s.now, e })));
  // Dedications fold out of the schedule as they age: with none left, one is put on the track on air (below).
  const first = scheds[0];
  const onAir = first?.entries[0];
  const fallback = first && onAir ? { station: first.station, now: first.now, e: { ...onAir, note: "Happy birthday Ana", by: TEST1 } } : undefined;
  const airing = withNote.find(({ now, e }) => e.start <= now && e.end > now);
  const pick = airing ?? withNote[0] ?? fallback;
  expect(pick, "no station has a schedule on this devnet").toBeDefined();
  if (!pick) return;
  const { station, e } = pick;
  if (!airing) {
    // The seeded dedication airs later: move it onto the track on air now, in the schedule the page reads.
    test.info().annotations.push({ type: "note", description: `dedication "${e.note}" airs later on station ${String(station)}: moved onto the track on air` });
    // The app batches its reads (a JSON-RPC array): patch the schedule's answer wherever it sits.
    interface Query { id?: number; params?: { data?: string } }
    interface Answer { id?: number; result: { response: { ResponseBase: { Data: string } } } }
    const isSched = (q: Query) => Buffer.from(q.params?.data ?? "", "base64").toString().includes(`ScheduleJSON(${String(station)},`);
    const patch = (base: { Data: string }) => {
      const raw = Buffer.from(base.Data, "base64").toString();
      const sched = JSON.parse(JSON.parse(/^\((".*") string\)$/s.exec(raw)?.[1] ?? '""') as string) as { now: number; entries: { start: number; end: number; note: string; by: string; queued: boolean }[] };
      const on = sched.entries.find((x) => x.start <= sched.now && x.end > sched.now);
      if (on) Object.assign(on, { note: e.note, by: e.by || TEST1, queued: true });
      base.Data = Buffer.from(`(${JSON.stringify(JSON.stringify(sched))} string)`).toString("base64");
    };
    await page.route("**/rpc", async (route) => {
      const body = route.request().postDataJSON() as Query | Query[] | null;
      const qs = Array.isArray(body) ? body : body ? [body] : [];
      if (!qs.some(isSched)) return route.fallback();
      const res = await route.fetch();
      const json = (await res.json()) as Answer | Answer[];
      const answers = Array.isArray(json) ? json : [json];
      qs.forEach((q, i) => {
        const ans = Array.isArray(json) ? answers.find((x) => x.id === q.id) : answers[i];
        if (isSched(q) && ans) patch(ans.result.response.ResponseBase);
      });
      await route.fulfill({ response: res, json });
    });
  }
  await open(page, `/live/${String(station)}`);
  const p = await player(page, mobile);
  await expect(p.getByRole("note", { name: `Dedication: ${e.note}` })).toBeVisible();
  await expect(p.getByRole("note")).toContainText(e.note ?? "");
});

test("7. listener page: readable name and gnoweb address link", async ({ page }) => {
  await open(page, `/listener/${TEST1}`);
  const h1 = page.getByRole("heading", { level: 1 });
  await expect(h1).toBeVisible();
  const name = (await h1.textContent())?.trim() ?? "";
  expect(name).not.toBe("");
  expect(name).not.toContain(TEST1);
  const link = page.getByRole("link", { name: new RegExp(TEST1) });
  await expect(link).toBeVisible();
  await expect(link).toHaveAttribute("href", new RegExp(`^http://127\\.0\\.0\\.1:8911/.*${TEST1}`));
});
