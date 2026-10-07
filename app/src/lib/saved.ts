import { useCallback, useState } from "react";
import { track } from "./analytics";

const KEY = "gnoradio.saved";

function read(): number[] {
  try {
    const v: unknown = JSON.parse(localStorage.getItem(KEY) ?? "[]");
    return Array.isArray(v) ? v.filter((x): x is number => typeof x === "number") : [];
  } catch {
    return [];
  }
}

/** useSaved keeps the listener's private saves in this browser only. */
export function useSaved() {
  const [ids, setIds] = useState<number[]>(read);
  const toggle = useCallback((id: number) => {
    setIds((cur) => {
      const next = cur.includes(id) ? cur.filter((x) => x !== id) : [id, ...cur];
      track("save", { on: next.length > cur.length });
      try {
        localStorage.setItem(KEY, JSON.stringify(next));
      } catch {
        // private mode: keep it for this session only
      }
      return next;
    });
  }, []);
  return { ids, has: (id: number) => ids.includes(id), toggle } as const;
}

/** Saved is what a screen needs of the saves: is a track saved, save or unsave it. */
export type Saved = Pick<ReturnType<typeof useSaved>, "has" | "toggle">;
