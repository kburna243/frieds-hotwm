export type Lang = "de" | "en";

export const LANGS: Lang[] = ["de", "en"];

export const REPO = "https://github.com/kburna243/frieds-hotwm";
export const RELEASE = `${REPO}/releases/latest`;
export const VERSION = "v0.10.0";

const de = {
  nav: {
    flow: "Signalweg",
    lab: "Labor",
    setup: "Einrichtung",
    ecosystem: "Familie",
    feedback: "Feedback",
    download: "Download",
  },
  hero: {
    kicker: "Hook of the Wiimote",
    title: "Spür den Schuss.",
    sub: "Rückstoß-Rumble & LED-Haptik für Wiimotes hinter Gunmote.",
    fire: "FEUER",
    hint: "Klick oder drück Leertaste",
    github: "GitHub",
    download: "Download",
    scroll: "Scrollen",
    stats: [
      ["16→150", "ms Puls-Streckung"],
      ["4", "LEDs = Lebensbalken"],
      ["3", "Emulatoren"],
      ["MIT", "Open Source"],
    ] as [string, string][],
  },
  flow: {
    title: "Der Signalweg",
    sub: "Vom Spiel bis zum Motor – in einem Klick.",
    fire: "Schuss senden",
    nodes: {
      games: "Spiele & Emulatoren",
      relay: "hotwm Relay",
      relayPort: "Port 8000",
      gunmote: "Gunmote ArcadeHook",
      wiimote: "Wiimote 1 & 2",
    },
    tags: {
      stretch: "Puls-Strecker",
      ammo: "Ammo → Schuss",
      health: "Leben → LEDs",
    },
  },
  lab: {
    title: "Haptik-Labor",
    sub: "Dreh an den Reglern – die Wiimote reagiert sofort.",
    pulse: {
      title: "Puls-Strecker",
      desc: "Ein Spiel sendet nur 16 ms. Zu kurz für den Motor. hotwm streckt es.",
      hold: "hold_ms",
      raw: "Spiel",
      stretched: "hotwm",
      fire: "Testpuls",
    },
    led: {
      title: "Lebensbalken",
      desc: "Die vier Spieler-LEDs zeigen die Lebensenergie.",
      health: "Leben",
    },
    ammo: {
      title: "Ammo → Schuss",
      desc: "Kein Rumble-Event vom Spiel? Jeder Munitionsabzug löst Rückstoß aus.",
      shoot: "Schießen",
      reload: "Nachladen",
      ammo: "Munition",
    },
  },
  platforms: {
    title: "Läuft mit",
    items: [
      ["TeknoParrot", "FFBBlaster · TCP 8002"],
      ["DemulShooter", "Window Messages"],
      ["MAME", "Output Windows"],
    ] as [string, string][],
  },
  setup: {
    title: "Geführte Einrichtung",
    sub: "Fünf Schritte. Nichts ändert sich ungefragt.",
    modes: ["Schnell", "Individuell", "Experte"],
    steps: [
      { t: "Ordner wählen", d: "RetroBat / Emulator – nur lesend geprüft." },
      { t: "Wiimotes koppeln", d: "Erkannt an ihrer Bluetooth-Adresse." },
      { t: "Spieler zuweisen", d: "Zuordnung ins Kit übernehmen." },
      { t: "Kalibrieren & zielen", d: "Manuell bestätigt – ehrlich." },
      { t: "Effekte anpassen", d: "Jede Änderung vorher sichtbar." },
    ],
    confirm: "Bestätigen",
    done: "Fertig!",
  },
  ecosystem: {
    title: "Fried’s Familie",
    sub: "Drei Werkzeuge, ein Maskottchen.",
    items: [
      {
        name: "Retrogaming Kit",
        v: "v1.5.1",
        d: "Geführte Installer, Dashboard & lokale API.",
        url: "https://kburna243.github.io/frieds-retrogaming-kit/",
      },
      {
        name: "HotWM",
        v: "v0.10.0",
        d: "Rumble & LED-Relay für Wiimotes.",
        url: "https://kburna243.github.io/frieds-hotwm/",
      },
      {
        name: "Retrogaming Agent",
        v: "v0.5.0",
        d: "Agent mit eigener Freigabe – ohne dein Ja passiert nichts.",
        url: "https://kburna243.github.io/frieds-retrogaming-agent/",
      },
    ],
    visit: "Öffnen",
  },
  status: {
    title: "Ehrlicher Stand",
    items: [
      ["Relay & Config", 100],
      ["Windows-Task-Tools", 100],
      ["WPF Dashboard", 90],
      ["Geführte Einrichtung", 75],
      ["Kit-Orchestrierung", 50],
      ["Hardwaretest 2× Wiimote", 20],
    ] as [string, number][],
  },
  feedback: {
    title: "Feedback",
    sub: "Dein Setup, deine Ideen, deine Bugs – genau das macht HotWM besser.",
    reactTitle: "Schnellreaktion",
    formTitle: "Nachricht hinterlassen",
    name: "Name",
    message: "Nachricht",
    kinds: { setup: "Setup", idea: "Idee", bug: "Bug", question: "Frage" },
    rating: "Bewertung",
    send: "Abschicken",
    sending: "Sendet…",
    thanks: "Danke – ist auf der Wand.",
    wallTitle: "Feedback-Wand",
    empty: "Noch leer – sei die erste Stimme.",
    error: "Hoppla, bitte nochmal versuchen.",
    style: "Darstellung",
    styleIcons: "Icons",
    styleEmoji: "Emoji",
    reactions: {
      flame: "Läuft heiss",
      burst: "Voller Rückstoß",
      target: "Zielt genau",
      rumble: "Spürbares Rumble",
      gamepad: "Will ich spielen",
    },
  },
  footer: {
    license: "MIT · © 2026 Friedrich Börner",
    made: "Gebaut mit Next.js, Three.js, GSAP & Framer Motion",
  },
};

