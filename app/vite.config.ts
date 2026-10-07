import { defineConfig } from "vitest/config";
import { loadEnv, type Plugin } from "vite";
import react from "@vitejs/plugin-react";

// In dev, /api/<name> runs the Netlify function netlify/functions/<name>.mts
// (the robot: verify, dedication) against the local devnet. Secrets go in
// .env.local: BOT_SIGNING_KEY (the robot key) and OPENAI_API_KEY; without them
// the functions only report what they would do.
function robot(): Plugin {
  return {
    name: "gnoradio-robot",
    configureServer(server) {
      const env = loadEnv("development", process.cwd(), ["BOT_", "OPENAI_"]);
      process.env.BOT_RPC ??= "http://127.0.0.1:27157";
      // Local only: the robot functions accept calls without a site URL, as under `netlify dev`.
      process.env.NETLIFY_DEV ??= "true";
      for (const k of ["BOT_SIGNING_KEY", "BOT_MNEMONIC", "OPENAI_API_KEY"]) if (env[k]) process.env[k] ??= env[k];
      for (const name of ["verify", "dedication"]) {
        server.middlewares.use(`/api/${name}`, (req, res) => {
          const chunks: Buffer[] = [];
          req.on("data", (c: Buffer) => chunks.push(c));
          req.on("end", () => {
            void (async () => {
              const mod = (await server.ssrLoadModule(`/netlify/functions/${name}.mts`)) as { default: (r: Request) => Promise<Response> };
              const out = await mod.default(new Request(`http://dev/api/${name}`, { method: req.method ?? "GET", body: req.method === "POST" ? Buffer.concat(chunks) : null }));
              res.statusCode = out.status;
              res.setHeader("content-type", "application/json");
              res.end(await out.text());
            })().catch((e: unknown) => { res.statusCode = 500; res.end(JSON.stringify({ error: String(e) })); });
          });
        });
      }
    },
  };
}

// The site's public URL (Netlify sets URL at build, see netlify.toml) makes the
// Open Graph image absolute and goes into robots.txt and the sitemap.
process.env.VITE_SITE_URL ??= "";
// Each release gets its own id (Netlify sets COMMIT_REF): the browser's catalog cache is keyed on it.
process.env.VITE_BUILD_ID ??= process.env.COMMIT_REF ?? "dev";
const SITE = process.env.VITE_SITE_URL;
const SECTIONS = ["", "live", "stations", "library", "community", "concerts", "contribute", "about", "legal"];

/** seoFiles writes robots.txt and sitemap.xml next to the build. */
function seoFiles(): Plugin {
  return {
    name: "gnoradio-seo",
    apply: "build",
    generateBundle() {
      const robots = `User-agent: *\nAllow: /\nDisallow: /api/\nDisallow: /rpc\n${SITE ? `Sitemap: ${SITE}/sitemap.xml\n` : ""}`;
      this.emitFile({ type: "asset", fileName: "robots.txt", source: robots });
      if (!SITE) return;
      const urls = SECTIONS.map((p) => `<url><loc>${SITE}/${p}</loc></url>`).join("");
      this.emitFile({ type: "asset", fileName: "sitemap.xml", source: `<?xml version="1.0" encoding="UTF-8"?><urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">${urls}</urlset>\n` });
    },
  };
}

// In dev, /rpc is proxied to the local gnodev node so the app works from any
// device that reaches this dev server (e.g. through Tailscale Serve).
export default defineConfig({
  plugins: [react(), robot(), seoFiles()],
  server: {
    host: "127.0.0.1",
    port: 5173,
    strictPort: true,
    allowedHosts: [".ts.net", "localhost"],
    proxy: { "/rpc": { target: "http://127.0.0.1:27157", changeOrigin: true, rewrite: (p) => p.replace(/^\/rpc/, "") } },
  },
  test: { environment: "jsdom", include: ["src/**/*.test.{ts,tsx}", "netlify/**/*.test.ts"], setupFiles: ["src/test/setup.ts"], restoreMocks: true },
});
