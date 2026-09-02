<#
===============================================================================
  YT-Schakal  --  Menuegesteuerter Downloader fuer spotdl und yt-dlp
  Versionsverlauf siehe CHANGELOG.md
===============================================================================
  Start ueber YT-Schakal.bat (Doppelklick) oder direkt:
      powershell -ExecutionPolicy Bypass -File .\YT-Schakal.ps1

  Ordnerstruktur:
      YT-Schakal.ps1      - dieses Script
      YT-Schakal.bat      - Starter (Doppelklick)
      wunschliste.txt     - Songwuensche, eine Zeile pro Eintrag
      Musik\              - Standard-Zielordner (relativ, per Einstellung aenderbar)
      data\               - alles Interne:
          einstellungen.json  - gespeicherte Konfiguration
          archiv.txt          - bereits geladene spotdl-Suchen
          archiv-yt.txt       - bereits geladene YouTube-Videos
          warteschlange.txt   - offene Auftraege
          log.txt             - Protokoll aller Laeufe
          sync\               - Sync-Dateien fuer Playlists
          diskografie\        - zwischengespeicherte Kuenstlerkataloge
===============================================================================
#>

try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
} catch { }

$ErrorActionPreference = 'Continue'

# Bei jeder nennenswerten Aenderung hochzaehlen und im CHANGELOG eintragen.
$Version = '1.4.3'

# =============================================================================
#  PFADE
# =============================================================================

if ($PSScriptRoot) { $Basis = $PSScriptRoot } else { $Basis = (Get-Location).Path }

# Alles Interne liegt in data\, damit der Hauptordner uebersichtlich bleibt.
$OrdnerData         = Join-Path $Basis 'data'

$DateiEinstellungen = Join-Path $OrdnerData 'einstellungen.json'
$DateiArchiv        = Join-Path $OrdnerData 'archiv.txt'
$DateiArchivYT      = Join-Path $OrdnerData 'archiv-yt.txt'
$DateiLog           = Join-Path $OrdnerData 'log.txt'
$DateiQueue         = Join-Path $OrdnerData 'warteschlange.txt'
$OrdnerSync         = Join-Path $OrdnerData 'sync'
$OrdnerDiskografie  = Join-Path $OrdnerData 'diskografie'
$OrdnerPlaylists    = Join-Path $OrdnerData 'playlists'

# Was der Nutzer selbst anfasst, bleibt im Hauptordner sichtbar.
$DateiListe         = Join-Path $Basis 'wunschliste.txt'

# Frueh anlegen - sonst laufen die ersten Logzeilen ins Leere.
if (-not (Test-Path $OrdnerData)) {
    try { New-Item -Path $OrdnerData -ItemType Directory -Force | Out-Null } catch { }
}

# --- Einmalige Migration aus dem alten Layout -------------------------------
# Bis Version 1.2 lagen diese Dateien direkt neben dem Script. Wer aktualisiert,
# soll Archiv, Einstellungen und Caches behalten statt neu anzufangen.
$altNeu = @(
    @{ Alt = 'einstellungen.json'; Neu = $DateiEinstellungen },
    @{ Alt = 'archiv.txt';         Neu = $DateiArchiv },
    @{ Alt = 'archiv-yt.txt';      Neu = $DateiArchivYT },
    @{ Alt = 'warteschlange.txt';  Neu = $DateiQueue },
    @{ Alt = 'log.txt';            Neu = $DateiLog },
    @{ Alt = 'sync';               Neu = $OrdnerSync },
    @{ Alt = 'diskografie';        Neu = $OrdnerDiskografie }
)

$verschoben = 0
foreach ($paar in $altNeu) {
    $quelle = Join-Path $Basis $paar.Alt
    # Nur verschieben, wenn es die Quelle gibt und das Ziel noch frei ist
    if ((Test-Path $quelle) -and -not (Test-Path $paar.Neu)) {
        try {
            Move-Item -Path $quelle -Destination $paar.Neu -ErrorAction Stop
            $verschoben++
        } catch { }
    }
}

if ($verschoben -gt 0) {
    Write-Host ''
    Write-Host ("  {0} Datei(en)/Ordner aus dem alten Layout nach data\ verschoben." -f $verschoben) -ForegroundColor Green
    Write-Host '  Einstellungen, Archiv und Zwischenspeicher bleiben erhalten.' -ForegroundColor DarkGray
    Write-Host ''
}

# Alte liste.txt heisst jetzt wunschliste.txt
$alteListe = Join-Path $Basis 'liste.txt'
if ((Test-Path $alteListe) -and -not (Test-Path $DateiListe)) {
    try {
        Move-Item -Path $alteListe -Destination $DateiListe -ErrorAction Stop
        Write-Host '  liste.txt wurde zu wunschliste.txt umbenannt.' -ForegroundColor Green
        Write-Host ''
    } catch { }
}

# =============================================================================
#  STANDARDEINSTELLUNGEN
# =============================================================================

$Standard = [ordered]@{
    Zielordner     = 'Musik'
    Format         = 'mp3'
    Bitrate        = '192k'
    Namensschema   = '{album-artist}/{album}/{track-number} - {title}.{output-ext}'
    Threads        = 4
    LyricsHolen    = $true
    ArchivNutzen   = $true
    NurVerifiziert = $false
    PlaylistOrdner = $true
    Nachtmodus     = $false    # Pausen zwischen Downloads, weniger parallel
    LogAusfuehrlich = $false   # Ausgabe von spotdl/yt-dlp mitprotokollieren
}

# =============================================================================
#  GRUNDFUNKTIONEN
# =============================================================================

function Schreibe-Log {
    param(
        [string]$Text,
        [ValidateSet('INFO','WARN','FEHLER','OK')]
        [string]$Stufe = 'INFO'
    )
    $zeile = '{0} [{1,-6}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Stufe, $Text
    try {
        # Rotation: ab 1 MB wird das Log zu log.alt.txt, die alte Sicherung
        # faellt weg. So bleiben maximal ~2 MB Protokoll liegen.
        if (Test-Path $DateiLog) {
            $groesse = (Get-Item $DateiLog -ErrorAction SilentlyContinue).Length
            if ($groesse -gt 1MB) {
                $altDatei = Join-Path (Split-Path $DateiLog) 'log.alt.txt'
                Remove-Item $altDatei -ErrorAction SilentlyContinue
                Move-Item $DateiLog $altDatei -ErrorAction SilentlyContinue
            }
        }
        Add-Content -Path $DateiLog -Value $zeile -Encoding UTF8
    } catch { }
}

function Melde {
    param(
        [string]$Text,
        [ValidateSet('Normal','Gut','Warnung','Fehler','Titel','Grau')]
        [string]$Art = 'Normal'
    )
    switch ($Art) {
        'Gut'     { Write-Host $Text -ForegroundColor Green }
        'Warnung' { Write-Host $Text -ForegroundColor Yellow }
        'Fehler'  { Write-Host $Text -ForegroundColor Red }
        'Titel'   { Write-Host $Text -ForegroundColor Cyan }
        'Grau'    { Write-Host $Text -ForegroundColor DarkGray }
        default   { Write-Host $Text }
    }
}

function Zeige-Linie {
    param([string]$Zeichen = '-')
    Melde ($Zeichen * 75) 'Grau'
}

function Warte-AufTaste {
    Write-Host ''
    Melde 'Weiter mit einer beliebigen Taste ...' 'Grau'
    try {
        [void]$Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    } catch {
        # In der ISE und bei umgeleiteter Eingabe gibt es kein RawUI
        [void](Read-Host)
    }
}

function Loese-Zielordner {
    <#
      Der Zielordner darf relativ gespeichert sein (z.B. 'Musik'). Dann
      liegt er neben dem Script - der Ordner bleibt so weitergabefaehig.
      Absolute Pfade werden unveraendert durchgereicht.
    #>
    param($Konfig)

    $pfad = [string]$Konfig.Zielordner
    if ([string]::IsNullOrWhiteSpace($pfad)) { $pfad = 'Musik' }

    if ([System.IO.Path]::IsPathRooted($pfad)) { return $pfad }

    try   { return [System.IO.Path]::GetFullPath((Join-Path $Basis $pfad)) }
    catch { return (Join-Path $Basis $pfad) }
}

function Kuerze-Text {
    param([string]$Text, [int]$Laenge)
    if ([string]::IsNullOrEmpty($Text)) { return '' }
    if ($Text.Length -le $Laenge) { return $Text }
    return $Text.Substring(0, [Math]::Max(1, $Laenge - 3)) + '...'
}

function Saeubere-Dateiname {
    param([string]$Name)
    $sauber = $Name -replace '[\\/:*?"<>|]', '_'
    $sauber = $sauber.Trim().TrimEnd('.')
    if ([string]::IsNullOrWhiteSpace($sauber)) { $sauber = 'Unbenannt' }
    return $sauber
}

# =============================================================================
#  EINSTELLUNGEN
# =============================================================================

function Lade-Einstellungen {
    if (Test-Path $DateiEinstellungen) {
        try {
            $roh = Get-Content -Path $DateiEinstellungen -Raw -Encoding UTF8 | ConvertFrom-Json
            $cfg = [ordered]@{}
            foreach ($schluessel in $Standard.Keys) {
                if ($null -ne $roh.$schluessel) { $cfg[$schluessel] = $roh.$schluessel }
                else                            { $cfg[$schluessel] = $Standard[$schluessel] }
            }
            return $cfg
        } catch {
            Melde 'Einstellungsdatei defekt - es werden Standardwerte verwendet.' 'Warnung'
            Schreibe-Log "einstellungen.json nicht lesbar: $($_.Exception.Message)" 'WARN'
        }
    }
    $neu = [ordered]@{}
    foreach ($schluessel in $Standard.Keys) { $neu[$schluessel] = $Standard[$schluessel] }
    return $neu
}

function Pruefe-Einstellungen {
    <#
      Faengt unsinnige Werte ab, die von Hand in die JSON geraten sind.
      Setzt sie auf den Standard zurueck und sagt, was korrigiert wurde.
    #>
    param($Konfig)

    $korrekturen = New-Object System.Collections.ArrayList

    $erlaubteFormate = @('mp3','flac','opus','m4a','ogg','wav')
    if ($Konfig.Format -notin $erlaubteFormate) {
        [void]$korrekturen.Add(("Format '{0}' unbekannt -> {1}" -f $Konfig.Format, $Standard.Format))
        $Konfig.Format = $Standard.Format
    }

    if ($Konfig.Bitrate -and $Konfig.Bitrate -ne 'disable' -and
        $Konfig.Bitrate -notmatch '^\d{2,4}k$') {
        [void]$korrekturen.Add(("Bitrate '{0}' ungueltig -> {1}" -f $Konfig.Bitrate, $Standard.Bitrate))
        $Konfig.Bitrate = $Standard.Bitrate
    }

    $zahl = 0
    if (-not [int]::TryParse([string]$Konfig.Threads, [ref]$zahl) -or $zahl -lt 1 -or $zahl -gt 8) {
        [void]$korrekturen.Add(("Threads '{0}' ausserhalb 1-8 -> {1}" -f $Konfig.Threads, $Standard.Threads))
        $Konfig.Threads = $Standard.Threads
    } else {
        $Konfig.Threads = $zahl
    }

    if ([string]::IsNullOrWhiteSpace([string]$Konfig.Namensschema) -or
        [string]$Konfig.Namensschema -notmatch '\{title\}') {
        [void]$korrekturen.Add('Namensschema ohne {title} -> Standard')
        $Konfig.Namensschema = $Standard.Namensschema
    }

    # Schalter muessen echte Wahrheitswerte sein.
    # ACHTUNG: [bool]'false' ist in PowerShell $true - jeder nichtleere
    # String wird wahr. Deshalb den Text auswerten statt zu casten.
    foreach ($feld in @('LyricsHolen','ArchivNutzen','NurVerifiziert','PlaylistOrdner','Nachtmodus','LogAusfuehrlich')) {
        if ($Konfig[$feld] -is [bool]) { continue }

        $wert = ([string]$Konfig[$feld]).Trim().ToLowerInvariant()

        switch ($wert) {
            'true'  { $Konfig[$feld] = $true }
            '1'     { $Konfig[$feld] = $true }
            'yes'   { $Konfig[$feld] = $true }
            'ja'    { $Konfig[$feld] = $true }
            'false' { $Konfig[$feld] = $false }
            '0'     { $Konfig[$feld] = $false }
            'no'    { $Konfig[$feld] = $false }
            'nein'  { $Konfig[$feld] = $false }
            default {
                [void]$korrekturen.Add(("{0} = '{1}' nicht deutbar -> Standard" -f $feld, $wert))
                $Konfig[$feld] = $Standard[$feld]
            }
        }
    }

    if ($korrekturen.Count -gt 0) {
        Write-Host ''
        Melde '  Einstellungen korrigiert:' 'Warnung'
        foreach ($k in $korrekturen) {
            Melde "    $k" 'Grau'
            Schreibe-Log ("Einstellung korrigiert: {0}" -f $k) 'WARN'
        }
        # Sofort speichern - sonst steht beim naechsten Start derselbe
        # Unsinn wieder in der Datei und die Meldung kommt erneut.
        Speichere-Einstellungen -Konfig $Konfig
        Melde '  Korrigierte Werte gespeichert.' 'Grau'
        Write-Host ''
    }

    return $Konfig
}

function Speichere-Einstellungen {
    param($Konfig)
    try {
        $Konfig | ConvertTo-Json -Depth 4 | Set-Content -Path $DateiEinstellungen -Encoding UTF8
        Schreibe-Log 'Einstellungen gespeichert.' 'INFO'
    } catch {
        Melde "Einstellungen konnten nicht gespeichert werden: $($_.Exception.Message)" 'Fehler'
    }
}

# =============================================================================
#  SELBSTTEST
# =============================================================================

function Pruefe-Werkzeuge {
    Zeige-Linie '='
    Melde '  Selbsttest' 'Titel'
    Zeige-Linie '='

    $allesDa = $true
    $hinweise = New-Object System.Collections.Generic.List[string]

    # --- Python -------------------------------------------------------------
    $python = Get-Command python -ErrorAction SilentlyContinue
    if (-not $python) { $python = Get-Command py -ErrorAction SilentlyContinue }
    if ($python) {
        # Gefundenen Interpreter merken - das Update-Menue nutzt denselben
        $script:PythonBefehl = $python.Source
        $rohVersion = ((& $python.Source --version 2>&1) -join ' ').Trim()

        $hauptVersion = 0
        $nebenVersion = 0
        if ($rohVersion -match 'Python\s+(\d+)\.(\d+)') {
            $hauptVersion = [int]$Matches[1]
            $nebenVersion = [int]$Matches[2]
        }

        if ($hauptVersion -eq 3 -and $nebenVersion -lt 11) {
            Melde ("  Python      : {0}  -- VERALTET" -f $rohVersion) 'Warnung'
            Melde '                spotdl hat den Support fuer 3.10 abgekuendigt.' 'Grau'
            $hinweise.Add('Python 3.12 von python.org, danach: pip install --upgrade spotdl yt-dlp')
        } else {
            Melde ("  Python      : {0}" -f $rohVersion) 'Gut'
        }
    } else {
        Melde '  Python      : NICHT GEFUNDEN' 'Fehler'
        Melde '                https://www.python.org/downloads/' 'Grau'
        Melde '                Beim Setup "Add python.exe to PATH" ankreuzen.' 'Grau'
        $allesDa = $false
    }

    # --- spotdl -------------------------------------------------------------
    if (Get-Command spotdl -ErrorAction SilentlyContinue) {
        $version = ((& spotdl --version 2>&1) -join ' ').Trim()
        Melde ("  spotdl      : {0}" -f $version) 'Gut'
    } else {
        Melde '  spotdl      : NICHT GEFUNDEN' 'Fehler'
        Melde '                pip install spotdl' 'Grau'
        $allesDa = $false
    }

    # --- yt-dlp -------------------------------------------------------------
    if (Get-Command yt-dlp -ErrorAction SilentlyContinue) {
        $version = ((& yt-dlp --version 2>&1) -join ' ').Trim()
        Melde ("  yt-dlp      : {0}" -f $version) 'Gut'
    } else {
        Melde '  yt-dlp      : NICHT GEFUNDEN' 'Fehler'
        Melde '                pip install yt-dlp' 'Grau'
        $allesDa = $false
    }

    # --- ffmpeg -------------------------------------------------------------
    $ffmpegLokal = Join-Path $env:APPDATA 'spotdl\ffmpeg.exe'
    if (Get-Command ffmpeg -ErrorAction SilentlyContinue) {
        Melde '  ffmpeg      : im Systempfad gefunden' 'Gut'
    } elseif (Test-Path $ffmpegLokal) {
        Melde '  ffmpeg      : von spotdl mitgebracht' 'Gut'
    } else {
        Melde '  ffmpeg      : NICHT GEFUNDEN' 'Fehler'
        Melde '                spotdl --download-ffmpeg' 'Grau'
        $allesDa = $false
    }

    # --- Deno ---------------------------------------------------------------
    if (Get-Command deno -ErrorAction SilentlyContinue) {
        $rohDeno = ((& deno --version 2>&1) -join ' ').Trim()
        $denoVersion = 'vorhanden'
        if ($rohDeno -match 'deno\s+(\S+)') { $denoVersion = $Matches[1] }
        Melde ("  Deno        : {0}" -f $denoVersion) 'Gut'
    } else {
        Melde '  Deno        : NICHT GEFUNDEN' 'Warnung'
        Melde '                YouTube liefert ohne JS-Laufzeit nur Teilformate.' 'Grau'
        $hinweise.Add('winget install DenoLand.Deno   (danach Fenster neu oeffnen)')
    }

    if ($hinweise.Count -gt 0) {
        Write-Host ''
        Melde '  Empfohlene Schritte:' 'Warnung'
        foreach ($h in $hinweise) { Melde "    $h" 'Grau' }
    }

    # Umgebung festhalten - hilft spaeter bei "ging gestern noch"
    $umgebung = New-Object System.Collections.ArrayList
    foreach ($werkzeug in @('python','spotdl','yt-dlp','deno')) {
        $befehl = Get-Command $werkzeug -ErrorAction SilentlyContinue
        if ($befehl) {
            try {
                $v = ((& $werkzeug --version 2>&1) -join ' ').Trim()
                $v = ($v -split "`r?`n")[0]
                [void]$umgebung.Add(("{0}={1}" -f $werkzeug, $v))
            } catch {
                [void]$umgebung.Add(("{0}=vorhanden" -f $werkzeug))
            }
        } else {
            [void]$umgebung.Add(("{0}=fehlt" -f $werkzeug))
        }
    }
    Schreibe-Log ("Umgebung: {0} | PowerShell {1}" -f ($umgebung -join ' | '), $PSVersionTable.PSVersion) 'INFO'

    Write-Host ''
    return $allesDa
}

# =============================================================================
#  ARCHIV
# =============================================================================

function Normalisiere-Eintrag {
    param([string]$Text)
    return ($Text.Trim().ToLowerInvariant() -replace '\s+', ' ')
}

$script:ArchivSatz     = $null
$script:ArchivGeladen  = $false

function Lade-ArchivInSpeicher {
    if ($script:ArchivGeladen) { return }

    $script:ArchivSatz = New-Object 'System.Collections.Generic.HashSet[string]'
    if (Test-Path $DateiArchiv) {
        try {
            foreach ($zeile in (Get-Content -Path $DateiArchiv -Encoding UTF8)) {
                if ($zeile) { [void]$script:ArchivSatz.Add((Normalisiere-Eintrag $zeile)) }
            }
        } catch {
            Schreibe-Log "Archiv nicht lesbar: $($_.Exception.Message)" 'WARN'
        }
    }
    $script:ArchivGeladen = $true
}

function Ist-ImArchiv {
    param([string]$Eintrag, $Konfig)
    if (-not $Konfig.ArchivNutzen) { return $false }
    Lade-ArchivInSpeicher
    return $script:ArchivSatz.Contains((Normalisiere-Eintrag $Eintrag))
}

function Merke-ImArchiv {
    param([string]$Eintrag, $Konfig)
    if (-not $Konfig.ArchivNutzen) { return }

    $roh = ([string]$Eintrag).Trim()
    if ([string]::IsNullOrWhiteSpace($roh)) { return }

    Lade-ArchivInSpeicher

    # HashSet.Add liefert $false, wenn der Eintrag schon drin ist. Ohne diese
    # Pruefung landet dieselbe Zeile bei jedem Lauf erneut in der Datei -
    # besonders seit "war bereits vorhanden" ebenfalls archiviert wird.
    if (-not $script:ArchivSatz.Add((Normalisiere-Eintrag $roh))) { return }

    try {
        Add-Content -Path $DateiArchiv -Value $roh -Encoding UTF8
    } catch {
        Schreibe-Log "Archiveintrag nicht geschrieben: $($_.Exception.Message)" 'FEHLER'
    }
}

# =============================================================================
#  DATEIZAEHLUNG
# =============================================================================

function Zaehle-Audiodateien {
    param([string]$Ordner)
    if (-not (Test-Path $Ordner)) { return 0 }
    $muster = @('*.mp3','*.flac','*.opus','*.m4a','*.ogg','*.wav')
    $anzahl = 0
    foreach ($m in $muster) {
        $anzahl += @(Get-ChildItem -Path $Ordner -Filter $m -Recurse -File -ErrorAction SilentlyContinue).Count
    }
    return $anzahl
}

# =============================================================================
#  SPOTDL
# =============================================================================

function Protokolliere-Werkzeugausgabe {
    <#
      Schreibt die Ausgabe eines externen Werkzeugs ins Log.
      Ohne 'LogAusfuehrlich' nur auffaellige Zeilen (Fehler, Warnungen,
      Bot-Pruefung), mit dem Schalter alles.
    #>
    param($Konfig, $Ausgabe, [string]$Quelle = 'tool')

    if (-not $Ausgabe) { return }

    $muster = 'error|warning|fehler|sign in to confirm|not a bot|unable|failed|' +
              'no usable results|forbidden|429|rate.?limit|timed out|skipping'

    foreach ($z in @($Ausgabe)) {
        $text = ([string]$z) -replace "`e\[[0-9;]*m", ''
        $text = $text.Trim()
        if (-not $text) { continue }
        if ($text -match 'Deprecated Feature') { continue }

        if ($Konfig.LogAusfuehrlich) {
            Schreibe-Log ("[{0}] {1}" -f $Quelle, $text) 'INFO'
        } elseif ($text -match $muster) {
            Schreibe-Log ("[{0}] {1}" -f $Quelle, $text) 'WARN'
        }
    }
}

