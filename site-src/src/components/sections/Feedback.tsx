"use client";

import { useCallback, useEffect, useRef, useState, type FormEvent } from "react";
import { AnimatePresence, motion } from "framer-motion";
import { useLang } from "@/i18n/LangProvider";
import {
  KINDS,
  KIND_COLOR,
  KIND_ICON,
  REACTIONS,
  type FeedbackKind,
} from "@/lib/constants";
import type { Feedback as FeedbackRow } from "@/db/schema";
import { Btn } from "@/components/ui";
import { Icon } from "@/components/Icon";
import { Mascot, Reveal, SectionHead, type Pose } from "@/components/ui";

const KIND_POSE: Record<FeedbackKind, Pose> = {
  setup: "laptop",
  idea: "friendly",
  bug: "surprised",
  question: "neutral",
};

type Style = "icons" | "emoji";

const DEFAULT_REACTIONS: Record<string, number> = {
  flame: 42,
  burst: 28,
  target: 35,
  rumble: 19,
  gamepad: 51,
};

/* ---------------- reactions ---------------- */
function Reactions({ style, onStyle }: { style: Style; onStyle: (s: Style) => void }) {
  const { t } = useLang();
  const [counts, setCounts] = useState<Record<string, number>>(DEFAULT_REACTIONS);
  const [bursts, setBursts] = useState<{ id: number; idx: number }[]>([]);
  const idRef = useRef(0);

  useEffect(() => {
    fetch("/api/reactions")
      .then((r) => r.json())
      .then((data) => {
        if (data && typeof data === "object") setCounts(data);
      })
      .catch(() => {
        try {
          const saved = localStorage.getItem("hotwm_reactions");
          if (saved) setCounts(JSON.parse(saved));
        } catch {}
      });
  }, []);

  const react = async (id: string, idx: number) => {
    setCounts((c) => {
      const updated = { ...c, [id]: (c[id] ?? 0) + 1 };
      try {
        localStorage.setItem("hotwm_reactions", JSON.stringify(updated));
      } catch {}
      return updated;
    });
    const bid = ++idRef.current;
    setBursts((b) => [...b, { id: bid, idx }]);
    setTimeout(() => setBursts((b) => b.filter((x) => x.id !== bid)), 900);
    try {
      const res = await fetch("/api/reactions", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ emoji: id }),
      });
      if (res.ok) {
        const row = await res.json();
        setCounts((c) => ({ ...c, [row.emoji]: row.count }));
      }
    } catch {
      /* keep optimistic count in state & localStorage */
    }
  };

  return (
    <div className="panel pixel p-6">
      <div className="mb-4 flex items-center justify-between gap-3">
        <span className="pixel-label text-cream/50">{t.feedback.reactTitle}</span>
        <div className="flex items-center gap-1">
          {(["icons", "emoji"] as Style[]).map((s) => (
            <button
              key={s}
              onClick={() => onStyle(s)}
              className={`pixel-sm px-2.5 py-1.5 font-mono text-[10px] transition ${
                style === s
                  ? "bg-gold text-deep"
                  : "bg-cream/5 text-cream/50 hover:text-cream"
              }`}
            >
              {s === "icons" ? (
                <span className="flex items-center gap-1">
                  <Icon name="sparkle" size={11} /> {t.feedback.styleIcons}
                </span>
              ) : (
                <span className="flex items-center gap-1">☺ {t.feedback.styleEmoji}</span>
              )}
            </button>
          ))}
        </div>
      </div>

      <div className="flex flex-wrap gap-3">
        {REACTIONS.map((r, i) => {
          const label = t.feedback.reactions[r.id as keyof typeof t.feedback.reactions];
          return (
            <motion.button
              key={r.id}
              whileHover={{ y: -3 }}
              whileTap={{ scale: 0.88 }}
              onClick={() => react(r.id, i)}
              title={label}
              aria-label={label}
              className="pixel-sm group relative flex items-center gap-2 bg-cream/5 px-3.5 py-2.5 text-cream/80 transition hover:bg-mint/15 hover:text-mint"
            >
              {style === "icons" ? (
                <Icon name={r.icon} size={22} />
              ) : (
                <span className="text-xl leading-none">{r.emoji}</span>
              )}
              <motion.span
                key={counts[r.id] ?? 0}
                initial={{ y: -8, opacity: 0 }}
                animate={{ y: 0, opacity: 1 }}
                className="font-mono text-sm font-bold text-gold"
              >
                {counts[r.id] ?? 0}
              </motion.span>
              <span className="pointer-events-none absolute -top-8 left-1/2 -translate-x-1/2 whitespace-nowrap rounded bg-deep px-2 py-1 text-[10px] text-cream/80 opacity-0 shadow-lg transition group-hover:opacity-100">
                {label}
              </span>
              <AnimatePresence>
                {bursts
                  .filter((b) => b.idx === i)
                  .map((b) => (
                    <span key={b.id} className="pointer-events-none absolute inset-0">
                      {Array.from({ length: 7 }).map((_, k) => (
                        <motion.span
                          key={k}
                          initial={{ opacity: 1, x: 0, y: 0, scale: 0.5 }}
                          animate={{
                            opacity: 0,
                            x: Math.cos((k / 7) * Math.PI * 2) * 56,
                            y: Math.sin((k / 7) * Math.PI * 2) * 56 - 16,
                            scale: 1.3,
                          }}
                          transition={{ duration: 0.8, ease: "easeOut" }}
                          className="absolute left-1/2 top-1/2 text-mint"
                        >
                          <Icon name={r.icon} size={14} />
                        </motion.span>
                      ))}
                    </span>
                  ))}
              </AnimatePresence>
            </motion.button>
          );
        })}
      </div>
    </div>
  );
}

