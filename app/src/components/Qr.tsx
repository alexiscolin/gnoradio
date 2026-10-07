import { encode } from "uqr";

/** Qr draws text as a QR code: one SVG path, dark modules on a white quiet zone so phones read it on any theme. */
export function Qr({ text, size, label }: { readonly text: string; readonly size: number; readonly label: string }) {
  const { data } = encode(text, { border: 2 });
  const d = data.flatMap((row, y) => row.flatMap((on, x) => (on ? [`M${String(x)} ${String(y)}h1v1h-1z`] : []))).join("");
  return (
    <svg className="qr" width={size} height={size} viewBox={`0 0 ${String(data.length)} ${String(data.length)}`} role="img" aria-label={label} shapeRendering="crispEdges">
      <rect width="100%" height="100%" fill="#fff" />
      <path d={d} fill="#0d0d0d" />
    </svg>
  );
}
