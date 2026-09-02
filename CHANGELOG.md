# Changelog

Alle nennenswerten Aenderungen an YT-Schakal.

Das Projekt entstand Ende August 2026 aus der Frage, ob es die alte
Radio-Mitschnitt-Software Audials noch gibt — und der Feststellung, dass
`spotdl` und `yt-dlp` zusammen alles koennen, was gebraucht wird, nur ohne
vernuenftige Bedienoberflaeche.

---

## [Unveroeffentlicht]

### Geaendert
- Menuepunkt 3 (Link laden) nennt jetzt ausdruecklich, dass Spotify-Playlists
  unterstuetzt werden — vorher stand dort nur "Spotify", was den Eindruck
  erwecken konnte, nur Tracks und Alben seien gemeint. Verweist zusaetzlich
  auf Menuepunkt 5 fuer ganze Kuenstler-Diskografien.
- Landet ein Playlist- oder Track-Link versehentlich in Menuepunkt 5
  (Diskografie), kommt jetzt ein gezielter Hinweis auf Menuepunkt 3 statt der
  allgemeinen "kein Spotify-Link"-Meldung mit Suchvorschlag.

### Bekannter Fehler
- Nach dem Abarbeiten der Warteschlange (Taste `S`) muss zweimal eine Taste
  gedrueckt werden, bevor es zurueck ins Hauptmenue geht: einmal fuer die
  Bilanzanzeige, danach laeuft die Menueschleife erneut an, findet die jetzt
  leere Warteschlange und fragt ein zweites Mal. Kein Datenverlust, nur ein
  ueberfluessiger Tastendruck. Bleibt vorerst so.

### Behoben
- `Start-Process` beim Metadaten-Abruf bekommt Argumente jetzt korrekt
  geschuetzt. Anfuehrungszeichen in Pfaden oder Kuenstlernamen konnten die
  Kommandozeile zerlegen.
- `Get-CimInstance` statt `Get-WmiObject` fuer die Stick-Erkennung, mit
  Rueckfall. `Get-WmiObject` fehlt in PowerShell 7.
- `Warte-AufTaste` faengt fehlendes `RawUI` ab — betraf die ISE und
  umgeleitete Eingaben.

### Geaendert
- Das Archiv wird einmal pro Sitzung in ein `HashSet` geladen statt bei jeder
  Pruefung neu von der Platte gelesen. Bei Listenlaeufen gegen ein grosses
  Archiv war das der Flaschenhals.
- Die Warnung vor dem loeschenden Playlist-Sync ist deutlich hervorgehoben.

---

## 2026-09-02 — Umbenennung und Repo

### Geaendert
- Aus `Musik.ps1` wird `YT-Schakal.ps1`, Starter entsprechend.

---

## 2026-09-01 — Ordnerstruktur und Nachtmodus

### Hinzugefuegt
- **Nachtmodus** (Einstellungen, Taste `N`): zwei statt vier gleichzeitige
  Anfragen, dazu 3–10 Sekunden Pause zwischen den Titeln. Verhindert, dass
  YouTube nach einigen hundert Downloads eine Bot-Bestaetigung verlangt.
- **Ausfuehrliches Log** (Taste `L`): protokolliert jede Zeile von `spotdl`
  und `yt-dlp`. Ohne den Schalter landen nur auffaellige Zeilen im Log —
  Fehler, Warnungen, Rate-Limits und die Bot-Pruefung.
- Beim Start werden Werkzeugversionen und aktive Einstellungen protokolliert.
- **Bestandsabgleich** (Taste `B`): vergleicht gespeicherte Diskografien mit
  der Sammlung, zeigt fehlende und unvollstaendige Alben und legt die Luecken
  auf Wunsch in die Warteschlange.
- **Sammlung pruefen** (Taste `P`): findet leere Dateien, Download-Reste
  (`.part`, `.ytdl`) und auffaellig kleine Dateien. Geloescht wird nur, was
  eindeutig Muell ist.

