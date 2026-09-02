# Changelog

Alle nennenswerten Aenderungen an YT-Schakal.

Das Projekt entstand Ende August 2026 aus der Frage, ob es die alte
Radio-Mitschnitt-Software Audials noch gibt — und der Feststellung, dass
`spotdl` und `yt-dlp` zusammen alles koennen, was gebraucht wird, nur ohne
vernuenftige Bedienoberflaeche.

---

## 1.4.3 — 2026-09-02

### Behoben
- `Merke-ImArchiv` schrieb dieselbe Zeile bei jedem Lauf erneut in
  `archiv.txt`. Der Rueckgabewert von `HashSet.Add()` wurde verworfen, statt
  ihn als "war schon drin"-Pruefung zu nutzen. Faellt seit 1.4.1 staerker
  auf, weil "bereits vorhanden" nun ebenfalls archiviert wird.
- `Hole-MitSpotdl` und `Hole-MitSpotdlMehrfach` pruefen jetzt wie ihre
  yt-dlp-Gegenstuecke, ob das Werkzeug ueberhaupt installiert ist.

---

## 1.4.2 — 2026-09-02

### Behoben
- **Menuepunkt 3 (Link laden)** wertete weiterhin nur neue Dateien aus.
  Ein Download, bei dem alles schon vorhanden war, galt als Fehlschlag und
  wurde nicht archiviert. Damit ist dieser Fehlertyp an allen Stellen
  bereinigt (Diskografie, Warteschlange, Einzelsuche, Wunschliste, Link).
- Playlist-Container blockierten die Rekursion: Ein Objekt mit eigenen
  `entries` wird jetzt immer durchlaufen, bevor geprueft wird, ob es selbst
  eine Playlist ist.
- Die ID-Laenge als Erkennungskriterium ist raus — sie traf auch Videos und
  Kanaele. Erkannt wird ueber URL, `_type`, `ie_key` und Zaehlfelder.
- Korrigierte Einstellungen werden sofort gespeichert. Vorher kam dieselbe
  Korrekturmeldung bei jedem Start erneut.

### Geaendert
- Die Kanal-Playlist-Bilanz trennt jetzt **neu geladen**, **bereits
  vorhanden** und **Fehler**. Ein wiederholter Kanalimport meldete vorher
  alles als "ohne Ergebnis".

---

## 1.4.1 — 2026-09-02

### Behoben
- **`[bool]'false'` ergibt in PowerShell `$true`** — jeder nichtleere String
  wird wahr. Wer `"Nachtmodus": "false"` in die JSON schrieb, schaltete ihn
  damit ein. Boolean-Werte werden jetzt textbasiert ausgewertet, unbekannte
  Eingaben fallen auf den Standard zurueck.
- **Einzelsuche und Wunschliste** werteten "bereits vorhanden" als
  Fehlschlag. Betroffene Eintraege wurden nicht archiviert und liefen bei
  jedem Lauf erneut mit.
- Eine Playlist wurde nicht gemerkt, wenn der Download in die Warteschlange
  ging — das `return` kam vor dem Merken.
- `Finde-Kanaele` prueft yt-dlp vor dem Aufruf.
- `Start-Process` beim Metadaten-Abruf ist mit `try/catch` abgesichert.
- Rueckgabeobjekte sind bei fruehem Abbruch vollstaendig (`Uebersprungen`,
  `Ermittlungsart`).
- Windows-Argument-Quoting behandelt Backslashes vor Anfuehrungszeichen und
  am Argumentende korrekt.

### Geaendert
- Die Gegenprobe im Dateisystem greift jetzt auch, wenn die Werkzeugausgabe
  gar nichts meldet — vorher nur bei bekanntem Soll.
- Playlist-Erkennung als Blacklist statt Whitelist: alles mit `list=` gilt,
  ausser den automatischen Listen `RD`, `LL`, `FL`, `WL`.
- Die Titel-Zuordnung beim USB-Export sammelt Mehrdeutigkeiten und zeigt
  sie an, statt still den ersten Treffer zu nehmen.

---

## 1.4.0 — 2026-09-02

### Hinzugefuegt
- **Playlists merken.** Beim Laden einer Spotify-Playlist ueber Menuepunkt 3
  kann die Zusammenstellung gemerkt werden — nur Interpret, Titel und
  Position, ohne Dateipfade. Die Musik bleibt album-sortiert in der
  Sammlung.
- **Playlist auf den USB-Stick.** Menuepunkt `U` bietet neben der
  Albenauswahl jetzt "gemerkte Playlist zusammenstellen": das Script sucht
  die Titel in der Sammlung und kopiert sie flach und nummeriert in einen
  eigenen Ordner auf den Stick. Fehlende Titel werden namentlich gemeldet.

### Geaendert
- Menuepunkt 3 und das Hauptmenue nennen ausdruecklich, dass Spotify-
  Playlists unterstuetzt werden, und verweisen fuer Kuenstlerkataloge auf
  Menuepunkt 5.
- Landet ein Playlist- oder Track-Link in Menuepunkt 5, kommt ein gezielter
  Hinweis auf Menuepunkt 3 statt der allgemeinen "kein Spotify-Link"-Meldung.

### Bekannte Grenzen
- Die Zuordnung beim Playlist-Export laeuft ueber Dateiname und
  Ordnerstruktur, nicht ueber die eingebetteten Tags. Bei abweichendem
  Namensschema oder umbenannten Ordnern koennen Titel faelschlich als
  fehlend gelten.
- `--ignore-errors` verschluckt einzelne gesperrte oder geloeschte Videos in
  Playlists. Eine Vollstaendigkeitswarnung fehlt noch.
- Nach dem Abarbeiten der Warteschlange (Taste `S`) muss zweimal eine Taste
  gedrueckt werden, bevor es zurueck ins Hauptmenue geht.

---

## 1.3.0 — 2026-09-02

### Hinzugefuegt
- Versionsnummer im Menuekopf und in jeder Startzeile des Logs.
- Konfigurationspruefung beim Laden: unbekanntes Format, unsinnige Bitrate,
  Threads ausserhalb 1–8 oder ein Namensschema ohne `{title}` werden auf den
  Standard zurueckgesetzt.
- Einmalige Migration aus dem alten Layout: Einstellungen, Archive, Log,
  Warteschlange sowie `sync\` und `diskografie\` wandern nach `data\`,
  `liste.txt` wird zu `wunschliste.txt`.

### Behoben
- Vollstaendig geladene Alben werden jetzt auch archiviert, wenn alle Titel
  bereits vorhanden waren (neu + uebersprungen >= Soll). Vorher wurde
  dasselbe Album bei jedem Lauf erneut versucht.

### Geaendert
- Die Erfolgsermittlung liest die Ausgabe von spotdl und yt-dlp, statt
  zweimal den kompletten Zielordner zu scannen. Der Zeitstempel-Faellback
  greift nur noch bei unbekanntem Ausgabeformat oder gemeldetem Fehlbetrag.
- Doppelte Kanalauswahl in `Waehle-Kanal` zusammengefasst.
- `Start-Process`-Argumente werden escaped, `Get-CimInstance` statt
  `Get-WmiObject`, `Warte-AufTaste` faengt fehlendes `RawUI` ab.
- Das Archiv wird einmal pro Sitzung als `HashSet` geladen statt bei jeder
  Pruefung neu von der Platte gelesen.

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
- Filter auf echte Playlist-IDs. Automatische Radio-Mixe wurden faelschlich
  als Alben gelesen.
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