function Zaehle-AusAusgabe {
    <#
      Ermittelt aus der Ausgabe von spotdl bzw. yt-dlp, wie viele Titel
      neu geladen und wie viele als vorhanden uebersprungen wurden.

      Gibt ein Objekt mit Neu und Uebersprungen zurueck, oder $null, wenn
      sich nichts Verwertbares finden liess - dann faellt der Aufrufer auf
      die Dateisuche zurueck. Das ist wichtig, weil sich die Ausgabeformate
      zwischen Versionen aendern koennen.
    #>
    param($Ausgabe, [string]$Quelle)

    if (-not $Ausgabe) { return $null }

    $neu = 0
    $uebersprungen = 0
    $erkannt = $false

    foreach ($z in @($Ausgabe)) {
        $text = ([string]$z) -replace "`e\[[0-9;]*m", ''
        if (-not $text.Trim()) { continue }

        if ($Quelle -eq 'spotdl') {
            if ($text -match '^\s*Downloaded\s')                     { $neu++; $erkannt = $true }
            elseif ($text -match 'Skipping .* \(file already exists') { $uebersprungen++; $erkannt = $true }
        }
        else {
            if ($text -match '^\[(ExtractAudio|Merger)\] Destination:')      { $neu++; $erkannt = $true }
            elseif ($text -match 'has already been downloaded')             { $uebersprungen++; $erkannt = $true }
            elseif ($text -match 'has already been recorded in the archive') { $uebersprungen++; $erkannt = $true }
        }
    }

    if (-not $erkannt) { return $null }
    return [pscustomobject]@{ Neu = $neu; Uebersprungen = $uebersprungen }
}

function Zaehle-NeueSeit {
    <#
      Zaehlt Audiodateien, die seit einem Zeitpunkt geschrieben wurden.
      Braucht keinen Vorher-Wert und damit auch keinen zweiten Vollscan.
    #>
    param([string]$Ordner, [datetime]$Seit)

    if (-not (Test-Path $Ordner)) { return 0 }
    $endungen = @('.mp3','.m4a','.flac','.ogg','.opus','.wav')

    return @(Get-ChildItem -Path $Ordner -File -Recurse -ErrorAction SilentlyContinue |
             Where-Object { $endungen -contains $_.Extension.ToLower() -and $_.LastWriteTime -ge $Seit }).Count
}

