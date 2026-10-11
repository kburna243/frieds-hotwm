"use client";

import { useState } from "react";
import { AnimatePresence, motion } from "framer-motion";
import { useLang } from "@/i18n/LangProvider";
import { Btn, Chip, Mascot, Reveal, SectionHead, type Pose } from "@/components/ui";
import { Icon } from "@/components/Icon";

const POSES: Pose[] = ["laptop", "controller", "thumbsup", "surprised", "happy"];

function StepArt({ i, lang }: { i: number; lang: string }) {
  const mono = "font-mono text-[11px]";
  switch (i) {
    case 0:
      return (
        <div className="flex flex-col gap-2">
          {["RetroBat/", "emulators/teknoparrot/", "emulators/demulshooter/", "emulators/mame/"].map((p, k) => (
            <motion.div
              key={p}
              initial={{ opacity: 0, x: -10 }}
              animate={{ opacity: 1, x: 0 }}
              transition={{ delay: k * 0.12 }}
              className={`flex items-center gap-2 rounded-lg bg-cream/5 px-3 py-2 ${mono} ${k ? "ml-5" : ""}`}
            >
              <span className="text-mint">
                <Icon name="folder" size={14} />
              </span>
              {p}
              <span className="ml-auto text-mint">read-only ✓</span>
            </motion.div>
          ))}
        </div>
      );
    case 1:
      return (
        <div className="flex items-center justify-around">
          {["00:1F:32:A4:9B:11", "00:1F:32:C7:02:5E"].map((mac, k) => (
            <div key={mac} className="relative flex flex-col items-center gap-2">
              {[0, 1, 2].map((r) => (
                <motion.span
                  key={r}
                  className="absolute top-6 h-16 w-16 rounded-full border border-mint/50"
                  animate={{ scale: [0.4, 1.6], opacity: [0.8, 0] }}
                  transition={{ duration: 1.8, repeat: Infinity, delay: r * 0.6 + k * 0.3 }}
                />
              ))}
              <div className="relative z-10 h-20 w-7 rounded-md border-2 border-night bg-cream" />
              <span className={`${mono} text-mint`}>{mac}</span>
            </div>
          ))}
        </div>
      );
    case 2:
      return (
        <div className="flex items-center justify-around">
          {["P1", "P2"].map((p, k) => (
            <motion.div
              key={p}
              initial={{ y: -20, opacity: 0 }}
              animate={{ y: 0, opacity: 1 }}
              transition={{ delay: 0.2 + k * 0.25, type: "spring" }}
              className="flex flex-col items-center gap-2"
            >
              <div className="flex h-14 w-14 items-center justify-center rounded-2xl bg-gold text-xl font-black text-night">
                {p}
              </div>
              <span className="text-mint">↓</span>
              <div className="h-16 w-6 rounded-md border-2 border-night bg-cream" />
              <span className={`${mono} text-cream/50`}>…{k ? "02:5E" : "9B:11"}</span>
            </motion.div>
          ))}
          <div className={`rounded-xl bg-mint/10 px-3 py-2 ${mono} text-mint`}>→ Kit API 1.8</div>
        </div>
      );
    case 3:
      return (
        <div className="relative mx-auto h-36 w-36">
          {[1, 0.7, 0.4].map((s) => (
            <div
              key={s}
              className="absolute inset-0 m-auto rounded-full border-2 border-coral/60"
              style={{ width: `${s * 100}%`, height: `${s * 100}%` }}
            />
          ))}
          <motion.div
            className="absolute h-5 w-5 rounded-full border-2 border-mint"
            animate={{ left: ["10%", "60%", "40%", "44%"], top: ["70%", "20%", "50%", "44%"] }}
            transition={{ duration: 2.4, repeat: Infinity, repeatDelay: 0.6 }}
          />
          <span className={`absolute -bottom-6 left-1/2 -translate-x-1/2 ${mono} text-cream/50`}>
            {lang === "de" ? "manuell" : "manual"} ✋
          </span>
        </div>
      );
    default:
      return (
        <div className={`rounded-xl bg-deep/80 p-4 ${mono} leading-6`}>
          <div className="text-cream/40">hotw.json</div>
          <div>
            <span className="text-coral">- &quot;hold_ms&quot;: 150</span>
          </div>
          <div>
            <span className="text-mint">+ &quot;hold_ms&quot;: 180</span>
          </div>
          <div className="text-cream/60">  &quot;led_mode&quot;: &quot;life_bar&quot;</div>
          <div className="mt-2 text-gold">backup ✓ · hot-reload ✓</div>
        </div>
      );
  }
}

