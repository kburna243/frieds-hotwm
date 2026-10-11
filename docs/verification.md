# Prüfstand der Hotwm-Erweiterung

## Ausgangspunkt — 2026-10-11

Revision vor Implementierung: `6edb166` auf `main`. Vorhandene lokale Trace-Datei ist kein Bestandteil der Änderungen.

Vor der Erweiterung ausgeführt im `code`-Ordner:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-Tests.ps1
```

Ergebnis: 18 bestanden, 0 fehlgeschlagen, 0 übersprungen, 0 ausstehend. Darin enthalten: Python-Selbsttest und 7 Python-Unit-Tests, PowerShell-Syntax/BOM, Fake-Kit, vorhandener lokaler Kit-Vertrag, WPF-Instanziierung mit `-NoShow` und portabler Paketbau in einem temporären Testziel.

Der lokale Kit-Vertrag meldete API 1.7 gegenüber Snapshot 1.6; die geprüften Operationen blieben kompatibel, Drift-Prüfung erfolgreich. Dies belegt keine allgemeine Kompatibilität mit beliebigen zukünftigen Kit-Versionen.

Keine physische Kopplung, Kalibrierung oder Spielprüfung wurde durchgeführt. Die automatisierten Tests belegen keine funktionierenden Wiimotes am Cabinet.

## Arbeitsweise

Jeder fertiggestellte Schritt erhält nach passenden Tests und separater Prüfung einen eigenen Commit. Neue Pester-Suiten müssen im Standard-Testlauf enthalten sein. Die dokumentierten Ergebnisse werden je abgeschlossener Etappe ergänzt; offene Hardwareprüfungen bleiben ausdrücklich offen.

## Abgeschlossene Teilabnahmen — 2026-10-11

| Schritt | Commit | Evidenz |
|---|---|---|
| Geprüfter Umsetzungsplan | a104067 | Unabhängige Planprüfung, Freigabegrenzen ergänzt |
| MAC-basierte Identität und gewünschte Spielerzuordnung | e7f1800 | 8 Pester-Tests und separate Quellprüfung |
| Standardlauf nimmt alle Testsuiten auf | ef92e8c | Separate Prüfung des Runners und der Baseline |
| Freigegebene Dateieingriffe, Sicherung und Wiederherstellung | 6bc0154 | 10 Pester-Tests; Manipulation, Wiederverwendung, Fremdänderungen, BOM und Rennen bei Vorschlagsbildung geprüft |
| Erste Einrichtungsansicht und Eingriffsbestätigungen | a2666fe | 6 GUI-Tests, unabhängige Prüfung; unbekannte aktuelle Konfigurationsfelder bleiben erhalten |
| Validierte Effekt-/semantische Buttonvorlagen | b3396fc | 8 Pester-Tests; geschützte Originalvorlagen, Import-/Exportvorschläge |
| Relay wertet Live-Effekte korrekt aus | c0be855 | 11 Python-Tests und Selbsttest; LED-Modus, Impulsdauer, Spielausnahmen, ungültige Konfiguration |
| Nintendo-HID-Elterneintrag und Herkunft der Identität | ef05cba | 12 Pester-Tests und separate Prüfung; gewünschter Spieler bleibt vom unbekannten Gunmote-Laufzeitslot getrennt |
| Tatsächliche Gunmote-Tastenlayouts und separater Auswahlmenü-Vorschlag | 9ebde68 | 9 Pester-Tests und unabhängige Prüfung; Prozesszustand, Zielschutz, gespeicherter Layout-Hash und getrennte Freigaben |
| Sichtbarer Effektprofil-Editor und semantische Button-Checklisten | 5772967 | 10 GUI-Tests und unabhängige Prüfung; Vorschau aus tatsächlichem Schreibvorschlag, Import-/Exporterhalt externer Spiele |
| Lokale Fried’s-Designquellen und Maskottchen | 11412fd | Vier SVG-Originale per Hash verglichen; vier transparente PNGs visuell geprüft; keine externe Bildabhängigkeit |
| Geführte Einrichtungszustände und manuelle Prüfschritte | 9cd9ae6 | 13 Pester-Tests und unabhängige Prüfung; Slotwechsel einschließlich 1→2→1 entwertet Folgeprüfungen, Zuordnungskonflikte verändern keinen Zustand |
| Native Night/Cream-Designressourcen | a05d81e | WPF-Dictionary mit 26 Ressourcen geladen; ausdrücklich benannte Stile, lokale Systemschriften, geschützte SVG-Originalbytes |
| Maskierte Cabinet-Diagnoseschnittstelle | 1c03678 | 6 Pester-Tests und separate Prüfung; nur Leseoperationen, MAC-Maskierung auch in verschachtelten Schlüsseln; lokaler Kit-Lesetest meldet NoWiimote ohne Bereitschaftsbehauptung |
| Tatsächlicher Gunmote-Tasten-Editor | a4b7b22 | 16 GUI-Tests und separate Prüfung; aktive Tabellenzelle wird vor Vorschlagsbildung übernommen, Freigabedialog sichtbar |
| Erststart ohne gespeicherte Zuordnung | 975c4ab | 14 Wizard-Tests und separate Prüfung; erstes erkanntes Gerät bleibt unzugeordnet und nicht bereit |
| Portable Kit-Erkennung | 50fe889 | 7 neue Tests, 18 Baseline-Prüfungen und separate Prüfung; kein fest eingebauter Maschinenpfad |
| Prüfhistorie erhalten | 37e16dd | 14 Wizard-Tests und separate Prüfung; Import/Speichern erhält Hinweise und Herkunft, erzeugt keine aktuellen Bestätigungen |
| Geführte Einrichtung in der Oberfläche | e60d1a1 | 22 GUI-Tests und separate Prüfung; beobachteter Laufzeitslot, manuelle Kalibrier-/Ziel-/Abzugsbestätigungen, unvertrauenswürdige importierte Historie |
| Portable Herkunftshinweise | eb27e23 | 18 Baseline-Prüfungen und separate Prüfung; Archiv enthält alle vier SVG-/PNG-Paare sowie Designquelle mit Namensnennung und Lizenzverweis |
| Fried’s-Design in der geführten Oberfläche | f2107eb | 29 GUI-Tests und separate Prüfung; lokales Theme/Bilder, Moduswechsel, Fehlermaskottchen, Vorlagennamen und sichtbare Prüfschritt-Buttons bei 850 Pixeln |
| Zusammenhängende Effekt-/Tastenmenüs | 15d2f3d | 31 GUI-Tests und separate Prüfung; Effekte einschließlich Werte in einem Tab, tatsächlicher Gunmote-Editor zuerst, Planung aufklappbar, lesbare Tabellen bei Mindestbreite |

Die Dateiaustauschtests benötigen in der lokalen Codex-Sandbox zusätzliche Testberechtigung: die Sandbox verweigert `File.Replace` auch in temporären Testordnern. Ein identischer isolierter Test außerhalb der Sandbox funktionierte. Das Produkt verwendet weiterhin den normalen atomaren Windows-Dateiaustausch; es enthält keinen Sandbox-Workaround. Alle Eingriffstests verwenden Testdateien, keine reale Gunmote-/Cabinet-Konfiguration.

Diese Teilabnahmen belegen noch keinen vollständig automatisierten Einrichtungsweg oder die physische Funktion der Lightguns. Die Editorprüfungen gelten für die ausdrücklich unterstützten Gunmote-Belegungen und globalen bzw. spielbezogenen Effekte. MAC-Zuordnung dokumentiert zunächst den gewünschten Spieler; Gunmotes aktuelle Nummerierung muss zusätzlich geprüft werden. Die Kit-Vorschaugrenzen und offenen Automatisierungsschritte stehen in kit-setup-capabilities.md; ein tatsächlicher Agent-Verbraucher ist noch nicht angeschlossen.

## Gesamtprüfung nach Design-/Menüintegration — 2026-10-11

Geprüfte Produktrevision: `15d2f3d`. Vollständiger Standardlauf unter Windows PowerShell 5.1: **115 bestanden, 0 fehlgeschlagen, 0 übersprungen, 0 ausstehend**. Enthalten sind 11 Python-Unit-Tests und der Relay-Selbsttest, alle Pester-Suiten, der lokale Kit-Lesevertrag und der portable Paketbau. Die abschließende separate GUI-Prüfung bestand zusätzlich 31/31 Tests. Die Suche in den bearbeiteten Hotwm-Quellen und Tests fand keine TODO-/Stub-/NotImplemented- oder test.skip/test.only-Platzhalter.

Zusätzlich wurde das portable ZIP in ein neues temporäres Verzeichnis entpackt und das Dashboard von einem fremden Arbeitsverzeichnis geladen. Theme, alle vier lokalen Maskottchen und Layoutvorlagen wurden ohne Zugriff auf das externe Asset-Projekt geladen. Einrichten, Effekte und Tasten wurden als WPF-Ansichten gerendert und visuell geprüft; die Einrichtungsansicht außerdem mit 125 % bei 850 logischen Pixeln. Bei der Aufnahme wurden verzögerte WPF-Dispatcher-Aufgaben abgearbeitet, damit Textvorlagen und Tabellenspalten korrekt gemessen werden. Mindestbreite und manuelle Prüfschritt-Buttons sind zusätzlich durch Tests abgesichert. Dies ist kein vollständiger Barrierefreiheits- oder Betriebssystem-DPI-Test.

Der All-in-one-Produktabschluss bleibt offen: exakte Kit-Installationspläne mit daran gebundener Freigabe, ein tatsächlicher Agent-Verbraucher und Hardware-Abnahme mit Wiederverbindung/vertauschtem Einschaltablauf, manueller Kalibrierung, Zielen, Abzug und Feedback pro Spieler. Die 3D-Quellen sind dokumentiert, aber noch nicht in die native Oberfläche eingebunden. Es wurde weder ein Release veröffentlicht noch ein Commit gepusht.