/* ---------------- stars ---------------- */
function Stars({ value, onChange }: { value: number; onChange: (v: number) => void }) {
  const [hover, setHover] = useState(0);
  return (
    <div className="flex gap-1" onMouseLeave={() => setHover(0)}>
      {[1, 2, 3, 4, 5].map((s) => (
        <motion.button
          type="button"
          key={s}
          whileHover={{ scale: 1.25, rotate: -12 }}
          whileTap={{ scale: 0.8 }}
          onMouseEnter={() => setHover(s)}
          onClick={() => onChange(s)}
          aria-label={`${s} / 5`}
          className="transition"
          style={{
            color: s <= (hover || value) ? "#ffc857" : "rgba(244,241,233,0.22)",
            filter:
              s <= (hover || value)
                ? "drop-shadow(0 0 8px rgba(255,200,87,.8))"
                : "none",
          }}
        >
          <Icon name="starFilled" size={26} />
        </motion.button>
      ))}
    </div>
  );
}

const DEFAULT_FEEDBACK: FeedbackRow[] = [
  {
    id: 1,
    name: "RetroArcadeFan",
    message: "Der Puls-Strecker auf 150ms macht Wiimote-Recoil in Time Crisis endlich richtig spürbar!",
    kind: "setup",
    rating: 5,
    lang: "de",
    createdAt: new Date().toISOString() as any,
  },
  {
    id: 2,
    name: "GunmoteUser99",
    message: "LEDs als Lebensbalken funktionieren 1A in TeknoParrot. Großes Lob an Fried!",
    kind: "idea",
    rating: 5,
    lang: "de",
    createdAt: new Date().toISOString() as any,
  },
];

