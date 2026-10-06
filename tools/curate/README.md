# Sélection du catalogue de lancement

Ce pipeline produit les morceaux importés par l'admin via `catalog.ImportTrack` (voir `docs/SPEC.md` §5).
Il n'utilise que la bibliothèque standard de Python 3 ; `ffmpeg` est optionnel (mesure du volume en LUFS).

**Règle d'or : tout part de la liste blanche `seeds.json`.** Le pipeline ne fait jamais de recherche ouverte.
La qualité vient des artistes et des labels qu'on a choisis et écoutés, pas des archives.

## Étapes

```sh
cd tools/curate
python3 curate.py fetch                      # seeds "approved" uniquement
python3 curate.py fetch --include-review     # + seeds "to_review"
python3 curate.py fetch --seed "Komiku"      # une seule seed (statut ignoré)
python3 curate.py hash --max 50              # sha256 (+ LUFS si ffmpeg) des fichiers non Audius
python3 -m http.server 8077                  # puis ouvrir http://localhost:8077/review.html
python3 curate.py batch                      # approved.json → import_batch.json
```

1. **`seeds.json`** : la liste blanche. Chaque seed indique une source (`archive`, `ccmixter`, `audius`), un artiste, une collection ou une requête, un genre par défaut (1 à 12) et un statut :
   - `approved` : écouté, on récupère ;
   - `to_review` : à vérifier avant de l'utiliser (originalité, qualité) ;
   - `paused` : ignoré.
2. **`fetch`** lit les métadonnées via les API officielles et filtre :
   - **licence** : CC0, CC BY ou CC BY-SA uniquement (normalisées en SPDX, ports nationaux compris, par exemple `CC-BY-SA-3.0-DE`) ;
   - **durée** : 1:30 à 10:00 ;
   - **débit** : au moins 128 kbps, signalé « low bitrate » sous 192 ;
   - **pour Audius** : ni remix, ni reprise, ni stem, ni morceau à accès restreint, et une pochette obligatoire.

   Le résultat va dans `candidates.json`, au format de `ImportTrack`.
3. **`hash`** télécharge les fichiers non Audius pour calculer leur sha256. Le résultat est mis en cache dans `hashes.json`.
4. **`review.html`** : écoute d'un extrait par morceau (à partir de 30 % de sa durée).
   - Touches : `K` garder, `D` jeter, `N`/`P` suivant/précédent ; `1`–`9`, `0`, `-`, `=` pour corriger le genre.
   - Les décisions restent dans le navigateur. **Export approved.json** produit le fichier final.
5. **`batch`** produit `import_batch.json` : les artistes à créer d'abord, puis les morceaux, avec le décompte par genre (objectif : 80 par station). Il bloque les morceaux sans sha256 et les morceaux ccMixter sans copie.

## Règles juridiques par source

| Source | Ce qu'on a le droit de faire | Obligations |
|---|---|---|
| **archive.org** (artistes, netlabels) | lire depuis `https://archive.org/download/…`, recopier (CC) | attribution : titre, artiste, licence avec lien, source. Les items sans `licenseurl` sont rejetés, même si le titre contient « (CC-BY) ». |
| **ccMixter** (sélections éditoriales) | recopier (CC BY) | **copie obligatoire** sur IPFS/CDN avant import : ccMixter bloque la lecture depuis un autre site (403). Renseigner `mirror_audio` dans `approved.json`. Attribution complète. |
| **Audius** | streamer et diffuser en public via l'API (Open Music License §1.2, droit accordé aux « Music Players ») | attribution OML §1.5 : artiste, ©, mention de l'OML, lien vers le morceau. **Cache limité à la session** (conditions API §2) : jamais de copie ni d'empreinte. Pas d'extraction massive au-delà de la liste blanche. **Pas d'entraînement d'IA** sur les morceaux. `app_name=GnoRadio` dans chaque appel ; demander une clé sur api.audius.co/plans avant la mise en ligne. |

Exclus : Free Music Archive (liens directs interdits par ses conditions), SoundCloud (radio et agrégation interdites), Jamendo (licence commerciale à demander), licences NC et ND.

## Points connus

- **Débit** : beaucoup de bonnes sorties archive.org sont en MP3 VBR autour de 128 à 190 kbps (Scott Buckley en 128). Elles passent, avec un signalement.
- **Pochettes** : ccMixter n'en fournit pas ; le realm dessine alors une pochette SVG.
- **Genres** : le genre de la seed sert par défaut. Pour Audius, il est déduit du genre déclaré par l'artiste. Il se corrige à l'écoute.
- **Volume en LUFS** : nécessite `ffmpeg` (`brew install ffmpeg`).
