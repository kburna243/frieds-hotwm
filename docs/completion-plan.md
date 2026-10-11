# Hotwm: vollständige Wiimote-Lightgun-Einrichtung

Stand: 2026-10-11. Status: Grundplan unabhängig geprüft; Nutzerergänzung zu Kopplung/Identität/Kalibrierung integriert. Umsetzung noch nicht begonnen.

## Ziel und Grenzen

Ein Nutzer wählt seinen Setup-Ordner und wird bis zum überprüften Betrieb seiner Wiimotes als Lightguns geführt. Schnellstart, Benutzerdefiniert und Experte verwenden dieselbe Konfiguration und dieselben Aktionen. Jede verändernde Aktion benötigt eine eigene verständliche Freigabe; auch Agent-Aufrufe dürfen dies nicht umgehen.

Die bestehende PowerShell/WPF-Oberfläche und das Python-Relay bleiben Ausgangspunkt. Kein Frameworkwechsel ohne nachgewiesenen Bedarf. Keine Zusage zur automatischen Bluetooth-Kopplung, Gunmote-Kalibrierung oder Installation, bevor die tatsächlich unterstützten Schnittstellen geprüft wurden. Wo Automatisierung fehlt, führt Hotwm einen manuellen Schritt mit anschließender Überprüfung durch. Spiele und ROMs werden nicht beschafft.

Verbindliche Nutzerpräzisierung: Kopplung ist halbautomatisch; Hotwm führt nötige physische Schritte (z. B. Kopplungsmodus) und unterstützt vorhandene technische Möglichkeiten. Kalibrierung erfolgt manuell, geführt durch Hotwm; eine vollautomatische Kalibrierung ist kein Releaseziel. Bluetooth-MAC ist die bevorzugte dauerhafte Geräteidentität zur Wiedererkennung und Spielerzuordnung. P0 prüft, welche unterstützten Bluetooth-/Gunmote-/DolphinBar-Pfade die tatsächliche Wiimote-MAC liefern. Keine MAC aus Anzeigenamen, Enumeration oder Adapter-MAC erfinden; bei fehlender eindeutiger Identität bleibt die Zuordnung unbestätigt und erfordert Nutzerzuordnung.

Geräteprofil: normalisierte Wiimote-Bluetooth-MAC, Anzeigename und gewünschter Spieler-Slot getrennt von flüchtigen Geräte-/Verbindungsnummern speichern. Abnahme P4/P5: zwei Wiimotes mit vertauschter Verbindungsreihenfolge behalten ihre Zuordnung, Wiederverbindung wird erkannt, unbekannte/fehlende/doppelte Identitäten werden nicht still einem Spieler zugeteilt. Gerät ersetzen oder Spielerzuordnung ändern ist ein freizugebender Profil-Eingriff. MACs in Diagnoseexporten standardmäßig maskieren. Manuelle Kalibrierung endet mit Zieltest je Spieler; bloßes Öffnen des Kalibrierungswerkzeugs gilt nicht als erfolgreiche Kalibrierung.

## Belegter Ausgangspunkt

- Drei Dashboard-Tabs statt Einrichtung: gui/HotwmDashboard.xaml:115, :291, :358.
- Aktuelle Konfiguration wird direkt gespeichert: gui/HotwmDashboard.ps1:293; Task-/Relay-Eingriffe liegen in Handlern ab :350.
- PnP-Erkennung in gui/HotwmDashboard.ps1:139 belegt noch keine spielbereite Lightgun.
- Kit-Client mit Leseoperationen und optionalem Apply: src/KitClient.ps1, insbesondere Get-HotwmSystemStatus, Get-HotwmInputProfiles, Set-HotwmInputProfile und Get-HotwmOutputSafety.
- README.de.md dokumentiert Gunmote, Python und gekoppelte Geräte als Voraussetzungen; die bisherige Roadmap gilt dem Relay/Dashboard, nicht dem vollständigen neuen Produktziel.
- config/hotw.json enthält globale Effekte und Spiele-Schalter, noch kein vollständiges Button-/Vorlagenschema.
- tests/Run-Tests.ps1 verwendet Pester 3; tools/Build-HotwmPackage.ps1 verpackt src/config/gui/tools/contract.

Graph-Evidenz: Hotwm war im vorhandenen Projektindex nicht enthalten. Die Aussagen stammen aus gezielten Quelldateilesungen. Keine Vollständigkeitsbehauptung über andere Repositories.

