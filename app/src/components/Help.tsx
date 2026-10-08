import { type CSSProperties, useEffect, useId, useRef, useState } from "react";
import { createPortal } from "react-dom";

const W = 240; // popover width; it is fixed-positioned and clamped so no panel edge clips it

/**
 * Help is a small round "?" that opens one short sentence. Hover, focus or tap
 * opens it; Escape or a tap outside closes it. Use at most one per block.
 */
export function Help({ text, more }: { readonly text: string; readonly more?: string }) {
  const [open, setOpen] = useState(false);
  const [pos, setPos] = useState<CSSProperties>({});
  // Inside a modal dialog the popover must render in it: the page under a dialog is inert and drawn below.
  const [host, setHost] = useState<Element>(document.body);
  const ref = useRef<HTMLSpanElement>(null);
  const id = useId();
  const btn = useRef<HTMLButtonElement>(null);
  const link = useRef<HTMLAnchorElement>(null);
  const quiet = useRef(false); // focus handed back to the button on close: it must not reopen
  const [byClick, setByClick] = useState(false); // opened from the button: its link takes focus (the popover is portaled, out of Tab order)
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
    setHost(ref.current?.closest("dialog") ?? document.body);
    stay();
    setOpen(true);
  };
  useEffect(() => {
    if (!open) return;
    // Escape closes this popover only, not the sheet or dialog around it (captured first, default prevented).
    const onKey = (e: KeyboardEvent) => {
      if (e.key !== "Escape") return;
      e.preventDefault();
      e.stopPropagation();
      setOpen(false);
      if (link.current && document.activeElement === link.current) { quiet.current = true; btn.current?.focus(); }
    };
    const onDown = (e: PointerEvent) => {
      const t = e.target as Element;
      if (!ref.current?.contains(t) && !t.closest(".help-pop")) setOpen(false);
    };
    window.addEventListener("keydown", onKey, true);
    window.addEventListener("pointerdown", onDown);
    if (byClick) link.current?.focus();
    return () => { window.removeEventListener("keydown", onKey, true); window.removeEventListener("pointerdown", onDown); };
  }, [open, byClick]);
  return (
    <span ref={ref} className="help" onMouseEnter={show} onMouseLeave={leave}>
      <button ref={btn} type="button" className="help-q" aria-label="Help" aria-expanded={open} aria-controls={id} aria-describedby={open ? id : undefined}
        onFocus={() => { if (quiet.current) { quiet.current = false; return; } setByClick(false); show(); }} onBlur={leave}
        onClick={(e) => { e.stopPropagation(); if (open && byClick) { setOpen(false); return; } setByClick(true); if (!open) show(); }}>?</button>
      {/* Rendered on <body> (or its dialog): no panel overflow can clip it. */}
      {open && createPortal(
        <span id={id} className="help-pop" role="tooltip" style={pos} onMouseEnter={stay} onMouseLeave={leave} onFocus={stay} onBlur={leave}>
          {text}
          {more && <> <a ref={link} href={more}>Learn more</a></>}
        </span>,
        host,
      )}
    </span>
  );
}
