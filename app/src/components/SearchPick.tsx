import { type KeyboardEvent, type ReactNode, useId, useState } from "react";
import { Icon } from "./Icons";

export interface PickItem {
  readonly id: number;
  readonly label: string;
  readonly sub?: string;
  readonly art?: ReactNode;
}

/** fold makes search case- and accent-insensitive: "Rhône" matches "rhone". */
export const fold = (s: string): string => s.normalize("NFD").replace(/\p{M}/gu, "").toLowerCase();

/** matches returns at most `max` items whose label or secondary line contains every typed word. */
export function matches(items: readonly PickItem[], q: string, max = 8): PickItem[] {
  const words = fold(q).split(/\s+/).filter(Boolean);
  if (words.length === 0) return [];
  const out: PickItem[] = [];
  for (const it of items) {
    const hay = fold(`${it.label} ${it.sub ?? ""}`);
    if (words.every((w) => hay.includes(w))) out.push(it);
    if (out.length === max) break;
  }
  return out;
}

/**
 * SearchPick is the combobox for long lists (tracks, artists, reports): type to
 * filter, arrows to move, Enter to choose. The chosen item shows as a chip.
 * With an empty field it offers `suggest` (recent or top items).
 */
export function SearchPick({ label, items, value, onChange, placeholder, suggest = [], hint, keepOpen = false }: {
  readonly label: string;
  readonly items: readonly PickItem[];
  readonly value: number;
  readonly onChange: (id: number) => void;
  readonly placeholder?: string;
  readonly suggest?: readonly PickItem[];
  readonly hint?: string;
  /** keepOpen clears the field after a choice instead of showing a chip (to add several). */
  readonly keepOpen?: boolean;
}) {
  const id = useId();
  const [q, setQ] = useState("");
  const [open, setOpen] = useState(false);
  const [active, setActive] = useState(0);
  const chosen = keepOpen ? undefined : items.find((it) => it.id === value);
  const list = q.trim() ? matches(items, q) : suggest.slice(0, 8);
  const choose = (it: PickItem) => { onChange(it.id); setQ(""); setActive(0); setOpen(keepOpen); };
  const key = (e: KeyboardEvent<HTMLInputElement>) => {
    if (e.key === "ArrowDown") { e.preventDefault(); setOpen(true); setActive((a) => Math.min(a + 1, list.length - 1)); }
    else if (e.key === "ArrowUp") { e.preventDefault(); setActive((a) => Math.max(a - 1, 0)); }
    else if (e.key === "Enter") { const it = list[active]; if (open && it) { e.preventDefault(); choose(it); } }
    else if (e.key === "Escape") { setOpen(false); }
  };
  return (
    <div className="field">
      <label htmlFor={`${id}-in`}>{label}</label>
      {chosen ? (
        <span className="pick-chip">
          {chosen.art}<span><b>{chosen.label}</b>{chosen.sub && <small>{chosen.sub}</small>}</span>
          <button type="button" aria-label={`Clear ${chosen.label}`} onClick={() => { onChange(0); }}><Icon name="close" size={14} /></button>
        </span>
      ) : (
        <div className="combo">
          <Icon name="search" size={16} />
          <input
            id={`${id}-in`}
            role="combobox"
            aria-expanded={open && list.length > 0}
            aria-controls={`${id}-list`}
            aria-autocomplete="list"
            aria-activedescendant={open && list[active] ? `${id}-o${String(active)}` : undefined}
            autoComplete="off"
            value={q}
            placeholder={placeholder}
            onFocus={() => { setOpen(true); }}
            onBlur={() => { window.setTimeout(() => { setOpen(false); }, 120); }}
            onChange={(e) => { setQ(e.target.value); setActive(0); setOpen(true); }}
            onKeyDown={key}
          />
          {open && (q.trim() !== "" || list.length > 0) && (
            <ul className="combo-list" role="listbox" id={`${id}-list`}>
              {list.length === 0 && <li className="combo-empty">No match</li>}
              {list.map((it, i) => (
                <li key={it.id} id={`${id}-o${String(i)}`} role="option" aria-selected={i === active} className={i === active ? "on" : ""}
                  onMouseDown={(e) => { e.preventDefault(); choose(it); }} onMouseEnter={() => { setActive(i); }}>
                  {it.art}<span><b>{it.label}</b>{it.sub && <small>{it.sub}</small>}</span>
                </li>
              ))}
            </ul>
          )}
        </div>
      )}
      {hint && <span className="hint-line">{hint}</span>}
    </div>
  );
}
