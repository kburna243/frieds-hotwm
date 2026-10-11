"use client";

import { motion } from "framer-motion";
import { useLang } from "@/i18n/LangProvider";
import { Btn, Card, Mascot, Reveal, SectionHead, type Pose } from "@/components/ui";
import { Icon } from "@/components/Icon";

const POSES: Pose[] = ["laptop", "controller", "thumbsup"];

export function Ecosystem() {
  const { t } = useLang();
  return (
    <section id="ecosystem" className="relative mx-auto max-w-7xl px-5 py-28">
      <SectionHead kicker="04" title={t.ecosystem.title} sub={t.ecosystem.sub} />

      <div className="relative grid gap-6 md:grid-cols-3">
        {/* connector line */}
        <div className="pointer-events-none absolute left-[16%] right-[16%] top-24 hidden h-0.5 bg-gradient-to-r from-gold/0 via-mint/60 to-gold/0 md:block" />
        {t.ecosystem.items.map((it, i) => (
          <Reveal key={it.name} delay={i * 0.12}>
            <motion.a
              href={it.url}
              target="_blank"
              rel="noreferrer"
              whileHover={{ y: -8, rotate: i === 1 ? 0 : i === 0 ? -1 : 1 }}
              className="panel-hover block"
            >
              <Card className={`h-full text-center ${i === 1 ? "border-gold/40 bg-gold/5" : ""}`}>
                <div className="flex justify-center">
                  <Mascot pose={POSES[i]} size={130} />
                </div>
                <div className="pixel-label mt-2 text-gold">FRIED’S</div>
                <h3 className="display text-3xl leading-none">{it.name}</h3>
                <span
                  className="pixel-sm mt-2 inline-block bg-mint/15 px-2.5 py-0.5 font-mono text-[10px] text-mint whitespace-nowrap"
                >
                  {it.v}
                </span>
                <p className="mt-3 text-sm text-cream/60">{it.d}</p>
                <div className="pixel-label mt-5 flex items-center justify-center gap-2 text-gold">
                  {t.ecosystem.visit} <Icon name="external" size={11} />
                </div>
              </Card>
            </motion.a>
          </Reveal>
        ))}
      </div>

      {/* honest status */}
      <Reveal className="mt-20 grid items-center gap-10 md:grid-cols-[auto_1fr]">
        <div className="flex flex-col items-center gap-3">
          <Mascot pose="neutral" size={150} />
          <h3 className="display text-3xl leading-none">{t.status.title}</h3>
        </div>
        <div className="grid gap-4 sm:grid-cols-2">
          {t.status.items.map(([label, pct], i) => {
            const color = pct === 100 ? "#3ddc84" : pct >= 60 ? "#ffc857" : "#ff4b3a";
            return (
              <div key={label} className="pixel-sm bg-cream/[0.04] p-4 min-w-0">
                <div className="mb-2 flex items-center justify-between gap-2 font-mono text-xs">
                  <span className="text-cream/70 truncate">{label}</span>
                  <span className="font-bold shrink-0" style={{ color }}>
                    {pct}%
                  </span>
                </div>
                <div className="h-2.5 overflow-hidden bg-cream/10">
                  <motion.div
                    initial={{ width: 0 }}
                    whileInView={{ width: `${pct}%` }}
                    viewport={{ once: true }}
                    transition={{ duration: 1.2, delay: i * 0.1, ease: [0.22, 1, 0.36, 1] }}
                    className="h-full"
                    style={{ backgroundColor: color, boxShadow: `0 0 12px ${color}` }}
                  />
                </div>
              </div>
            );
          })}
        </div>
      </Reveal>
    </section>
  );
}