function Ermittle-Ergebnis {
    <#
      Bevorzugt die Ausgabe der Werkzeuge - das ist schnell und braucht
      keinen Verzeichnisdurchlauf.

      Zwei Faelle fuehren zur Gegenprobe im Dateisystem:
        1. Das Ausgabeformat wurde gar nicht erkannt (Werkzeug aktualisiert)
        2. Die Ausgabe meldet weniger als erwartet - dann kann statt eines
           fehlenden Titels auch eine Abschlusszeile in unbekanntem Format
           vorliegen. Betrifft Alben und Playlists, wo die Teilzahl ueber
           die Archivierung entscheidet.
      Bei vollstaendigem Ergebnis wird nicht nachgezaehlt.

      Liefert immer ein Objekt mit:
        Neu            - geladene Titel
        Uebersprungen  - waren schon vorhanden
        Ermittlungsart - 'Toolausgabe' (aus den Konsolenzeilen gelesen) oder
                         'Zeitstempel' (im Dateisystem nachgezaehlt)
    #>
    param(
        $Ausgabe,
        [string]$Quelle,
        [datetime]$Startzeit,
        [string]$Zielordner,
        [int]$Soll = 0
    )

    $ausAusgabe = Zaehle-AusAusgabe -Ausgabe $Ausgabe -Quelle $Quelle

    if ($null -ne $ausAusgabe) {
        $abgedeckt = $ausAusgabe.Neu + $ausAusgabe.Uebersprungen

        # Gegenprobe in zwei Faellen:
        #   a) bekanntes Soll nicht erreicht
        #   b) gar nichts erkannt (0 neu, 0 uebersprungen) - dann kann das
        #      Werkzeug etwas geladen haben, dessen Abschlusszeile wir nur
        #      nicht kennen. Betrifft vor allem Einzeldownloads ohne Soll.
        $pruefen = ($Soll -gt 0 -and $abgedeckt -lt $Soll) -or ($abgedeckt -eq 0)

        if ($pruefen) {
            $imDateisystem = Zaehle-NeueSeit -Ordner $Zielordner -Seit $Startzeit

            if ($imDateisystem -gt $ausAusgabe.Neu) {
                Schreibe-Log ("Gegenprobe: Ausgabe meldete {0} neu, im Dateisystem liegen {1} - nehme den hoeheren Wert" -f `
                              $ausAusgabe.Neu, $imDateisystem) 'WARN'
                return [pscustomobject]@{
                    Neu            = $imDateisystem
                    Uebersprungen  = $ausAusgabe.Uebersprungen
                    Ermittlungsart = 'Zeitstempel'
                }
            }
        }

        return [pscustomobject]@{
            Neu            = $ausAusgabe.Neu
            Uebersprungen  = $ausAusgabe.Uebersprungen
            Ermittlungsart = 'Toolausgabe'
        }
    }

    Schreibe-Log ("Ausgabe von {0} nicht auswertbar - suche nach Zeitstempel" -f $Quelle) 'WARN'
    return [pscustomobject]@{
        Neu            = (Zaehle-NeueSeit -Ordner $Zielordner -Seit $Startzeit)
        Uebersprungen  = 0
        Ermittlungsart = 'Zeitstempel'
    }
}

function Baue-SpotdlArgumente {
    param($Konfig, [string]$Befehl, [string]$Abfrage)

    $ziel = Join-Path (Loese-Zielordner $Konfig) ($Konfig.Namensschema -replace '/', '\')

    $argumente = New-Object System.Collections.Generic.List[string]
    $argumente.Add($Befehl)
    if ($Abfrage) { $argumente.Add($Abfrage) }

    $argumente.Add('--output');  $argumente.Add($ziel)
    $argumente.Add('--format');  $argumente.Add($Konfig.Format)

    # Nachtmodus: weniger gleichzeitige Anfragen, dazu Pausen zwischen den
    # Titeln. Verhindert, dass YouTube nach ein paar hundert Downloads eine
    # Bot-Pruefung verlangt. Kostet Zeit, laeuft dafuer durch.
    if ($Konfig.Nachtmodus) {
        $argumente.Add('--threads'); $argumente.Add('2')
    } else {
        $argumente.Add('--threads'); $argumente.Add([string]$Konfig.Threads)
    }

    if ($Konfig.Bitrate -and $Konfig.Bitrate -ne 'disable') {
        $argumente.Add('--bitrate'); $argumente.Add($Konfig.Bitrate)
    }
    if ($Konfig.LyricsHolen) {
        $argumente.Add('--lyrics'); $argumente.Add('genius'); $argumente.Add('musixmatch')
    }
    if ($Konfig.NurVerifiziert) {
        $argumente.Add('--only-verified-results')
    }
    $argumente.Add('--overwrite'); $argumente.Add('skip')

    # Im Nachtmodus zusaetzlich Pausen an das interne yt-dlp durchreichen.
    if ($Konfig.Nachtmodus) {
        $argumente.Add('--yt-dlp-args')
        $argumente.Add('--sleep-interval 3 --max-sleep-interval 10')
    }

    # Komma verhindert das Entpacken der Liste beim Rueckgabewert.
    return ,$argumente
}

function Hole-MitSpotdl {
    param($Konfig, [string]$Abfrage, [string]$Befehl = 'download', [int]$Soll = 0)

    if (-not (Get-Command spotdl -ErrorAction SilentlyContinue)) {
        Melde '  spotdl ist nicht installiert.  Abhilfe:  pip install spotdl' 'Fehler'
        return [pscustomobject]@{
            Erfolg         = $false
            ExitCode       = -1
            NeueDateien    = 0
            Uebersprungen  = 0
            Ermittlungsart = 'Nicht gestartet'
        }
    }

    $argumente = Baue-SpotdlArgumente -Konfig $Konfig -Befehl $Befehl -Abfrage $Abfrage

    Melde ("  -> spotdl {0}" -f ($argumente -join ' ')) 'Grau'
    Schreibe-Log "spotdl $($argumente -join ' ')" 'INFO'

    $start = Get-Date
    $alteEinstellung = $ErrorActionPreference
    $ErrorActionPreference = 'SilentlyContinue'
    try {
        & spotdl @argumente 2>&1 | Tee-Object -Variable rohAusgabe
    } finally {
        $ErrorActionPreference = $alteEinstellung
    }
    $code = $LASTEXITCODE

    Protokolliere-Werkzeugausgabe -Konfig $Konfig -Ausgabe $rohAusgabe -Quelle 'spotdl'

    $ergebnis = Ermittle-Ergebnis -Ausgabe $rohAusgabe -Quelle 'spotdl' `
                                  -Startzeit $start -Zielordner (Loese-Zielordner $Konfig) `
                                  -Soll $Soll
    $dauer = (Get-Date) - $start

    Schreibe-Log ("spotdl beendet: Exit {0}, {1} neu, {2} uebersprungen, {3:mm\:ss} Laufzeit" -f `
                  $code, $ergebnis.Neu, $ergebnis.Uebersprungen, $dauer) 'INFO'

    return [pscustomobject]@{
        Erfolg        = ($code -eq 0)
        ExitCode      = $code
        NeueDateien   = $ergebnis.Neu
        Uebersprungen = $ergebnis.Uebersprungen
        Ermittlungsart = $ergebnis.Ermittlungsart
    }
}

# =============================================================================
#  YT-DLP
# =============================================================================

function Baue-YtdlpBasisArgumente {
    param($Konfig)

    $argumente = New-Object System.Collections.Generic.List[string]
    $argumente.Add('-x')
    $argumente.Add('--audio-format'); $argumente.Add($Konfig.Format)

    if ($Konfig.Bitrate -and $Konfig.Bitrate -ne 'disable') {
        $argumente.Add('--audio-quality'); $argumente.Add($Konfig.Bitrate.ToUpper())
    } else {
        $argumente.Add('--audio-quality'); $argumente.Add('0')
    }

    $argumente.Add('--embed-thumbnail')
    $argumente.Add('--embed-metadata')
    $argumente.Add('--sponsorblock-remove'); $argumente.Add('music_offtopic')
    $argumente.Add('--no-overwrites')
    $argumente.Add('--ignore-errors')

    # Nachtmodus: Pausen zwischen den Titeln, weniger parallele Fragmente.
    if ($Konfig.Nachtmodus) {
        $argumente.Add('--sleep-interval');     $argumente.Add('3')
        $argumente.Add('--max-sleep-interval'); $argumente.Add('10')
        $argumente.Add('-N'); $argumente.Add('2')
    } else {
        # Fragmente parallel laden - beschleunigt vor allem lange Videos
        $argumente.Add('-N'); $argumente.Add('4')
    }

    if ($Konfig.ArchivNutzen) {
        $argumente.Add('--download-archive'); $argumente.Add($DateiArchivYT)
    }

    return ,$argumente
}

function Hole-MitYtdlp {
    param($Konfig, [string]$Adresse, [bool]$AlsPlaylist = $false, [string]$ZielMuster = '', [int]$Soll = 0)

    if (-not (Get-Command yt-dlp -ErrorAction SilentlyContinue)) {
        Melde '  yt-dlp ist nicht installiert.  Abhilfe:  pip install yt-dlp' 'Fehler'
        return [pscustomobject]@{
            Erfolg         = $false
            ExitCode       = -1
            NeueDateien    = 0
            Uebersprungen  = 0
            Ermittlungsart = 'Nicht gestartet'
        }
    }


    if ([string]::IsNullOrWhiteSpace($ZielMuster)) {
        $ZielMuster = Join-Path (Loese-Zielordner $Konfig) '%(artist,uploader)s\%(album,playlist_title|Einzeltitel)s\%(title)s.%(ext)s'
    }

    $argumente = Baue-YtdlpBasisArgumente -Konfig $Konfig
    $argumente.Add('-o'); $argumente.Add($ZielMuster)

    if ($AlsPlaylist) { $argumente.Add('--yes-playlist') }
    else             { $argumente.Add('--no-playlist')  }

    $argumente.Add($Adresse)

    Melde ("  -> yt-dlp {0}" -f ($argumente -join ' ')) 'Grau'
    Schreibe-Log "yt-dlp $($argumente -join ' ')" 'INFO'

    $start = Get-Date
    $alteEinstellung = $ErrorActionPreference
    $ErrorActionPreference = 'SilentlyContinue'
    try {
        & yt-dlp @argumente 2>&1 | Tee-Object -Variable rohAusgabe
    } finally {
        $ErrorActionPreference = $alteEinstellung
    }
    $code = $LASTEXITCODE

    Protokolliere-Werkzeugausgabe -Konfig $Konfig -Ausgabe $rohAusgabe -Quelle 'yt-dlp'

    $ergebnis = Ermittle-Ergebnis -Ausgabe $rohAusgabe -Quelle 'yt-dlp' `
                                  -Startzeit $start -Zielordner (Loese-Zielordner $Konfig) `
                                  -Soll $Soll
    $dauer = (Get-Date) - $start

    Schreibe-Log ("yt-dlp beendet: Exit {0}, {1} neu, {2} uebersprungen, {3:mm\:ss} Laufzeit" -f `
                  $code, $ergebnis.Neu, $ergebnis.Uebersprungen, $dauer) 'INFO'

    return [pscustomobject]@{
        Erfolg        = ($code -eq 0)
        ExitCode      = $code
        NeueDateien   = $ergebnis.Neu
        Uebersprungen = $ergebnis.Uebersprungen
        Ermittlungsart = $ergebnis.Ermittlungsart
    }
}

# =============================================================================
#  MEHRFACHAUSWAHL  --  Pfeiltasten, Space, Enter
# =============================================================================

function Waehle-AusListe {
    <#
      Erwartet Objekte mit den Eigenschaften:
        Anzeige   (string)  - was in der Liste steht
        Zusatz    (string)  - rechte Spalte
        Markiert  (bool)    - Startzustand
      Gibt die markierten Objekte zurueck, oder $null bei Abbruch.
    #>
    param(
        [array]$Elemente,
        [string]$Ueberschrift = 'Auswahl'
    )

    if ($Elemente.Count -eq 0) { return $null }

    $position = 0
    $offset   = 0

    try   { $fensterHoehe  = $Host.UI.RawUI.WindowSize.Height } catch { $fensterHoehe  = 30 }
    try   { $fensterBreite = $Host.UI.RawUI.WindowSize.Width }  catch { $fensterBreite = 100 }

    if ($fensterBreite -lt 60) { $fensterBreite = 60 }

    $seitenGroesse = [Math]::Max(5, $fensterHoehe - 12)
    $textBreite    = [Math]::Max(25, $fensterBreite - 26)
    $zeilenBreite  = $fensterBreite - 1

    Clear-Host

    while ($true) {

        if ($position -lt $offset)                    { $offset = $position }
        if ($position -ge ($offset + $seitenGroesse)) { $offset = $position - $seitenGroesse + 1 }
        if ($offset -lt 0)                            { $offset = 0 }

        $anzahlMarkiert = @($Elemente | Where-Object { $_.Markiert }).Count

        try { [Console]::SetCursorPosition(0, 0) } catch { }

        # --- Kopf -----------------------------------------------------------
        $trenner = '=' * [Math]::Min($zeilenBreite, 75)
        foreach ($z in @($trenner, "  $Ueberschrift", $trenner)) {
            Write-Host ($z.PadRight($zeilenBreite).Substring(0, $zeilenBreite)) -ForegroundColor Cyan
        }
        $stand = "  {0} von {1} markiert" -f $anzahlMarkiert, $Elemente.Count
        Write-Host ($stand.PadRight($zeilenBreite).Substring(0, $zeilenBreite)) -ForegroundColor Green
        Write-Host (''.PadRight($zeilenBreite))

        # --- Liste ----------------------------------------------------------
        for ($i = 0; $i -lt $seitenGroesse; $i++) {
            $index = $offset + $i

            if ($index -ge $Elemente.Count) {
                Write-Host (''.PadRight($zeilenBreite))
                continue
            }

            $e = $Elemente[$index]
            $haken  = if ($e.Markiert) { '[x]' } else { '[ ]' }
            $zeiger = if ($index -eq $position) { '>' } else { ' ' }

            $text   = (Kuerze-Text -Text $e.Anzeige -Laenge $textBreite).PadRight($textBreite)
            $zusatz = if ($e.Zusatz) { [string]$e.Zusatz } else { '' }

            $zeile = ' {0} {1} {2}  {3}' -f $zeiger, $haken, $text, $zusatz
            $zeile = $zeile.PadRight($zeilenBreite).Substring(0, $zeilenBreite)

            if ($index -eq $position) {
                Write-Host $zeile -ForegroundColor Black -BackgroundColor Gray
            } elseif ($e.Markiert) {
                Write-Host $zeile -ForegroundColor Green
            } else {
                Write-Host $zeile
            }
        }

        # --- Fuss -----------------------------------------------------------
        $fuss = @(
            '',
            ('-' * [Math]::Min($zeilenBreite, 75)),
            '  Pfeile = bewegen   Space = an/aus   A = alle   K = keine   I = umkehren',
            '  Enter = starten    Esc = abbrechen'
        )
        foreach ($z in $fuss) {
            Write-Host ($z.PadRight($zeilenBreite).Substring(0, $zeilenBreite)) -ForegroundColor DarkGray
        }

        # --- Taste ----------------------------------------------------------
        $taste = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')

        switch ($taste.VirtualKeyCode) {
            38 { if ($position -gt 0) { $position-- } else { $position = $Elemente.Count - 1 } }
            40 { if ($position -lt ($Elemente.Count - 1)) { $position++ } else { $position = 0 } }
            33 { $position = [Math]::Max(0, $position - $seitenGroesse) }
            34 { $position = [Math]::Min($Elemente.Count - 1, $position + $seitenGroesse) }
            36 { $position = 0 }
            35 { $position = $Elemente.Count - 1 }
            32 { $Elemente[$position].Markiert = -not $Elemente[$position].Markiert }
            65 { foreach ($e in $Elemente) { $e.Markiert = $true } }
            75 { foreach ($e in $Elemente) { $e.Markiert = $false } }
            73 { foreach ($e in $Elemente) { $e.Markiert = -not $e.Markiert } }
            13 { Clear-Host; return @($Elemente | Where-Object { $_.Markiert }) }
            27 { Clear-Host; return $null }
        }
    }
}

# =============================================================================
#  KANAL UND PLAYLISTS ERMITTELN
# =============================================================================

function Finde-Kanaele {
    param([string]$Suchbegriff)

    if (-not (Get-Command yt-dlp -ErrorAction SilentlyContinue)) {
        Melde '  yt-dlp ist nicht installiert.  Abhilfe:  pip install yt-dlp' 'Fehler'
        return @()
    }

    Melde '  Suche laeuft ...' 'Grau'

    $argumente = @(
        '--flat-playlist',
        '--dump-json',
        '--no-warnings',
        ("ytsearch12:$Suchbegriff")
    )

    $roh = & yt-dlp @argumente 2>$null

    if (-not $roh) { return @() }

    $gefunden = @{}
    foreach ($zeile in $roh) {
        if ([string]::IsNullOrWhiteSpace($zeile)) { continue }
        try { $eintrag = $zeile | ConvertFrom-Json } catch { continue }

        $kanalUrl = $eintrag.channel_url
        if (-not $kanalUrl) { $kanalUrl = $eintrag.uploader_url }
        if (-not $kanalUrl) { continue }

        $kanalName = $eintrag.channel
        if (-not $kanalName) { $kanalName = $eintrag.uploader }
        if (-not $kanalName) { $kanalName = 'Unbekannt' }

        if (-not $gefunden.ContainsKey($kanalUrl)) {
            $gefunden[$kanalUrl] = [pscustomobject]@{
                Name    = $kanalName
                Url     = $kanalUrl
                Treffer = 1
            }
        } else {
            $gefunden[$kanalUrl].Treffer++
        }
    }

    return @($gefunden.Values | Sort-Object -Property Treffer -Descending)
}

function Baue-PlaylistObjekt {
    param($Eintrag)

    $titel = ''
    try { if ($null -ne $Eintrag.title) { $titel = [string]$Eintrag.title } } catch { }
    if ([string]::IsNullOrWhiteSpace($titel)) { $titel = 'Ohne Titel' }

    $url = ''
    try { if ($null -ne $Eintrag.url) { $url = [string]$Eintrag.url } } catch { }

    if ([string]::IsNullOrWhiteSpace($url) -and $Eintrag.id) {
        $url = 'https://www.youtube.com/playlist?list=' + [string]$Eintrag.id
    }
    if ([string]::IsNullOrWhiteSpace($url)) { return $null }

    $anzahl = 0
    foreach ($feld in @('playlist_count','video_count')) {
        if ($Eintrag.$feld) {
            try { $anzahl = [int]$Eintrag.$feld; break } catch { }
        }
    }

    $zusatz = if ($anzahl -gt 0) { '{0,5} Titel' -f $anzahl } else { '    ? Titel' }

    return [pscustomobject]@{
        Anzeige  = $titel
        Zusatz   = $zusatz
        Url      = $url
        Titel    = $titel
        Anzahl   = $anzahl
        Markiert = $false
    }
}

function Sammle-Playlists {
    <#
      Laeuft rekursiv durch die entries-Struktur. Manche Kanaele gruppieren
      ihre Playlists in Rubriken, dann liegen sie mehrere Ebenen tief.
    #>
    param($Knoten, $Sammler, [int]$Tiefe = 0)

    if ($Tiefe -gt 5 -or -not $Knoten) { return }

    foreach ($e in $Knoten) {
        if (-not $e) { continue }

        # Ausdruecklich in Strings wandeln - manche Felder kommen als Array
        $url = ''
        $id  = ''
        try { if ($null -ne $e.url) { $url = [string]$e.url } } catch { }
        try { if ($null -ne $e.id)  { $id  = [string]$e.id  } } catch { }

        # Ein Objekt mit eigenen 'entries' ist ein Container (Rubrik, Tab).
        # Dort IMMER hineinsteigen - unabhaengig davon, wie seine ID aussieht.
        # Sonst blockiert eine Rubrik mit langer ID die darunterliegenden
        # echten Playlists.
        if ($e.entries) {
            Sammle-Playlists -Knoten $e.entries -Sammler $Sammler -Tiefe ($Tiefe + 1)
            continue
        }

        # Blattobjekt: Playlist, wenn URL oder Metadaten es sagen.
        # Die ID-Laenge allein reicht NICHT - auch Videos und Kanaele koennen
        # lange IDs tragen.
        $istPlaylist = $false
        if ($url -match '[?&]list=')                       { $istPlaylist = $true }
        elseif ($e._type -eq 'playlist')                   { $istPlaylist = $true }
        elseif ($e.ie_key -eq 'YoutubeTab')                { $istPlaylist = $true }
        elseif ($e.playlist_count -or $e.video_count)      { $istPlaylist = $true }

        # Automatische Listen ausschliessen:
        #   RD - Radio-Mixe, LL - Likes, FL - Favoriten, WL - Watch Later
        if ($id -match '^(RD|LL|FL|WL)')            { $istPlaylist = $false }
        if ($url -match '[?&]list=(RD|LL|FL|WL)')   { $istPlaylist = $false }

        if ($istPlaylist) {
            $obj = Baue-PlaylistObjekt $e
            if ($obj -and -not [string]::IsNullOrWhiteSpace($obj.Url)) {
                [void]$Sammler.Add($obj)
            }
        }
    }
}

function Hole-PlaylistAnzahl {
    <#
      Fragt die Gesamtzahl der Titel einer Playlist ab, ohne die ganze
      Liste aufzuloesen. -I 1 begrenzt auf den ersten Eintrag, in dessen
      Kontext playlist_count aber bereits die Gesamtzahl enthaelt.
    #>
    param([string]$PlaylistUrl)

    $argumente = @(
        '--flat-playlist',
        '--no-warnings',
        '-I', '1',
        '--print', '%(playlist_count)s',
        $PlaylistUrl
    )

    try {
        $roh = & yt-dlp @argumente 2>$null
        foreach ($zeile in @($roh)) {
            $wert = ([string]$zeile).Trim()
            $zahl = 0
            if ([int]::TryParse($wert, [ref]$zahl) -and $zahl -gt 0) { return $zahl }
        }
    } catch { }

    return 0
}

function Hole-KanalPlaylistsVonTab {
    param([string]$TabUrl)

    $argumente = @(
        '--flat-playlist',
        '--dump-single-json',
        '--ignore-no-formats-error',
        $TabUrl
    )

    $fehlerDatei = Join-Path $env:TEMP ('ytdlp-fehler-' + [guid]::NewGuid().ToString('N') + '.txt')

    # PowerShell wirft eine NativeCommandError, sobald ein externes Programm
    # auf stderr schreibt. Fuer diesen Aufruf abschalten.
    $alteEinstellung = $ErrorActionPreference
    $ErrorActionPreference = 'SilentlyContinue'
    try {
        $roh = & yt-dlp @argumente 2>$fehlerDatei
    } finally {
        $ErrorActionPreference = $alteEinstellung
    }

    $json = ($roh -join '')

    $fehlertext = ''
    if (Test-Path $fehlerDatei) {
        $rohFehler = Get-Content $fehlerDatei -ErrorAction SilentlyContinue
        # Nur echte yt-dlp-Meldungen behalten, kein PowerShell-Rauschen
        $gefiltert = @($rohFehler | Where-Object {
            $_ -match '^(ERROR|WARNING)' -and $_ -notmatch 'Deprecated Feature'
        })
        $fehlertext = ($gefiltert -join "`n")
        Remove-Item $fehlerDatei -ErrorAction SilentlyContinue
    }

    if ([string]::IsNullOrWhiteSpace($json)) {
        return [pscustomobject]@{ Liste = @(); Fehler = $fehlertext; RohAnzahl = 0; Titel = '' }
    }

    try { $daten = $json | ConvertFrom-Json }
    catch {
        return [pscustomobject]@{
            Liste = @()
            Fehler = "Antwort war kein gueltiges JSON ($($json.Length) Zeichen)"
            RohAnzahl = 0
            Titel = ''
        }
    }

    $sammler = New-Object System.Collections.ArrayList
    Sammle-Playlists -Knoten $daten.entries -Sammler $sammler

    $gesehen  = New-Object 'System.Collections.Generic.HashSet[string]'
    $ergebnis = New-Object System.Collections.ArrayList

    foreach ($p in $sammler) {
        $schluessel = [string]$p.Url
        if ([string]::IsNullOrWhiteSpace($schluessel)) { continue }
        if ($gesehen.Add($schluessel)) { [void]$ergebnis.Add($p) }
    }

    $rohAnzahl = 0
    if ($daten.entries) { $rohAnzahl = @($daten.entries).Count }

    $seitenTitel = ''
    if ($daten.title) { $seitenTitel = [string]$daten.title }

    return [pscustomobject]@{
        Liste     = $ergebnis.ToArray()
        Fehler    = $fehlertext
        RohAnzahl = $rohAnzahl
        Titel     = $seitenTitel
    }
}

function Hole-KanalPlaylists {
    param([string]$KanalUrl)

    $basis = $KanalUrl.TrimEnd('/')
    $basis = $basis -replace '/(playlists|releases|videos|streams|shorts|featured|community|about)$', ''

    # Quellen der Reihe nach:
    #   playlists - normale Kanaele
    #   releases  - Kuenstlerkanaele mit Veroeffentlichungen
    #   music     - YouTube Music; bei Topic-Kanaelen liegen die Alben nur dort
    #               abrufbar, auf der normalen Kanalseite laedt YouTube sie
    #               per API in ein Overlay nach, an das yt-dlp nicht herankommt.
    $quellen = New-Object System.Collections.ArrayList
    [void]$quellen.Add("$basis/playlists")
    [void]$quellen.Add("$basis/releases")

    if ($basis -match '/channel/(UC[\w\-]+)') {
        $kanalId = $Matches[1]
        [void]$quellen.Add("https://music.youtube.com/channel/$kanalId")
    }

    $letzterFehler   = ''
    $letzteRohAnzahl = 0
    $letzterTitel    = ''

    foreach ($quelle in $quellen) {
        Melde ("  Lese {0} ..." -f $quelle) 'Grau'

        $ergebnis = Hole-KanalPlaylistsVonTab -TabUrl $quelle

        if ($ergebnis.Liste.Count -gt 0) {
            Melde ("  {0} Playlist(s) gefunden." -f $ergebnis.Liste.Count) 'Gut'
            Schreibe-Log "Quelle $quelle : $($ergebnis.Liste.Count) Playlists." 'OK'
            return ,$ergebnis.Liste
        }

        if ($ergebnis.Fehler) {
            $kurz = ($ergebnis.Fehler -split "`n" | Select-Object -First 1)
            Melde ("    {0}" -f $kurz) 'Grau'
            $letzterFehler = $ergebnis.Fehler
        } elseif ($ergebnis.RohAnzahl -gt 0) {
            Melde ("    {0} Eintraege gelesen, aber keine Playlists darunter." -f $ergebnis.RohAnzahl) 'Grau'
            $letzteRohAnzahl = $ergebnis.RohAnzahl
        } else {
            Melde '    Nichts erhalten.' 'Grau'
        }

        if ($ergebnis.Titel) { $letzterTitel = $ergebnis.Titel }
    }

    # --- Nichts gefunden ----------------------------------------------------
    Write-Host ''
    Melde '  In keiner Quelle wurden Playlists gefunden.' 'Warnung'
    if ($letzterTitel) { Melde ("  Seitentitel zuletzt: {0}" -f $letzterTitel) 'Grau' }

    Schreibe-Log "Keine Playlists fuer $basis (Roh: $letzteRohAnzahl | $letzterFehler)" 'WARN'
    return @()
}

# =============================================================================
#  GEMERKTE PLAYLISTS
# =============================================================================
#  Die Musik bleibt album-sortiert in der Sammlung liegen. Zusaetzlich wird
#  nur die Songliste gemerkt: welcher Titel, welcher Interpret, welche
#  Position. Beim USB-Export sucht das Script die Dateien anhand ihrer Tags
#  wieder zusammen und legt sie flach in einen Playlist-Ordner auf den Stick.
#
#  Bewusst KEINE Dateipfade speichern: die Sammlung darf umsortiert,
#  umbenannt oder neu getaggt werden, ohne dass die Playlist kaputtgeht.
# =============================================================================

function Merke-Playlist {
    <#
      Liest eine per 'spotdl save' erzeugte Songliste und legt daraus eine
      schlanke Playlist-Datei an (Interpret, Titel, Position).
    #>
    param([string]$Name, [string]$SpotdlDatei, [string]$Quelle = '')

    if (-not (Test-Path $SpotdlDatei)) { return $false }

    try {
        $roh = Get-Content $SpotdlDatei -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        Schreibe-Log "Playlist merken: JSON nicht lesbar ($SpotdlDatei)" 'FEHLER'
        return $false
    }

    $eintraege = New-Object System.Collections.ArrayList
    $position = 0

    foreach ($s in @($roh)) {
        if (-not $s) { continue }
        $position++

        $interpret = ''
        $titel     = ''
        try { if ($s.artist) { $interpret = [string]$s.artist } } catch { }
        try { if ($s.name)   { $titel     = [string]$s.name   } } catch { }
        if (-not $titel) { try { if ($s.title) { $titel = [string]$s.title } } catch { } }

        if ([string]::IsNullOrWhiteSpace($titel)) { continue }

        [void]$eintraege.Add([pscustomobject]@{
            Position  = $position
            Interpret = $interpret
            Titel     = $titel
        })
    }

    if ($eintraege.Count -eq 0) { return $false }

    if (-not (Test-Path $OrdnerPlaylists)) {
        New-Item -Path $OrdnerPlaylists -ItemType Directory -Force | Out-Null
    }

    $datei = Join-Path $OrdnerPlaylists ((Saeubere-Dateiname $Name) + '.json')
    $inhalt = [pscustomobject]@{
        Name     = $Name
        Quelle   = $Quelle
        Erstellt = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        Anzahl   = $eintraege.Count
        Songs    = @($eintraege)
    }

    try {
        $inhalt | ConvertTo-Json -Depth 5 | Set-Content -Path $datei -Encoding UTF8
        Schreibe-Log ("Playlist gemerkt: {0} ({1} Titel)" -f $Name, $eintraege.Count) 'OK'
        return $true
    } catch {
        Schreibe-Log "Playlist merken fehlgeschlagen: $($_.Exception.Message)" 'FEHLER'
        return $false
    }
}

function Lese-GemerktePlaylists {
    if (-not (Test-Path $OrdnerPlaylists)) { return @() }

    $liste = New-Object System.Collections.ArrayList
    foreach ($d in @(Get-ChildItem -Path $OrdnerPlaylists -Filter '*.json' -File -ErrorAction SilentlyContinue)) {
        try {
            $inhalt = Get-Content $d.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            [void]$liste.Add([pscustomobject]@{
                Name     = $inhalt.Name
                Anzahl   = $inhalt.Anzahl
                Erstellt = $inhalt.Erstellt
                Songs    = @($inhalt.Songs)
                Datei    = $d.FullName
            })
        } catch {
            Schreibe-Log "Playlist-Datei defekt: $($d.Name)" 'WARN'
        }
    }
    return @($liste)
}

function Baue-Titelindex {
    <#
      Liest alle Audiodateien im Zielordner ein und legt sie unter einem
      normalisierten Schluessel aus Interpret und Titel ab.

      Der TITEL kommt aus dem Dateinamen (ohne fuehrende Nummer).
      Der INTERPRET kommt aus der ORDNERSTRUKTUR - beim Standardschema
      Zielordner\Interpret\Album\Datei ist das der Grossvater-Ordner.
      Bei anderen Schemata kann der Interpret falsch oder leer sein; dann
      greift nur noch der Titel-Schluessel, der mehrdeutig sein kann.

      Tags aus den Dateien zu lesen waere zuverlaessiger, braeuchte aber
      eine externe Bibliothek (TagLib, ffprobe).

      Rueckgabe: Hashtable Schluessel -> Liste von FileInfo
      (Liste statt Einzelwert, damit Mehrdeutigkeiten sichtbar bleiben)
    #>
    param([string]$Zielordner)

    $index = @{}
    if (-not (Test-Path $Zielordner)) { return $index }

    $endungen = @('.mp3','.m4a','.flac','.ogg','.opus','.wav')
    $zielNorm = $Zielordner.TrimEnd('\')

    foreach ($d in @(Get-ChildItem -Path $Zielordner -File -Recurse -ErrorAction SilentlyContinue)) {
        if ($endungen -notcontains $d.Extension.ToLower()) { continue }

        # Fuehrende Titelnummer abstreifen: "03 - Titel" -> "Titel"
        $titel = $d.BaseName -replace '^\d+\s*-\s*', ''

        # Interpret aus der Ordnerstruktur ableiten
        $interpret = ''
        $eltern = $d.Directory
        if ($eltern -and $eltern.Parent) {
            if ($eltern.Parent.FullName -eq $zielNorm) {
                # Datei liegt direkt in Zielordner\X\ - X ist dann der Interpret
                $interpret = $eltern.Name
            } else {
                # Datei liegt in Zielordner\Interpret\Album\ - Grossvater
                $interpret = $eltern.Parent.Name
            }
        }

        foreach ($schluessel in @(
            (Normalisiere-Titelschluessel -Interpret $interpret -Titel $titel),
            (Normalisiere-Titelschluessel -Interpret ''         -Titel $titel)
        )) {
            if (-not $schluessel) { continue }
            if (-not $index.ContainsKey($schluessel)) {
                $index[$schluessel] = New-Object System.Collections.ArrayList
            }
            [void]$index[$schluessel].Add($d)
        }
    }

    return $index
}

function Normalisiere-Titelschluessel {
    <#
      Macht Interpret und Titel vergleichbar: Kleinschreibung, Klammerzusaetze
      wie "(Remastered 2011)" oder "- Live" raus, dann alle Sonderzeichen.
    #>
    param([string]$Interpret, [string]$Titel)

    $t = [string]$Titel
    if ([string]::IsNullOrWhiteSpace($t)) { return '' }

    $t = $t.ToLowerInvariant()
    $t = $t -replace '\((feat|ft|with)[^)]*\)', ''
    $t = $t -replace '\((remaster|remastered|live|radio edit|single version|album version)[^)]*\)', ''
    $t = $t -replace '\s*-\s*(remaster|remastered|live|radio edit)\b.*$', ''
    $t = $t -replace '[^\p{L}\p{Nd}]', ''

    $i = [string]$Interpret
    if ($i) {
        $i = $i.ToLowerInvariant()
        # Nur der erste Interpret zaehlt - Featurings stehen unterschiedlich da
        $i = ($i -split '[,;&/]')[0]
        $i = $i -replace '[^\p{L}\p{Nd}]', ''
    }

    if ([string]::IsNullOrWhiteSpace($t)) { return '' }
    return ('{0}|{1}' -f $i, $t)
}

function Finde-PlaylistDateien {
    <#
      Sucht zu den Songs einer gemerkten Playlist die Dateien in der Sammlung.

      Reihenfolge: erst Interpret+Titel (eindeutig), dann nur Titel. Beim
      Titel-Schluessel koennen mehrere Dateien passen ("Intro", "Home" ...) -
      dann wird der erste Treffer genommen und der Fall als mehrdeutig
      gemeldet, damit der Nutzer ihn pruefen kann.

      Rueckgabe: Objekt mit Gefunden, Fehlend und Mehrdeutig (alles Listen).
    #>
    param($Playlist, [string]$Zielordner)

    $index = Baue-Titelindex -Zielordner $Zielordner

    $gefunden   = New-Object System.Collections.ArrayList
    $fehlend    = New-Object System.Collections.ArrayList
    $mehrdeutig = New-Object System.Collections.ArrayList

    foreach ($s in $Playlist.Songs) {
        $mitInterpret = Normalisiere-Titelschluessel -Interpret $s.Interpret -Titel $s.Titel
        $nurTitel     = Normalisiere-Titelschluessel -Interpret ''           -Titel $s.Titel

        $kandidaten = $null
        $ueberTitelAllein = $false

        if ($mitInterpret -and $index.ContainsKey($mitInterpret)) {
            $kandidaten = $index[$mitInterpret]
        } elseif ($nurTitel -and $index.ContainsKey($nurTitel)) {
            $kandidaten = $index[$nurTitel]
            $ueberTitelAllein = $true
        }

        if (-not $kandidaten -or $kandidaten.Count -eq 0) {
            [void]$fehlend.Add([pscustomobject]@{
                Position  = $s.Position
                Interpret = $s.Interpret
                Titel     = $s.Titel
            })
            continue
        }

        $treffer = [pscustomobject]@{
            Position  = $s.Position
            Interpret = $s.Interpret
            Titel     = $s.Titel
            Datei     = $kandidaten[0]
        }
        [void]$gefunden.Add($treffer)

        # Mehrdeutig, wenn nur ueber den Titel gefunden UND mehrere passen
        if ($ueberTitelAllein -and $kandidaten.Count -gt 1) {
            [void]$mehrdeutig.Add([pscustomobject]@{
                Position  = $s.Position
                Interpret = $s.Interpret
                Titel     = $s.Titel
                Gewaehlt  = $kandidaten[0].FullName
                Anzahl    = $kandidaten.Count
            })
        }
    }

    return [pscustomobject]@{
        Gefunden   = @($gefunden   | Sort-Object -Property Position)
        Fehlend    = @($fehlend    | Sort-Object -Property Position)
        Mehrdeutig = @($mehrdeutig | Sort-Object -Property Position)
    }
}

# =============================================================================
#  MENUEPUNKT 1  --  EINZELSUCHE
# =============================================================================

function Menue-Einzelsuche {
    param($Konfig)

    Zeige-Linie '='
    Melde '  Einzelsuche' 'Titel'
    Zeige-Linie '='
    Melde '  Beispiel:  Dire Straits Sultans of Swing' 'Grau'
    Write-Host ''

    $abfrage = (Read-Host '  Titel').Trim()
    if ([string]::IsNullOrWhiteSpace($abfrage)) { return }

    if (Ist-ImArchiv -Eintrag $abfrage -Konfig $Konfig) {
        Melde '  Steht bereits im Archiv.' 'Warnung'
        $trotzdem = Read-Host '  Trotzdem laden? (j/n)'
        if ($trotzdem -notmatch '^[jJyY]') { return }
    }

    Write-Host ''
    $start = Get-Date
    $ergebnis = Hole-MitSpotdl -Konfig $Konfig -Abfrage $abfrage
    $dauer = (Get-Date) - $start

    Write-Host ''
    $abgedeckt = $ergebnis.NeueDateien
    if ($null -ne $ergebnis.Uebersprungen) { $abgedeckt += $ergebnis.Uebersprungen }

    if ($ergebnis.Erfolg -and $abgedeckt -gt 0) {
        if ($ergebnis.NeueDateien -gt 0) {
            Melde ("  Fertig: {0} Datei(en) in {1:N0} Sekunden." -f $ergebnis.NeueDateien, $dauer.TotalSeconds) 'Gut'
        } else {
            Melde '  War bereits vorhanden - nichts zu tun.' 'Gut'
        }
        Merke-ImArchiv -Eintrag $abfrage -Konfig $Konfig
        Schreibe-Log "OK: $abfrage ($($ergebnis.NeueDateien) neu, $($ergebnis.Uebersprungen) vorhanden)" 'OK'
    } else {
        Melde ("  Nichts geladen - kein Treffer oder Fehler (Exit {0})." -f $ergebnis.ExitCode) 'Warnung'
        Schreibe-Log "Ohne Ergebnis: $abfrage (Exit $($ergebnis.ExitCode))" 'WARN'
    }
    Warte-AufTaste
}

# =============================================================================
#  MENUEPUNKT 2  --  WUNSCHLISTE ABARBEITEN
# =============================================================================

function Menue-Liste {
    param($Konfig)

    Zeige-Linie '='
    Melde '  Wunschliste abarbeiten' 'Titel'
    Zeige-Linie '='

    if (-not (Test-Path $DateiListe)) {
        $vorlage = @(
            '# Wunschliste - eine Zeile pro Eintrag.',
            '# Zeilen mit # am Anfang werden uebersprungen.',
            '#',
            '# Moeglich sind drei Arten von Eintraegen:',
            '#',
            '#   1) Suchbegriff aus Interpret und Titel',
            '#      Dire Straits Sultans of Swing',
            '#',
            '#   2) Link auf einen einzelnen Titel',
            '#      https://open.spotify.com/track/...',
            '#',
            '#   3) Link auf ein ganzes Album',
            '#      https://open.spotify.com/album/...',
            '#',
            '# Erledigte Eintraege merkt sich das Archiv und ueberspringt sie',
            '# beim naechsten Lauf. Die Zeilen koennen also stehenbleiben.',
            ''
        )
        Set-Content -Path $DateiListe -Value $vorlage -Encoding UTF8
        Melde '  wunschliste.txt war nicht vorhanden und wurde angelegt:' 'Warnung'
        Melde "  $DateiListe" 'Grau'
        Melde '  Trage dort deine Wuensche ein und starte diesen Punkt erneut.' 'Grau'
        Warte-AufTaste
        return
    }

    $zeilen = @(Get-Content -Path $DateiListe -Encoding UTF8 |
                Where-Object { $_.Trim() -ne '' -and $_.Trim() -notmatch '^#' })

    if ($zeilen.Count -eq 0) {
        Melde '  wunschliste.txt enthaelt keine verwertbaren Zeilen.' 'Warnung'
        Warte-AufTaste
        return
    }

    Melde ("  {0} Eintrag/Eintraege gefunden." -f $zeilen.Count)
    Write-Host ''

    $erfolgreich = 0
    $uebersprungen = 0
    $fehlgeschlagen = 0
    $fehlerliste = New-Object System.Collections.Generic.List[string]
    $nummer = 0
    $startGesamt = Get-Date

    foreach ($eintrag in $zeilen) {
        $nummer++
        $eintrag = $eintrag.Trim()

        Zeige-Linie
        Melde ("  [{0}/{1}]  {2}" -f $nummer, $zeilen.Count, $eintrag) 'Titel'

        if (Ist-ImArchiv -Eintrag $eintrag -Konfig $Konfig) {
            Melde '  Bereits im Archiv - uebersprungen.' 'Grau'
            $uebersprungen++
            continue
        }

        $ergebnis = Hole-MitSpotdl -Konfig $Konfig -Abfrage $eintrag

        $abgedeckt = $ergebnis.NeueDateien
        if ($null -ne $ergebnis.Uebersprungen) { $abgedeckt += $ergebnis.Uebersprungen }

        if ($ergebnis.Erfolg -and $abgedeckt -gt 0) {
            if ($ergebnis.NeueDateien -gt 0) {
                Melde ("  OK ({0} Datei(en))" -f $ergebnis.NeueDateien) 'Gut'
            } else {
                Melde ("  Bereits vorhanden ({0} uebersprungen)." -f $ergebnis.Uebersprungen) 'Grau'
            }
            Merke-ImArchiv -Eintrag $eintrag -Konfig $Konfig
            $erfolgreich++
            Schreibe-Log "OK: $eintrag" 'OK'
        } else {
            Melde ("  Nichts geladen (Exit {0})." -f $ergebnis.ExitCode) 'Fehler'
            $fehlgeschlagen++
            $fehlerliste.Add($eintrag)
            Schreibe-Log "FEHLER: $eintrag (Exit $($ergebnis.ExitCode))" 'FEHLER'
        }
    }

    $dauerGesamt = (Get-Date) - $startGesamt

    Write-Host ''
    Zeige-Linie '='
    Melde '  Bilanz' 'Titel'
    Zeige-Linie '='
    Melde ("  Erfolgreich    : {0}" -f $erfolgreich) 'Gut'
    Melde ("  Uebersprungen  : {0}" -f $uebersprungen) 'Grau'
    if ($fehlgeschlagen -gt 0) {
        Melde ("  Fehlgeschlagen : {0}" -f $fehlgeschlagen) 'Fehler'
        Write-Host ''
        Melde '  Nicht gefunden:' 'Fehler'
        foreach ($f in $fehlerliste) { Melde "    - $f" 'Fehler' }
    } else {
        Melde '  Fehlgeschlagen : 0'
    }
    Melde ("  Laufzeit       : {0:hh\:mm\:ss}" -f $dauerGesamt) 'Grau'

    Schreibe-Log "Listenlauf: $erfolgreich ok, $uebersprungen uebersprungen, $fehlgeschlagen Fehler." 'INFO'
    Warte-AufTaste
}

# =============================================================================
#  MENUEPUNKT 3  --  LINK LADEN
# =============================================================================

function Menue-Link {
    param($Konfig)

    Zeige-Linie '='
    Melde '  Link laden' 'Titel'
    Zeige-Linie '='
    Melde '  Spotify-Link      -> spotdl (Track, Album ODER Playlist - sauberes Tagging)' 'Grau'
    Melde '  YouTube und Rest  -> yt-dlp  (auch Live, Sets, Vortraege)' 'Grau'
    Melde '  Kein Link         -> spotdl-Suche' 'Grau'
    Melde '  Fuer eine ganze Kuenstler-Diskografie: Menuepunkt 5' 'Grau'
    Write-Host ''

    $eingabe = (Read-Host '  Link oder Suchbegriff').Trim()
    if ([string]::IsNullOrWhiteSpace($eingabe)) { return }

    # Spotify-Sprachsegment (/intl-de/) und Tracking-Parameter entfernen
    if ($eingabe -match 'open\.spotify\.com') {
        $eingabe = $eingabe -replace '/intl-[a-zA-Z\-]+/', '/'
        $eingabe = $eingabe -replace '\?.*$', ''
    }

    $istSpotify = $eingabe -match 'open\.spotify\.com|spotify:'
    $istLink    = $eingabe -match '^https?://'
    $istSpotifyPlaylist = $eingabe -match 'open\.spotify\.com/playlist/'

    $alsPlaylist = $false
    if ($istLink -and -not $istSpotify) {
        if ($eingabe -match 'list=|/playlist|/sets/|/album/') {
            $antwort = Read-Host '  Sieht nach Playlist/Album aus. Alles laden? (j/n)'
            $alsPlaylist = ($antwort -match '^[jJyY]')
        }
    }

    # Bei Spotify-Playlists anbieten, die Zusammenstellung zu merken.
    # Die Musik selbst bleibt album-sortiert - gemerkt wird nur, welche
    # Titel dazugehoeren. Beim USB-Export laesst sich daraus ein
    # Playlist-Ordner zusammenstellen.
    $playlistMerken = $false
    $playlistName   = ''
    if ($istSpotifyPlaylist) {
        Write-Host ''
        Melde '  Das ist eine Playlist. Die Titel landen wie gewohnt in ihren' 'Grau'
        Melde '  Album-Ordnern - die Playlist-Zusammenstellung geht dabei verloren.' 'Grau'
        Melde '  Auf Wunsch merkt sich das Script, welche Titel dazugehoeren.' 'Grau'
        Melde '  Beim USB-Export kannst du sie dann als Ordner zusammenstellen.' 'Grau'
        Write-Host ''
        $antwortMerken = (Read-Host '  Playlist merken? (J/n)').Trim()
        $playlistMerken = ($antwortMerken -eq '' -or $antwortMerken -match '^[jJyY]')

        if ($playlistMerken) {
            $playlistName = (Read-Host '  Name fuer die Playlist').Trim()
            if ([string]::IsNullOrWhiteSpace($playlistName)) {
                $playlistName = 'Playlist-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
            }
        }
    }

    Write-Host ''
    $sofort = (Read-Host '  (J)etzt laden oder in (W)arteschlange legen? [J]').Trim()

    if ($sofort -match '^[wW]') {
        if ($istSpotify -or -not $istLink) { $typ = 'spotdl' }
        elseif ($alsPlaylist)              { $typ = 'ytdlp-playlist' }
        else                               { $typ = 'ytdlp' }
        $beschreibung = Kuerze-Text -Text $eingabe -Laenge 60
        if (Fuege-ZurWarteschlange -Typ $typ -Beschreibung $beschreibung -Abfrage $eingabe) {
            Melde '  In die Warteschlange gelegt (Menuepunkt W).' 'Gut'
        }

        # Das Merken haengt nicht am Download - die Songliste kommt von
        # Spotify und laesst sich sofort holen, auch wenn das Audio erst
        # spaeter aus der Warteschlange geladen wird.
        if ($playlistMerken) {
            Write-Host ''
            Melde '  Hole die Songliste zum Merken ...' 'Grau'

            $tempListe = Join-Path $env:TEMP ('playlist-' + [guid]::NewGuid().ToString('N') + '.spotdl')
            [void](Fuehre-SpotdlSaveAus -Abfrage $eingabe -ZielDatei $tempListe `
                                        -Threads ([int]$Konfig.Threads) -Beschriftung 'Titel  ')

            if (Merke-Playlist -Name $playlistName -SpotdlDatei $tempListe -Quelle $eingabe) {
                Melde ("  Playlist '{0}' gemerkt." -f $playlistName) 'Gut'
            } else {
                Melde '  Playlist konnte nicht gemerkt werden.' 'Warnung'
            }

            Remove-Item $tempListe -ErrorAction SilentlyContinue
        }

        Warte-AufTaste
        return
    }

    Write-Host ''
    $start = Get-Date

    if ($istSpotify -or -not $istLink) {
        Melde '  Werkzeug: spotdl' 'Grau'
        $ergebnis = Hole-MitSpotdl -Konfig $Konfig -Abfrage $eingabe
    } else {
        Melde '  Werkzeug: yt-dlp' 'Grau'
        $ergebnis = Hole-MitYtdlp -Konfig $Konfig -Adresse $eingabe -AlsPlaylist $alsPlaylist
    }

    $dauer = (Get-Date) - $start

    Write-Host ''
    $abgedeckt = $ergebnis.NeueDateien
    if ($null -ne $ergebnis.Uebersprungen) { $abgedeckt += $ergebnis.Uebersprungen }

    if ($ergebnis.Erfolg -and $abgedeckt -gt 0) {
        if ($ergebnis.NeueDateien -gt 0) {
            Melde ("  Fertig: {0} Datei(en) in {1:hh\:mm\:ss}." -f $ergebnis.NeueDateien, $dauer) 'Gut'
        } else {
            Melde ("  Bereits vorhanden - {0} Datei(en) uebersprungen." -f $ergebnis.Uebersprungen) 'Gut'
        }
        if ($istSpotify -or -not $istLink) { Merke-ImArchiv -Eintrag $eingabe -Konfig $Konfig }
        Schreibe-Log "OK: $eingabe ($($ergebnis.NeueDateien) neu, $($ergebnis.Uebersprungen) vorhanden)" 'OK'
    } else {
        Melde ("  Nichts geladen - kein Treffer oder Fehler (Exit {0})." -f $ergebnis.ExitCode) 'Warnung'
        Schreibe-Log "Ohne Ergebnis: $eingabe (Exit $($ergebnis.ExitCode))" 'WARN'
    }

    # --- Playlist merken ----------------------------------------------------
    if ($playlistMerken) {
        Write-Host ''
        Melde '  Hole die Songliste zum Merken ...' 'Grau'

        $tempListe = Join-Path $env:TEMP ('playlist-' + [guid]::NewGuid().ToString('N') + '.spotdl')
        [void](Fuehre-SpotdlSaveAus -Abfrage $eingabe -ZielDatei $tempListe `
                                    -Threads ([int]$Konfig.Threads) -Beschriftung 'Titel  ')

        if (Merke-Playlist -Name $playlistName -SpotdlDatei $tempListe -Quelle $eingabe) {
            Melde ("  Playlist '{0}' gemerkt." -f $playlistName) 'Gut'
            Melde '  Zusammenstellen beim USB-Export (Menuepunkt U).' 'Grau'
        } else {
            Melde '  Playlist konnte nicht gemerkt werden.' 'Warnung'
        }

        Remove-Item $tempListe -ErrorAction SilentlyContinue
    }

    Warte-AufTaste
}

# =============================================================================
#  MENUEPUNKT 4  --  KANAL-PLAYLISTS
# =============================================================================

function Waehle-Kanal {
    <#
      Sucht Kanaele zu einem Suchbegriff und laesst den Nutzer einen
      auswaehlen. Gibt die Kanal-URL zurueck oder $null bei Abbruch.
    #>
    param([string]$Suchbegriff)

    Write-Host ''
    $kanaele = Finde-Kanaele -Suchbegriff $Suchbegriff

    if ($kanaele.Count -eq 0) {
        Melde '  Kein Kanal gefunden.' 'Fehler'
        return $null
    }

    Write-Host ''
    Melde '  Gefundene Kanaele:' 'Titel'
    Write-Host ''
    for ($i = 0; $i -lt $kanaele.Count; $i++) {
        Melde ("    [{0}]  {1}" -f ($i + 1), $kanaele[$i].Name)
        Melde ("         {0}" -f $kanaele[$i].Url) 'Grau'
    }
    Write-Host ''

    $wahl = (Read-Host '  Nummer (Enter bricht ab)').Trim()
    $nummer = 0
    if (-not [int]::TryParse($wahl, [ref]$nummer))    { return $null }
    if ($nummer -lt 1 -or $nummer -gt $kanaele.Count) { return $null }

    return $kanaele[$nummer - 1].Url
}

function Menue-KanalPlaylists {
    param($Konfig)

    Clear-Host
    Zeige-Linie '='
    Melde '  Kanal-Playlists' 'Titel'
    Zeige-Linie '='
    Melde '  Kanalname, @handle oder Kanal-URL eingeben.' 'Grau'
    Melde '  Beispiele:  @NPRMusic' 'Grau'
    Melde '              Tiny Desk Concerts' 'Grau'
    Melde '              https://www.youtube.com/@NPRMusic' 'Grau'
    Write-Host ''

    $eingabe = (Read-Host '  Kanal').Trim()
    if ([string]::IsNullOrWhiteSpace($eingabe)) { return }

    # --- Kanal-URL bestimmen ------------------------------------------------
    $kanalUrl = $null
    $ueberSucheGefunden = $false

    if ($eingabe -match '^https?://') {
        $kanalUrl = $eingabe
    }
    elseif ($eingabe -match '^@[\w\.\-]+$') {
        $kanalUrl = "https://www.youtube.com/$eingabe"
    }
    else {
        $kanalUrl = Waehle-Kanal -Suchbegriff $eingabe
        if (-not $kanalUrl) { Warte-AufTaste; return }
        $ueberSucheGefunden = $true
    }

    # --- Playlists holen ----------------------------------------------------
    Write-Host ''
    $playlists = Hole-KanalPlaylists -KanalUrl $kanalUrl

    # --- Rueckfall: Handle war falsch, per Suche nachfassen -----------------
    # Bei einer /channel/UC...-URL ist die Adresse eindeutig - dann bringt
    # eine Suche nichts und wir sparen sie uns.
    $istKanalId = $eingabe -match '/channel/UC[\w\-]{20,}'

    if ($playlists.Count -eq 0 -and -not $ueberSucheGefunden -and -not $istKanalId) {
        Write-Host ''
        Melde '  Der Kanal liess sich so nicht oeffnen.' 'Warnung'
        Melde '  Haeufigster Grund: den @handle gibt es nicht genau so.' 'Grau'
        Write-Host ''

        $suchName = $eingabe -replace '^https?://(www\.)?youtube\.com/', ''
        $suchName = $suchName -replace '/(playlists|videos|featured).*$', ''
        $suchName = $suchName -replace '^@', ''
        $suchName = $suchName -replace '([a-z0-9])([A-Z])', '$1 $2'
        $suchName = ($suchName -replace '[_\-]', ' ').Trim()

        if ([string]::IsNullOrWhiteSpace($suchName)) {
            Melde '  Aus der Eingabe laesst sich kein Suchbegriff bilden.' 'Fehler'
            Warte-AufTaste
            return
        }

        Melde ("  Suchen nach: {0}" -f $suchName) 'Grau'
        $weiter = Read-Host '  Kanal per Suche finden? (j/n)'

        if ($weiter -match '^[jJyY]') {
            $kanalUrl = Waehle-Kanal -Suchbegriff $suchName
            if (-not $kanalUrl) { Warte-AufTaste; return }
            Write-Host ''
            $playlists = Hole-KanalPlaylists -KanalUrl $kanalUrl
        }
    }

    if ($playlists.Count -eq 0) {
        Write-Host ''
        Melde '  Keine Playlists gefunden.' 'Fehler'
        Melde '  Moegliche Gruende:' 'Grau'
        Melde '   - Kanal hat keine oeffentlichen Playlists' 'Grau'
        Melde '   - Es ist ein "- Topic"-Kanal: dessen Albenliste laedt YouTube' 'Grau'
        Melde '     per Overlay nach, da kommt yt-dlp nicht heran.' 'Grau'
        Melde '     Fuer Kuenstler-Alben nimm Menuepunkt 5 (Diskografie).' 'Titel'
        Warte-AufTaste
        return
    }

    Schreibe-Log "Kanal $kanalUrl : $($playlists.Count) Playlists gefunden." 'INFO'

    # --- Auswahl ------------------------------------------------------------
    $ausgewaehlt = Waehle-AusListe -Elemente $playlists -Ueberschrift ("Playlists  --  {0}" -f $kanalUrl)

    if ($null -eq $ausgewaehlt -or $ausgewaehlt.Count -eq 0) {
        Melde '  Abgebrochen.' 'Grau'
        Start-Sleep -Seconds 1
        return
    }

    # --- Titelanzahl fuer die Auswahl nachladen -----------------------------
    $ohneAnzahl = @($ausgewaehlt | Where-Object { -not $_.Anzahl -or $_.Anzahl -le 0 })

    if ($ohneAnzahl.Count -gt 0) {
        Clear-Host
        Zeige-Linie '='
        Melde '  Titelanzahl wird ermittelt' 'Titel'
        Zeige-Linie '='
        Melde ("  {0} Playlist(s) abzufragen - einen Moment ..." -f $ohneAnzahl.Count) 'Grau'
        Write-Host ''

        $zaehler = 0
        foreach ($p in $ohneAnzahl) {
            $zaehler++
            Write-Host ("`r  [{0}/{1}]  {2}" -f $zaehler, $ohneAnzahl.Count,
                        (Kuerze-Text -Text $p.Titel -Laenge 45).PadRight(48)) -NoNewline

            $anzahl = Hole-PlaylistAnzahl -PlaylistUrl $p.Url
            if ($anzahl -gt 0) {
                $p.Anzahl = $anzahl
                $p.Zusatz = '{0,5} Titel' -f $anzahl
            }
        }
        Write-Host ''
    }

    # --- Bestaetigung -------------------------------------------------------
    Clear-Host
    Zeige-Linie '='
    Melde '  Ausgewaehlt' 'Titel'
    Zeige-Linie '='
    foreach ($p in $ausgewaehlt) {
        Melde ("    {0}  {1}" -f $p.Zusatz, (Kuerze-Text -Text $p.Titel -Laenge 55))
    }
    Write-Host ''

    $gesamt = 0
    $unbekannt = $false
    foreach ($p in $ausgewaehlt) {
        if ($p.Anzahl) { $gesamt += [int]$p.Anzahl } else { $unbekannt = $true }
    }
    if ($unbekannt) {
        Melde ("  Mindestens {0} Titel (bei einigen Playlists unbekannt)." -f $gesamt) 'Warnung'
    } else {
        Melde ("  Insgesamt {0} Titel." -f $gesamt)
    }

    Write-Host ''
    $bestaetigung = (Read-Host '  (J)etzt laden, in (W)arteschlange legen, (N)ichts?').Trim()

    if ($bestaetigung -match '^[wW]') {
        $anzahl = 0
        foreach ($p in $ausgewaehlt) {
            $typ = if ($Konfig.PlaylistOrdner) { 'ytdlp-album' } else { 'ytdlp-playlist' }
            if (Fuege-ZurWarteschlange -Typ $typ -Beschreibung $p.Titel -Abfrage $p.Url) { $anzahl++ }
        }
        Write-Host ''
        Melde ("  {0} Playlist(s) in die Warteschlange gelegt (Menuepunkt W)." -f $anzahl) 'Gut'
        Schreibe-Log ("Kanal-Playlists: {0} eingereiht." -f $anzahl) 'INFO'
        Warte-AufTaste
        return
    }

    if ($bestaetigung -notmatch '^[jJyY]') { return }

    # --- Download -----------------------------------------------------------
    $erfolgreich = 0
    $vorhanden = 0
    $ohneErgebnis = 0
    $dateienGesamt = 0
    $nummer = 0
    $startGesamt = Get-Date

    foreach ($p in $ausgewaehlt) {
        $nummer++
        Write-Host ''
        Zeige-Linie
        Melde ("  [{0}/{1}]  {2}" -f $nummer, $ausgewaehlt.Count, $p.Titel) 'Titel'
        Zeige-Linie

        if ($Konfig.PlaylistOrdner) {
            $ordnerName = Saeubere-Dateiname $p.Titel
            $muster = Join-Path (Loese-Zielordner $Konfig) ($ordnerName + '\%(playlist_index)03d - %(title)s.%(ext)s')
        } else {
            $muster = Join-Path (Loese-Zielordner $Konfig) '%(artist,uploader)s\%(playlist_title)s\%(title)s.%(ext)s'
        }

        $sollPlaylist = 0
        if ($p.Anzahl) { $sollPlaylist = [int]$p.Anzahl }
        $ergebnis = Hole-MitYtdlp -Konfig $Konfig -Adresse $p.Url -AlsPlaylist $true `
                                  -ZielMuster $muster -Soll $sollPlaylist

        if ($ergebnis.Erfolg -and $ergebnis.NeueDateien -gt 0) {
            Melde ("  OK - {0} neue Datei(en)" -f $ergebnis.NeueDateien) 'Gut'
            $erfolgreich++
            $dateienGesamt += $ergebnis.NeueDateien
            Schreibe-Log "Playlist OK: $($p.Titel) ($($ergebnis.NeueDateien) Dateien)" 'OK'
        } elseif ($ergebnis.Erfolg -and $ergebnis.Uebersprungen -gt 0) {
            Melde ("  Bereits vorhanden - {0} Titel uebersprungen." -f $ergebnis.Uebersprungen) 'Grau'
            $vorhanden++
            Schreibe-Log "Playlist vorhanden: $($p.Titel)" 'INFO'
        } else {
            Melde ("  Fehler oder kein verwertbarer Titel (Exit {0})." -f $ergebnis.ExitCode) 'Warnung'
            $ohneErgebnis++
            Schreibe-Log "Playlist ohne Ergebnis: $($p.Titel) (Exit $($ergebnis.ExitCode))" 'WARN'
        }
    }

    $dauer = (Get-Date) - $startGesamt

    Write-Host ''
    Zeige-Linie '='
    Melde '  Bilanz' 'Titel'
    Zeige-Linie '='
    Melde ("  Neu geladen        : {0}" -f $erfolgreich) 'Gut'
    Melde ("  Bereits vorhanden  : {0}" -f $vorhanden) 'Grau'
    if ($ohneErgebnis -gt 0) {
        Melde ("  Fehler             : {0}" -f $ohneErgebnis) 'Warnung'
    } else {
        Melde '  Fehler             : 0'
    }
    Melde ("  Neue Dateien       : {0}" -f $dateienGesamt) 'Gut'
    Melde ("  Laufzeit           : {0:hh\:mm\:ss}" -f $dauer) 'Grau'

    Schreibe-Log "Kanallauf: $dateienGesamt Dateien aus $erfolgreich Playlists, $vorhanden vorhanden, $ohneErgebnis Fehler." 'INFO'
    Warte-AufTaste
}

# =============================================================================
#  MENUEPUNKT 5  --  DISKOGRAFIE  (Alben eines Kuenstlers auswaehlen und laden)
# =============================================================================

function Hole-MitSpotdlMehrfach {
    <#
      Wie Hole-MitSpotdl, nimmt aber mehrere Abfragen (z.B. alle Song-URLs
      eines Albums) in einem einzigen spotdl-Aufruf entgegen.
    #>
    param($Konfig, [string[]]$Abfragen, [int]$Soll = 0)

    if (-not (Get-Command spotdl -ErrorAction SilentlyContinue)) {
        Melde '  spotdl ist nicht installiert.  Abhilfe:  pip install spotdl' 'Fehler'
        return [pscustomobject]@{
            Erfolg         = $false
            ExitCode       = -1
            NeueDateien    = 0
            Uebersprungen  = 0
            Ermittlungsart = 'Nicht gestartet'
        }
    }

    $argumente = Baue-SpotdlArgumente -Konfig $Konfig -Befehl 'download' -Abfrage $null

    # Abfragen direkt hinter 'download' einreihen
    $pos = 1
    foreach ($a in $Abfragen) { $argumente.Insert($pos, $a); $pos++ }

    Schreibe-Log ("spotdl download ({0} Abfragen): {1}" -f $Abfragen.Count,
                  (Kuerze-Text -Text ($Abfragen -join ' ') -Laenge 200)) 'INFO'

    $start = Get-Date
    $alteEinstellung = $ErrorActionPreference
    $ErrorActionPreference = 'SilentlyContinue'
    try {
        & spotdl @argumente 2>&1 | Tee-Object -Variable rohAusgabe
    } finally {
        $ErrorActionPreference = $alteEinstellung
    }
    $code = $LASTEXITCODE

    Protokolliere-Werkzeugausgabe -Konfig $Konfig -Ausgabe $rohAusgabe -Quelle 'spotdl'

    $ergebnis = Ermittle-Ergebnis -Ausgabe $rohAusgabe -Quelle 'spotdl' `
                                  -Startzeit $start -Zielordner (Loese-Zielordner $Konfig) `
                                  -Soll $Soll
    $dauer = (Get-Date) - $start

    Schreibe-Log ("spotdl beendet: Exit {0}, {1} neu, {2} uebersprungen, {3:mm\:ss} Laufzeit" -f `
                  $code, $ergebnis.Neu, $ergebnis.Uebersprungen, $dauer) 'INFO'

    return [pscustomobject]@{
        Erfolg        = ($code -eq 0)
        ExitCode      = $code
        NeueDateien   = $ergebnis.Neu
        Uebersprungen = $ergebnis.Uebersprungen
        Ermittlungsart = $ergebnis.Ermittlungsart
    }
}

function Fuehre-SpotdlSaveAus {
    <#
      Fuehrt 'spotdl save' als Hintergrundprozess aus und zeigt dabei
      Spinner, Laufzeit und die letzte spotdl-Statuszeile.
      AlbumTyp '' holt Alben (Standard), 'single' holt Singles und EPs.
      Gibt $true zurueck, wenn die Zieldatei entstanden ist.
    #>
    param(
        [string]$Abfrage,
        [string]$ZielDatei,
        [int]$Threads,
        [string]$AlbumTyp = '',
        [string]$Beschriftung = 'Songliste'
    )

    $outDatei = Join-Path $env:TEMP ('spotdl-save-out-' + [guid]::NewGuid().ToString('N') + '.txt')
    $errDatei = Join-Path $env:TEMP ('spotdl-save-err-' + [guid]::NewGuid().ToString('N') + '.txt')

    # Start-Process nimmt in PowerShell 5.1 nur eine Zeichenkette entgegen und
    # quotet nicht selbst. Windows-Regel: Backslashes unmittelbar vor einem
    # Anfuehrungszeichen muessen verdoppelt werden, das Anfuehrungszeichen
    # selbst wird mit Backslash escaped. Sonst zerlegt es die Kommandozeile.
    function Schuetze-Argument {
        param([string]$Wert)
        # Null oder mehr Backslashes vor einem ": Backslashes verdoppeln,
        # dann \" - gilt auch fuer nackte Anfuehrungszeichen ohne Backslash
        $w = $Wert -replace '(\\*)"', '$1$1\"'
        # Backslash-Folgen am Ende verdoppeln (stehen dann vor dem schliessenden ")
        $w = $w -replace '(\\+)$', '$1$1'
        return '"' + $w + '"'
    }

    $argZeile = 'save {0} --save-file {1} --threads {2}' -f `
                (Schuetze-Argument $Abfrage), (Schuetze-Argument $ZielDatei), [int]$Threads
    if ($AlbumTyp) { $argZeile += (' --album-type {0}' -f $AlbumTyp) }

    try {
        $prozess = Start-Process -FilePath 'spotdl' -ArgumentList $argZeile `
                                 -NoNewWindow -PassThru `
                                 -RedirectStandardOutput $outDatei `
                                 -RedirectStandardError  $errDatei `
                                 -ErrorAction Stop
    } catch {
        Melde "  spotdl konnte nicht gestartet werden: $($_.Exception.Message)" 'Fehler'
        Schreibe-Log "spotdl save Startfehler: $($_.Exception.Message)" 'FEHLER'
        Remove-Item $outDatei, $errDatei -ErrorAction SilentlyContinue
        return $false
    }

    $uhr = [System.Diagnostics.Stopwatch]::StartNew()
    $drehfeld = '|/-\'
    $schritt = 0
    $status = 'verbinde ...'

    while (-not $prozess.HasExited) {
        try {
            $letzte = Get-Content $outDatei -ErrorAction SilentlyContinue |
                      Where-Object { $_ -match '\S' } | Select-Object -Last 1
            if ($letzte) {
                $sauber = ([string]$letzte) -replace "`e\[[0-9;]*m", ''
                $status = Kuerze-Text -Text $sauber.Trim() -Laenge 42
            }
        } catch { }

        $zeichen = $drehfeld[$schritt % 4]
        $schritt++
        Write-Host ("`r  {0}  {1}  {2:mm\:ss}   {3}" -f $zeichen, $Beschriftung, $uhr.Elapsed, $status.PadRight(44)) -NoNewline
        Start-Sleep -Milliseconds 400
    }
    $uhr.Stop()
    Write-Host ''

    try {
        Get-Content $outDatei -ErrorAction SilentlyContinue |
            Where-Object { $_ -match 'Found \d+ songs' } |
            Select-Object -First 1 |
            ForEach-Object {
                $sauber = ([string]$_) -replace "`e\[[0-9;]*m", ''
                Melde ("  {0}  ({1:mm\:ss})" -f $sauber.Trim(), $uhr.Elapsed) 'Gut'
            }
    } catch { }
    try {
        Get-Content $errDatei -ErrorAction SilentlyContinue |
            Where-Object { $_ -match '^ERROR' } |
            ForEach-Object { Melde "  $_" 'Fehler' }
    } catch { }

    Remove-Item $outDatei, $errDatei -ErrorAction SilentlyContinue

    return (Test-Path $ZielDatei)
}

function Menue-Diskografie {
    param($Konfig)

    Clear-Host
    Zeige-Linie '='
    Melde '  Diskografie' 'Titel'
    Zeige-Linie '='
    Melde '  Laedt die Albenliste eines Kuenstlers und laesst dich auswaehlen.' 'Grau'
    Melde '  Dafuer wird ein Spotify-Kuenstler-Link gebraucht - geht ohne Konto:' 'Grau'
    Melde '  open.spotify.com -> Band suchen -> Kuenstlerseite -> Adresse kopieren' 'Grau'
    Write-Host ''

    $eingabe = (Read-Host '  Kuenstler-Link oder Bandname').Trim()
    if ([string]::IsNullOrWhiteSpace($eingabe)) { return }

    # Spotify haengt je nach Browsersprache ein Segment wie /intl-de/ ein.
    # Das fliegt raus, ebenso Parameter wie ?si=...
    $eingabe = $eingabe -replace '/intl-[a-zA-Z\-]+/', '/'
    $eingabe = $eingabe -replace '\?.*$', ''

    # --- Bandname statt Link: fertigen Suchlink anbieten --------------------
    if ($eingabe -notmatch '^https?://open\.spotify\.com/(artist|album)/') {

        # Playlist- oder Track-Link erkannt: gezielt auf Menuepunkt 3 verweisen,
        # statt ihn wie einen Bandnamen zu behandeln.
        if ($eingabe -match '^https?://open\.spotify\.com/(playlist|track)/') {
            Write-Host ''
            Melde '  Das ist ein Playlist- bzw. Track-Link, keine Kuenstlerseite.' 'Warnung'
            Melde '  Diskografie kennt nur Kuenstler- und Album-Links.' 'Grau'
            Melde '  Fuer Playlists und Einzeltitel: Menuepunkt 3 (Link laden).' 'Titel'
            Warte-AufTaste
            return
        }

        $such = [uri]::EscapeDataString($eingabe)
        Write-Host ''
        Melde '  Das ist kein Spotify-Link. Oeffne im Browser (ohne Konto nutzbar):' 'Warnung'
        Write-Host ''
        Melde ("    https://open.spotify.com/search/{0}/artists" -f $such) 'Titel'
        Write-Host ''
        Melde '  Dort die Band anklicken und die Adresse hier neu einwerfen.' 'Grau'
        Warte-AufTaste
        return
    }

    # --- Songlisten holen oder aus dem Zwischenspeicher nehmen ---------------
    $ordnerDisko = $OrdnerDiskografie
    if (-not (Test-Path $ordnerDisko)) { New-Item -Path $ordnerDisko -ItemType Directory | Out-Null }

    $spotifyId = 'unbekannt'
    if ($eingabe -match '/(artist|album)/([A-Za-z0-9]+)') { $spotifyId = $Matches[2] }
    $cacheDatei   = Join-Path $ordnerDisko "$spotifyId.spotdl"
    $singlesDatei = Join-Path $ordnerDisko "$spotifyId-singles.spotdl"

    $neuHolen = $true
    if (Test-Path $cacheDatei) {
        $stand = (Get-Item $cacheDatei).LastWriteTime
        $singlesInfo = if (Test-Path $singlesDatei) { ', inkl. Singles/EPs' } else { ', nur Alben' }
        Write-Host ''
        Melde ("  Songliste vom {0:dd.MM.yyyy HH:mm} liegt schon vor{1}." -f $stand, $singlesInfo) 'Gut'
        $antwort = Read-Host '  Verwenden statt neu holen? (j/n)'
        if ($antwort -match '^[jJyY]') { $neuHolen = $false }
    }

    if ($neuHolen) {
        Write-Host ''
        Melde '  Spotify fuehrt Alben und Singles/EPs getrennt. Ohne Singles fehlen' 'Grau'
        Melde '  EPs und Einzelveroeffentlichungen in der Liste.' 'Grau'
        $antwortSingles = (Read-Host '  Singles und EPs einbeziehen? (J/n)').Trim()
        $mitSingles = ($antwortSingles -eq '' -or $antwortSingles -match '^[jJyY]')

        Write-Host ''
        Melde '  Hole die Songlisten von Spotify - nur Metadaten, kein Audio.' 'Grau'
        Melde '  Wird gespeichert, beim naechsten Aufruf entfaellt das Warten.' 'Grau'
        Write-Host ''

        Remove-Item $cacheDatei, $singlesDatei -ErrorAction SilentlyContinue

        [void](Fuehre-SpotdlSaveAus -Abfrage $eingabe -ZielDatei $cacheDatei `
                                    -Threads ([int]$Konfig.Threads) -Beschriftung 'Alben  ')
        if ($mitSingles) {
            [void](Fuehre-SpotdlSaveAus -Abfrage $eingabe -ZielDatei $singlesDatei `
                                        -Threads ([int]$Konfig.Threads) -AlbumTyp 'single' -Beschriftung 'Singles')
        }
        Write-Host ''
    }

    if (-not (Test-Path $cacheDatei)) {
        Melde '  Es kam keine Songliste zurueck - Link pruefen.' 'Fehler'
        Schreibe-Log "Diskografie: save fehlgeschlagen fuer $eingabe" 'FEHLER'
        Warte-AufTaste
        return
    }

    $songs = New-Object System.Collections.ArrayList
    foreach ($datei in @($cacheDatei, $singlesDatei)) {
        if (-not (Test-Path $datei)) { continue }
        try {
            $teil = Get-Content $datei -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($s in @($teil)) { if ($s) { [void]$songs.Add($s) } }
        } catch {
            Melde ("  Datei nicht lesbar: {0}" -f (Split-Path $datei -Leaf)) 'Warnung'
            Schreibe-Log "Diskografie: JSON defekt in $datei" 'FEHLER'
        }
    }

    $songs = @($songs.ToArray())
    if ($songs.Count -eq 0) {
        Melde '  Songliste ist leer.' 'Fehler'
        Warte-AufTaste
        return
    }

    # --- Nach Alben gruppieren ----------------------------------------------
    $alben = @{}
    foreach ($s in $songs) {
        $albumName = ''
        try { if ($null -ne $s.album_name) { $albumName = [string]$s.album_name } } catch { }
        if ([string]::IsNullOrWhiteSpace($albumName)) { $albumName = 'Unbekanntes Album' }

        $schluessel = $albumName.ToLowerInvariant()

        if (-not $alben.ContainsKey($schluessel)) {
            $jahr = 0
            try {
                if ($s.year) { $jahr = [int]$s.year }
                elseif ($s.date -and ([string]$s.date).Length -ge 4) {
                    $jahr = [int]([string]$s.date).Substring(0, 4)
                }
            } catch { }

            $albumId = ''
            try { if ($null -ne $s.album_id) { $albumId = [string]$s.album_id } } catch { }

            $kuenstler = ''
            try {
                if ($s.album_artist)  { $kuenstler = [string]$s.album_artist }
                elseif ($s.artist)    { $kuenstler = [string]$s.artist }
            } catch { }

            $alben[$schluessel] = [pscustomobject]@{
                Name      = $albumName
                Jahr      = $jahr
                AlbumId   = $albumId
                Kuenstler = $kuenstler
                Urls      = (New-Object System.Collections.ArrayList)
            }
        }

        $url = ''
        try { if ($null -ne $s.url) { $url = [string]$s.url } } catch { }
        if ($url) { [void]$alben[$schluessel].Urls.Add($url) }
    }

    # --- Auswahlliste bauen, sortiert nach Jahr -----------------------------
    $auswahlElemente = New-Object System.Collections.ArrayList
    foreach ($a in ($alben.Values | Sort-Object -Property Jahr, Name)) {
        $jahrText = if ($a.Jahr -gt 0) { " ($($a.Jahr))" } else { '' }
        [void]$auswahlElemente.Add([pscustomobject]@{
            Anzeige  = "$($a.Name)$jahrText"
            Zusatz   = '{0,5} Titel' -f $a.Urls.Count
            Markiert = $false
            Album    = $a
        })
    }

    Melde ("  {0} Songs in {1} Alben/Veroeffentlichungen." -f $songs.Count, $auswahlElemente.Count) 'Gut'
    Start-Sleep -Seconds 1

    $ausgewaehlt = Waehle-AusListe -Elemente ($auswahlElemente.ToArray()) `
                                   -Ueberschrift 'Diskografie - Alben auswaehlen'

    if ($null -eq $ausgewaehlt -or $ausgewaehlt.Count -eq 0) {
        Melde '  Abgebrochen.' 'Grau'
        Start-Sleep -Seconds 1
        return
    }

    # --- Bestaetigung -------------------------------------------------------
    Clear-Host
    Zeige-Linie '='
    Melde '  Ausgewaehlt' 'Titel'
    Zeige-Linie '='
    $gesamt = 0
    foreach ($e in $ausgewaehlt) {
        Melde ("    {0}  {1}" -f $e.Zusatz, (Kuerze-Text -Text $e.Anzeige -Laenge 55))
        $gesamt += $e.Album.Urls.Count
    }
    Write-Host ''
    Melde ("  Insgesamt {0} Titel." -f $gesamt)
    Write-Host ''

    $bestaetigung = (Read-Host '  (J)etzt laden, in (W)arteschlange legen, (N)ichts?').Trim()

    if ($bestaetigung -match '^[wW]') {
        $anzahl = 0
        foreach ($e in $ausgewaehlt) {
            $a = $e.Album
            # Song-URLs statt Album-URL: so kennt die Warteschlange die
            # Sollzahl und kann Teilerfolge erkennen.
            $abfrage = (@($a.Urls | ForEach-Object { [string]$_ }) -join ' ')
            $beschreibung = '{0} - {1}' -f $a.Kuenstler, $a.Name
            if (Fuege-ZurWarteschlange -Typ 'spotdl' -Beschreibung $beschreibung -Abfrage $abfrage) { $anzahl++ }
        }
        Write-Host ''
        Melde ("  {0} Album/Alben in die Warteschlange gelegt (Menuepunkt W)." -f $anzahl) 'Gut'
        Schreibe-Log ("Diskografie: {0} Alben eingereiht." -f $anzahl) 'INFO'
        Warte-AufTaste
        return
    }

    if ($bestaetigung -notmatch '^[jJyY]') { return }

    # --- Download -----------------------------------------------------------
    $erfolgreich = 0
    $uebersprungen = 0
    $ohneErgebnis = 0
    $dateienGesamt = 0
    $nummer = 0
    $startGesamt = Get-Date

    foreach ($e in $ausgewaehlt) {
        $nummer++
        $a = $e.Album

        Write-Host ''
        Zeige-Linie
        Melde ("  [{0}/{1}]  {2}" -f $nummer, $ausgewaehlt.Count, $e.Anzeige) 'Titel'
        Zeige-Linie

        $archivEintrag = 'album: {0} - {1}' -f $a.Kuenstler, $a.Name

        if (Ist-ImArchiv -Eintrag $archivEintrag -Konfig $Konfig) {
            Melde '  Bereits im Archiv - uebersprungen.' 'Grau'
            $uebersprungen++
            continue
        }

        if ($a.AlbumId) {
            $abfragen = @("https://open.spotify.com/album/$($a.AlbumId)")
        } else {
            $abfragen = @($a.Urls | ForEach-Object { [string]$_ })
        }

        $soll = $a.Urls.Count
        $ergebnis = Hole-MitSpotdlMehrfach -Konfig $Konfig -Abfragen $abfragen -Soll $soll
        $abgedeckt = $ergebnis.NeueDateien + $ergebnis.Uebersprungen

        if ($abgedeckt -ge $soll -and $soll -gt 0) {
            if ($ergebnis.NeueDateien -gt 0) {
                Melde ("  OK - {0} neu, {1} waren vorhanden" -f $ergebnis.NeueDateien, $ergebnis.Uebersprungen) 'Gut'
            } else {
                Melde ("  Vollstaendig - alle {0} Titel waren bereits da" -f $soll) 'Gut'
            }
            Merke-ImArchiv -Eintrag $archivEintrag -Konfig $Konfig
            $erfolgreich++
            $dateienGesamt += $ergebnis.NeueDateien
            Schreibe-Log "Album vollstaendig: $($a.Name) ($($ergebnis.NeueDateien) neu)" 'OK'
        } elseif ($ergebnis.NeueDateien -gt 0) {
            Melde ("  Teilerfolg: {0} von {1} Titeln - NICHT archiviert." -f $abgedeckt, $soll) 'Warnung'
            Melde '  Ein erneuter Lauf laedt die fehlenden nach.' 'Grau'
            $erfolgreich++
            $dateienGesamt += $ergebnis.NeueDateien
            Schreibe-Log "Album TEIL: $($a.Name) ($abgedeckt/$soll)" 'WARN'
        } else {
            Melde '  Nichts geladen - Fehler oder kein Treffer.' 'Warnung'
            $ohneErgebnis++
            Schreibe-Log "Album ohne Ergebnis: $($a.Name) (Exit $($ergebnis.ExitCode))" 'WARN'
        }
    }

    $dauer = (Get-Date) - $startGesamt

    Write-Host ''
    Zeige-Linie '='
    Melde '  Bilanz' 'Titel'
    Zeige-Linie '='
    Melde ("  Alben mit Ergebnis  : {0}" -f $erfolgreich) 'Gut'
    Melde ("  Uebersprungen       : {0}" -f $uebersprungen) 'Grau'
    if ($ohneErgebnis -gt 0) { Melde ("  Ohne Ergebnis       : {0}" -f $ohneErgebnis) 'Warnung' }
    else                     { Melde '  Ohne Ergebnis       : 0' }
    Melde ("  Neue Dateien        : {0}" -f $dateienGesamt) 'Gut'
    Melde ("  Laufzeit            : {0:hh\:mm\:ss}" -f $dauer) 'Grau'

    Schreibe-Log "Diskografielauf: $dateienGesamt Dateien aus $erfolgreich Alben." 'INFO'
    Warte-AufTaste
}

# =============================================================================
#  MENUEPUNKT 6  --  PLAYLIST-SYNC
# =============================================================================

function Menue-Sync {
    param($Konfig)

    if (-not (Test-Path $OrdnerSync)) { New-Item -Path $OrdnerSync -ItemType Directory | Out-Null }

    while ($true) {
        Clear-Host
        Zeige-Linie '='
        Melde '  Playlist-Sync' 'Titel'
        Zeige-Linie '='
        Melde '  Haelt einen Ordner mit einer Spotify-Playlist gleich.' 'Grau'
        Write-Host ''
        Melde '  ACHTUNG: Beim Abgleich werden Dateien GELOESCHT, die nicht' 'Warnung'
        Melde '  mehr in der Playlist stehen - ohne Papierkorb, ohne Rueckfrage.' 'Warnung'
        Melde '  Nur fuer Ordner verwenden, die allein der Playlist gehoeren.' 'Warnung'
        Write-Host ''

        $dateien = @(Get-ChildItem -Path $OrdnerSync -Filter '*.spotdl' -File -ErrorAction SilentlyContinue)

        if ($dateien.Count -gt 0) {
            Melde '  Eingerichtete Playlists:'
            for ($i = 0; $i -lt $dateien.Count; $i++) {
                Melde ("    [{0}]  {1}" -f ($i + 1), $dateien[$i].BaseName)
            }
        } else {
            Melde '  Noch keine Playlist eingerichtet.' 'Grau'
        }

        Write-Host ''
        Melde '    [N]  Neue Playlist einrichten'
        if ($dateien.Count -gt 0) { Melde '    [A]  Alle abgleichen' }
        Melde '    [Z]  Zurueck'
        Write-Host ''

        $wahl = (Read-Host '  Auswahl').Trim()

        if ($wahl -match '^[zZ]$' -or $wahl -eq '') { return }

        if ($wahl -match '^[nN]$') {
            Write-Host ''
            $url = (Read-Host '  Spotify-Playlist-URL').Trim()
            if ([string]::IsNullOrWhiteSpace($url)) { continue }
            $name = (Read-Host '  Kurzname').Trim()
            if ([string]::IsNullOrWhiteSpace($name)) { $name = 'playlist-' + (Get-Date -Format 'yyyyMMdd-HHmmss') }
            $name = Saeubere-Dateiname $name

            $syncDatei = Join-Path $OrdnerSync "$name.spotdl"
            $argumente = Baue-SpotdlArgumente -Konfig $Konfig -Befehl 'sync' -Abfrage $url
            $argumente.Add('--save-file'); $argumente.Add($syncDatei)

            Write-Host ''
            Schreibe-Log "sync einrichten: $url -> $syncDatei" 'INFO'
            & spotdl @argumente

            Write-Host ''
            if (Test-Path $syncDatei) { Melde '  Playlist eingerichtet.' 'Gut' }
            else                      { Melde '  Einrichtung fehlgeschlagen.' 'Fehler' }
            Warte-AufTaste
            continue
        }

        if ($wahl -match '^[aA]$' -and $dateien.Count -gt 0) {
            foreach ($d in $dateien) {
                Write-Host ''
                Zeige-Linie
                Melde ("  Abgleich: {0}" -f $d.BaseName) 'Titel'
                $argumente = Baue-SpotdlArgumente -Konfig $Konfig -Befehl 'sync' -Abfrage $d.FullName
                & spotdl @argumente
                Schreibe-Log "sync: $($d.BaseName)" 'INFO'
            }
            Write-Host ''
            Melde '  Alle Playlists abgeglichen.' 'Gut'
            Warte-AufTaste
            continue
        }

        $nummer = 0
        if ([int]::TryParse($wahl, [ref]$nummer)) {
            if ($nummer -ge 1 -and $nummer -le $dateien.Count) {
                $d = $dateien[$nummer - 1]
                Write-Host ''
                Melde ("  Abgleich: {0}" -f $d.BaseName) 'Titel'
                $argumente = Baue-SpotdlArgumente -Konfig $Konfig -Befehl 'sync' -Abfrage $d.FullName
                & spotdl @argumente
                Schreibe-Log "sync: $($d.BaseName)" 'INFO'
                Write-Host ''
                Melde '  Fertig.' 'Gut'
                Warte-AufTaste
            }
        }
    }
}

# =============================================================================
#  MENUEPUNKT 7  --  TAGS REPARIEREN
# =============================================================================

function Menue-Tags {
    param($Konfig)

    Zeige-Linie '='
    Melde '  Tags reparieren' 'Titel'
    Zeige-Linie '='
    Melde '  Sucht zu vorhandenen Dateien Metadaten und schreibt sie neu.' 'Grau'
    Write-Host ''

    $ordner = (Read-Host ("  Ordner [{0}]" -f (Loese-Zielordner $Konfig))).Trim()
    if ([string]::IsNullOrWhiteSpace($ordner)) { $ordner = (Loese-Zielordner $Konfig) }

    if (-not (Test-Path $ordner)) {
        Melde '  Ordner existiert nicht.' 'Fehler'
        Warte-AufTaste
        return
    }

    $muster = Join-Path $ordner ('**\*.' + $Konfig.Format)
    $anzahl = Zaehle-Audiodateien $ordner

    Write-Host ''
    Melde ("  {0} Audiodatei(en) im Ordnerbaum." -f $anzahl)
    $bestaetigung = Read-Host '  Wirklich alle Tags neu schreiben? (j/n)'
    if ($bestaetigung -notmatch '^[jJyY]') { return }

    Write-Host ''
    Schreibe-Log "meta: $muster" 'INFO'
    & spotdl meta $muster

    Write-Host ''
    Melde '  Durchlauf beendet.' 'Gut'
    Warte-AufTaste
}

# =============================================================================
#  MENUEPUNKT 8  --  WERKZEUGE AKTUALISIEREN
# =============================================================================

function Menue-Update {
    Zeige-Linie '='
    Melde '  Werkzeuge aktualisieren' 'Titel'
    Zeige-Linie '='
    Melde '  Haeufigster Grund fuer "geht ploetzlich nicht mehr":' 'Grau'
    Melde '  YouTube hat etwas geaendert und yt-dlp ist veraltet.' 'Grau'
    Write-Host ''

    $py = if ($script:PythonBefehl) { $script:PythonBefehl } else { 'python' }

    Melde '  spotdl ...' 'Titel'
    & $py -m pip install --upgrade spotdl
    Write-Host ''

    Melde '  yt-dlp ...' 'Titel'
    & $py -m pip install --upgrade yt-dlp
    Write-Host ''

    Melde '  Aktuelle Versionen:' 'Titel'
    Melde ("    spotdl : {0}" -f ((& spotdl --version 2>&1) -join ' ').Trim())
    if (Get-Command yt-dlp -ErrorAction SilentlyContinue) {
        Melde ("    yt-dlp : {0}" -f ((& yt-dlp --version 2>&1) -join ' ').Trim())
    }
    if (Get-Command deno -ErrorAction SilentlyContinue) {
        Melde '    Deno   : vorhanden' 'Gut'
    } else {
        Melde '    Deno   : fehlt  ->  winget install DenoLand.Deno' 'Warnung'
    }

    Schreibe-Log 'Werkzeuge aktualisiert.' 'INFO'
    Warte-AufTaste
}

# =============================================================================
#  MENUEPUNKT 9  --  EINSTELLUNGEN
# =============================================================================

function Menue-Einstellungen {
    param($Konfig)

    while ($true) {
        Clear-Host
        Zeige-Linie '='
        Melde '  Einstellungen' 'Titel'
        Zeige-Linie '='
        Melde ("    [1]  Zielordner              : {0}" -f (Loese-Zielordner $Konfig))
        Melde ("    [2]  Format                  : {0}" -f $Konfig.Format)
        Melde ("    [3]  Bitrate                 : {0}" -f $Konfig.Bitrate)
        Melde ("    [4]  Namensschema            : {0}" -f $Konfig.Namensschema)
        Melde ("    [5]  Parallele Downloads     : {0}" -f $Konfig.Threads)
        Melde ("    [6]  Liedtexte holen         : {0}" -f $(if ($Konfig.LyricsHolen) { 'ja' } else { 'nein' }))
        Melde ("    [7]  Archiv nutzen           : {0}" -f $(if ($Konfig.ArchivNutzen) { 'ja' } else { 'nein' }))
        Melde ("    [8]  Nur verifizierte Treffer: {0}" -f $(if ($Konfig.NurVerifiziert) { 'ja' } else { 'nein' }))
        Melde ("    [9]  Playlist-Unterordner    : {0}" -f $(if ($Konfig.PlaylistOrdner) { 'ja' } else { 'nein' }))
        Melde ("    [N]  Nachtmodus (schonend)   : {0}" -f $(if ($Konfig.Nachtmodus) { 'ja' } else { 'nein' }))
        Melde ("    [L]  Ausfuehrliches Log      : {0}" -f $(if ($Konfig.LogAusfuehrlich) { 'ja' } else { 'nein' }))
        Write-Host ''
        Melde '    [S]  Speichern und zurueck'
        Melde '    [Z]  Zurueck ohne Speichern'
        Write-Host ''

        $wahl = (Read-Host '  Auswahl').Trim()

        switch -Regex ($wahl) {
            '^1$' {
                $neu = (Read-Host '  Neuer Zielordner').Trim()
                if ($neu) { $Konfig.Zielordner = $neu }
            }
            '^2$' {
                Melde '  Moeglich: mp3, flac, opus, m4a, ogg, wav' 'Grau'
                $neu = (Read-Host '  Format').Trim().ToLower()
                if ($neu -in @('mp3','flac','opus','m4a','ogg','wav')) { $Konfig.Format = $neu }
                else { Melde '  Unbekanntes Format - unveraendert.' 'Warnung'; Start-Sleep -Seconds 2 }
            }
            '^3$' {
                Melde '  Moeglich: 320k, 256k, 192k, 128k oder disable' 'Grau'
                Melde '  YouTube liefert real 128-160 kbps. Hoehere Werte blaehen' 'Grau'
                Melde '  die Datei auf, ohne Qualitaet hinzuzufuegen.' 'Grau'
                $neu = (Read-Host '  Bitrate').Trim().ToLower()
                if ($neu) { $Konfig.Bitrate = $neu }
            }
            '^4$' {
                Melde '  Platzhalter: {album-artist} {artist} {album} {title} {track-number} {year} {output-ext}' 'Grau'
                Melde '  Empfohlen ist {album-artist}: sortiert nach Albumkuenstler, damit' 'Grau'
                Melde '  Alben mit Gast-Features nicht in mehrere Ordner zerfallen.' 'Grau'
                Melde ('  Empfehlung: {album-artist}/{album}/{track-number} - {title}.{output-ext}') 'Grau'
                $neu = (Read-Host '  Namensschema').Trim()
                if ($neu) { $Konfig.Namensschema = $neu }
            }
            '^5$' {
                $neu = (Read-Host '  Anzahl (1-8)').Trim()
                $zahl = 0
                if ([int]::TryParse($neu, [ref]$zahl) -and $zahl -ge 1 -and $zahl -le 8) { $Konfig.Threads = $zahl }
            }
            '^6$' { $Konfig.LyricsHolen    = -not $Konfig.LyricsHolen }
            '^7$' { $Konfig.ArchivNutzen   = -not $Konfig.ArchivNutzen }
            '^8$' { $Konfig.NurVerifiziert = -not $Konfig.NurVerifiziert }
            '^9$' { $Konfig.PlaylistOrdner = -not $Konfig.PlaylistOrdner }
            '^[nN]$' {
                $Konfig.Nachtmodus = -not $Konfig.Nachtmodus
                if ($Konfig.Nachtmodus) {
                    Write-Host ''
                    Melde '  Nachtmodus an: 2 statt mehr gleichzeitige Anfragen,' 'Gut'
                    Melde '  dazu 3-10 Sekunden Pause zwischen den Titeln.' 'Grau'
                    Melde '  Bei grossen Diskografien deutlich langsamer, dafuer' 'Grau'
                    Melde '  verlangt YouTube seltener eine Bot-Bestaetigung.' 'Grau'
                    Start-Sleep -Seconds 3
                }
            }
            '^[lL]$' {
                $Konfig.LogAusfuehrlich = -not $Konfig.LogAusfuehrlich
                if ($Konfig.LogAusfuehrlich) {
                    Write-Host ''
                    Melde '  Ausfuehrliches Log an: jede Zeile von spotdl und yt-dlp' 'Gut'
                    Melde '  wandert in log.txt. Gut zur Fehlersuche, laesst die Datei' 'Grau'
                    Melde '  aber schnell wachsen (Rotation greift ab 1 MB).' 'Grau'
                    Start-Sleep -Seconds 3
                }
            }
            '^[sS]$' {
                Speichere-Einstellungen -Konfig $Konfig
                Melde '  Gespeichert.' 'Gut'
                Start-Sleep -Seconds 1
                return $Konfig
            }
            '^[zZ]$' { return (Lade-Einstellungen) }
            default { }
        }
    }
}

# =============================================================================
#  MENUEPUNKT A  --  ARCHIV
# =============================================================================

function Menue-Archiv {
    Zeige-Linie '='
    Melde '  Archiv' 'Titel'
    Zeige-Linie '='

    $anzahlSpotdl = 0
    $anzahlYT = 0
    if (Test-Path $DateiArchiv)   { $anzahlSpotdl = @(Get-Content $DateiArchiv -Encoding UTF8).Count }
    if (Test-Path $DateiArchivYT) { $anzahlYT     = @(Get-Content $DateiArchivYT -Encoding UTF8).Count }

    Melde ("  spotdl-Eintraege  : {0}" -f $anzahlSpotdl)
    Melde ("  YouTube-Eintraege : {0}" -f $anzahlYT)
    Write-Host ''
    Melde '    [1]  Letzte 20 spotdl-Eintraege zeigen'
    Melde '    [2]  spotdl-Archiv leeren'
    Melde '    [3]  YouTube-Archiv leeren'
    Melde '    [Z]  Zurueck'
    Write-Host ''

    $wahl = (Read-Host '  Auswahl').Trim()

    switch -Regex ($wahl) {
        '^1$' {
            Write-Host ''
            if ($anzahlSpotdl -gt 0) {
                Get-Content $DateiArchiv -Encoding UTF8 | Select-Object -Last 20 |
                    ForEach-Object { Melde "    $_" 'Grau' }
            } else {
                Melde '  Archiv ist leer.' 'Grau'
            }
            Warte-AufTaste
        }
        '^2$' {
            $b = Read-Host '  spotdl-Archiv wirklich leeren? (j/n)'
            if ($b -match '^[jJyY]') {
                Remove-Item $DateiArchiv -ErrorAction SilentlyContinue
                $script:ArchivSatz    = $null
                $script:ArchivGeladen = $false
                Melde '  Geleert.' 'Gut'
                Schreibe-Log 'spotdl-Archiv geleert.' 'INFO'
                Start-Sleep -Seconds 1
            }
        }
        '^3$' {
            $b = Read-Host '  YouTube-Archiv wirklich leeren? (j/n)'
            if ($b -match '^[jJyY]') {
                Remove-Item $DateiArchivYT -ErrorAction SilentlyContinue
                Melde '  Geleert.' 'Gut'
                Schreibe-Log 'YouTube-Archiv geleert.' 'INFO'
                Start-Sleep -Seconds 1
            }
        }
        default { }
    }
}

# =============================================================================
#  MENUEPUNKT U  --  USB-STICK BESTUECKEN  (fuer das Autoradio)
# =============================================================================

function Menue-UsbStick {
    param($Konfig)

    Clear-Host
    Zeige-Linie '='
    Melde '  USB-Stick bestuecken' 'Titel'
    Zeige-Linie '='
    Melde '  Kopiert ausgewaehlte Alben aus deiner Sammlung auf einen Stick.' 'Grau'
    Melde '  Ordner = Alben im Autoradio-Browser. Optional ein Mix-Ordner.' 'Grau'
    Write-Host ''

    # --- Wechseldatentraeger finden -----------------------------------------
    # Get-CimInstance ist der aktuelle Weg; Get-WmiObject fehlt in PowerShell 7.
    $laufwerke = @()
    try {
        $laufwerke = @(Get-CimInstance -ClassName Win32_LogicalDisk -Filter 'DriveType=2' -ErrorAction Stop)
    } catch {
        try {
            $laufwerke = @(Get-WmiObject Win32_LogicalDisk -Filter 'DriveType=2' -ErrorAction SilentlyContinue)
        } catch {
            Melde "  Laufwerke nicht abfragbar: $($_.Exception.Message)" 'Fehler'
        }
    }

    if ($laufwerke.Count -eq 0) {
        Melde '  Kein USB-Stick gefunden. Einstecken und neu versuchen.' 'Fehler'
        Warte-AufTaste
        return
    }

    Melde '  Gefundene Sticks:' 'Titel'
    Write-Host ''
    for ($i = 0; $i -lt $laufwerke.Count; $i++) {
        $l = $laufwerke[$i]
        $name = if ($l.VolumeName) { $l.VolumeName } else { 'Ohne Namen' }
        $freiGB   = [Math]::Round([double]$l.FreeSpace / 1GB, 1)
        $gesamtGB = [Math]::Round([double]$l.Size / 1GB, 1)
        Melde ("    [{0}]  {1}  ({2})  {3}  -  {4} von {5} GB frei" -f `
               ($i + 1), $l.DeviceID, $name, $l.FileSystem, $freiGB, $gesamtGB)
    }
    Write-Host ''

    $wahl = (Read-Host '  Nummer (Enter bricht ab)').Trim()
    $nummer = 0
    if (-not [int]::TryParse($wahl, [ref]$nummer)) { return }
    if ($nummer -lt 1 -or $nummer -gt $laufwerke.Count) { return }

    $stick = $laufwerke[$nummer - 1]
    $stickPfad = $stick.DeviceID + '\'

    if ($stick.FileSystem -ne 'FAT32') {
        Write-Host ''
        Melde ("  Achtung: Stick ist {0} formatiert." -f $stick.FileSystem) 'Warnung'
        Melde '  Das Toyota Touch 2 liest zuverlaessig nur FAT32.' 'Grau'
        Melde '  Weitermachen auf eigene Gefahr, oder Stick erst umformatieren.' 'Grau'
        $weiter = Read-Host '  Trotzdem fortfahren? (j/n)'
        if ($weiter -notmatch '^[jJyY]') { return }
    }

    # --- Was soll auf den Stick? --------------------------------------------
    $gemerkte = Lese-GemerktePlaylists

    $modus = 'alben'
    if ($gemerkte.Count -gt 0) {
        Write-Host ''
        Melde '  Was soll auf den Stick?' 'Titel'
        Melde '    [1]  Alben aus der Sammlung auswaehlen'
        Melde ("    [2]  Gemerkte Playlist zusammenstellen ({0} vorhanden)" -f $gemerkte.Count)
        Write-Host ''
        $wahlModus = (Read-Host '  Auswahl [1]').Trim()
        if ($wahlModus -eq '2') { $modus = 'playlist' }
    }

    if ($modus -eq 'playlist') {
        Menue-UsbPlaylist -Konfig $Konfig -Stick $stick -Gemerkte $gemerkte
        return
    }

    # --- Alben der Sammlung einsammeln --------------------------------------
    Write-Host ''
    Melde '  Lese die Sammlung ein ...' 'Grau'

    $endungen = @('.mp3','.m4a','.flac','.ogg','.opus','.wav')
    $zielLaenge = (Loese-Zielordner $Konfig).TrimEnd('\').Length

    $alben = New-Object System.Collections.ArrayList
    $alleOrdner = @(Get-ChildItem -Path (Loese-Zielordner $Konfig) -Directory -Recurse -ErrorAction SilentlyContinue)

    foreach ($o in $alleOrdner) {
        $dateien = @(Get-ChildItem -Path $o.FullName -File -ErrorAction SilentlyContinue |
                     Where-Object { $endungen -contains $_.Extension.ToLower() })
        if ($dateien.Count -eq 0) { continue }

        $groesse = 0
        foreach ($d in $dateien) { $groesse += $d.Length }

        $rel = $o.FullName.Substring($zielLaenge).TrimStart('\')

        [void]$alben.Add([pscustomobject]@{
            Anzeige  = $rel
            Zusatz   = ('{0,3} Titel {1,6:N0} MB' -f $dateien.Count, ($groesse / 1MB))
            Markiert = $false
            Pfad     = $o.FullName
            RelPfad  = $rel
            Dateien  = $dateien
            Groesse  = $groesse
        })
    }

    if ($alben.Count -eq 0) {
        Melde ("  Keine Alben unter {0} gefunden." -f (Loese-Zielordner $Konfig)) 'Fehler'
        Warte-AufTaste
        return
    }

    $albenSortiert = @($alben | Sort-Object -Property RelPfad)

    # --- Auswahl ------------------------------------------------------------
    $ausgewaehlt = Waehle-AusListe -Elemente $albenSortiert `
                                   -Ueberschrift ("USB-Stick {0} - Alben auswaehlen" -f $stick.DeviceID)

    if ($null -eq $ausgewaehlt -or $ausgewaehlt.Count -eq 0) {
        Melde '  Abgebrochen.' 'Grau'
        Start-Sleep -Seconds 1
        return
    }

    # --- Mix-Ordner? --------------------------------------------------------
    $alleTitel = New-Object System.Collections.ArrayList
    $summeBytes = 0
    foreach ($a in $ausgewaehlt) {
        $summeBytes += $a.Groesse
        foreach ($d in $a.Dateien) {
            [void]$alleTitel.Add([pscustomobject]@{ Datei = $d; RelPfad = $a.RelPfad })
        }
    }

    Clear-Host
    Zeige-Linie '='
    Melde '  Zusammenfassung' 'Titel'
    Zeige-Linie '='
    Melde ("  {0} Alben, {1} Titel, {2:N0} MB" -f $ausgewaehlt.Count, $alleTitel.Count, ($summeBytes / 1MB))
    Write-Host ''

    $mixAnzahl = 0
    $mixTitel = @()
    $antwortMix = Read-Host '  Zusaetzlich einen Mix-Ordner mit Zufallstiteln anlegen? (j/n)'
    if ($antwortMix -match '^[jJyY]') {
        $vorschlag = [Math]::Min(50, $alleTitel.Count)
        $eingabeAnzahl = (Read-Host ("  Wie viele Titel? [{0}]" -f $vorschlag)).Trim()
        $mixAnzahl = $vorschlag
        $tmp = 0
        if ([int]::TryParse($eingabeAnzahl, [ref]$tmp) -and $tmp -gt 0) {
            $mixAnzahl = [Math]::Min($tmp, $alleTitel.Count)
        }
        $mixTitel = @($alleTitel | Get-Random -Count $mixAnzahl)
        foreach ($m in $mixTitel) { $summeBytes += $m.Datei.Length }
    }

    # --- Platz pruefen ------------------------------------------------------
    $frei = [double]$stick.FreeSpace
    $reserve = 50MB
    if (($summeBytes + $reserve) -gt $frei) {
        Write-Host ''
        Melde ("  Zu wenig Platz: {0:N0} MB benoetigt, {1:N0} MB frei." -f `
               ($summeBytes / 1MB), ($frei / 1MB)) 'Fehler'
        Melde '  Auswahl verkleinern oder groesseren Stick nehmen.' 'Grau'
        Warte-AufTaste
        return
    }

    Write-Host ''
    Melde ("  Wird kopiert: {0:N0} MB nach {1}" -f ($summeBytes / 1MB), $stick.DeviceID)
    $bestaetigung = Read-Host '  Los? (j/n)'
    if ($bestaetigung -notmatch '^[jJyY]') { return }

    # --- Alben kopieren -----------------------------------------------------
    $kopiert = 0
    $uebersprungen = 0
    $fehler = 0
    $gesamtDateien = $alleTitel.Count + $mixTitel.Count
    $zaehler = 0
    $startZeit = Get-Date

    Write-Host ''
    foreach ($a in $ausgewaehlt) {
        $zielOrdner = Join-Path $stickPfad $a.RelPfad
        if (-not (Test-Path $zielOrdner)) {
            New-Item -Path $zielOrdner -ItemType Directory -Force | Out-Null
        }

        foreach ($d in $a.Dateien) {
            $zaehler++
            $zielDatei = Join-Path $zielOrdner $d.Name

            Write-Host ("`r  [{0}/{1}]  {2}" -f $zaehler, $gesamtDateien,
                        (Kuerze-Text -Text $d.Name -Laenge 50).PadRight(53)) -NoNewline

            try {
                if ((Test-Path $zielDatei) -and
                    (Get-Item $zielDatei).Length -eq $d.Length) {
                    $uebersprungen++
                } else {
                    Copy-Item -Path $d.FullName -Destination $zielDatei -Force
                    $kopiert++
                }
            } catch {
                $fehler++
                Schreibe-Log "USB-Kopie fehlgeschlagen: $($d.FullName) ($($_.Exception.Message))" 'FEHLER'
            }
        }
    }

    # --- Mix-Ordner schreiben -----------------------------------------------
    $m3uZeilen = New-Object System.Collections.ArrayList
    if ($mixTitel.Count -gt 0) {
        $mixOrdner = Join-Path $stickPfad '_Fahrmix'
        if (Test-Path $mixOrdner) { Remove-Item $mixOrdner -Recurse -Force -ErrorAction SilentlyContinue }
        New-Item -Path $mixOrdner -ItemType Directory -Force | Out-Null

        $lfd = 0
        foreach ($m in $mixTitel) {
            $lfd++
            $zaehler++

            # Fuehrende Titelnummer des Originals abstreifen, Interpret voranstellen
            $basisName = $m.Datei.BaseName -replace '^\d+\s*-\s*', ''
            $interpret = ($m.RelPfad -split '\\')[0]
            $rumpf = '{0} - {1}' -f $interpret, $basisName
            # Laenge begrenzen - FAT32/MAX_PATH vertragen keine Endlosnamen
            $rumpf = Kuerze-Text -Text $rumpf -Laenge 90
            $neuName = '{0:D3} - {1}{2}' -f $lfd, $rumpf, $m.Datei.Extension
            $neuName = Saeubere-Dateiname $neuName

            Write-Host ("`r  [{0}/{1}]  Mix: {2}" -f $zaehler, $gesamtDateien,
                        (Kuerze-Text -Text $neuName -Laenge 45).PadRight(48)) -NoNewline

            try {
                Copy-Item -Path $m.Datei.FullName -Destination (Join-Path $mixOrdner $neuName) -Force
                $kopiert++
                [void]$m3uZeilen.Add("_Fahrmix\$neuName")
            } catch {
                $fehler++
                Schreibe-Log "Mix-Kopie fehlgeschlagen: $($m.Datei.FullName)" 'FEHLER'
            }
        }

        # Test-M3U dazulegen - kostet nichts; ob das Radio sie liest, zeigt der Versuch
        try {
            $m3uInhalt = @('#EXTM3U') + @($m3uZeilen)
            Set-Content -Path (Join-Path $stickPfad '_Fahrmix.m3u') -Value $m3uInhalt -Encoding Default
        } catch { }
    }

    $dauer = (Get-Date) - $startZeit

    Write-Host ''
    Write-Host ''
    Zeige-Linie '='
    Melde '  Bilanz' 'Titel'
    Zeige-Linie '='
    Melde ("  Kopiert       : {0}" -f $kopiert) 'Gut'
    Melde ("  Uebersprungen : {0}  (waren schon drauf)" -f $uebersprungen) 'Grau'
    if ($fehler -gt 0) { Melde ("  Fehler        : {0}  (siehe log.txt)" -f $fehler) 'Fehler' }
    else               { Melde '  Fehler        : 0' }
    Melde ("  Dauer         : {0:hh\:mm\:ss}" -f $dauer) 'Grau'
    Write-Host ''
    Melde '  Stick ueber "Hardware sicher entfernen" auswerfen, sonst drohen' 'Warnung'
    Melde '  halbe Dateien - FAT32 hat kein Sicherheitsnetz.' 'Warnung'

    Schreibe-Log "USB-Lauf: $kopiert kopiert, $uebersprungen uebersprungen, $fehler Fehler." 'INFO'
    Warte-AufTaste
}

