import { type Glyph, Shape } from "../components/Shapes";

// One pure glyph per genre: the 4 shapes × the 3 colours give exactly 12, ids 1..12.
const SHAPES: readonly Glyph[] = ["square", "circle", "triangle", "quarter"];
const COLOURS = ["var(--blue)", "var(--yellow)", "var(--red)"] as const;

export function genreGlyph(id: number): { readonly g: Glyph; readonly fill: string } {
  const i = Math.max(0, id - 1);
  return { g: SHAPES[i % 4] ?? "circle", fill: COLOURS[Math.floor(i / 4) % 3] ?? "var(--red)" };
}

/** GenreGlyph draws a genre's shape; muted greys it until hovered or chosen. */
export function GenreGlyph({ id, size = 12, muted = false }: { readonly id: number; readonly size?: number; readonly muted?: boolean }) {
  const { g, fill } = genreGlyph(id);
  return <Shape g={g} size={size} fill={muted ? "var(--tick)" : fill} />;
}
