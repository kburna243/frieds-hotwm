"use client";

import { motion, type HTMLMotionProps } from "framer-motion";
import type { ButtonHTMLAttributes, ReactNode } from "react";
import { ledsFromHealth } from "@/lib/store";
import { assetUrl } from "@/lib/asset";
import { Icon, type IconName } from "@/components/Icon";

export type Pose =
  | "friendly"
  | "happy"
  | "celebrate"
  | "controller"
  | "laptop"
  | "neutral"
  | "surprised"
  | "thumbsup"
  | "winking";

export function Mascot({
  pose = "friendly",
  size = 160,
  float = true,
  className = "",
}: {
  pose?: Pose;
  size?: number;
  float?: boolean;
  className?: string;
}) {
  return (
    <motion.img
      key={pose}
      src={assetUrl(`/brand/character-${pose}.svg`)}
      alt=""
      width={size}
      height={size}
      draggable={false}
      initial={{ scale: 0.7, opacity: 0, rotate: -6 }}
      animate={{
        scale: 1,
        opacity: 1,
        rotate: 0,
        y: float ? [0, -10, 0] : 0,
      }}
      transition={{
        scale: { type: "spring", stiffness: 260, damping: 18 },
        opacity: { duration: 0.3 },
        y: { duration: 3.2, repeat: Infinity, ease: "easeInOut" },
      }}
      className={`select-none drop-shadow-[0_18px_30px_rgba(0,0,0,0.45)] ${className}`}
    />
  );
}

type Variant = "primary" | "accent" | "danger" | "ghost";

/** Arcade button with pixel-cut corners + retro press effect. */
export function Btn({
  variant = "primary",
  icon,
  size = "md",
  className = "",
  children,
  ...rest
}: {
  variant?: Variant;
  icon?: IconName;
  size?: "sm" | "md";
} & ButtonHTMLAttributes<HTMLButtonElement>) {
  return (
    <button
      className={`btn btn-${variant} ${size === "sm" ? "btn-sm" : ""} pixel ${className}`}
      {...rest}
    >
      {icon && <Icon name={icon} size={size === "sm" ? 12 : 14} />}
      {children}
    </button>
  );
}

export function Chip({
  children,
  color = "rgba(244,241,233,0.6)",
  active = false,
  className = "",
  ...rest
}: {
  children: ReactNode;
  color?: string;
  active?: boolean;
} & ButtonHTMLAttributes<HTMLButtonElement>) {
  return (
    <button
      className={`pixel-sm px-2.5 sm:px-3 py-1 sm:py-1.5 font-mono text-[10px] sm:text-[11px] uppercase tracking-wider whitespace-nowrap transition ${className}`}
      style={{
        background: active ? `${color}2e` : "rgba(244,241,233,0.05)",
        color: active ? color : "rgba(244,241,233,0.6)",
        boxShadow: active
          ? `inset 0 0 0 2px ${color}`
          : "inset 0 0 0 1px rgba(244,241,233,0.12)",
      }}
      {...rest}
    >
      {children}
    </button>
  );
}

export function Reveal({
  children,
  delay = 0,
  className = "",
  ...rest
}: { children: ReactNode; delay?: number } & HTMLMotionProps<"div">) {
  return (
    <motion.div
      initial={{ opacity: 0, y: 32 }}
      whileInView={{ opacity: 1, y: 0 }}
      viewport={{ once: true, margin: "-80px" }}
      transition={{ duration: 0.7, delay, ease: [0.22, 1, 0.36, 1] }}
      className={className}
      {...rest}
    >
      {children}
    </motion.div>
  );
}

export function SectionHead({
  kicker,
  title,
  sub,
  pose,
}: {
  kicker?: string;
  title: string;
  sub?: string;
  pose?: Pose;
}) {
  return (
    <Reveal className="mb-12 flex items-end justify-between gap-6">
      <div>
        {kicker && (
          <div className="pixel-label mb-3 flex items-center gap-2 text-gold">
            <span className="inline-block h-2 w-2 bg-gold" />
            {kicker}
          </div>
        )}
        <h2 className="display text-4xl leading-none text-cream md:text-6xl">{title}</h2>
        {sub && <p className="mt-3 max-w-xl text-sm text-cream/60 md:text-base">{sub}</p>}
      </div>
      {pose && <Mascot pose={pose} size={110} className="hidden sm:block" />}
    </Reveal>
  );
}

/** Flat 2D Wiimote used in the lab cards. Shakes when `rumble` is true. */
export function WiimoteSVG({
  health = 100,
  rumble = false,
  strength = 1,
  className = "",
}: {
  health?: number;
  rumble?: boolean;
  strength?: number;
  className?: string;
}) {
  const leds = ledsFromHealth(health);
  const a = 4 * strength;
  return (
    <motion.svg
      viewBox="0 0 60 220"
      className={className}
      animate={
        rumble
          ? { x: [0, -a, a, -a, a, 0], rotate: [0, -2 * strength, 2 * strength, 0] }
          : { x: 0, rotate: 0 }
      }
      transition={{ duration: 0.18, repeat: rumble ? Infinity : 0 }}
    >
      <defs>
        <filter id="ledGlow" x="-100%" y="-100%" width="300%" height="300%">
          <feGaussianBlur stdDeviation="2.5" result="b" />
          <feMerge>
            <feMergeNode in="b" />
            <feMergeNode in="SourceGraphic" />
          </feMerge>
        </filter>
      </defs>
      <rect x="4" y="4" width="52" height="212" rx="12" fill="#f4f1e9" stroke="#0b1b23" strokeWidth="3" />
      <circle cx="16" cy="22" r="3.5" fill="#ff4b3a" />
      {/* d-pad */}
      <rect x="20" y="44" width="20" height="7" rx="1.5" fill="#1a2630" />
      <rect x="26.5" y="37.5" width="7" height="20" rx="1.5" fill="#1a2630" />
      {/* A */}
      <circle cx="30" cy="78" r="8" fill="#1a2630" />
      {/* - home + */}
      <circle cx="18" cy="100" r="3.2" fill="#1a2630" />
      <circle cx="30" cy="100" r="4" fill="#243440" />
      <circle cx="42" cy="100" r="3.2" fill="#1a2630" />
      {/* speaker */}
      {Array.from({ length: 9 }).map((_, i) => (
        <circle key={i} cx={24 + (i % 3) * 6} cy={118 + Math.floor(i / 3) * 6} r="1.4" fill="#9aa4aa" />
      ))}
      {/* 1 2 */}
      <circle cx="30" cy="150" r="5.5" fill="#1a2630" />
      <circle cx="30" cy="168" r="5.5" fill="#1a2630" />
      {/* LEDs */}
      {leds.map((on, i) => (
        <rect
          key={i}
          x={12 + i * 10}
          y="196"
          width="6"
          height="4"
          rx="1"
          fill={on ? "#3ddc84" : "#2a3a44"}
          filter={on ? "url(#ledGlow)" : undefined}
        />
      ))}
    </motion.svg>
  );
}

export function Card({
  children,
  className = "",
}: {
  children: ReactNode;
  className?: string;
}) {
  return (
    <div className={`panel pixel relative p-6 ${className}`}>{children}</div>
  );
}
