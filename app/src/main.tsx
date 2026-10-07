import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import App from "./App";
import { captureRef } from "./lib/incentives";
// Geist and Geist Mono, self-hosted (SIL OFL 1.1, see NOTICE).
import "@fontsource/geist/400.css";
import "@fontsource/geist/500.css";
import "@fontsource/geist/600.css";
import "@fontsource/geist/700.css";
import "@fontsource/geist-mono/400.css";
import "@fontsource/geist-mono/500.css";
import "./styles.css";

const root = document.getElementById("root");
if (!root) throw new Error("GnoRadio: #root element is missing");

// A shared link's ?ref= is kept before the app rewrites the address bar.
captureRef(window.location.search);

createRoot(root).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
