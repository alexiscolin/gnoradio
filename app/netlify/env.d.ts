// Netlify functions run on Node; this is the only Node API they use.
declare const process: { env: Record<string, string | undefined> };
// Netlify edge functions (Deno) read their environment through this global.
declare const Netlify: { env: { get: (key: string) => string | undefined } };
