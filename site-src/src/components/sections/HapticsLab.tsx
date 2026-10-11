"use client";

import { useMemo, useRef, useState } from "react";
import { AnimatePresence, motion } from "framer-motion";
import { useLang } from "@/i18n/LangProvider";
import { useHaptics, useRumbling } from "@/lib/store";
import { Btn, Card, Chip, Reveal, SectionHead, WiimoteSVG } from "@/components/ui";
import { Icon } from "@/components/Icon";

/* ---------- motor physics (visual explanation) ---------- */
const TAU_UP = 70; // ms until the motor spins up
const TAU_DOWN = 55;
const T_MAX = 360;
function motorCurve(hold: number): { d: string; peak: number } {
  const pts: string[] = [];
  let peak = 0;
  const levelAt = (t: number) => {
    if (t <= hold) return 1 - Math.exp(-t / TAU_UP);
    const atHold = 1 - Math.exp(-hold / TAU_UP);
    return atHold * Math.exp(-(t - hold) / TAU_DOWN);
  };
  for (let t = 0; t <= T_MAX; t += 3) {
    const l = levelAt(t);
    peak = Math.max(peak, l);
    pts.push(`${(t / T_MAX) * 100},${100 - l * 100}`);
  }
  return { d: `M${pts.join(" L")}`, peak };
}

function Scope({ hold }: { hold: number }) {
  const raw = useMemo(() => motorCurve(16), []);
  const stretched = useMemo(() => motorCurve(hold), [hold]);
  const { t } = useLang();
  return (
    <div className="relative">
      <svg viewBox="0 0 100 100" preserveAspectRatio="none" className="h-44 w-full rounded-2xl bg-deep/80">
        {/* grid */}
        {[20, 40, 60, 80].map((v) => (
          <g key={v}>
            <line x1="0" x2="100" y1={v} y2={v} stroke="rgba(61,220,132,0.08)" strokeWidth="0.3" />
            <line y1="0" y2="100" x1={v} x2={v} stroke="rgba(61,220,132,0.08)" strokeWidth="0.3" />
          </g>
        ))}
        {/* pulse windows */}
        <rect x="0" y="0" width={(16 / T_MAX) * 100} height="100" fill="#ffc857" opacity="0.15" />
        <motion.rect
          x="0"
          y="0"
          height="100"
          fill="#3ddc84"
          opacity="0.1"
          animate={{ width: (hold / T_MAX) * 100 }}
          transition={{ type: "spring", stiffness: 120, damping: 20 }}
        />
        {/* curves */}
        <path d={raw.d} fill="none" stroke="#ffc857" strokeWidth="1" vectorEffect="non-scaling-stroke" strokeDasharray="2 2" />
        <motion.path
          d={stretched.d}
          fill="none"
          stroke="#3ddc84"
          strokeWidth="2.2"
          vectorEffect="non-scaling-stroke"
          animate={{ d: stretched.d }}
          transition={{ type: "spring", stiffness: 120, damping: 20 }}
          style={{ filter: "drop-shadow(0 0 4px rgba(61,220,132,0.8))" }}
        />
      </svg>
      <div className="pointer-events-none absolute left-3 top-3 flex flex-col gap-1 font-mono text-[11px]">
        <span className="text-gold">
          ▪ {t.lab.pulse.raw} 16 ms → {Math.round(raw.peak * 100)}%
        </span>
        <span className="text-mint">
          ▪ {t.lab.pulse.stretched} {hold} ms → {Math.round(stretched.peak * 100)}%
        </span>
      </div>
    </div>
  );
}