Ergänzende Integrationsbefunde (begrenzte geprüfte Ausschnitte):
- Kit: core/modules/SetupContext.ps1:87 exportiert einen generischen Setup-Kontext; arcade/modules/InputMatrix.ps1:58 liest/validiert Eingabeprofile. output/modules/HookOfTheWiimote.ps1:184–289 enthält abgesicherte Output-/INI-/Task-Einrichtung, aber keinen belegten Kopplungs-/Kalibrierungsablauf.
- RetroGamingAgent: retro-gaming-ops-agent/src/app/api/devices/route.ts:6–49 liest/ändert gespeicherte Gerätezustände und simuliert test_trigger; diese Route ist kein Nachweis physischer Gerätefunktion.
- Graph Kit Generation 2026-10-05T19:44:21Z: zitierte Pfade ohne erfasste Abdeckungslücke, aber metadata_changed; konkrete Ausschnitte nachgelesen. Agent Generation 2026-10-05T19:44:26Z: Route metadata_match. Aussagen über fehlende Fähigkeiten bleiben auf geprüfte Ausschnitte begrenzt.
- Zusätzlich durch Freigabeschicht zu erfassen: Haptik-/LED-Tests gui/HotwmDashboard.ps1:448–494 und Log-Leeren :508–515. Auch Hardwaretests benötigen eine bewusste Freigabe; ihr Button kann diese konkrete Freigabe darstellen, wenn Wirkung/Spieler vorher klar bezeichnet sind.

## Produktablauf

Ordner wählen → lesend prüfen → Geräte/Spieler zuordnen → Vorschlag → Aktionen einzeln freigeben → ausführen → Zielen/Buttons/Feedback prüfen → Status anzeigen.

Schnellstart verwendet Empfehlungen. Benutzerdefiniert bietet Entscheidungen je Schritt. Experte zeigt zusätzlich Pfade, Routing und unterstützte Overrides. Moduswechsel erhält Eingaben und gibt keine zusätzlichen Rechte.

Navigation: Übersicht; Einrichtung; Geräte & Kalibrierung; Tasten; Effekte; Spiele/Profile; Diagnose. Cabinet/Agent-Verbindung als integrierter Status-/Einstellungsbereich. Detailansichten innerhalb einer gemeinsamen Oberfläche; Dialoge für gezielte Bestätigungen.

## Gemeinsame technische Regeln

- Discovery ist rein lesend. Ein Aktionsplan enthält stabile Aktions-ID, Art, Zielpfade, Vorbedingungen, Auswirkungen, Abhängigkeiten und Wiederherstellungsmöglichkeit.
- Freigaben sind an Inhalt, Ziel und aktuellen Zustand gebunden. Änderungen am Plan, an Dateien oder am Ziel entwerten betroffene Freigaben. Kein globales Apply als stillschweigende Sammelfreigabe.
- Nur eine bewusste Nutzeraktion in der vertrauenswürdigen Oberfläche erzeugt eine Freigabe. Agent-Eingaben und importierte Pläne dürfen keine Freigaben erzeugen oder mitliefern. Die Ausführung akzeptiert keine vom Aufrufer selbst gesetzten Approved-Flags als Berechtigungsnachweis.
- Freigaben an exakten Aktionsinhalt, kanonisches Ziel und geprüfte Vorbedingungen binden; unmittelbar vor Eingriff erneut validieren. Konkurrierende Ausführung desselben Ziels verhindern. Freigaben einmalig konsumieren; nach Fehler, Neustart oder Wiederverbindung erneut prüfen und erforderliche Freigabe neu einholen.
- P1/P6-Negativtests: gefälschte Freigabe, Wiederverwendung (Replay), Zielwechsel, parallele Ausführung und Fremdänderung zwischen Freigabe und Eingriff müssen ohne Eingriff scheitern.
- Zustände: vorgeschlagen, freigegeben, abgelehnt, läuft, erfolgreich, fehlgeschlagen, übersprungen. Abhängige Aktionen werden nach Ablehnung/Fehler blockiert und erklärt.
- Vor Dateieingriffen Original sichern, unbekannte Felder erhalten, atomar schreiben und Ergebnis prüfen. Wiederherstellung ist ebenfalls ein freizugebender Eingriff und prüft zwischenzeitliche Änderungen.
- Nach Unterbrechung Zustand neu prüfen; gespeicherte Freigaben nicht blind wiederverwenden. Keine automatischen Wiederholungen nicht idempotenter Aktionen.
- Plan-/Diagnoseansicht erklärt fehlende Komponenten und widersprüchliche Zustände ohne rohe JSON-Dialoge als Standard.
- Hotwm führt den Ablauf; Kit besitzt gemeinsame Installations-/Konfigurationsoperationen. Agent nutzt dieselbe Plan-/Freigabe-/Ausführungsschicht. Zunächst vorhandene Schnittstellen prüfen, neue Versionen explizit aushandeln.
- Spielbereit nur mit belegten Prüfschritten. Unbekannt, nicht unterstützt und nicht getestet sind eigene Zustände. Physische Funktion benötigt Hardwareprüfung oder klar ausgewiesene Nutzerbestätigung.

