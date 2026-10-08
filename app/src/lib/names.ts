// gno.land names (r/sys/users), shown instead of addresses, and registering one
// through the chain's registrar. Same reads as gno-golf's web/lib/chain.ts.
import { useEffect, useSyncExternalStore } from "react";
import { RealmError, SAFE, type SysPath, qeval, unquote } from "./gno";
import { nickname } from "./nickname";
import { isAddress } from "./proof";

const USERS: SysPath = "gno.land/r/sys/users";
const isName = (n: string) => /^[a-z0-9._-]{1,64}$/i.test(n);
/** nameShape is what a new name may look like before the registrar's own checks. */
export const nameShape = (n: string): boolean => /^[a-z0-9_-]{1,64}$/.test(n);

// A query's bool answer, alone or among other results: IsCanonicalTaken
// returns ("…" string) then (true bool), so the bool is not always first.
export const isTrue = (raw: string) => raw.includes("(true bool)");

// In-memory cache, shared by every screen; listeners re-render on new names.
const names = new Map<string, string>();
const listeners = new Set<() => void>();
let version = 0;
let noUsers = false; // a chain without r/sys/users (a bare devnet): stop asking
const bump = () => { version++; for (const l of listeners) l(); };

/** loadNames fetches the names of addresses not cached yet, 100 per read. */
export async function loadNames(addrs: readonly string[]): Promise<void> {
  if (noUsers) return;
  const todo = [...new Set(addrs)].filter((a) => isAddress(a) && !names.has(a));
  for (let i = 0; i < todo.length; i += 100) {
    const chunk = todo.slice(i, i + 100);
    const list = chunk.map((a) => `address("${a}")`).join(", ");
    let out: string;
    try {
      out = unquote(await qeval(USERS, `func() string { o := ""; for _, a := range []address{${list}} { if d := ResolveAddress(a); d != nil { o += d.Name() }; o += "," }; return o }()`));
    } catch (e) {
      if (e instanceof RealmError) noUsers = true;
      return;
    }
    const parts = out.split(",");
    const got = chunk.map((_, j) => { const n = parts[j] ?? ""; return isName(n) ? n : ""; });
    let bad: boolean[];
    try { bad = await blocked(got); } catch { return; } // unchecked names stay short addresses; retried on the next load
    chunk.forEach((a, j) => { names.set(a, bad[j] ? "" : got[j] ?? ""); });
    bump();
  }
}

/** blocked asks p/gnoradio/safe which names are offensive (shown as the address instead), 25 per free read. */
async function blocked(ns: readonly string[]): Promise<boolean[]> {
  const out: boolean[] = ns.map(() => false);
  const named = ns.flatMap((n, i) => (n ? [i] : []));
  for (let i = 0; i < named.length; i += 25) {
    const idx = named.slice(i, i + 25);
    const list = idx.map((j) => JSON.stringify(ns[j])).join(", ");
    const bits = unquote(await qeval(SAFE, `func() string { o := ""; for _, n := range []string{${list}} { if Blocked(n) { o += "1" } else { o += "0" } }; return o }()`));
    idx.forEach((j, k) => { out[j] = bits[k] !== "0"; }); // a short answer hides the name
  }
  return out;
}

/** forgetName drops a cached name, e.g. right after registering one. */
export function forgetName(addr: string): void { names.delete(addr); bump(); }

/** nameOf is the cached name, "" if none or unknown yet. */
export const nameOf = (addr: string): string => names.get(addr) ?? "";

/** displayName is @name once loaded, else the address's readable nickname ("Coral Vinyl 4F"). */
const displayName = (addr: string): string => { const n = names.get(addr); return n ? `@${n}` : nickname(addr); };

/** useNames loads the names of addrs and returns a display function (displayName). */
export function useNames(addrs: readonly string[]): (addr: string) => string {
  useSyncExternalStore((l) => { listeners.add(l); return () => { listeners.delete(l); }; }, () => version);
  const key = addrs.join(",");
  useEffect(() => { void loadNames(key ? key.split(",") : []); }, [key]);
  return displayName;
}

let registrar: Promise<SysPath | ""> | undefined;
/** nameReg finds the chain's name registrar (v0 on onyx, mainnet and gno; v1 on older chains), "" if none. */
export function nameReg(): Promise<SysPath | ""> {
  registrar ??= (async () => {
    for (const r of ["gno.land/r/sys/namereg/v0", "gno.land/r/sys/namereg/v1"] as const) {
      try { await qeval(r, "IsPaused()"); return r; } catch { /* not on this chain */ }
    }
    return "";
  })();
  return registrar;
}

/** nameProblem says why a name cannot be taken ("" if it can): shape, the registrar's rules, then taken or too close. */
export async function nameProblem(name: string): Promise<string> {
  const reg = await nameReg();
  if (!reg) return "This chain has no name registrar.";
  if (!nameShape(name)) return "Lowercase letters, digits, dashes and underscores only.";
  const bad = unquote(await qeval(reg, `func() string { if e := ValidateNymFormat("${name}"); e != nil { return e.Error() }; return "" }()`));
  if (bad) return bad.replace(/^namereg: /, "");
  if (isTrue(await qeval(USERS, `IsNameTaken("${name}")`))) return "That name is taken.";
  return isTrue(await qeval(USERS, `IsCanonicalTaken("${name}")`)) ? "Too close to a name already taken." : "";
}
