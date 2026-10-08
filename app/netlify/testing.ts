// Test helpers for the robot's functions (not deployed: outside functions/).

const hex = (b: ArrayBuffer) => [...new Uint8Array(b)].map((x) => x.toString(16).padStart(2, "0")).join("");
const bytes = (h: string) => Uint8Array.from(h.match(/../g) ?? [], (b) => parseInt(b, 16));

/** keyPair makes an Ed25519 key and returns its 32-byte seed (BOT_SIGNING_KEY) and public key. */
export async function keyPair(): Promise<{ seed: string; publicKey: CryptoKey }> {
  const k = (await crypto.subtle.generateKey({ name: "Ed25519" }, true, ["sign", "verify"]));
  const pkcs8 = new Uint8Array(await crypto.subtle.exportKey("pkcs8", k.privateKey));
  return { seed: hex(pkcs8.slice(-32).buffer), publicKey: k.publicKey };
}

export const verifies = async (publicKey: CryptoKey, sig: string, message: string): Promise<boolean> =>
  crypto.subtle.verify("Ed25519", publicKey, bytes(sig), new TextEncoder().encode(message));

/** str is a vm/qeval string result, as GnoJSONRPCProvider.evaluateExpression returns it. */
export const str = (s: string): string => `(${JSON.stringify(s)} string)`;

let ip = 0;
/** post is a same-site POST from a fresh client IP (the rate limit stays out of the way). */
export const post = (body: unknown): Request =>
  new Request("https://radio.example/api", {
    method: "POST",
    headers: { origin: "https://radio.example", "content-type": "application/json", "x-nf-client-connection-ip": `192.0.2.${String(++ip)}` },
    body: typeof body === "string" ? body : JSON.stringify(body),
  });

/** WALLET is a well-formed g1 address. */
export const WALLET = `g1${"q".repeat(38)}`;

/**
 * chain fakes the node's abci_query for fetch: answer gets the queried "realm.expr" and returns
 * the value the realm's string holds (objects as JSON), or undefined for a realm error.
 */
export const chain = (answer: (q: string) => unknown) => (_url: string, init?: RequestInit): Promise<Response> => {
  const q = Buffer.from((JSON.parse(init?.body as string) as { params: { data: string } }).params.data, "base64").toString();
  const v = answer(q);
  const data = v === undefined ? undefined : Buffer.from(str(typeof v === "string" ? v : JSON.stringify(v))).toString("base64");
  return Promise.resolve(Response.json({ result: { response: { ResponseBase: data === undefined ? { Error: { msg: "panic" } } : { Data: data } } } }));
};