function Menue-UsbPlaylist {
    <#
      Stellt eine gemerkte Playlist auf dem Stick zusammen: sucht die Dateien
      in der Sammlung, kopiert sie flach und nummeriert in einen eigenen
      Ordner. Die Sammlung selbst bleibt unberuehrt.
    #>
    param($Konfig, $Stick, $Gemerkte)

    $stickPfad = $Stick.DeviceID + '\'

    # --- Playlist auswaehlen ------------------------------------------------
    Clear-Host
    Zeige-Linie '='
    Melde '  Gemerkte Playlists' 'Titel'
    Zeige-Linie '='
    Write-Host ''
    for ($i = 0; $i -lt $Gemerkte.Count; $i++) {
        $p = $Gemerkte[$i]
        Melde ("    [{0}]  {1}" -f ($i + 1), $p.Name)
        Melde ("         {0} Titel, gemerkt am {1}" -f $p.Anzahl, $p.Erstellt) 'Grau'
    }
    Write-Host ''

    $wahl = (Read-Host '  Nummer (Enter bricht ab)').Trim()
    $nummer = 0
    if (-not [int]::TryParse($wahl, [ref]$nummer)) { return }
    if ($nummer -lt 1 -or $nummer -gt $Gemerkte.Count) { return }

    $playlist = $Gemerkte[$nummer - 1]

    # --- Dateien in der Sammlung suchen -------------------------------------
    Write-Host ''
    Melde '  Suche die Titel in der Sammlung ...' 'Grau'

    $treffer = Finde-PlaylistDateien -Playlist $playlist -Zielordner (Loese-Zielordner $Konfig)

    Write-Host ''
    Zeige-Linie '='
    Melde ("  {0}" -f $playlist.Name) 'Titel'
    Zeige-Linie '='
    Melde ("  Gefunden : {0} von {1}" -f $treffer.Gefunden.Count, $playlist.Anzahl) 'Gut'

    if ($treffer.Fehlend.Count -gt 0) {
        Melde ("  Fehlend  : {0}" -f $treffer.Fehlend.Count) 'Warnung'
        Write-Host ''
        Melde '  Diese Titel liegen nicht in der Sammlung:' 'Warnung'
        foreach ($f in ($treffer.Fehlend | Select-Object -First 15)) {
            Melde ("    {0,3}. {1} - {2}" -f $f.Position, $f.Interpret, (Kuerze-Text -Text $f.Titel -Laenge 40)) 'Grau'
        }
        if ($treffer.Fehlend.Count -gt 15) {
            Melde ("    ... und {0} weitere" -f ($treffer.Fehlend.Count - 15)) 'Grau'
        }
        Write-Host ''
        Melde '  Moegliche Gruende: noch nicht geladen, oder Interpret/Titel' 'Grau'
        Melde '  weichen nach dem Tagging ab (Remaster, Live-Fassung, Featuring).' 'Grau'
    }

    if ($treffer.Mehrdeutig.Count -gt 0) {
        Write-Host ''
        Melde ("  Unsicher : {0}  (nur ueber den Titel gefunden, mehrere Kandidaten)" -f $treffer.Mehrdeutig.Count) 'Warnung'
        foreach ($m in ($treffer.Mehrdeutig | Select-Object -First 10)) {
            Melde ("    {0,3}. {1} - {2}" -f $m.Position, $m.Interpret, (Kuerze-Text -Text $m.Titel -Laenge 35)) 'Grau'
            Melde ("         -> {0}  ({1} Kandidaten)" -f (Kuerze-Text -Text $m.Gewaehlt -Laenge 60), $m.Anzahl) 'Grau'
        }
        Melde '  Der jeweils erste Kandidat wird genommen - bitte pruefen.' 'Grau'
    }

    if ($treffer.Gefunden.Count -eq 0) {
        Write-Host ''
        Melde '  Nichts zu kopieren.' 'Fehler'
        Warte-AufTaste
        return
    }

    # --- Platz pruefen ------------------------------------------------------
    $summeBytes = 0
    foreach ($g in $treffer.Gefunden) { $summeBytes += $g.Datei.Length }

    $frei = [double]$Stick.FreeSpace
    if (($summeBytes + 50MB) -gt $frei) {
        Write-Host ''
        Melde ("  Zu wenig Platz: {0:N0} MB benoetigt, {1:N0} MB frei." -f `
               ($summeBytes / 1MB), ($frei / 1MB)) 'Fehler'
        Warte-AufTaste
        return
    }

    Write-Host ''
    Melde ("  Wird kopiert: {0} Titel, {1:N0} MB" -f $treffer.Gefunden.Count, ($summeBytes / 1MB))
    $bestaetigung = Read-Host '  Los? (j/n)'
    if ($bestaetigung -notmatch '^[jJyY]') { return }

    # --- Kopieren -----------------------------------------------------------
    $zielOrdner = Join-Path $stickPfad (Saeubere-Dateiname $playlist.Name)
    if (-not (Test-Path $zielOrdner)) {
        New-Item -Path $zielOrdner -ItemType Directory -Force | Out-Null
    }

    $kopiert = 0
    $fehler  = 0
    $lfd     = 0
    $startZeit = Get-Date
    $m3uZeilen = New-Object System.Collections.ArrayList

    Write-Host ''
    foreach ($g in $treffer.Gefunden) {
        $lfd++

        # Interpret voranstellen, damit im Autoradio erkennbar bleibt,
        # von wem der Titel ist - die Ordnerstruktur faellt hier ja weg.
        $rumpf = if ($g.Interpret) { '{0} - {1}' -f $g.Interpret, $g.Titel } else { $g.Titel }
        $rumpf = Kuerze-Text -Text $rumpf -Laenge 90
        $neuName = Saeubere-Dateiname ('{0:D3} - {1}{2}' -f $lfd, $rumpf, $g.Datei.Extension)

        Write-Host ("`r  [{0}/{1}]  {2}" -f $lfd, $treffer.Gefunden.Count,
                    (Kuerze-Text -Text $neuName -Laenge 50).PadRight(53)) -NoNewline

        try {
            Copy-Item -Path $g.Datei.FullName -Destination (Join-Path $zielOrdner $neuName) -Force
            $kopiert++
            [void]$m3uZeilen.Add((Join-Path (Saeubere-Dateiname $playlist.Name) $neuName))
        } catch {
            $fehler++
            Schreibe-Log "Playlist-Kopie fehlgeschlagen: $($g.Datei.FullName)" 'FEHLER'
        }
    }

    # M3U dazulegen - manche Radios lesen sie, kostet nichts
    try {
        $m3uInhalt = @('#EXTM3U') + @($m3uZeilen)
        $m3uDatei = Join-Path $stickPfad ((Saeubere-Dateiname $playlist.Name) + '.m3u')
        Set-Content -Path $m3uDatei -Value $m3uInhalt -Encoding Default
    } catch { }

    $dauer = (Get-Date) - $startZeit

    Write-Host ''
    Write-Host ''
    Zeige-Linie '='
    Melde '  Bilanz' 'Titel'
    Zeige-Linie '='
    Melde ("  Kopiert  : {0}" -f $kopiert) 'Gut'
    if ($treffer.Fehlend.Count -gt 0) {
        Melde ("  Fehlend  : {0}  (nicht in der Sammlung)" -f $treffer.Fehlend.Count) 'Warnung'
    }
    if ($fehler -gt 0) { Melde ("  Fehler   : {0}" -f $fehler) 'Fehler' }
    Melde ("  Ordner   : {0}" -f $zielOrdner) 'Grau'
    Melde ("  Dauer    : {0:hh\:mm\:ss}" -f $dauer) 'Grau'
    Write-Host ''
    Melde '  Stick ueber "Hardware sicher entfernen" auswerfen.' 'Warnung'

    Schreibe-Log ("USB-Playlist '{0}': {1} kopiert, {2} fehlend." -f $playlist.Name, $kopiert, $treffer.Fehlend.Count) 'INFO'
    Warte-AufTaste
}

