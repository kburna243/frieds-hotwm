"use client";

import dynamic from "next/dynamic";
import { useEffect, useState } from "react";
import { AnimatePresence, motion } from "framer-motion";
import { useLang } from "@/i18n/LangProvider";
import { RELEASE, REPO, VERSION } from "@/i18n/dictionaries";
import { useHaptics } from "@/lib/store";
import { Btn, Mascot, type Pose } from "@/components/ui";
import { Icon } from "@/components/Icon";

const WiimoteScene = dynamic(() => import("@/components/three/WiimoteScene"), {
  ssr: false,
  loading: () => (
    <div className="flex h-full w-full items-center justify-center">
      <div className="h-10 w-10 animate-spin rounded-full border-2 border-mint border-t-transparent" />
    </div>
  ),
});

export function Hero() {
  const { t } = useLang();
  const fire = useHaptics((s) => s.fire);
  const shots = useHaptics((s) => s.shots);
  const [pose, setPose] = useState<Pose>("friendly");

  // space = fire
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.code === "Space" && !(e.target instanceof HTMLInputElement) && !(e.target instanceof HTMLTextAreaElement)) {
        e.preventDefault();
        fire();
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [fire]);

  // mascot reacts to shots
  useEffect(() => {
    let timer: ReturnType<typeof setTimeout> | undefined;
    const unsub = useHaptics.subscribe((s, prev) => {
      if (s.shots === prev.shots) return;
      setPose(s.shots % 10 === 0 ? "celebrate" : "surprised");
      clearTimeout(timer);
      timer = setTimeout(() => setPose("happy"), 700);
    });
    return () => {
      unsub();
      clearTimeout(timer);
    };
  }, []);

  const lastSpace = t.hero.title.lastIndexOf(" ");
  const line1 = lastSpace > 0 ? t.hero.title.slice(0, lastSpace).split("") : t.hero.title.split("");
  const line2 = lastSpace > 0 ? t.hero.title.slice(lastSpace + 1).split("") : [];

  return (
    <section className="relative min-h-screen overflow-hidden pt-24">
      <div className="pixel-grid absolute inset-0" />
      <div className="absolute -left-40 top-20 h-[32rem] w-[32rem] rounded-full bg-mint/10 blur-[120px]" />
      <div className="absolute -right-40 bottom-0 h-[32rem] w-[32rem] rounded-full bg-gold/10 blur-[120px]" />

      {/* muzzle flash */}
      <AnimatePresence>
        {shots > 0 && (
          <motion.div
            key={shots}
            initial={{ opacity: 0.55 }}
            animate={{ opacity: 0 }}
            exit={{ opacity: 0 }}
            transition={{ duration: 0.35 }}
            className="pointer-events-none absolute inset-0 z-20 bg-gold mix-blend-screen"
          />
        )}
      </AnimatePresence>

      <div className="relative mx-auto grid min-h-[calc(100vh-6rem)] max-w-7xl grid-cols-1 items-center gap-8 px-5 lg:grid-cols-2">
        {/* copy */}
        <div className="relative z-10 py-10">
          <motion.div
            initial={{ opacity: 0, y: 10 }}
            animate={{ opacity: 1, y: 0 }}
            className="pixel-sm mb-5 inline-flex items-center gap-2 bg-gold/10 px-3 py-2 text-gold max-w-full"
            style={{ boxShadow: "inset 0 0 0 1px rgba(255,200,87,0.35)" }}
          >
            <span className="inline-block h-2 w-2 animate-pulse bg-mint shrink-0" />
            <span className="font-mono text-[10px] uppercase tracking-[0.12em] whitespace-nowrap overflow-hidden text-ellipsis">
              {t.hero.kicker} · {VERSION}
            </span>
          </motion.div>

          <h1
            className="display text-6xl leading-[0.95] md:text-8xl"
            aria-label={t.hero.title}
          >
            <span className="block">
              {line1.map((ch, i) => (
                <motion.span
                  key={`l1-${i}`}
                  initial={{ opacity: 0, y: 40, rotateX: -90 }}
                  animate={{ opacity: 1, y: 0, rotateX: 0 }}
                  transition={{ delay: 0.15 + i * 0.035, type: "spring", stiffness: 200, damping: 16 }}
                  className={`inline-block ${ch === " " ? "w-3 md:w-4" : ""}`}
                >
                  {ch}
                </motion.span>
              ))}
            </span>
            {line2.length > 0 && (
              <span className="block text-mint glow-mint mt-1 md:mt-2">
                {line2.map((ch, i) => (
                  <motion.span
                    key={`l2-${i}`}
                    initial={{ opacity: 0, y: 40, rotateX: -90 }}
                    animate={{ opacity: 1, y: 0, rotateX: 0 }}
                    transition={{
                      delay: 0.15 + (line1.length + 1 + i) * 0.035,
                      type: "spring",
                      stiffness: 200,
                      damping: 16,
                    }}
                    className={`inline-block ${ch === " " ? "w-3 md:w-4" : ""}`}
                  >
                    {ch}
                  </motion.span>
                ))}
              </span>
            )}
          </h1>

          <motion.p
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            transition={{ delay: 0.8 }}
            className="mt-5 max-w-md text-base text-cream/65 md:text-lg"
          >
            {t.hero.sub}
          </motion.p>

          <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 1 }}
            className="mt-8 flex flex-wrap items-center gap-4"
          >
            <motion.button
              onClick={() => fire()}
              whileTap={{ scale: 0.92 }}
              whileHover={{ scale: 1.04, rotate: -2 }}
              className="btn btn-danger pixel relative h-24 w-24 !p-0 !text-[13px]"
              aria-label={t.hero.fire}
            >
              <span className="absolute inset-0 animate-ping bg-coral/30" />
              <span className="relative flex flex-col items-center gap-1">
                <Icon name="flame" size={20} />
                {t.hero.fire}
              </span>
            </motion.button>
            <div className="flex flex-col gap-2.5">
              <a href={RELEASE} target="_blank" rel="noreferrer" className="btn btn-primary pixel">
                <Icon name="download" size={13} /> {t.hero.download}
              </a>
              <a href={REPO} target="_blank" rel="noreferrer" className="btn btn-ghost pixel">
                <Icon name="github" size={13} /> {t.hero.github}
              </a>
            </div>
            <div className="pixel-label text-cream/40">
              {t.hero.hint}
              <div className="mt-2 font-mono text-3xl text-gold glow-gold">
                {String(shots).padStart(3, "0")}
              </div>
            </div>
          </motion.div>

          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            transition={{ delay: 1.3 }}
            className="mt-12 grid grid-cols-2 gap-3 sm:grid-cols-4"
          >
            {t.hero.stats.map(([v, l]) => (
              <div key={l} className="pixel-sm bg-cream/[0.04] p-3 sm:px-4 sm:py-3.5 min-w-0">
                <div className="display text-2xl sm:text-3xl leading-none text-gold glow-gold truncate">{v}</div>
                <div className="font-mono mt-1.5 text-[9px] sm:text-[10px] leading-snug text-cream/65 uppercase tracking-wider break-words hyphens-auto">
                  {l}
                </div>
              </div>
            ))}
          </motion.div>
        </div>

        {/* 3D */}
        <div className="relative h-[60vh] min-h-[420px] lg:h-[80vh]">
          <WiimoteScene />
          <div className="pointer-events-none absolute bottom-4 left-4 lg:-left-6">
            <Mascot pose={pose} size={150} />
          </div>
        </div>
      </div>

      <motion.a
        href="#flow"
        animate={{ y: [0, 8, 0] }}
        transition={{ repeat: Infinity, duration: 1.6 }}
        className="absolute bottom-6 left-1/2 hidden -translate-x-1/2 flex-col items-center gap-2 text-cream/40 md:flex"
      >
        <span className="pixel-label text-[8px]">{t.hero.scroll}</span>
        <span className="text-mint">
          <Icon name="arrowDown" size={18} />
        </span>
      </motion.a>
    </section>
  );
}
