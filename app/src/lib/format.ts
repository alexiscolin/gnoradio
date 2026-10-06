export const clock = (seconds: number): string => {
  const s = Math.max(0, Math.floor(seconds));
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
};

export const gnot = (ugnot: number): string => `${(ugnot / 1e6).toLocaleString("en", { maximumFractionDigits: 2 })} GNOT`;

export const shortAddr = (a: string): string => (a.length > 12 ? `${a.slice(0, 7)}…${a.slice(-4)}` : a);

export const licenseLabel = (l: string): string => (l === "Audius-OML" ? "Audius Open Music License" : l.replaceAll("-", " "));

export function hostOf(url: string): string {
  try {
    return new URL(url).host.replace(/^www\./, "");
  } catch {
    return "source";
  }
}

/** fnv is the same 32-bit FNV-1a hash the realms use to pick generated covers. */
export function fnv(s: string): number {
  let h = 2166136261 >>> 0;
  for (let i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i);
    h = Math.imul(h, 16777619) >>> 0;
  }
  return h;
}

export const errorMessage = (e: unknown): string => (e instanceof Error ? e.message : String(e));

/** firstNonEmpty returns the first non-empty string (realms use "" for "unset"). */
export const firstNonEmpty = (...xs: readonly (string | undefined)[]): string => xs.find((x) => x !== undefined && x !== "") ?? "";
