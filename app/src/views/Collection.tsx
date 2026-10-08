import { Crumbs, Empty, Head, LIBRARY, TrackRows } from "../components/common";
import { Icon } from "../components/Icons";
import { tracksOf } from "../lib/catalog";
import type { Saved } from "../lib/saved";
import type { Catalog, Navigate, Track } from "../lib/types";
import type { Actions } from "../player/useActions";
import type { Player } from "../player/usePlayer";

type Mine = Saved & { readonly ids: readonly number[] };

/** MineLinks are the two doors to Your library: what you saved and what you liked, with counts. */
export function MineLinks({ go, saved, liked }: { readonly go: Navigate; readonly saved: number; readonly liked: number }) {
  return (
    <div className="mine-links">
      <button className="mine-link" onClick={() => { go({ k: "collection", list: "saved" }); }}>
        <Icon name="bookmark-on" size={18} /><b>Saved <span className="muted">{saved.toLocaleString("en")}</span></b><Icon name="arrow-right" className="nudge" />
      </button>
      <button className="mine-link" onClick={() => { go({ k: "collection", list: "liked" }); }}>
        <Icon name="heart-on" size={18} /><b>Liked <span className="muted">{liked.toLocaleString("en")}</span></b><Icon name="arrow-right" className="nudge" />
      </button>
    </div>
  );
}

/** CollectionView is Your library: every saved or every liked track, one tab each, playable as a whole. */
export function CollectionView({ cat, player, go, actions, saved, list }: { readonly cat: Catalog; readonly player: Player; readonly go: Navigate; readonly actions: Actions; readonly saved: Mine; readonly list: "saved" | "liked" }) {
  const tracks: readonly Track[] = tracksOf(cat, list === "saved" ? saved.ids : [...actions.liked]);
  const connected = actions.wallet.state.status === "connected" || actions.wallet.state.status === "wrong-network";
  const empty = list === "saved"
    ? "Save a track with the bookmark on any track. Stored in this browser only."
    : connected ? "No like yet: tap ♥ on any track. Likes are public and on-chain." : "Connect your wallet to see the tracks you liked.";
  return (
    <section className="collection">
      <Crumbs trail={[LIBRARY, { label: "Your library" }]} go={go} />
      <Head a="Your library" note="Saved stays in this browser; likes are public and on-chain." />
      <h3 className="sub sub-row">
        <nav className="chips mine-tabs" aria-label="Your library">
          {(["saved", "liked"] as const).map((l) => (
            <button key={l} className="chip" aria-current={l === list ? "page" : undefined} onClick={() => { go({ k: "collection", list: l }); }}>
              {l === "saved" ? "Saved" : "Liked"} <span className="muted">· {(l === "saved" ? saved.ids.length : actions.liked.size).toLocaleString("en")}</span>
            </button>
          ))}
        </nav>
        {tracks.length > 1 && <button className="cta small" onClick={() => { player.playList(tracks.map((t) => t.id), 0); }}>Play all</button>}
      </h3>
      {tracks.length === 0 ? <Empty text={empty}><button className="cta" onClick={() => { go({ k: "library", genre: 0 }); }}>Open the Library <Icon name="arrow-right" size={16} className="nudge" /></button></Empty> : <TrackRows key={list} tracks={tracks} player={player} actions={actions} saved={saved} />}
    </section>
  );
}