## Arbeitspakete und Abnahme

### P0 — Bestandsaufnahme und Testbaseline
Dateien: bestehende gui/, src/, tests/, contract/; gezielte Kit-/Agent-API-Prüfung.
Ergebnis: Fähigkeitsmatrix für Erkennung, Kopplung, Kalibrierung, Buttons, Outputs, Installation, Autostart und Spieleintegration mit vorhanden/manuell/fehlt sowie zuständigem Projekt. Vorhandene Tests auf unverändertem Code ausführen, Befunde dokumentieren. Fehlende Hardware getrennt ausweisen.
Abnahme: Jede Fähigkeit besitzt konkrete Evidenz oder ausdrücklich offenen Status; Baseline enthält Befehle, Ergebnisse, Umgebung und Einschränkungen.

### P1 — Gemeinsame Aktions- und Freigabeschicht
Vorgeschlagen: src/HotwmSetup.ps1, tests/HotwmSetup.Tests.ps1; Integration in gui/HotwmDashboard.ps1.
Abnahme: Ohne gültige Einzelfreigabe keinerlei Dateischreiben, Prozessstoppen oder Task-Ändern. Ablehnung verändert nichts. Geänderter Plan/Zielzustand verhindert Ausführung. Vorhandene direkten Eingriffe werden durch die Schicht geführt; keine Bypass-Handler. Fehler/Abhängigkeiten werden korrekt fortgesetzt oder blockiert. Sicherung und Wiederherstellung mit Fremdänderungskonflikt sind getestet.

### P2 — Profile und Vorlagen
Vorgeschlagen: versionierte Dateien in config/templates/ und eigene Nutzerprofile; src/HotwmProfiles.ps1; gezielte Tests.
Abnahme: Unveränderliche mitgelieferte Vorlagen können kopiert, bearbeitet, validiert und exportiert/importiert werden. Schema-/Werteprüfung vor Anwendung. Effektive Werte folgen Standard → Spieler → Spiel mit sichtbarer Herkunft. Unbekannte Bestandsfelder bleiben erhalten; kaputte Konfiguration wird nicht überschrieben. Portables Paket enthält benötigte Dateien. Buttonvorlagen werden nur für tatsächlich unterstützte Ziele angeboten.

### P3 — Gemeinsame Oberfläche und drei Modi
Dateien: gui/HotwmDashboard.xaml und .ps1; bei Bedarf abgegrenzte Hilfsmodule.
Abnahme: Ordnerauswahl, drei wechselbare Modi, dauerhafte Navigation, verständlicher Status, keine verlorenen Eingaben beim Wechsel. Empfehlung und manuelle Auswahl erzeugen denselben Aktionsplan. Tastaturbedienung, Fokus und skalierte Anzeige prüfen. Bestehende Relay-/Testfunktionen bleiben erreichbar.

### P4 — Vollständiger Schnellstart
Hängt von P0/P1/P3 ab. Erst einen funktionierenden vertikalen Ablauf abschließen.
Abnahme: Frisches und vorhandenes Setup durchlaufen Ordnerprüfung, Bestandsaufnahme, Plan, Einzelfreigaben, Ausführung und Ergebnisprüfung. Fehlende Komponenten, Ablehnung, ungültige Pfade, Neustartbedarf und Unterbrechung haben verständliche Fortsetzung. Keine unbelegten Installations-/Kalibrierungsannahmen. Keine Erfolgsanzeige allein aufgrund von Prozess- oder PnP-Präsenz.

### P5 — Tasten- und Effekteditor
Hängt von P2/P3/P4 ab.
Abnahme: Spieler 1/2 getrennt; unterstützte Buttonziele und Effektsignale auswählbar; Vorlage kopieren/anpassen; Änderungen vor Anwendung sichtbar. Live-Eingang und gezielte Tests unterscheiden empfangenes Signal, ausgegebenes Signal und bestätigte Hardwarewirkung. Nicht unterstützte Effekte sind erklärt. Spieleausnahmen überlagern definierte Defaults ohne andere Profile zu verändern.

### P6 — Cabinet und Agent
Hängt von P0/P1/P4 ab. Externe Repository-Änderungen nur mit präzisem Vertrag und separater Dateiverantwortung.
Abnahme: Standalone funktioniert ohne lokalen Entwicklungspfad. Kit fehlt/zu alt/nicht erreichbar führt zu verständlichem Zustand. UI und Agent erzeugen gleichwertige Pläne; Agent kann Freigaben nicht selbst erteilen. Doppelte Anwendung und veraltete Pläne werden abgefangen. Vertragsprüfung schützt bestehende Verbraucher.

