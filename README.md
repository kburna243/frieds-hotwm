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

---

## 🚀 Geplante Meilensteine

1. **Phase 1: Kern-Relay Verankerung**
   - TCP-Server (Port 8002 für FFBBlaster)
   - Win32-Message-Loop für DemulShooter & MAME
   - Optimierter Output-Adapter für Gunmote
2. **Phase 2: Konfigurations- & Filter-Engine (`hotw.json`)**
   - Spieleprofile und Haptik-Toggles (Rumble / LEDs)
   - Sofort-Test-Trigger per Socket (`--test-p1-rumble`, `--test-p1-leds`)
3. **Phase 3: Windows-Automatisierung & Kit-Schritt**
   - Automatische Erkennung & Konfiguration (Gunmote, ViGEmBus, Bluetooth)
   - Hintergrund-Task `Gunmote Recoil Stretch`
4. **Phase 4: Grafische Benutzeroberfläche (WPF-Dashboard)**
   - Status-Ampel für alle Komponenten
   - Spiele-Auswahl & Test-Buttons für schnelles Feedback
5. **Phase 5: Eigenständiges Standalone-Paket**
   - Portable Distribution (`HookOfTheWiimote-Setup.zip`)

---

## 📜 Lizenz

MIT License — Copyright (c) 2026 Friedrich Börner