/* ---------- card 1: pulse stretcher ---------- */
function PulseCard() {
  const { t } = useLang();
  const holdMs = useHaptics((s) => s.holdMs);
  const setHoldMs = useHaptics((s) => s.setHoldMs);
  const fire = useHaptics((s) => s.fire);
  const health = useHaptics((s) => s.health);
  const rumbling = useRumbling();
  const strength = motorCurve(holdMs).peak;

  return (
    <Card className="lg:col-span-2">
      <div className="mb-4 flex items-start justify-between gap-4">
        <div>
          <h3 className="display text-3xl leading-none">{t.lab.pulse.title}</h3>
          <p className="mt-1.5 text-sm text-cream/55">{t.lab.pulse.desc}</p>
        </div>
        <div className="pixel-sm shrink-0 bg-mint/10 px-3 sm:px-4 py-2 text-right">
          <div className="display text-3xl leading-none text-mint glow-mint">{holdMs}</div>
          <div className="font-mono mt-1 text-[9px] uppercase tracking-wider text-mint/70 whitespace-nowrap">{t.lab.pulse.hold}</div>
        </div>
      </div>

      <div className="grid gap-6 md:grid-cols-[1fr_auto]">
        <div>
          <Scope hold={holdMs} />
          <div className="mt-5 flex items-center gap-4">
            <span className="font-mono text-xs text-cream/40">80</span>
            <input
              type="range"
              min={80}
              max={300}
              step={5}
              value={holdMs}
              onChange={(e) => setHoldMs(Number(e.target.value))}
              aria-label={t.lab.pulse.hold}
            />
            <span className="font-mono text-xs text-cream/40">300</span>
          </div>
          <div className="mt-4 flex items-center justify-between">
            <div className="flex gap-1">
              {[80, 120, 150, 200, 300].map((v) => (
                <Chip key={v} color="#ffc857" active={holdMs === v} onClick={() => setHoldMs(v)}>
                  {v}
                </Chip>
              ))}
            </div>
            <Btn variant="danger" icon="burst" onClick={() => fire(holdMs, strength)}>
              {t.lab.pulse.fire}
            </Btn>
          </div>
        </div>
        <div className="flex items-center justify-center">
          <WiimoteSVG health={health} rumble={rumbling} strength={strength} className="h-56" />
        </div>
      </div>
    </Card>
  );
}

/* ---------- card 2: life bar ---------- */
function LedCard() {
  const { t } = useLang();
  const health = useHaptics((s) => s.health);
  const setHealth = useHaptics((s) => s.setHealth);
  const fire = useHaptics((s) => s.fire);
  const rumbling = useRumbling();
  const color = health > 50 ? "#3ddc84" : health > 25 ? "#ffc857" : "#ff4b3a";

  return (
    <Card>
      <h3 className="display text-3xl leading-none">{t.lab.led.title}</h3>
      <p className="mt-1.5 text-sm text-cream/55">{t.lab.led.desc}</p>

      <div className="mt-6 flex items-center gap-6">
        <WiimoteSVG health={health} rumble={rumbling} strength={0.6} className="h-48" />
        <div className="flex-1">
          <div className="mb-2 flex items-end justify-between">
            <span className="pixel-label text-cream/50">{t.lab.led.health}</span>
            <span className="display text-3xl leading-none" style={{ color, textShadow: `0 0 12px ${color}80` }}>
              {health}%
            </span>
          </div>
          <div className="h-4 overflow-hidden rounded-full bg-cream/10">
            <motion.div
              className="h-full rounded-full"
              animate={{ width: `${health}%`, backgroundColor: color }}
              transition={{ type: "spring", stiffness: 160, damping: 22 }}
              style={{ boxShadow: `0 0 16px ${color}` }}
            />
          </div>
          <input
            type="range"
            min={0}
            max={100}
            value={health}
            onChange={(e) => setHealth(Number(e.target.value))}
            className="mt-4"
            aria-label={t.lab.led.health}
          />
          <div className="mt-4 flex gap-2">
            <Btn
              variant="danger"
              size="sm"
              icon="target"
              className="flex-1"
              onClick={() => {
                setHealth(health - 25);
                fire(120, 0.7);
              }}
            >
              −25 Hit
            </Btn>
            <Btn
              variant="primary"
              size="sm"
              icon="heart"
              className="flex-1"
              onClick={() => setHealth(100)}
            >
              100
            </Btn>
          </div>
        </div>
      </div>
    </Card>
  );
}