export function Setup() {
  const { t, lang } = useLang();
  const [mode, setMode] = useState(0);
  const [step, setStep] = useState(0);
  const [done, setDone] = useState<boolean[]>([false, false, false, false, false]);
  const allDone = done.every(Boolean);

  const confirm = () => {
    const next = [...done];
    next[step] = true;
    setDone(next);
    if (step < 4) setStep(step + 1);
  };

  return (
    <section id="setup" className="relative mx-auto max-w-7xl px-5 py-28">
      <SectionHead kicker="03" title={t.setup.title} sub={t.setup.sub} />

      <Reveal className="panel pixel p-6 md:p-10">
        {/* modes */}
        <div className="mb-8 flex flex-wrap items-center justify-between gap-4">
          <div className="flex gap-2">
            {t.setup.modes.map((m, i) => (
              <Chip key={m} color="#ffc857" active={mode === i} onClick={() => setMode(i)}>
                {m}
              </Chip>
            ))}
          </div>
          <div className="flex items-center gap-2">
            {done.map((d, i) => (
              <button
                key={i}
                onClick={() => setStep(i)}
                className={`h-2.5 transition-all ${
                  i === step ? "w-8 bg-gold" : d ? "w-2.5 bg-mint" : "w-2.5 bg-cream/20"
                }`}
                aria-label={`Step ${i + 1}`}
              />
            ))}
          </div>
        </div>

        <div className="grid items-center gap-8 md:grid-cols-[auto_1fr_1fr]">
          <div className="flex justify-center">
            <Mascot pose={allDone ? "celebrate" : POSES[step]} size={170} />
          </div>

          <AnimatePresence mode="wait">
            <motion.div
              key={step}
              initial={{ opacity: 0, x: 24 }}
              animate={{ opacity: 1, x: 0 }}
              exit={{ opacity: 0, x: -24 }}
              transition={{ duration: 0.3 }}
            >
              <div className="pixel-label text-gold">0{step + 1} / 05</div>
              <h3 className="display mt-2 text-4xl leading-none">{t.setup.steps[step].t}</h3>
              <p className="mt-2 text-sm text-cream/60">{t.setup.steps[step].d}</p>
              <div className="mt-6">
                <Btn
                  variant={done[step] ? "ghost" : "primary"}
                  icon={done[step] ? "check" : "checkSquare"}
                  onClick={confirm}
                >
                  {t.setup.confirm}
                </Btn>
              </div>
            </motion.div>
          </AnimatePresence>

          <AnimatePresence mode="wait">
            <motion.div
              key={`art-${step}`}
              initial={{ opacity: 0, scale: 0.95 }}
              animate={{ opacity: 1, scale: 1 }}
              exit={{ opacity: 0, scale: 0.95 }}
              className="rounded-2xl border border-cream/10 bg-night-2/60 p-5"
            >
              <StepArt i={step} lang={lang} />
            </motion.div>
          </AnimatePresence>
        </div>

        {/* confetti */}
        <AnimatePresence>
          {allDone && (
            <motion.div
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              exit={{ opacity: 0 }}
              className="pointer-events-none absolute inset-0 overflow-hidden"
            >
              {Array.from({ length: 36 }).map((_, i) => (
                <motion.span
                  key={i}
                  initial={{ y: -20, x: `${(i / 36) * 100}%`, rotate: 0, opacity: 1 }}
                  animate={{ y: "110%", rotate: 720 }}
                  transition={{ duration: 2.2 + (i % 5) * 0.3, delay: (i % 7) * 0.1, ease: "easeIn" }}
                  className="absolute top-0 h-3 w-2 rounded-sm"
                  style={{ backgroundColor: ["#ffc857", "#3ddc84", "#ff4b3a", "#f4f1e9"][i % 4] }}
                />
              ))}
              <div className="display absolute inset-x-0 bottom-6 text-center text-3xl text-gold glow-gold">
                {t.setup.done}
              </div>
            </motion.div>
          )}
        </AnimatePresence>
      </Reveal>
    </section>
  );
}
