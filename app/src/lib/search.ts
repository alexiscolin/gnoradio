// One search for the whole app: the sidebar field and ⌘K open Library and focus its search.
export const SEARCH_EVENT = "gnoradio:search";

/** openSearch goes to Library and asks it to focus its search field. */
export function openSearch(): void {
  if (!window.location.pathname.startsWith("/library")) {
    window.history.pushState(null, "", "/library");
    window.dispatchEvent(new PopStateEvent("popstate"));
  }
  // Library may mount on the next frame: ask twice.
  window.dispatchEvent(new Event(SEARCH_EVENT));
  window.setTimeout(() => window.dispatchEvent(new Event(SEARCH_EVENT)), 60);
}
