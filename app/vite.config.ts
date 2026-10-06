import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// In dev, /rpc is proxied to the local gnodev node so the app works from any
// device that reaches this dev server (e.g. through Tailscale Serve).
export default defineConfig({
  plugins: [react()],
  server: {
    host: "127.0.0.1",
    port: 5173,
    strictPort: true,
    allowedHosts: [".ts.net", "localhost"],
    proxy: { "/rpc": { target: "http://127.0.0.1:27157", changeOrigin: true, rewrite: (p) => p.replace(/^\/rpc/, "") } },
  },
});
