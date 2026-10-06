// A tiny runtime schema: chain data is untrusted, so every JSON export is
// checked before the app uses it. Types are derived from the schemas.

export type Guard<T> = (v: unknown) => v is T;
export type Infer<G> = G extends Guard<infer T> ? T : never;

export const str: Guard<string> = (v): v is string => typeof v === "string";
export const num: Guard<number> = (v): v is number => typeof v === "number" && Number.isFinite(v);
export const bool: Guard<boolean> = (v): v is boolean => typeof v === "boolean";

export const arr =
  <T>(g: Guard<T>): Guard<T[]> =>
  (v): v is T[] =>
    Array.isArray(v) && v.every(g);

export const oneOf =
  <const L extends readonly string[]>(...literals: L): Guard<L[number]> =>
  (v): v is L[number] =>
    typeof v === "string" && literals.includes(v);

type Shape = Record<string, Guard<unknown>>;
type FromShape<S extends Shape> = { readonly [K in keyof S]: Infer<S[K]> };

/** obj checks that every listed key has the right type (extra keys are allowed). */
export const obj =
  <S extends Shape>(shape: S): Guard<FromShape<S>> =>
  (v): v is FromShape<S> => {
    if (typeof v !== "object" || v === null) return false;
    const rec = v as Record<string, unknown>;
    return Object.entries(shape).every(([k, g]) => g(rec[k]));
  };

/** opt accepts undefined as well as the guarded type. */
export const opt =
  <T>(g: Guard<T>): Guard<T | undefined> =>
  (v): v is T | undefined =>
    v === undefined || g(v);

/** check narrows v with g or throws a readable error. */
export function check<T>(v: unknown, g: Guard<T>, what: string): T {
  if (!g(v)) throw new Error(`Unexpected data from the chain (${what})`);
  return v;
}