# =============================================================================
#  MENUEPUNKT W  --  WARTESCHLANGE
# =============================================================================

function Fuege-ZurWarteschlange {
    <#
      Haengt einen Auftrag an warteschlange.txt an.
      Format pro Zeile:  typ|beschreibung|abfrage
      Typen: spotdl, ytdlp, ytdlp-playlist, ytdlp-album
      (ytdlp-album legt einen Ordner mit dem Beschreibungsnamen an)
    #>
    param([string]$Typ, [string]$Beschreibung, [string]$Abfrage)

    $Beschreibung = ($Beschreibung -replace '\|', '/').Trim()
    $zeile = '{0}|{1}|{2}' -f $Typ, $Beschreibung, $Abfrage.Trim()
    try {
        Add-Content -Path $DateiQueue -Value $zeile -Encoding UTF8
        return $true
    } catch {
        Melde "  Eintrag konnte nicht gespeichert werden: $($_.Exception.Message)" 'Fehler'
        return $false
    }
}

function Lese-Warteschlange {
    if (-not (Test-Path $DateiQueue)) { return @() }
    $eintraege = New-Object System.Collections.ArrayList
    foreach ($zeile in (Get-Content $DateiQueue -Encoding UTF8)) {
        if ([string]::IsNullOrWhiteSpace($zeile)) { continue }
        $teile = $zeile -split '\|', 3
        if ($teile.Count -lt 3) { continue }
        [void]$eintraege.Add([pscustomobject]@{
            Typ          = $teile[0].Trim()
            Beschreibung = $teile[1].Trim()
            Abfrage      = $teile[2].Trim()
            Zeile        = $zeile
        })
    }
    return @($eintraege)
}

