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
