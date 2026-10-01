# frieds-hotwm — Hook of the Wiimote 🎯🎮

> **Standalone & Kit-Ready Recoil Rumble & LED Haptics Relay for Gunmote and Wiimotes**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform: Windows](https://img.shields.io/badge/Platform-Windows%2010%20%7C%2011-0078D6.svg)](https://microsoft.com/windows)

---

## 🎯 Über das Projekt

**Hook of the Wiimote (`hotwm`)** ist ein anfängerfreundliches, transparentes Setup- und Relay-Tool für Arcade-Lightgun-Enthusiasten. Es ermöglicht vollwertiges Haptik-Feedback für Wiimotes hinter **Gunmote**:
- 💥 **Schuss- und Treffer-Rumble:** Intelligente Pulsdehnung (16ms → 150ms), damit der Vibrationsmotor der Wiimote spürbar anläuft.
- 🚦 **Dynamische Lebensanzeige:** Visualisierung des Gesundheitszustands über die 4 Wiimote-Player-LEDs.
- 🔄 **Ammo-Drop zu Schuss:** Automatisches Auslösen von Haptik bei Munitionsverlust.
- 🕹️ **Multi-Plattform-Support:** Nahtlose Integration mit **TeknoParrot / FFBBlaster**, **DemulShooter** und **MAME**.

Entwickelt sowohl als **tragbares Standalone-Tool** für bestehende RetroBat-, TeknoParrot- und MAME-Setups als auch als nativer Baustein für das [*Fried's Retrogaming Kit*](https://github.com/kburna243/frieds-retrogaming-kit).

---

## 🏗️ Architektur

```mermaid
flowchart TD
    subgraph Emulatoren["1. Spiele & Emulatoren"]
        TP["TeknoParrot / FFBBlaster<br/>(OutputsSystem=1, TCP 8002)"]
        DS["DemulShooter<br/>(WM_OutputsEnabled=True, Window Messages)"]
        MAME["MAME<br/>(output windows, Window Messages)"]
    end

    subgraph HotW["2. Hook of the Wiimote Kern (hotwm relay)"]
        Relay["Relay Server (Port 8000)"]
        Config["hotw.json<br/>(Spiele-Filter, Effekte, Toggles)"]
        Trace["recoil-stretch-trace.log<br/>(Live-Diagnose)"]
        
        Relay -->|Pulsdehnung 16ms → 150ms| Pulser["Recoil Pulse Stretcher"]
        Relay -->|Ammo Drop zu Pn_Shot| Ammo["Ammo-to-Shot Generator"]
        Relay -->|Health zu 4 LEDs| Health["Life Bar Scaler"]
    end

    subgraph Hardware["3. Gunmote & Wiimotes"]
        GHook["Gunmote ArcadeHook<br/>(TCP Client auf localhost:8000)"]
        INIs["Gemeinsame INIs<br/>TeknoParrot FFB.ini / DemulShooter.ini"]
        Wiimotes["Wiimote 1 & 2<br/>(Motor: wii n 5 / LEDs: wii n 1..4)"]
    end

    TP --> Relay
    DS --> Relay
    MAME --> Relay
    Config -.-> Relay
    Relay --> GHook
    GHook --> INIs
    INIs --> Wiimotes
```

```

---

## 🖥️ Standalone WPF Dashboard

Das Dashboard bietet eine grafische Oberfläche für Hardware-Status, Haptik-Tests, Tuning und Live-Logüberwachung:

- **1-Klick Start:** Doppelklick auf `Start-HotwmDashboard.bat` (oder `.\gui\HotwmDashboard.ps1`).
- **Hardware-Ampeln:** Echtzeit-Status von Relay, Gunmote-Prozess, ViGEmBus-Treiber, Wiimotes / DolphinBar und Kit-API.
- **Haptik-Testbench:** Direkte Test-Buttons für Player 1 & 2 Recoil Kick (150ms) und LED-Sequenzen (1–4) ohne Spielstart.
- **Echtzeit-Tuning:** Recoil-Stretch-Schieberegler (80–300 ms), Toggles für Ammo-Drop-Kick und LED-Lebensbalken, sowie Per-Game-Profile. Änderungen werden direkt in `hotw.json` gespeichert und im laufenden Relay **in unter 1 Sekunde hot-reloaded**.
- **Live-Log:** Eingebetteter Stream von MAMEOutput-Events und Recoil-Impulsen.

---

## 🚀 Meilensteine

1. **Phase 1: Kern-Relay Verankerung** ✅ *(Abgeschlossen)*
   - TCP-Server (Port 8000 für Gunmote, Port 8002 für FFBBlaster)
   - Win32-Message-Loop für DemulShooter & MAME
   - Optimierter Output-Adapter mit Pulsdehnung (16ms → 150ms) und Ammo-Drop-Trigger
2. **Phase 2: Konfigurations- & Filter-Engine (`hotw.json`)** ✅ *(Abgeschlossen)*
   - 14 vorkonfigurierte Spieleprofile und Haptik-Toggles (Rumble / LEDs)
   - Sofort-Test-Trigger per Socket (`--test-p1-rumble`, `--test-p1-leds`, `tools\Test-HotwmHaptics.ps1`)
   - Kit-API-Contract v1.5 Pinned Snapshot & Drift-Prüfung
3. **Phase 3: Windows-Automatisierung & Tools** ✅ *(Abgeschlossen)*
   - Hintergrund-Task `Gunmote Recoil Stretch` (`Install-HotwmTask.ps1` / `Uninstall-HotwmTask.ps1`)
   - KitClient für nahtlose Abfrage der Kit-Operation `outputs.wiimote_hook`
4. **Phase 4: Grafische Benutzeroberfläche (WPF-Dashboard)** ✅ *(Abgeschlossen)*
   - `gui/HotwmDashboard.ps1` & `HotwmDashboard.xaml` mit Arcade Dark Theme
   - Status-Ampel für alle Komponenten, Haptik-Testbench, Live-Tuning und Log-Monitor
   - 1-Klick-Starter `Start-HotwmDashboard.bat`
5. **Phase 5: Eigenständiges Standalone-Paket & Release** ⏳ *(Nächster Schritt)*
   - Portable Distribution (`Build-HotwmPackage.ps1` → ZIP-Release)
   - Zweisprachige Dokumentation (`README.de.md` & `README.md`)

---

## 📜 Lizenz

MIT License — Copyright (c) 2026 Friedrich Börner