const en: typeof de = {
  nav: {
    flow: "Signal path",
    lab: "Lab",
    setup: "Setup",
    ecosystem: "Family",
    feedback: "Feedback",
    download: "Download",
  },
  hero: {
    kicker: "Hook of the Wiimote",
    title: "Feel the shot.",
    sub: "Recoil rumble & LED haptics for Wiimotes behind Gunmote.",
    fire: "FIRE",
    hint: "Click or press space",
    github: "GitHub",
    download: "Download",
    scroll: "Scroll",
    stats: [
      ["16→150", "ms pulse stretch"],
      ["4", "LEDs = life bar"],
      ["3", "emulators"],
      ["MIT", "open source"],
    ],
  },
  flow: {
    title: "The signal path",
    sub: "From game to motor – in one click.",
    fire: "Send shot",
    nodes: {
      games: "Games & emulators",
      relay: "hotwm relay",
      relayPort: "port 8000",
      gunmote: "Gunmote ArcadeHook",
      wiimote: "Wiimote 1 & 2",
    },
    tags: {
      stretch: "Pulse stretcher",
      ammo: "Ammo → shot",
      health: "Health → LEDs",
    },
  },
  lab: {
    title: "Haptics lab",
    sub: "Turn the knobs – the Wiimote reacts instantly.",
    pulse: {
      title: "Pulse stretcher",
      desc: "A game only sends 16 ms. Too short for the motor. hotwm stretches it.",
      hold: "hold_ms",
      raw: "game",
      stretched: "hotwm",
      fire: "Test pulse",
    },
    led: {
      title: "Life bar",
      desc: "The four player LEDs show health.",
      health: "Health",
    },
    ammo: {
      title: "Ammo → shot",
      desc: "No rumble event from the game? Every ammo decrement triggers recoil.",
      shoot: "Shoot",
      reload: "Reload",
      ammo: "Ammo",
    },
  },
  platforms: {
    title: "Works with",
    items: [
      ["TeknoParrot", "FFBBlaster · TCP 8002"],
      ["DemulShooter", "Window messages"],
      ["MAME", "Output windows"],
    ],
  },
  setup: {
    title: "Guided setup",
    sub: "Five steps. Nothing changes without asking.",
    modes: ["Quick", "Custom", "Expert"],
    steps: [
      { t: "Pick folder", d: "RetroBat / emulator – read-only check." },
      { t: "Pair Wiimotes", d: "Recognised by Bluetooth address." },
      { t: "Assign players", d: "Save the mapping into the Kit." },
      { t: "Calibrate & aim", d: "Confirmed by hand – honestly." },
      { t: "Tune effects", d: "Every change visible before saving." },
    ],
    confirm: "Confirm",
    done: "Done!",
  },
  ecosystem: {
    title: "Fried’s family",
    sub: "Three tools, one mascot.",
    items: [
      {
        name: "Retrogaming Kit",
        v: "v1.5.1",
        d: "Guided installers, dashboard & local API.",
        url: "https://kburna243.github.io/frieds-retrogaming-kit/",
      },
      {
        name: "HotWM",
        v: "v0.10.0",
        d: "Rumble & LED relay for Wiimotes.",
        url: "https://kburna243.github.io/frieds-hotwm/",
      },
      {
        name: "Retrogaming Agent",
        v: "v0.5.0",
        d: "Agent with its own approval gate – nothing without your yes.",
        url: "https://kburna243.github.io/frieds-retrogaming-agent/",
      },
    ],
    visit: "Open",
  },
  status: {
    title: "Honest status",
    items: [
      ["Relay & config", 100],
      ["Windows task tools", 100],
      ["WPF dashboard", 90],
      ["Guided setup", 75],
      ["Kit orchestration", 50],
      ["Hardware test 2× Wiimote", 20],
    ],
  },
  feedback: {
    title: "Feedback",
    sub: "Your setup, your ideas, your bugs – that is exactly what makes HotWM better.",
    reactTitle: "Quick reaction",
    formTitle: "Leave a message",
    name: "Name",
    message: "Message",
    kinds: { setup: "Setup", idea: "Idea", bug: "Bug", question: "Question" },
    rating: "Rating",
    send: "Send",
    sending: "Sending…",
    thanks: "Thanks – it is on the wall.",
    wallTitle: "Feedback wall",
    empty: "Still empty – be the first voice.",
    error: "Oops, please try again.",
    style: "Display",
    styleIcons: "Icons",
    styleEmoji: "Emoji",
    reactions: {
      flame: "Runs hot",
      burst: "Full recoil",
      target: "Aims true",
      rumble: "Felt that rumble",
      gamepad: "Want to play",
    },
  },
  footer: {
    license: "MIT · © 2026 Friedrich Börner",
    made: "Built with Next.js, Three.js, GSAP & Framer Motion",
  },
};

export const dictionaries: Record<Lang, typeof de> = { de, en };
export type Dict = typeof de;

export function isLang(value: string): value is Lang {
  return LANGS.includes(value as Lang);
}