### P7 — Release-Abnahme
Dateien: tests/, tools/Build-HotwmPackage.ps1, README.md, README.de.md, VERSION nach tatsächlicher Abnahme.
Abnahme: Automatisierte relevante Tests bestehen. Neuer portabler Build startet außerhalb des Entwicklungsordners. Manuelle Hardwarematrix deckt einen/zwei Spieler, Neustart/Wiederverbindung, Zielen, Trigger, Nachladen, Rumble/LEDs und repräsentative tatsächlich unterstützte Spielpfade ab. Nicht verfügbare Hardware bleibt offen; keine Fake-Erfolgsmarkierung. Keine neu eingeführten Stubs, TODO-Zweige oder übersprungenen Abnahmetests als Fertigbeleg.

## Reihenfolge und Arbeitsaufteilung

P0 → P1 → P3 → P4 als erste nutzbare Strecke. P2 kann nach stabiler Daten-/Aktionsschnittstelle parallel zu P3 erfolgen. Dann P5/P6, danach P7. Keine parallelen Änderungen derselben GUI-Dateien. Architekturentscheidungen und Freigabegrenzen zuerst festlegen, um Nacharbeit zu vermeiden.

Coding: GPT-6-Luna für kleine, eindeutig abgegrenzte Pakete. Jeder Auftrag enthält erlaubte Dateien, Ein-/Ausgabeverträge, Abnahmekriterien, auszuführende Tests und verbotene Nebenänderungen. Arbeiter wissen von parallelen Änderungen und dürfen fremde Arbeit nicht zurücksetzen. Nach spätestens zwei gescheiterten Korrekturzyklen Ursache prüfen und Aufgabe verkleinern oder stärkeres Modell gezielt einsetzen; kein endloses billiges Wiederholen.

Koordination/Architektur: Hauptagent. Separate Review-/Verifier-Lane bewertet fertige Änderungen und Testevidenz; Autor genehmigt seine eigene Arbeit nicht. Hardwareprüfungen bleiben tatsächliche Hardwareprüfungen. Pro Paket: geplant → in Arbeit → Review → verifiziert oder blockiert. Bericht nennt Änderungen, Testergebnis, offene Punkte und nächstes Paket. Keine unbeaufsichtigte spätere Ausführung ohne explizit eingerichtete Automation.

## Verifikation und Risiken

Baseline und Wiederholung nach relevanten Änderungen: Windows PowerShell/Pester über tests/Run-Tests.ps1, Python-Tests anhand des vorhandenen Testmoduls/CI-Einstiegs. Neue Pester-Dateien explizit einbinden, da der Runner standardmäßig nur Hotwm.Tests.ps1 lädt. Separat Syntax-/XAML-Prüfung und GUI-/Hardwaretests. Eingriffslogik gegen temporäre Dateien/Fakes testen, nicht am echten Cabinet. Paketbau später in neues Artefaktziel, damit bestehende Releases nicht überschrieben werden.

Konkreter vorhandener Einstieg im code/-Ordner: powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-Tests.ps1. Bestehende Integritätsprüfungen erwarten UTF-8 BOM bei PowerShell-Dateien (tests/Hotwm.Tests.ps1:21–60); bei neuen Modulen berücksichtigen. GUI -NoShow und Fake-Kit-Tests erlauben hardwarefreie Prüfungen, ersetzen aber keine physische Abnahme. Tests bislang im Planungsschritt nicht ausgeführt.

Hauptrisiken: fehlende Gunmote-Automatisierung (vorher erforschen, manuelle Führung); doppelte Konfigurationsverantwortung (Kit-Vertrag); irreführender Hardwarestatus (Evidenzstufen); verlorene Bestandsdaten (Merge/Sicherung/Konfliktprüfung); UI-Blockieren bei Prüfungen (Hintergrundarbeit und Abbruch); ausufernde Expertenoptionen (nur belegte Fähigkeiten anbieten).

## Fertigdefinition

Ein neuer Nutzer erreicht ausgehend von seinem Setup-Ordner einen nachvollziehbar überprüften Lightgun-Betrieb. Jeder Eingriff ist einzeln freigegeben und protokolliert; Fehler und Ablehnungen sind fortsetzbar. Alle drei Modi verwenden dieselbe Engine; Button-/Effektvorlagen und unterstützte Cabinet-/Agent-Pfade funktionieren. Automatisierte und manuelle Prüfevidenz liegt vor. Offene Hardware-/Integrationspunkte verhindern eine pauschale Fertigmeldung.
