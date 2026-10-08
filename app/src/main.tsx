import { StrictMode } from "react";
import { hydrateRoot } from "react-dom/client";
import App from "./App";
import { captureRef } from "./lib/incentives";

const root = document.getElementById("root");
if (!root) throw new Error("GnoRadio: #root element is missing");

// A shared link's ?ref= is kept before the app rewrites the address bar.
captureRef(window.location.search);

// /features is served with its text before the splash, for crawlers (prerender.ts): it goes before
// React takes over, so what is left matches App's first render.
root.querySelector(".seo-static")?.remove();

// index.html already shows the splash (App's first render): React takes over that markup as it is,
// so the poster's animation runs on without a restart.
hydrateRoot(
  root,
  <StrictMode>
    <App />
  </StrictMode>,
);