/* ---------- card 3: ammo → shot ---------- */
function AmmoCard() {
  const { t } = useLang();
  const fire = useHaptics((s) => s.fire);
  const health = useHaptics((s) => s.health);
  const rumbling = useRumbling();
  const [ammo, setAmmo] = useState(6);
  const [casings, setCasings] = useState<{ id: number; dx: number; dy: number }[]>([]);
  const idRef = useRef(0);

  const shoot = () => {
    if (ammo <= 0) return;
    setAmmo((a) => a - 1);
    const id = ++idRef.current;
    setCasings((c) => [...c.slice(-6), { id, dx: 70 + Math.random() * 30, dy: -40 - Math.random() * 30 }]);
    fire();
  };

  return (
    <Card>
      <h3 className="display text-3xl leading-none">{t.lab.ammo.title}</h3>
      <p className="mt-1.5 text-sm text-cream/55">{t.lab.ammo.desc}</p>

      <div className="mt-6 flex items-center gap-6">
        <div className="relative">
          <WiimoteSVG health={health} rumble={rumbling} className="h-48" />
          <AnimatePresence>
            {casings.map(({ id, dx, dy }) => (
              <motion.span
                key={id}
                initial={{ opacity: 1, x: 10, y: 20, rotate: 0 }}
                animate={{ opacity: 0, x: dx, y: dy, rotate: 420 }}
                exit={{ opacity: 0 }}
                transition={{ duration: 0.7, ease: "easeOut" }}
                onAnimationComplete={() => setCasings((c) => c.filter((x) => x.id !== id))}
                className="pointer-events-none absolute left-6 top-6 h-2 w-4 rounded-sm bg-gold"
              />
            ))}
          </AnimatePresence>
        </div>
        <div className="flex-1">
          <div className="mb-1 flex items-end justify-between">
            <span className="pixel-label text-cream/50">{t.lab.ammo.ammo}</span>
            <span className="display text-3xl leading-none text-gold glow-gold">{ammo}/6</span>
          </div>
          <div className="flex gap-1.5">
            {Array.from({ length: 6 }).map((_, i) => (
              <motion.div
                key={i}
                animate={{
                  opacity: i < ammo ? 1 : 0.15,
                  scaleY: i < ammo ? 1 : 0.6,
                  backgroundColor: i < ammo ? "#ffc857" : "#f4f1e9",
                }}
                className="h-9 flex-1 rounded-t-full rounded-b-sm"
              />
            ))}
          </div>
          <div className="mt-5 flex gap-2">
            <Btn
              variant="danger"
              icon="burst"
              className="flex-1"
              onClick={shoot}
              disabled={ammo <= 0}
            >
              {t.lab.ammo.shoot}
            </Btn>
            <Btn variant="ghost" icon="refresh" onClick={() => setAmmo(6)}>
              {t.lab.ammo.reload}
            </Btn>
          </div>
          <div className="mt-3 font-mono text-[11px] text-cream/40">
            ammo−1 → <span className="text-mint">P1_Shot</span> → rumble
          </div>
        </div>
      </div>
    </Card>
  );
}

export function HapticsLab() {
  const { t } = useLang();
  return (
    <section id="lab" className="relative mx-auto max-w-7xl px-5 py-28">
      <SectionHead kicker="02" title={t.lab.title} sub={t.lab.sub} pose="controller" />
      <div className="grid gap-6 lg:grid-cols-2">
        <Reveal className="lg:col-span-2">
          <PulseCard />
        </Reveal>
        <Reveal delay={0.1}>
          <LedCard />
        </Reveal>
        <Reveal delay={0.2}>
          <AmmoCard />
        </Reveal>
      </div>

      {/* platform marquee */}
      <Reveal className="mt-16 overflow-hidden">
        <div className="pixel-label mb-4 text-center text-cream/40">{t.platforms.title}</div>
        <div className="marquee flex w-max gap-3">
          {[...t.platforms.items, ...t.platforms.items, ...t.platforms.items, ...t.platforms.items].map(
            ([n, d], i) => (
              <div
                key={i}
                className="pixel-sm flex items-center gap-3 bg-cream/[0.04] px-5 py-3"
                style={{ boxShadow: "inset 0 0 0 1px rgba(244,241,233,0.1)" }}
              >
                <span className="inline-block h-2 w-2 bg-mint" />
                <span className="display text-xl leading-none">{n}</span>
                <span className="font-mono text-[11px] text-cream/40">{d}</span>
              </div>
            ),
          )}
        </div>
      </Reveal>
    </section>
  );
}
