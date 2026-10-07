import { type CSSProperties, useEffect, useRef, useState } from "react";
import { createPortal } from "react-dom";

const W = 240; // popover width; it is fixed-positioned and clamped so no panel edge clips it

/**
 * Help is a small round "?" that opens one short sentence. Hover, focus or tap
 * opens it; Escape or a tap outside closes it. Use at most one per block.
 */
export function Help({ text, more }: { readonly text: string; readonly more?: string }) {
  const [open, setOpen] = useState(false);
  const [pos, setPos] = useState<CSSProperties>({});
  const ref = useRef<HTMLSpanElement>(null);
  // A short grace period lets the pointer travel from the "?" to the popover (to reach "Learn more").
  const timer = useRef(0);
  const leave = () => { timer.current = window.setTimeout(() => { setOpen(false); }, 160); };
  const stay = () => { window.clearTimeout(timer.current); };
  const show = () => {
    const b = ref.current?.getBoundingClientRect();
    if (b) {
      const left = Math.min(Math.max(8, b.left + b.width / 2 - W / 2), window.innerWidth - W - 8);
      setPos(b.top > 140 ? { left, bottom: window.innerHeight - b.top + 8 } : { left, top: b.bottom + 8 });
    }
    stay();
    setOpen(true);
  };
  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => { if (e.key === "Escape") setOpen(false); };
    const onDown = (e: PointerEvent) => {
      const t = e.target as Element;
      if (!ref.current?.contains(t) && !t.closest(".help-pop")) setOpen(false);
    };
    window.addEventListener("keydown", onKey);
    window.addEventListener("pointerdown", onDown);
    return () => { window.removeEventListener("keydown", onKey); window.removeEventListener("pointerdown", onDown); };
  }, [open]);
  return (
    <span ref={ref} className="help" onMouseEnter={show} onMouseLeave={leave}>
      <button type="button" className="help-q" aria-label="Help" aria-expanded={open} onClick={(e) => { e.stopPropagation(); if (open) setOpen(false); else show(); }}>?</button>
      {/* Rendered on <body>: no panel overflow, transform or containment can clip or shift it. */}
      {open && createPortal(
        <span className="help-pop" role="tooltip" style={pos} onMouseEnter={stay} onMouseLeave={leave}>
          {text}
          {more && <> <a href={more}>Learn more</a></>}
        </span>,
        document.body,
      )}
    </span>
  );
}