### Geaendert
- Alles Interne liegt jetzt unter `data\` — Einstellungen, Archive, Log,
  Warteschlange, Sync- und Diskografie-Ordner. Im Hauptordner bleiben nur
  Script, Starter und Wunschliste.
- `liste.txt` heisst jetzt `wunschliste.txt`, der Menuepunkt entsprechend.
  Die Vorlage erklaert alle drei Eingabearten.
- Der Zielordner ist standardmaessig **relativ** (`Musik`), damit der ganze
  Ordner weitergabefaehig bleibt. Absolute Pfade sind weiter moeglich.

---

## 2026-08-31 — Warteschlange und USB

### Hinzugefuegt
- **Warteschlange** (Taste `W`): Auftraege sammeln und unbeaufsichtigt
  abarbeiten, optional mit Herunterfahren danach. Erledigtes wird sofort aus
  der Liste gestrichen, ein Abbruch setzt also beim naechsten offenen Auftrag
  fort.
- **USB-Stick bestuecken** (Taste `U`): Alben auswaehlen und auf einen Stick
  kopieren. Prueft freien Platz, warnt bei anderem Dateisystem als FAT32,
  ueberspringt bereits vorhandene Dateien. Optional ein `_Fahrmix`-Ordner mit
  Zufallstiteln plus Test-M3U.

### Behoben
- Ein Album galt schon dann als erledigt, wenn irgendeine Datei entstanden
  war. Teilerfolge landeten im Archiv und die fehlenden Titel wurden nie
  nachgeholt. Jetzt wird die Sollzahl gefuehrt und nur bei Vollstaendigkeit
  archiviert.
- Der im Selbsttest gefundene Python-Interpreter wird auch vom Update-Menue
  genutzt. Vorher war dort `python` fest verdrahtet, was auf Systemen mit nur
  `py` scheiterte.
- Mix-Dateinamen werden gekuerzt — FAT32 und MAX_PATH vertragen keine
  Endlosnamen.

---

## 2026-08-30 — Diskografie

### Hinzugefuegt
- **Diskografie** (Taste `5`): Spotify-Kuenstlerlink eingeben, Albenliste
  erscheint zur Auswahl, Download Album fuer Album. Die Songlisten werden
  zwischengespeichert — der lange Metadaten-Abruf faellt beim naechsten Mal
  weg.
- Fortschrittsanzeige mit Spinner und Laufzeit waehrend des Abrufs. `spotdl
  save` gibt selbst keinen Fortschritt aus, das Fenster wirkte eingefroren.

### Behoben
- **Singles und EPs fehlten komplett.** Spotifys API teilt Kataloge in
  `album`, `single` und `compilation`; `spotdl save` holt standardmaessig nur
  `album`. EPs zaehlen dort als Single. Der Abruf fragt jetzt getrennt nach.
- Spotify-Links mit Sprachsegment (`/intl-de/`) und Tracking-Parametern
  werden normalisiert.
- Standard-Namensschema auf `{album-artist}` umgestellt. `{artist}` ist der
  Interpret des einzelnen Tracks — bei Gastsaengern zerfiel ein Album in
  mehrere Ordner. Titelnummer ergaenzt, damit Autoradios richtig sortieren.

---

## 2026-08-29 — Kanal-Playlists

### Hinzugefuegt
- **Kanal-Playlists** (Taste `4`): YouTube-Kanal per URL, `@handle` oder
  Suchbegriff, Playlists per Mehrfachauswahl. Titelanzahl wird nach der
  Auswahl nachgeladen.
- Mehrfachauswahl mit Pfeiltasten, `Space`, `A`/`K`/`I`, `Enter`, `Esc`.
- Selbsttest prueft zusaetzlich Deno und die Python-Version.

### Behoben
- `Out-String` zerstoerte lange JSON-Antworten, weil es auf Konsolenbreite
  umbricht. Ersetzt durch `-join ''`.
- Filter auf echte Playlist-IDs (`PL`, `OLAK5uy_`, `UU`). Automatische
  Radio-Mixe (`RD`) wurden faelschlich als Alben gelesen.
- Typsichere Behandlung der JSON-Felder — eine `ArgumentException` beim
  Deduplizieren.
- Kein Such-Rueckfall mehr bei `/channel/UC...`-URLs; die sind eindeutig.

### Bekannte Grenze
- Automatisch erzeugte „Kuenstler – Thema"-Kanaele laden ihre Albenliste per
  Overlay nach. Dort kommt yt-dlp nicht heran — fuer Kuenstlerkataloge ist
  Menuepunkt `5` der richtige Weg.

---

## 2026-08-27 — Erste Fassung

### Hinzugefuegt
- Menuegefuehrte Oberflaeche mit Einzelsuche, Listenverarbeitung,
  Link-Erkennung (Spotify → spotdl, alles andere → yt-dlp), Playlist-Sync,
  Tag-Reparatur, Werkzeug-Update, Einstellungen und Archiv.
- Selbsttest beim Start fuer Python, spotdl, yt-dlp und ffmpeg.
- Einstellungen in JSON, Logdatei mit Rotation ab 1 MB.
- Erfolgsmessung ueber Dateizaehlung statt Exit-Code — `spotdl` liefert bei
  Teilfehlern trotzdem 0.