function Schreibe-Warteschlange {
    param($Eintraege)
    $zeilen = @($Eintraege | ForEach-Object { $_.Zeile })
    if ($zeilen.Count -eq 0) {
        Remove-Item $DateiQueue -ErrorAction SilentlyContinue
    } else {
        Set-Content -Path $DateiQueue -Value $zeilen -Encoding UTF8
    }
}

function Verarbeite-Warteschlangeneintrag {
    param($Konfig, $Eintrag, [int]$Soll = 0)

    switch ($Eintrag.Typ) {
        'spotdl' {
            if ($Eintrag.Abfrage -match '^https?://') {
                $abfragen = @($Eintrag.Abfrage -split '\s+' | Where-Object { $_ })
            } else {
                $abfragen = @($Eintrag.Abfrage)
            }
            return Hole-MitSpotdlMehrfach -Konfig $Konfig -Abfragen $abfragen -Soll $Soll
        }
        'ytdlp' {
            return Hole-MitYtdlp -Konfig $Konfig -Adresse $Eintrag.Abfrage -AlsPlaylist $false -Soll $Soll
        }
        'ytdlp-playlist' {
            return Hole-MitYtdlp -Konfig $Konfig -Adresse $Eintrag.Abfrage -AlsPlaylist $true -Soll $Soll
        }
        'ytdlp-album' {
            $ordnerName = Saeubere-Dateiname $Eintrag.Beschreibung
            $muster = Join-Path (Loese-Zielordner $Konfig) ($ordnerName + '\%(playlist_index)03d - %(title)s.%(ext)s')
            return Hole-MitYtdlp -Konfig $Konfig -Adresse $Eintrag.Abfrage -AlsPlaylist $true `
                                 -ZielMuster $muster -Soll $Soll
        }
        default {
            Melde ("  Unbekannter Typ '{0}' - uebersprungen." -f $Eintrag.Typ) 'Warnung'
            return [pscustomobject]@{
            Erfolg         = $false
            ExitCode       = -1
            NeueDateien    = 0
            Uebersprungen  = 0
            Ermittlungsart = 'Nicht gestartet'
        }
        }
    }
}

function Menue-Warteschlange {
    param($Konfig)

    while ($true) {
        Clear-Host
        Zeige-Linie '='
        Melde '  Warteschlange' 'Titel'
        Zeige-Linie '='

        $eintraege = Lese-Warteschlange

        if ($eintraege.Count -eq 0) {
            Melde '  Die Warteschlange ist leer.' 'Grau'
            Melde '  Befuellen: in Diskografie, Kanal-Playlists oder Link laden' 'Grau'
            Melde '  bei der Nachfrage W statt J waehlen.' 'Grau'
            Warte-AufTaste
            return
        }

        Melde ("  {0} Auftrag/Auftraege:" -f $eintraege.Count)
        Write-Host ''
        for ($i = 0; $i -lt $eintraege.Count; $i++) {
            $e = $eintraege[$i]
            Melde ("    [{0,2}]  {1,-14} {2}" -f ($i + 1), $e.Typ,
                   (Kuerze-Text -Text $e.Beschreibung -Laenge 45))
        }
        Write-Host ''
        Melde '    [S]  Abarbeiten starten'
        Melde '    [E]  Einzelnen Eintrag loeschen'
        Melde '    [L]  Alles leeren'
        Melde '    [Z]  Zurueck'
        Write-Host ''

        $wahl = (Read-Host '  Auswahl').Trim()

        if ($wahl -match '^[zZ]$' -or $wahl -eq '') { return }

        if ($wahl -match '^[lL]$') {
            $b = Read-Host '  Wirklich alles leeren? (j/n)'
            if ($b -match '^[jJyY]') {
                Remove-Item $DateiQueue -ErrorAction SilentlyContinue
                Schreibe-Log 'Warteschlange geleert.' 'INFO'
            }
            continue
        }

        if ($wahl -match '^[eE]$') {
            $nr = (Read-Host '  Welche Nummer').Trim()
            $zahl = 0
            if ([int]::TryParse($nr, [ref]$zahl) -and $zahl -ge 1 -and $zahl -le $eintraege.Count) {
                $rest = New-Object System.Collections.ArrayList
                for ($i = 0; $i -lt $eintraege.Count; $i++) {
                    if ($i -ne ($zahl - 1)) { [void]$rest.Add($eintraege[$i]) }
                }
                Schreibe-Warteschlange -Eintraege $rest
            }
            continue
        }

        if ($wahl -notmatch '^[sS]$') { continue }

        # --- Abarbeiten -----------------------------------------------------
        Write-Host ''
        $runterfahren = Read-Host '  Rechner nach Abschluss herunterfahren? (j/n)'
        $mitShutdown = ($runterfahren -match '^[jJyY]')
        if ($mitShutdown) {
            Melde '  Ok - nach dem letzten Auftrag faehrt der Rechner mit 2 Minuten' 'Warnung'
            Melde '  Vorlauf herunter. Abbrechen geht dann mit:  shutdown /a' 'Warnung'
        }

        $erfolgreich = 0
        $fehlgeschlagen = 0
        $dateienGesamt = 0
        $nummer = 0
        $startGesamt = Get-Date
        $verbleibend = New-Object System.Collections.ArrayList
        foreach ($e in $eintraege) { [void]$verbleibend.Add($e) }

        Schreibe-Log ("Warteschlange gestartet: {0} Auftraege." -f $eintraege.Count) 'INFO'

        foreach ($e in $eintraege) {
            $nummer++
            Write-Host ''
            Zeige-Linie
            Melde ("  [{0}/{1}]  {2}  ({3})" -f $nummer, $eintraege.Count, $e.Beschreibung, $e.Typ) 'Titel'
            Zeige-Linie

            # Sollzahl: bei spotdl-Eintraegen mit URL-Liste bekannt
            $soll = 0
            if ($e.Typ -eq 'spotdl' -and $e.Abfrage -match '^https?://') {
                $soll = @($e.Abfrage -split '\s+' | Where-Object { $_ }).Count
            }

            $ergebnis = Verarbeite-Warteschlangeneintrag -Konfig $Konfig -Eintrag $e -Soll $soll

            $abgedeckt = $ergebnis.NeueDateien
            if ($null -ne $ergebnis.Uebersprungen) { $abgedeckt += $ergebnis.Uebersprungen }

            $vollstaendig = if ($soll -gt 0) { $abgedeckt -ge $soll }
                            else             { $ergebnis.NeueDateien -gt 0 }

            if ($vollstaendig) {
                if ($ergebnis.NeueDateien -gt 0) {
                    Melde ("  OK - {0} neu geladen" -f $ergebnis.NeueDateien) 'Gut'
                } else {
                    Melde '  Vollstaendig - war bereits vorhanden' 'Gut'
                }
                $erfolgreich++
                $dateienGesamt += $ergebnis.NeueDateien
                [void]$verbleibend.Remove($e)
                Schreibe-Warteschlange -Eintraege $verbleibend
                if ($e.Typ -eq 'spotdl') {
                    Merke-ImArchiv -Eintrag ("album: {0}" -f $e.Beschreibung) -Konfig $Konfig
                }
                Schreibe-Log ("Queue OK: {0}" -f $e.Beschreibung) 'OK'
            } elseif ($ergebnis.NeueDateien -gt 0) {
                Melde ("  Teilerfolg: {0} von {1} - Eintrag bleibt zum Nachladen." -f $abgedeckt, $soll) 'Warnung'
                $dateienGesamt += $ergebnis.NeueDateien
                $fehlgeschlagen++
                Schreibe-Log ("Queue TEIL: {0} ({1}/{2})" -f $e.Beschreibung, $abgedeckt, $soll) 'WARN'
            } else {
                Melde '  Nichts geladen - Eintrag bleibt in der Schlange.' 'Warnung'
                $fehlgeschlagen++
                Schreibe-Log ("Queue ohne Ergebnis: {0} (Exit {1})" -f $e.Beschreibung, $ergebnis.ExitCode) 'WARN'
            }
        }

        $dauer = (Get-Date) - $startGesamt

        Write-Host ''
        Zeige-Linie '='
        Melde '  Bilanz' 'Titel'
        Zeige-Linie '='
        Melde ("  Erledigt      : {0}" -f $erfolgreich) 'Gut'
        if ($fehlgeschlagen -gt 0) {
            Melde ("  Ohne Ergebnis : {0}  (bleiben in der Schlange)" -f $fehlgeschlagen) 'Warnung'
        } else {
            Melde '  Ohne Ergebnis : 0'
        }
        Melde ("  Neue Dateien  : {0}" -f $dateienGesamt) 'Gut'
        Melde ("  Laufzeit      : {0:hh\:mm\:ss}" -f $dauer) 'Grau'
        Schreibe-Log ("Warteschlange beendet: {0} ok, {1} offen, {2} Dateien." -f $erfolgreich, $fehlgeschlagen, $dateienGesamt) 'INFO'

        if ($mitShutdown) {
            Write-Host ''
            Melde '  Der Rechner faehrt in 2 Minuten herunter.  Abbruch:  shutdown /a' 'Warnung'
            Schreibe-Log 'Shutdown ausgeloest.' 'INFO'
            & shutdown /s /t 120 /c "Musik-Downloader: Warteschlange abgearbeitet"
            return
        }

        Warte-AufTaste
    }
}

# =============================================================================
#  MENUEPUNKT B  --  BESTANDSABGLEICH
# =============================================================================

function Sammle-Albenordner {
    <#
      Liest alle Ordner unterhalb des Zielordners ein, die Audiodateien
      enthalten, und gibt eine Hashtable zurueck:
        normalisierter Albumname -> Anzahl Dateien
      Der Ordnername ist das, was das Namensschema erzeugt hat.
    #>
    param([string]$Zielordner)

    $tabelle = @{}
    if (-not (Test-Path $Zielordner)) { return $tabelle }

    $endungen = @('.mp3','.m4a','.flac','.ogg','.opus','.wav')

    foreach ($o in @(Get-ChildItem -Path $Zielordner -Directory -Recurse -ErrorAction SilentlyContinue)) {
        $anzahl = @(Get-ChildItem -Path $o.FullName -File -ErrorAction SilentlyContinue |
                    Where-Object { $endungen -contains $_.Extension.ToLower() }).Count
        if ($anzahl -eq 0) { continue }

        $schluessel = Normalisiere-Albumname $o.Name
        if ($tabelle.ContainsKey($schluessel)) { $tabelle[$schluessel] += $anzahl }
        else                                   { $tabelle[$schluessel]  = $anzahl }
    }

    return $tabelle
}

function Normalisiere-Albumname {
    <#
      Vergleichbar machen: Kleinschreibung, Sonderzeichen raus,
      Zusaetze wie "(Deluxe Edition)" oder "- Remastered" abschneiden.
    #>
    param([string]$Name)

    $n = [string]$Name
    $n = $n.ToLowerInvariant()
    $n = $n -replace '\((deluxe|remaster(ed)?|expanded|bonus|special|anniversary)[^)]*\)', ''
    $n = $n -replace '\s*-\s*(deluxe|remaster(ed)?|expanded|single|ep)\b.*$', ''
    $n = $n -replace '[^\p{L}\p{Nd}]', ''
    return $n.Trim()
}

function Menue-Bestandsabgleich {
    param($Konfig)

    Clear-Host
    Zeige-Linie '='
    Melde '  Bestandsabgleich' 'Titel'
    Zeige-Linie '='
    Melde '  Vergleicht gespeicherte Diskografien mit dem, was auf der Platte liegt.' 'Grau'
    Melde '  Zeigt fehlende und unvollstaendige Alben.' 'Grau'
    Write-Host ''

    $ordnerDisko = $OrdnerDiskografie
    if (-not (Test-Path $ordnerDisko)) {
        Melde '  Noch keine Diskografie gespeichert.' 'Warnung'
        Melde '  Hole erst eine ueber Menuepunkt 5.' 'Grau'
        Warte-AufTaste
        return
    }

    $dateien = @(Get-ChildItem -Path $ordnerDisko -Filter '*.spotdl' -File -ErrorAction SilentlyContinue |
                 Where-Object { $_.Name -notmatch '-singles\.spotdl$' })

    if ($dateien.Count -eq 0) {
        Melde '  Keine Diskografie-Dateien gefunden.' 'Warnung'
        Warte-AufTaste
        return
    }

    # --- Kuenstler auswaehlen ------------------------------------------------
    $kuenstlerListe = New-Object System.Collections.ArrayList
    foreach ($d in $dateien) {
        $name = '(unbekannt)'
        try {
            $erste = Get-Content $d.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            $erste = @($erste)
            if ($erste.Count -gt 0) {
                if ($erste[0].album_artist)  { $name = [string]$erste[0].album_artist }
                elseif ($erste[0].artist)    { $name = [string]$erste[0].artist }
            }
        } catch { }

        [void]$kuenstlerListe.Add([pscustomobject]@{
            Anzeige  = $name
            Zusatz   = '{0:dd.MM.yyyy}' -f $d.LastWriteTime
            Markiert = $false
            Datei    = $d.FullName
            Singles  = ($d.FullName -replace '\.spotdl$', '-singles.spotdl')
        })
    }

    $ausgewaehlt = Waehle-AusListe -Elemente ($kuenstlerListe.ToArray()) `
                                   -Ueberschrift 'Bestandsabgleich - Kuenstler auswaehlen'

    if ($null -eq $ausgewaehlt -or $ausgewaehlt.Count -eq 0) { return }

    # --- Sammlung einlesen ---------------------------------------------------
    Clear-Host
    Melde '  Lese die Sammlung ein ...' 'Grau'
    $vorhanden = Sammle-Albenordner -Zielordner (Loese-Zielordner $Konfig)
    Write-Host ''

    $fehlend = New-Object System.Collections.ArrayList
    $unvollstaendig = New-Object System.Collections.ArrayList
    $komplett = 0

    foreach ($k in $ausgewaehlt) {
        # Songs aus Alben- und Singles-Datei zusammenfuehren
        $songs = New-Object System.Collections.ArrayList
        foreach ($p in @($k.Datei, $k.Singles)) {
            if (-not (Test-Path $p)) { continue }
            try {
                $teil = Get-Content $p -Raw -Encoding UTF8 | ConvertFrom-Json
                foreach ($s in @($teil)) { if ($s) { [void]$songs.Add($s) } }
            } catch { }
        }

        # Nach Alben gruppieren
        $alben = @{}
        foreach ($s in $songs) {
            $albumName = ''
            try { if ($null -ne $s.album_name) { $albumName = [string]$s.album_name } } catch { }
            if ([string]::IsNullOrWhiteSpace($albumName)) { continue }

            if (-not $alben.ContainsKey($albumName)) {
                $albumId = ''
                try { if ($null -ne $s.album_id) { $albumId = [string]$s.album_id } } catch { }
                $alben[$albumName] = [pscustomobject]@{
                    Name      = $albumName
                    AlbumId   = $albumId
                    Kuenstler = $k.Anzeige
                    Soll      = 0
                    Urls      = (New-Object System.Collections.ArrayList)
                }
            }
            $alben[$albumName].Soll++
            $url = ''
            try { if ($null -ne $s.url) { $url = [string]$s.url } } catch { }
            if ($url) { [void]$alben[$albumName].Urls.Add($url) }
        }

        foreach ($a in ($alben.Values | Sort-Object -Property Name)) {
            $schluessel = Normalisiere-Albumname $a.Name
            $ist = 0
            if ($vorhanden.ContainsKey($schluessel)) { $ist = $vorhanden[$schluessel] }

            $eintrag = [pscustomobject]@{
                Anzeige   = ('{0} - {1}' -f $k.Anzeige, $a.Name)
                Zusatz    = ('{0,3} / {1,3}' -f $ist, $a.Soll)
                Markiert  = $false
                Album     = $a
                Ist       = $ist
            }

            if ($ist -eq 0)            { [void]$fehlend.Add($eintrag) }
            elseif ($ist -lt $a.Soll)  { [void]$unvollstaendig.Add($eintrag) }
            else                       { $komplett++ }
        }
    }

    # --- Ergebnis ------------------------------------------------------------
    Clear-Host
    Zeige-Linie '='
    Melde '  Ergebnis' 'Titel'
    Zeige-Linie '='
    Melde ("  Vollstaendig    : {0}" -f $komplett) 'Gut'
    Melde ("  Unvollstaendig  : {0}" -f $unvollstaendig.Count) $(if ($unvollstaendig.Count -gt 0) { 'Warnung' } else { 'Normal' })
    Melde ("  Fehlt ganz      : {0}" -f $fehlend.Count) $(if ($fehlend.Count -gt 0) { 'Warnung' } else { 'Normal' })
    Write-Host ''

    if ($unvollstaendig.Count -gt 0) {
        Melde '  Unvollstaendig (vorhanden / erwartet):' 'Warnung'
        foreach ($e in $unvollstaendig) {
            Melde ("    {0}  {1}" -f $e.Zusatz, (Kuerze-Text -Text $e.Anzeige -Laenge 50))
        }
        Write-Host ''
    }

    if ($fehlend.Count -gt 0) {
        Melde '  Fehlt komplett:' 'Warnung'
        foreach ($e in ($fehlend | Select-Object -First 25)) {
            Melde ("    {0,3} Titel  {1}" -f $e.Album.Soll, (Kuerze-Text -Text $e.Anzeige -Laenge 50))
        }
        if ($fehlend.Count -gt 25) {
            Melde ("    ... und {0} weitere" -f ($fehlend.Count - 25)) 'Grau'
        }
        Write-Host ''
    }

    Melde '  Hinweis: Der Abgleich vergleicht Ordnernamen mit Albumtiteln.' 'Grau'
    Melde '  Umbenannte oder verschobene Ordner erscheinen faelschlich als fehlend.' 'Grau'
    Write-Host ''

    $luecken = New-Object System.Collections.ArrayList
    foreach ($e in $unvollstaendig) { [void]$luecken.Add($e) }
    foreach ($e in $fehlend)        { [void]$luecken.Add($e) }

    if ($luecken.Count -eq 0) {
        Melde '  Nichts zu tun - alles vollstaendig.' 'Gut'
        Warte-AufTaste
        return
    }

    $antwort = Read-Host '  Luecken auswaehlen und in die Warteschlange legen? (j/n)'
    if ($antwort -notmatch '^[jJyY]') { return }

    $zuLaden = Waehle-AusListe -Elemente ($luecken.ToArray()) `
                               -Ueberschrift 'Luecken - was soll nachgeladen werden?'

    if ($null -eq $zuLaden -or $zuLaden.Count -eq 0) { return }

    $anzahl = 0
    foreach ($e in $zuLaden) {
        $a = $e.Album
        $abfrage = (@($a.Urls | ForEach-Object { [string]$_ }) -join ' ')
        if ([string]::IsNullOrWhiteSpace($abfrage)) { continue }
        $beschreibung = '{0} - {1}' -f $a.Kuenstler, $a.Name
        if (Fuege-ZurWarteschlange -Typ 'spotdl' -Beschreibung $beschreibung -Abfrage $abfrage) { $anzahl++ }
    }

    Write-Host ''
    Melde ("  {0} Auftrag/Auftraege in die Warteschlange gelegt (Menuepunkt W)." -f $anzahl) 'Gut'
    Schreibe-Log ("Bestandsabgleich: {0} Luecken eingereiht." -f $anzahl) 'INFO'
    Warte-AufTaste
}

# =============================================================================
#  MENUEPUNKT P  --  SAMMLUNG PRUEFEN
# =============================================================================

function Menue-SammlungPruefen {
    param($Konfig)

    Clear-Host
    Zeige-Linie '='
    Melde '  Sammlung pruefen' 'Titel'
    Zeige-Linie '='
    Melde '  Sucht Reste abgebrochener Downloads und auffaellig kleine Dateien.' 'Grau'
    Write-Host ''

    if (-not (Test-Path (Loese-Zielordner $Konfig))) {
        Melde '  Zielordner existiert nicht.' 'Fehler'
        Warte-AufTaste
        return
    }

    $grenzeKB = 300
    $eingabe = (Read-Host ("  Verdaechtig unter wie vielen KB? [{0}]" -f $grenzeKB)).Trim()
    $tmp = 0
    if ([int]::TryParse($eingabe, [ref]$tmp) -and $tmp -gt 0) { $grenzeKB = $tmp }

    Write-Host ''
    Melde '  Durchsuche die Sammlung ...' 'Grau'

    $endungen = @('.mp3','.m4a','.flac','.ogg','.opus','.wav')
    $reste    = New-Object System.Collections.ArrayList
    $klein    = New-Object System.Collections.ArrayList
    $leer     = New-Object System.Collections.ArrayList
    $gesamt   = 0

    foreach ($d in @(Get-ChildItem -Path (Loese-Zielordner $Konfig) -File -Recurse -ErrorAction SilentlyContinue)) {
        $endung = $d.Extension.ToLower()

        # Reste abgebrochener Downloads
        if ($endung -in @('.part','.ytdl','.temp','.tmp') -or $d.Name -match '\.part-') {
            [void]$reste.Add($d)
            continue
        }

        if ($endungen -notcontains $endung) { continue }
        $gesamt++

        if ($d.Length -eq 0) {
            [void]$leer.Add($d)
        } elseif ($d.Length -lt ($grenzeKB * 1KB)) {
            [void]$klein.Add($d)
        }
    }

    $zielLaenge = (Loese-Zielordner $Konfig).TrimEnd('\').Length

    Write-Host ''
    Zeige-Linie '='
    Melde '  Ergebnis' 'Titel'
    Zeige-Linie '='
    Melde ("  Audiodateien gesamt : {0}" -f $gesamt)
    Melde ("  Leere Dateien       : {0}" -f $leer.Count)   $(if ($leer.Count  -gt 0) { 'Fehler' }  else { 'Normal' })
    Melde ("  Unter {0} KB        : {1}" -f $grenzeKB, $klein.Count) $(if ($klein.Count -gt 0) { 'Warnung' } else { 'Normal' })
    Melde ("  Download-Reste      : {0}" -f $reste.Count)  $(if ($reste.Count -gt 0) { 'Warnung' } else { 'Normal' })

    foreach ($gruppe in @(
        @{ Titel = 'Leere Dateien';    Liste = $leer;  Farbe = 'Fehler' },
        @{ Titel = 'Sehr klein';       Liste = $klein; Farbe = 'Warnung' },
        @{ Titel = 'Download-Reste';   Liste = $reste; Farbe = 'Warnung' }
    )) {
        if ($gruppe.Liste.Count -eq 0) { continue }
        Write-Host ''
        Melde ("  {0}:" -f $gruppe.Titel) $gruppe.Farbe
        foreach ($d in ($gruppe.Liste | Select-Object -First 20)) {
            $rel = $d.FullName.Substring($zielLaenge).TrimStart('\')
            Melde ("    {0,6:N0} KB  {1}" -f ($d.Length / 1KB), (Kuerze-Text -Text $rel -Laenge 55)) 'Grau'
        }
        if ($gruppe.Liste.Count -gt 20) {
            Melde ("    ... und {0} weitere" -f ($gruppe.Liste.Count - 20)) 'Grau'
        }
    }

    $verdaechtig = $leer.Count + $klein.Count + $reste.Count
    if ($verdaechtig -eq 0) {
        Write-Host ''
        Melde '  Nichts Auffaelliges gefunden.' 'Gut'
        Warte-AufTaste
        return
    }

    Write-Host ''
    Melde '  Achtung: Kurze Intros, Skits und Zwischenspiele sind legitim klein.' 'Warnung'
    Melde '  Vor dem Loeschen also einmal in die Liste schauen.' 'Warnung'
    Write-Host ''
    Melde '    [1]  Nur Download-Reste und leere Dateien loeschen'
    Melde '    [2]  Liste in pruefbericht.txt schreiben'
    Melde '    [Z]  Nichts tun'
    Write-Host ''

    $wahl = (Read-Host '  Auswahl').Trim()

    if ($wahl -eq '1') {
        $zuLoeschen = @($leer) + @($reste)
        if ($zuLoeschen.Count -eq 0) {
            Melde '  Nichts davon vorhanden.' 'Grau'
            Warte-AufTaste
            return
        }
        $b = Read-Host ("  {0} Datei(en) wirklich loeschen? (j/n)" -f $zuLoeschen.Count)
        if ($b -match '^[jJyY]') {
            $weg = 0
            foreach ($d in $zuLoeschen) {
                try { Remove-Item $d.FullName -Force; $weg++ }
                catch { Schreibe-Log "Loeschen fehlgeschlagen: $($d.FullName)" 'FEHLER' }
            }
            Melde ("  {0} Datei(en) geloescht." -f $weg) 'Gut'
            Schreibe-Log "Sammlungspruefung: $weg Dateien geloescht." 'INFO'
        }
        Warte-AufTaste
        return
    }

    if ($wahl -eq '2') {
        $bericht = Join-Path $Basis 'pruefbericht.txt'
        $zeilen = New-Object System.Collections.ArrayList
        [void]$zeilen.Add(('Pruefbericht vom {0:dd.MM.yyyy HH:mm}' -f (Get-Date)))
        [void]$zeilen.Add(('Zielordner: {0}' -f (Loese-Zielordner $Konfig)))
        [void]$zeilen.Add('')
        foreach ($gruppe in @(
            @{ Titel = 'LEERE DATEIEN';  Liste = $leer },
            @{ Titel = ('UNTER {0} KB' -f $grenzeKB); Liste = $klein },
            @{ Titel = 'DOWNLOAD-RESTE'; Liste = $reste }
        )) {
            if ($gruppe.Liste.Count -eq 0) { continue }
            [void]$zeilen.Add(('=== {0} ({1}) ===' -f $gruppe.Titel, $gruppe.Liste.Count))
            foreach ($d in $gruppe.Liste) {
                [void]$zeilen.Add(('{0,8:N0} KB  {1}' -f ($d.Length / 1KB), $d.FullName))
            }
            [void]$zeilen.Add('')
        }
        try {
            Set-Content -Path $bericht -Value $zeilen -Encoding UTF8
            Melde ("  Geschrieben: {0}" -f $bericht) 'Gut'
        } catch {
            Melde "  Bericht fehlgeschlagen: $($_.Exception.Message)" 'Fehler'
        }
        Warte-AufTaste
    }
}

# =============================================================================
#  HAUPTMENUE
# =============================================================================

function Zeige-Hauptmenue {
    param($Konfig)

    Clear-Host
    Zeige-Linie '='
    Melde ("   Y T - S C H A K A L   v{0}" -f $Version) 'Titel'
    Zeige-Linie '='
    Melde ("   Ziel: {0}     Format: {1} @ {2}" -f (Loese-Zielordner $Konfig), $Konfig.Format, $Konfig.Bitrate) 'Grau'
    if ($Konfig.Nachtmodus) {
        Melde '   Nachtmodus aktiv - langsam und schonend' 'Warnung'
    }
    Zeige-Linie '='
    Write-Host ''
    Melde '     [1]  Einzelsuche          - Titel eingeben, wird gesucht und geladen'
    Melde '     [2]  Wunschliste          - alle Eintraege aus wunschliste.txt'
    Melde '     [3]  Link laden           - Spotify (auch Playlist), YouTube, Soundcloud, Bandcamp'
    Melde '     [4]  Kanal-Playlists      - YouTube-Kanal durchsuchen und auswaehlen'
    Melde '     [5]  Diskografie          - Alben eines Kuenstlers auswaehlen' 'Titel'
    Melde '     [6]  Playlist-Sync        - Ordner mit Spotify-Playlist gleichhalten'
    Melde '     [7]  Tags reparieren      - Metadaten vorhandener Dateien erneuern'
    Melde '     [8]  Werkzeuge aktualisieren'
    Melde '     [9]  Einstellungen'
    Melde '     [A]  Archiv'
    Melde '     [U]  USB-Stick bestuecken - Alben oder gemerkte Playlist auf den Stick'
    Melde '     [W]  Warteschlange        - gesammelte Auftraege abarbeiten'
    Melde '     [B]  Bestandsabgleich     - was fehlt aus gespeicherten Diskografien?' 'Titel'
    Melde '     [P]  Sammlung pruefen     - Reste und auffaellig kleine Dateien' 'Titel'
    Write-Host ''
    Melde '     [0]  Beenden'
    Write-Host ''
    Zeige-Linie
}

# =============================================================================
#  START
# =============================================================================

Clear-Host
Schreibe-Log ("=== YT-Schakal v{0} gestartet ===" -f $Version) 'INFO'

$Konfig = Lade-Einstellungen
$Konfig = Pruefe-Einstellungen -Konfig $Konfig

Schreibe-Log ("Einstellungen: Ziel={0} | Format={1} @ {2} | Threads={3} | Nachtmodus={4} | NurVerifiziert={5} | Schema={6}" -f `
              (Loese-Zielordner $Konfig), $Konfig.Format, $Konfig.Bitrate, $Konfig.Threads,
              $Konfig.Nachtmodus, $Konfig.NurVerifiziert, $Konfig.Namensschema) 'INFO'

# Einmalige Anpassung: alte Standard-Namensschemata auf den aktuellen Stand
# heben. Selbst gebaute Schemata werden nicht angefasst.
$alteSchemata = @(
    '{artist}/{album}/{title}.{output-ext}',
    '{artist}/{album}/{track-number} - {title}.{output-ext}'
)
if ($alteSchemata -contains $Konfig.Namensschema) {
    $Konfig.Namensschema = $Standard.Namensschema
    Speichere-Einstellungen -Konfig $Konfig
    Melde '  Namensschema aktualisiert: sortiert jetzt nach {album-artist} und' 'Gut'
    Melde '  nummeriert die Titel. Gilt fuer alle kommenden Downloads.' 'Grau'
    Write-Host ''
}

if (-not (Test-Path $DateiEinstellungen)) {
    Speichere-Einstellungen -Konfig $Konfig
    Melde '  Erststart - einstellungen.json wurde angelegt.' 'Gut'
    Melde ("  Zielordner steht auf: {0}" -f (Loese-Zielordner $Konfig)) 'Grau'
    Melde '  Aendern unter Menuepunkt 9 (Einstellungen).' 'Grau'
    Write-Host ''
}

$bereit = Pruefe-Werkzeuge

if (-not $bereit) {
    Melde '  Es fehlen Voraussetzungen. Installiere sie und starte neu.' 'Fehler'
    Schreibe-Log 'Selbsttest fehlgeschlagen.' 'FEHLER'
    Warte-AufTaste
    exit 1
}

$zielAbsolut = Loese-Zielordner $Konfig

if (-not (Test-Path $zielAbsolut)) {
    # Ein relativer Ordner gehoert zum Paket und wird ohne Rueckfrage angelegt.
    # Bei einem absoluten Pfad koennte ein Tippfehler dahinterstecken - da fragen wir.
    $istRelativ = -not [System.IO.Path]::IsPathRooted([string]$Konfig.Zielordner)

    if ($istRelativ) {
        try {
            New-Item -Path $zielAbsolut -ItemType Directory -Force | Out-Null
            Melde ("  Zielordner angelegt: {0}" -f $zielAbsolut) 'Grau'
            Write-Host ''
        } catch {
            Melde "  Zielordner konnte nicht angelegt werden: $($_.Exception.Message)" 'Fehler'
        }
    } else {
        Melde ("  Zielordner {0} existiert nicht." -f $zielAbsolut) 'Warnung'
        $anlegen = Read-Host '  Jetzt anlegen? (j/n)'
        if ($anlegen -match '^[jJyY]') {
            try {
                New-Item -Path $zielAbsolut -ItemType Directory -Force | Out-Null
                Melde '  Angelegt.' 'Gut'
            } catch {
                Melde "  Fehlgeschlagen: $($_.Exception.Message)" 'Fehler'
            }
        }
    }
}

Warte-AufTaste

while ($true) {
    Zeige-Hauptmenue -Konfig $Konfig
    $wahl = (Read-Host '  Auswahl').Trim()

    switch ($wahl) {
        '1' { Clear-Host; Menue-Einzelsuche    -Konfig $Konfig }
        '2' { Clear-Host; Menue-Liste          -Konfig $Konfig }
        '3' { Clear-Host; Menue-Link           -Konfig $Konfig }
        '4' {             Menue-KanalPlaylists -Konfig $Konfig }
        '5' {             Menue-Diskografie    -Konfig $Konfig }
        '6' {             Menue-Sync           -Konfig $Konfig }
        '7' { Clear-Host; Menue-Tags           -Konfig $Konfig }
        '8' { Clear-Host; Menue-Update }
        '9' {             $Konfig = Menue-Einstellungen -Konfig $Konfig }
        'A' { Clear-Host; Menue-Archiv }
        'a' { Clear-Host; Menue-Archiv }
        'U' {             Menue-UsbStick -Konfig $Konfig }
        'u' {             Menue-UsbStick -Konfig $Konfig }
        'W' {             Menue-Warteschlange -Konfig $Konfig }
        'w' {             Menue-Warteschlange -Konfig $Konfig }
        'B' {             Menue-Bestandsabgleich -Konfig $Konfig }
        'b' {             Menue-Bestandsabgleich -Konfig $Konfig }
        'P' {             Menue-SammlungPruefen -Konfig $Konfig }
        'p' {             Menue-SammlungPruefen -Konfig $Konfig }
        '0' {
            Schreibe-Log '=== Script beendet ===' 'INFO'
            Clear-Host
            Melde '  Bis dann.' 'Gut'
            Write-Host ''
            exit 0
        }
        default { }
    }
}
