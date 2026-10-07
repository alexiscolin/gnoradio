// A readable stand-in for people without a gno.land name: "Coral Vinyl 4F", always the
// same for one address. Colours and radio words only, so no pair can read as an insult
// (no skin colours, no body or animal words).
const COLOURS = [
  "Coral", "Amber", "Indigo", "Teal", "Olive", "Ivory", "Cobalt", "Saffron", "Jade", "Ruby", "Slate", "Sienna",
  "Azure", "Plum", "Mint", "Ochre", "Pearl", "Cedar", "Sage", "Copper", "Lilac", "Denim", "Lemon", "Cherry",
] as const;
const WORDS = [
  "Listener", "Tuner", "Echo", "Melody", "Rhythm", "Chord", "Groove", "Tempo", "Signal", "Wave",
  "Dial", "Record", "Vinyl", "Cassette", "Bassline", "Encore", "Chorus", "Remix", "Beat", "Tune",
] as const;

/** nickname is the deterministic display name of a g1 address: colour, radio word, 2 hex digits. */
export function nickname(addr: string): string {
  let h = 0x811c9dc5; // FNV-1a, 32 bits
  for (let i = 0; i < addr.length; i++) h = Math.imul(h ^ addr.charCodeAt(i), 0x01000193) >>> 0;
  const colour = COLOURS[h % COLOURS.length] ?? "Coral";
  const word = WORDS[Math.floor(h / COLOURS.length) % WORDS.length] ?? "Listener";
  return `${colour} ${word} ${(h >>> 24).toString(16).toUpperCase().padStart(2, "0")}`;
}
