# YT-Schakal

Menuegesteuertes PowerShell-Frontend fuer [spotdl](https://github.com/spotDL/spotify-downloader) und [yt-dlp](https://github.com/yt-dlp/yt-dlp).

Die Idee dahinter: **Spotify liefert die Metadaten** (Alben, Titelnummern, Cover, Liedtexte), **YouTube liefert das Audio**. Ergebnis sind sauber getaggte Dateien in einer ordentlichen Albenstruktur — ohne fuer jeden Handgriff Parameter nachzuschlagen.

Ein Spotify-Konto wird **nicht** gebraucht. spotdl nutzt Spotify nur als Datenbank.

---

## Funktionen

| Taste | Punkt | Was er tut |
|-------|-------|------------|
| `1` | Einzelsuche | Titel eintippen, wird gesucht und geladen |
| `2` | Wunschliste | Alle Eintraege aus `wunschliste.txt` abarbeiten |
| `3` | Link laden | Erkennt selbst die Art: Spotify-Track, -Album **oder -Playlist**, sowie YouTube/Soundcloud/Bandcamp. Fuer eine ganze Kuenstler-Diskografie ist Punkt `5` der bessere Weg |
| `4` | Kanal-Playlists | YouTube-Kanal durchsuchen, Playlists auswaehlen |
| `5` | Diskografie | Albenliste eines Kuenstlers, ankreuzen, laden |
| `6` | Playlist-Sync | Ordner mit einer Spotify-Playlist gleichhalten |
| `7` | Tags reparieren | Metadaten vorhandener Dateien erneuern |
| `8` | Werkzeuge aktualisieren | spotdl und yt-dlp per pip auffrischen |
| `9` | Einstellungen | Format, Bitrate, Namensschema, Nachtmodus … |
| `A` | Archiv | Bereits geladenes einsehen und zuruecksetzen |
| `U` | USB-Stick | Alben auf einen Stick kopieren, optional Zufallsmix |
| `W` | Warteschlange | Auftraege sammeln und unbeaufsichtigt abarbeiten |
| `B` | Bestandsabgleich | Was fehlt aus gespeicherten Diskografien? |
| `P` | Sammlung pruefen | Download-Reste und auffaellig kleine Dateien finden |

**Mehrfachauswahl** ueberall dort, wo es mehrere Treffer gibt: Pfeiltasten bewegen, `Space` markiert, `A` alle, `K` keine, `I` umkehren, `Enter` startet, `Esc` bricht ab.

### Wo lade ich was?

Bei drei Menuepunkten ist auf den ersten Blick nicht klar, welcher der richtige ist — deshalb hier einmal explizit:

| Ich habe... | ...gehoert in |
|---|---|
| einen Link auf einen einzelnen Spotify-Song | `3` |
| einen Link auf ein einzelnes Spotify-Album | `3` |
| einen Link auf eine Spotify-Playlist (eigene oder fremde) | `3` |
| einen Bandnamen und will die ganze Diskografie durchsehen | `5` |
| einen YouTube-Kanal mit kuratierten Playlists (z.B. "Tiny Desk Concerts") | `4` |
| einen YouTube-"Kuenstler – Thema"-Kanal (automatisch erzeugt) | `5`, nicht `4` — siehe unten |

---

## Installation

Voraussetzung ist **Python 3.11 oder neuer**. Danach:

```powershell
pip install spotdl yt-dlp
spotdl --download-ffmpeg
winget install DenoLand.Deno
```

Nach der Deno-Installation ein **neues Terminalfenster** oeffnen — sonst ist der PATH noch nicht aktualisiert.

Wozu die einzelnen Teile gebraucht werden:

- **spotdl** — Metadaten von Spotify, Suche und Tagging
- **yt-dlp** — laedt das Audio von YouTube und anderen Seiten
- **ffmpeg** — wandelt um und bettet Cover ein
- **Deno** — YouTube verlangt inzwischen eine JavaScript-Laufzeit; ohne sie liefert es nur Teilformate

Der Selbsttest beim Start prueft alle vier und nennt den fehlenden Befehl im Klartext.

## Start

Doppelklick auf **`YT-Schakal.bat`**. Die Batchdatei umgeht die Ausfuehrungsrichtlinie fuer genau diesen einen Aufruf und aendert nichts an den Systemeinstellungen.

Alternativ direkt:

```powershell
powershell -ExecutionPolicy Bypass -File .\YT-Schakal.ps1
```

---

## Ordnerstruktur

```
YT-Schakal/
├── YT-Schakal.ps1      das Script
├── YT-Schakal.bat      Starter
├── wunschliste.txt     selbst befuellen, eine Zeile pro Eintrag
├── Musik/              Standard-Zielordner (relativ, aenderbar)
└── data/               alles Interne
    ├── einstellungen.json
    ├── archiv.txt
    ├── archiv-yt.txt
    ├── warteschlange.txt
    ├── log.txt
    ├── sync/
    └── diskografie/
```

Der Zielordner ist standardmaessig **relativ** — der ganze Ordner bleibt damit weitergabefaehig. Ueber Einstellungen laesst sich jederzeit ein absoluter Pfad setzen, etwa `D:\Musik`.

---

## Einstellungen

Alles unter Menuepunkt `9`, gespeichert in `data/einstellungen.json`.

| Feld | Vorgabe | Bemerkung |
|------|---------|-----------|
| Zielordner | `Musik` | relativ oder absolut |
| Format | `mp3` | mp3, flac, opus, m4a, ogg, wav |
| Bitrate | `192k` | siehe Hinweis unten |
| Namensschema | `{album-artist}/{album}/{track-number} - {title}.{output-ext}` | |
| Parallele Downloads | `4` | 1–8 |
| Liedtexte holen | ja | Genius und Musixmatch |
| Archiv nutzen | ja | verhindert doppelte Downloads |
| Nur verifizierte Treffer | nein | strenger, findet aber weniger |
| Playlist-Unterordner | ja | je Playlist ein eigener Ordner |
| Nachtmodus | nein | langsamer, dafuer keine Bot-Pruefung |
| Ausfuehrliches Log | nein | jede Zeile von spotdl und yt-dlp |

### `{album-artist}` statt `{artist}`

`{artist}` ist der Interpret des **einzelnen Tracks**. Bei Alben mit Gastsaengern zerfaellt so ein Album in mehrere Interpretenordner mit je zwei Titeln. `{album-artist}` haelt es zusammen.

### Zur Bitrate

YouTube liefert real etwa **128–160 kbps**. Wer `320k` einstellt, bekommt groessere Dateien, nicht bessere. Sinnvoll sind `192k` oder `disable` (keine zweite Umwandlung).

### Nachtmodus

Reduziert auf zwei gleichzeitige Anfragen und legt 3–10 Sekunden Pause zwischen die Titel. Bei grossen Diskografien deutlich langsamer — verhindert aber, dass YouTube nach einigen hundert Downloads eine Bot-Bestaetigung verlangt. Fuer unbeaufsichtigte Laeufe ueber Nacht die richtige Wahl.

---

## Bekannte Eigenheiten

**Topic-Kanaele geben ihre Alben nicht her.** Automatisch erzeugte „Kuenstler – Thema"-Kanaele laden ihre Albenliste per Overlay nach; dort kommt yt-dlp nicht heran. Fuer Kuenstlerkataloge ist Menuepunkt `5` (Diskografie) der richtige Weg, nicht `4`.

**Singles und EPs sind bei Spotify kein „Album".** Der Diskografie-Abruf fragt deshalb getrennt nach. Wer verneint, bekommt nur regulaere Alben — EPs fehlen dann.

**Der Bestandsabgleich vergleicht Ordnernamen.** Ein von Hand umbenannter Ordner erscheint faelschlich als fehlend.

**„Sign in to confirm you're not a bot"** bedeutet, dass YouTube die IP voruebergehend gesperrt hat. Meist nach einigen Stunden vorbei. Dagegen hilft der Nachtmodus.

**Nach dem Abarbeiten der Warteschlange (Taste `S`) zweimal eine Taste druecken.** Einmal fuer die Bilanzanzeige, danach prueft das Menue erneut, findet die jetzt leere Warteschlange und fragt noch einmal, bevor es zurueck ins Hauptmenue geht. Kein Fehler im Sinne von Datenverlust, nur ein ueberfluessiger zweiter Tastendruck.

---

## Rechtliches

Fuer eigene Inhalte, gemeinfreies Material oder Werke mit entsprechender Download-Lizenz ist die Nutzung unproblematisch. Bei lizenzierter Musik gelten die Regeln zur Privatkopie, und die unterscheiden sich je nach Land. Wer das Werkzeug nutzt, sollte die bei ihm geltende Rechtslage kennen.

## Lizenz

MIT — siehe [LICENSE](LICENSE).
