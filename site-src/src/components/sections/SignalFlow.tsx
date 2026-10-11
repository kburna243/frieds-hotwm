"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import gsap from "gsap";
import { ScrollTrigger } from "gsap/ScrollTrigger";
import { motion } from "framer-motion";
import { useLang } from "@/i18n/LangProvider";
import { useHaptics } from "@/lib/store";
import { assetUrl } from "@/lib/asset";
import { Reveal, SectionHead } from "@/components/ui";
import { Icon } from "@/components/Icon";

gsap.registerPlugin(ScrollTrigger);

const Y = 150;
const NODES = {
  games: { x: 20, w: 200 },
  relay: { x: 300, w: 270 },
  gunmote: { x: 650, w: 170 },
  wiimote: { x: 900, w: 80 },
};

export function SignalFlow() {
  const { t } = useLang();
  const fire = useHaptics((s) => s.fire);
  const holdMs = useHaptics((s) => s.holdMs);
  const svgRef = useRef<SVGSVGElement>(null);
  const dotRef = useRef<SVGCircleElement>(null);
  const labelRef = useRef<SVGTextElement>(null);
  const relayRef = useRef<SVGRectElement>(null);
  const wiiRef = useRef<SVGGElement>(null);
  const ledRefs = useRef<(SVGRectElement | null)[]>([]);
  const tagRefs = useRef<(SVGGElement | null)[]>([]);
  const tlRef = useRef<gsap.core.Timeline | null>(null);
  const [busy, setBusy] = useState(false);

  const play = useCallback(() => {
    if (!dotRef.current || !labelRef.current) return;
    tlRef.current?.kill();
    setBusy(true);
    const dot = dotRef.current;
    const label = labelRef.current;
    const tags = tagRefs.current.filter(Boolean);
    const leds = ledRefs.current.filter(Boolean);

    const tl = gsap.timeline({
      onComplete: () => setBusy(false),
      defaults: { ease: "power2.inOut" },
    });
    tl.set(dot, { attr: { cx: NODES.games.x + NODES.games.w, cy: Y, r: 6 }, fill: "#ffc857", opacity: 1 })
      .call(() => {
        label.textContent = "16 ms";
      })
      .set(label, { attr: { x: NODES.games.x + NODES.games.w + 40, y: Y - 18 }, opacity: 1, fill: "#ffc857" })
      .to(dot, { attr: { cx: NODES.relay.x }, duration: 0.55 })
      .to(label, { attr: { x: NODES.relay.x - 10 }, duration: 0.55 }, "<")
      // relay processing
      .to(relayRef.current, { attr: { stroke: "#3ddc84" }, strokeWidth: 3, duration: 0.15 })
      .to(tags, { opacity: 1, scale: 1.08, transformOrigin: "center", stagger: 0.08, duration: 0.15 }, "<")
      .to(dot, { attr: { cx: NODES.relay.x + NODES.relay.w / 2, r: 18 }, fill: "#3ddc84", duration: 0.45 })
      .call(
        () => {
          label.textContent = `${holdMs} ms`;
        },
        [],
        "<",
      )
      .to(label, { attr: { x: NODES.relay.x + NODES.relay.w / 2, y: Y - 34 }, fill: "#3ddc84", duration: 0.45 }, "<")
      .to(tags, { scale: 1, duration: 0.2 })
      .to(relayRef.current, { attr: { stroke: "rgba(244,241,233,0.15)" }, strokeWidth: 1.5, duration: 0.3 }, "<")
      // to gunmote
      .to(dot, { attr: { cx: NODES.gunmote.x + NODES.gunmote.w / 2, r: 14 }, duration: 0.45 })
      .to(label, { attr: { x: NODES.gunmote.x + NODES.gunmote.w / 2 }, duration: 0.45 }, "<")
      // to wiimote
      .to(dot, { attr: { cx: NODES.wiimote.x + NODES.wiimote.w / 2, r: 12 }, duration: 0.35 })
      .to(label, { opacity: 0, duration: 0.2 }, "<")
      .call(() => fire())
      .to(dot, { opacity: 0, attr: { r: 40 }, duration: 0.35 })
      .to(wiiRef.current, { x: 3, repeat: 7, yoyo: true, duration: 0.03, ease: "none" }, "<")
      .to(leds, { fill: "#3ddc84", stagger: 0.05, duration: 0.1 }, "<")
      .to(wiiRef.current, { x: 0, duration: 0.1 });
    tlRef.current = tl;
  }, [fire, holdMs]);

  // autoplay once on scroll into view
  useEffect(() => {
    const el = svgRef.current;
    if (!el) return;
    const st = ScrollTrigger.create({
      trigger: el,
      start: "top 70%",
      once: true,
      onEnter: () => play(),
    });
    return () => {
      st.kill();
      tlRef.current?.kill();
    };
  }, [play]);

  const tags = [t.flow.tags.stretch, t.flow.tags.ammo, t.flow.tags.health];
  const platforms = ["TeknoParrot", "DemulShooter", "MAME"];

  return (
    <section id="flow" className="relative mx-auto max-w-7xl px-5 py-28">
      <SectionHead kicker="01" title={t.flow.title} sub={t.flow.sub} pose="laptop" />


      <Reveal className="panel pixel p-4 md:p-8">
        <svg ref={svgRef} viewBox="0 0 1000 330" className="w-full" role="img" aria-label={t.flow.title}>
          <defs>
            <linearGradient id="wire" x1="0" x2="1">
              <stop offset="0" stopColor="#ffc857" stopOpacity="0.5" />
              <stop offset="1" stopColor="#3ddc84" stopOpacity="0.5" />
            </linearGradient>
            <filter id="softGlow" x="-50%" y="-50%" width="200%" height="200%">
              <feGaussianBlur stdDeviation="6" result="b" />
              <feMerge>
                <feMergeNode in="b" />
                <feMergeNode in="SourceGraphic" />
              </feMerge>
            </filter>
          </defs>

          {/* wires */}
          {[
            [NODES.games.x + NODES.games.w, NODES.relay.x],
            [NODES.relay.x + NODES.relay.w, NODES.gunmote.x],
            [NODES.gunmote.x + NODES.gunmote.w, NODES.wiimote.x],
          ].map(([x1, x2], i) => (
            <g key={i}>
              <line x1={x1} y1={Y} x2={x2} y2={Y} stroke="url(#wire)" strokeWidth="2" />
              <motion.line
                x1={x1}
                y1={Y}
                x2={x2}
                y2={Y}
                stroke="#3ddc84"
                strokeWidth="2"
                strokeDasharray="6 14"
                animate={{ strokeDashoffset: [0, -40] }}
                transition={{ duration: 1.2, repeat: Infinity, ease: "linear" }}
              />
            </g>
          ))}

          {/* games */}
          <g>
            <rect x={NODES.games.x} y={Y - 80} width={NODES.games.w} height={160} rx="22" fill="rgba(244,241,233,0.04)" stroke="rgba(244,241,233,0.15)" strokeWidth="1.5" />
            <text
              x={NODES.games.x + NODES.games.w / 2}
              y={Y - 50}
              textAnchor="middle"
              fill="#f4f1e9"
              fontSize="21"
              fontFamily="var(--font-display)"
              letterSpacing="0.5"
            >
              {t.flow.nodes.games}
            </text>
            {platforms.map((p, i) => (
              <g key={p}>
                <rect x={NODES.games.x + 20} y={Y - 32 + i * 34} width={NODES.games.w - 40} height={26} rx="13" fill="#ffc857" fillOpacity="0.12" stroke="#ffc857" strokeOpacity="0.4" />
                <text
                  x={NODES.games.x + NODES.games.w / 2}
                  y={Y - 32 + i * 34 + 17}
                  textAnchor="middle"
                  fill="#ffc857"
                  fontSize="11"
                  fontFamily="var(--font-mono)"
                >
                  {p}
                </text>
              </g>
            ))}
          </g>

          {/* relay */}
          <g>
            <rect ref={relayRef} x={NODES.relay.x} y={Y - 90} width={NODES.relay.w} height={180} rx="26" fill="rgba(61,220,132,0.05)" stroke="rgba(244,241,233,0.15)" strokeWidth="1.5" />
            <image href={assetUrl("/brand/character-controller.svg")} x={NODES.relay.x + 14} y={Y - 80} width="70" height="70" />
            <text x={NODES.relay.x + 96} y={Y - 46} fill="#f4f1e9" fontSize="24" fontFamily="var(--font-display)">
              {t.flow.nodes.relay}
            </text>
            <text x={NODES.relay.x + 96} y={Y - 28} fill="#3ddc84" fontSize="11" fontFamily="monospace">
              localhost · {t.flow.nodes.relayPort}
            </text>
            <text x={NODES.relay.x + 96} y={Y - 12} fill="rgba(244,241,233,0.5)" fontSize="11" fontFamily="monospace">
              hotw.json
            </text>
            {tags.map((tag, i) => {
              const parts = tag.includes(" → ")
                ? [tag.split(" → ")[0] + " →", tag.split(" → ")[1] || ""]
                : tag.includes("-")
                ? [tag.split("-")[0] + "-", tag.split("-")[1] || ""]
                : tag.includes(" ")
                ? [tag.split(" ")[0] || "", tag.slice(tag.indexOf(" ") + 1)]
                : [tag];
              const bx = NODES.relay.x + 10 + i * 85;
              const bw = 80;
              const cx = bx + bw / 2;
              return (
                <g
                  key={tag}
                  ref={(el) => {
                    tagRefs.current[i] = el;
                  }}
                  opacity="0.75"
                >
                  <rect
                    x={bx}
                    y={Y + 36}
                    width={bw}
                    height={38}
                    rx="10"
                    fill="#3ddc84"
                    fillOpacity="0.12"
                    stroke="#3ddc84"
                    strokeOpacity="0.5"
                  />
                  {parts.length === 1 ? (
                    <text
                      x={cx}
                      y={Y + 59}
                      textAnchor="middle"
                      fill="#3ddc84"
                      fontSize="9.5"
                      fontFamily="var(--font-mono)"
                    >
                      {parts[0]}
                    </text>
                  ) : (
                    <>
                      <text
                        x={cx}
                        y={Y + 51}
                        textAnchor="middle"
                        fill="#3ddc84"
                        fontSize="9"
                        fontFamily="var(--font-mono)"
                      >
                        {parts[0]}
                      </text>
                      <text
                        x={cx}
                        y={Y + 64}
                        textAnchor="middle"
                        fill="#3ddc84"
                        fontSize="9"
                        fontFamily="var(--font-mono)"
                      >
                        {parts[1]}
                      </text>
                    </>
                  )}
                </g>
              );
            })}
          </g>

          {/* gunmote */}
          <g>
            <rect x={NODES.gunmote.x} y={Y - 60} width={NODES.gunmote.w} height={120} rx="22" fill="rgba(244,241,233,0.04)" stroke="rgba(244,241,233,0.15)" strokeWidth="1.5" />
            <text x={NODES.gunmote.x + NODES.gunmote.w / 2} y={Y - 8} textAnchor="middle" fill="#f4f1e9" fontSize="19" fontFamily="var(--font-display)">
              Gunmote
            </text>
            <text x={NODES.gunmote.x + NODES.gunmote.w / 2} y={Y + 12} textAnchor="middle" fill="rgba(244,241,233,0.5)" fontSize="11" fontFamily="var(--font-mono)">
              ArcadeHook · TCP client
            </text>
            <text x={NODES.gunmote.x + NODES.gunmote.w / 2} y={Y + 30} textAnchor="middle" fill="#ffc857" fontSize="10" fontFamily="monospace">
              FFB.ini / DemulShooter.ini
            </text>
          </g>

          {/* wiimote */}
          <g ref={wiiRef}>
            <rect x={NODES.wiimote.x + 15} y={Y - 85} width={50} height={170} rx="12" fill="#f4f1e9" stroke="#0b1b23" strokeWidth="3" />
            <circle cx={NODES.wiimote.x + 40} cy={Y - 30} r="7" fill="#1a2630" />
            <rect x={NODES.wiimote.x + 30} y={Y - 62} width={20} height={6} rx="1.5" fill="#1a2630" />
            <rect x={NODES.wiimote.x + 37} y={Y - 69} width={6} height={20} rx="1.5" fill="#1a2630" />
            <circle cx={NODES.wiimote.x + 40} cy={Y + 20} r="5" fill="#1a2630" />
            <circle cx={NODES.wiimote.x + 40} cy={Y + 38} r="5" fill="#1a2630" />
            {[0, 1, 2, 3].map((i) => (
              <rect
                key={i}
                ref={(el) => {
                  ledRefs.current[i] = el;
                }}
                x={NODES.wiimote.x + 22 + i * 10}
                y={Y + 66}
                width={6}
                height={4}
                rx="1"
                fill="#2a3a44"
              />
            ))}
          </g>
          <text x={NODES.wiimote.x + NODES.wiimote.w / 2} y={Y + 108} textAnchor="middle" fill="rgba(244,241,233,0.6)" fontSize="11" fontFamily="var(--font-mono)">
            {t.flow.nodes.wiimote}
          </text>

          {/* travelling pulse */}
          <circle ref={dotRef} cx="0" cy={Y} r="0" fill="#ffc857" opacity="0" filter="url(#softGlow)" />
          <text
            ref={labelRef}
            x="0"
            y="0"
            textAnchor="middle"
            fontSize="15"
            fontFamily="var(--font-mono)"
            opacity="0"
          />
        </svg>

        <div className="mt-6 flex justify-center">
          <motion.button
            whileTap={{ scale: 0.95 }}
            className="btn btn-accent pixel disabled:opacity-60"
            disabled={busy}
            onClick={play}
          >
            <Icon name="bolt" size={13} /> {t.flow.fire}
          </motion.button>
        </div>
      </Reveal>
    </section>
  );
}