/* ---------------- section ---------------- */
export function Feedback() {
  const { t, lang } = useLang();
  const [items, setItems] = useState<FeedbackRow[]>(DEFAULT_FEEDBACK);
  const [name, setName] = useState("");
  const [message, setMessage] = useState("");
  const [kind, setKind] = useState<FeedbackKind>("setup");
  const [rating, setRating] = useState(5);
  const [state, setState] = useState<"idle" | "sending" | "sent" | "error">("idle");
  const [style, setStyle] = useState<Style>("icons");

  const loadStorage = useCallback(() => {
    try {
      const saved = localStorage.getItem("hotwm_feedback");
      if (saved) {
        setItems(JSON.parse(saved));
        return;
      }
    } catch {}
    setItems(DEFAULT_FEEDBACK);
  }, []);

  const load = useCallback(() => {
    fetch("/api/feedback")
      .then((r) => r.json())
      .then((rows) => {
        if (Array.isArray(rows) && rows.length > 0) {
          setItems(rows);
        } else {
          loadStorage();
        }
      })
      .catch(() => loadStorage());
  }, [loadStorage]);

  useEffect(() => load(), [load]);

  const submit = async (e: FormEvent) => {
    e.preventDefault();
    if (!name.trim() || !message.trim()) return;
    setState("sending");
    const newRow: FeedbackRow = {
      id: Date.now(),
      name: name.trim(),
      message: message.trim(),
      kind,
      rating,
      lang,
      createdAt: new Date().toISOString() as any,
    };
    try {
      const res = await fetch("/api/feedback", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ name, message, kind, rating, lang }),
      });
      if (res.ok) {
        const row: FeedbackRow = await res.json();
        setItems((prev) => [row, ...prev]);
      } else {
        throw new Error("api unavailable");
      }
    } catch {
      setItems((prev) => {
        const updated = [newRow, ...prev];
        try {
          localStorage.setItem("hotwm_feedback", JSON.stringify(updated));
        } catch {}
        return updated;
      });
    }
    setName("");
    setMessage("");
    setRating(5);
    setState("sent");
    setTimeout(() => setState("idle"), 3000);
  };

  const pose: Pose =
    state === "sent" ? "celebrate" : state === "error" ? "surprised" : KIND_POSE[kind];

  return (
    <section id="feedback" className="relative mx-auto max-w-7xl px-5 py-28">
      <div className="pointer-events-none absolute inset-x-0 top-0 -z-10 h-96 bg-gradient-to-b from-mint/5 to-transparent" />
      <SectionHead kicker="05" title={t.feedback.title} sub={t.feedback.sub} pose="friendly" />

      <div className="grid gap-6 lg:grid-cols-[1.1fr_1fr]">
        <div className="flex flex-col gap-6">
          <Reveal>
            <Reactions style={style} onStyle={setStyle} />
          </Reveal>

          <Reveal delay={0.1}>
            <div className="panel pixel p-6">
              <div className="flex items-start justify-between gap-4">
                <span className="pixel-label text-cream/50">
                  {t.feedback.formTitle}
                </span>
                <div className="-mt-12 -mr-3 shrink-0">
                  <Mascot pose={pose} size={110} />
                </div>
              </div>

              <form onSubmit={submit} className="mt-3 flex flex-col gap-4">
                <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
                  {KINDS.map((k) => {
                    const active = kind === k;
                    return (
                      <motion.button
                        type="button"
                        key={k}
                        whileTap={{ scale: 0.94 }}
                        onClick={() => setKind(k)}
                        className="pixel-sm flex flex-col items-center gap-1.5 px-2 py-3 transition"
                        style={{
                          background: active ? `${KIND_COLOR[k]}26` : "rgba(244,241,233,0.04)",
                          boxShadow: active
                            ? `inset 0 0 0 2px ${KIND_COLOR[k]}`
                            : "inset 0 0 0 1px rgba(244,241,233,0.12)",
                          color: active ? KIND_COLOR[k] : "rgba(244,241,233,0.65)",
                        }}
                      >
                        <Icon name={KIND_ICON[k]} size={22} />
                        <span className="font-mono text-[9px] sm:text-[10px] uppercase tracking-wider text-center break-words px-0.5">
                          {t.feedback.kinds[k]}
                        </span>
                      </motion.button>
                    );
                  })}
                </div>

                <input
                  value={name}
                  onChange={(e) => setName(e.target.value)}
                  placeholder={t.feedback.name}
                  maxLength={60}
                  required
                  className="pixel-sm bg-deep/70 px-4 py-3 text-sm text-cream outline-none transition placeholder:text-cream/30 focus:bg-deep"
                  style={{ boxShadow: "inset 0 0 0 1px rgba(244,241,233,0.15)" }}
                />
                <textarea
                  value={message}
                  onChange={(e) => setMessage(e.target.value)}
                  placeholder={t.feedback.message}
                  maxLength={600}
                  required
                  rows={3}
                  className="pixel-sm resize-none bg-deep/70 px-4 py-3 text-sm text-cream outline-none transition placeholder:text-cream/30 focus:bg-deep"
                  style={{ boxShadow: "inset 0 0 0 1px rgba(244,241,233,0.15)" }}
                />

                <div className="flex flex-wrap items-center justify-between gap-4">
                  <div>
                    <div className="pixel-label mb-1.5 text-cream/40">
                      {t.feedback.rating}
                    </div>
                    <Stars value={rating} onChange={setRating} />
                  </div>
                  <Btn variant="primary" type="submit" disabled={state === "sending"}>
                    {state === "sending" ? t.feedback.sending : t.feedback.send}
                    <Icon name="arrowRight" size={13} />
                  </Btn>
                </div>

                <AnimatePresence>
                  {state === "sent" && (
                    <motion.div
                      initial={{ opacity: 0, y: 8 }}
                      animate={{ opacity: 1, y: 0 }}
                      exit={{ opacity: 0 }}
                      className="pixel-sm flex items-center justify-center gap-2 bg-mint/15 py-2.5 font-mono text-xs uppercase tracking-wider text-mint"
                    >
                      <Icon name="check" size={14} /> {t.feedback.thanks}
                    </motion.div>
                  )}
                  {state === "error" && (
                    <motion.div
                      initial={{ opacity: 0, y: 8 }}
                      animate={{ opacity: 1, y: 0 }}
                      exit={{ opacity: 0 }}
                      className="pixel-sm flex items-center justify-center gap-2 bg-coral/15 py-2.5 font-mono text-xs uppercase tracking-wider text-coral"
                    >
                      <Icon name="bug" size={14} /> {t.feedback.error}
                    </motion.div>
                  )}
                </AnimatePresence>
              </form>
            </div>
          </Reveal>
        </div>

        {/* wall */}
        <Reveal delay={0.15}>
          <div className="panel pixel h-full p-6">
            <div className="mb-4 flex items-center justify-between">
              <span className="pixel-label text-cream/50">{t.feedback.wallTitle}</span>
              <span className="font-mono text-xs text-gold">{items.length}</span>
            </div>
            <div className="flex max-h-[640px] flex-col gap-3 overflow-y-auto pr-1">
              <AnimatePresence initial={false}>
                {items.length === 0 && (
                  <motion.div
                    initial={{ opacity: 0 }}
                    animate={{ opacity: 1 }}
                    className="flex flex-col items-center gap-3 py-10 text-center text-sm text-cream/50"
                  >
                    <Mascot pose="neutral" size={90} float={false} />
                    {t.feedback.empty}
                  </motion.div>
                )}
                {items.map((f) => {
                  const k = (
                    KINDS.includes(f.kind as FeedbackKind) ? f.kind : "setup"
                  ) as FeedbackKind;
                  return (
                    <motion.div
                      key={f.id}
                      layout
                      initial={{ opacity: 0, y: -16, scale: 0.97 }}
                      animate={{ opacity: 1, y: 0, scale: 1 }}
                      className="pixel-sm bg-night-2/80 p-4"
                      style={{
                        boxShadow: `inset 0 0 0 1px rgba(244,241,233,0.1), inset 3px 0 0 ${KIND_COLOR[k]}`,
                      }}
                    >
                      <div className="flex items-center justify-between gap-3">
                        <div className="flex items-center gap-2">
                          <span style={{ color: KIND_COLOR[k] }}>
                            <Icon name={KIND_ICON[k]} size={16} />
                          </span>
                          <span className="text-sm font-bold">{f.name}</span>
                          <span className="pixel-sm bg-cream/5 px-2 py-0.5 font-mono text-[9px] uppercase tracking-wider text-cream/40 whitespace-nowrap">
                            {f.lang}
                          </span>
                        </div>
                        <span className="flex gap-0.5 text-gold">
                          {Array.from({ length: 5 }).map((_, i) => (
                            <Icon
                              key={i}
                              name="starFilled"
                              size={11}
                              style={{
                                color: i < f.rating ? "#ffc857" : "rgba(244,241,233,0.15)",
                              }}
                            />
                          ))}
                        </span>
                      </div>
                      <p className="mt-2 text-sm leading-relaxed text-cream/75">
                        {f.message}
                      </p>
                    </motion.div>
                  );
                })}
              </AnimatePresence>
            </div>
          </div>
        </Reveal>
      </div>
    </section>
  );
}
