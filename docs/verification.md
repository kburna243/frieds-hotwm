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

Die Dateiaustauschtests benötigen in der lokalen Codex-Sandbox zusätzliche Testberechtigung: die Sandbox verweigert `File.Replace` auch in temporären Testordnern. Ein identischer isolierter Test außerhalb der Sandbox funktionierte. Das Produkt verwendet weiterhin den normalen atomaren Windows-Dateiaustausch; es enthält keinen Sandbox-Workaround. Alle Eingriffstests verwenden Testdateien, keine reale Gunmote-/Cabinet-Konfiguration.

Diese Teilabnahmen belegen weder den fertigen Schnellstart noch einen vollständigen Editor oder die physische Funktion der Lightguns. Vorlagenbackend und erste Bedienansichten werden in getrennten weiteren Schritten verbunden. MAC-Zuordnung dokumentiert zunächst den gewünschten Spieler; Gunmotes aktuelle Nummerierung muss zusätzlich geprüft werden.
