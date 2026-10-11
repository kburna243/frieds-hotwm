"use client";

import { useEffect, useState } from "react";
import { create } from "zustand";

type HapticState = {
  /** Timestamp (ms) until which the Wiimote should rumble. */
  rumbleUntil: number;
  /** Strength 0..1 of the current rumble. */
  rumbleStrength: number;
  /** Health 0..100 → LED life bar. */
  health: number;
  /** Global hold time (ms) – the "stretched" pulse length. */
  holdMs: number;
  /** Total shots fired this session (for fun). */
  shots: number;
  fire: (ms?: number, strength?: number) => void;
  setHealth: (h: number) => void;
  setHoldMs: (ms: number) => void;
};

export const useHaptics = create<HapticState>((set, get) => ({
  rumbleUntil: 0,
  rumbleStrength: 1,
  health: 100,
  holdMs: 150,
  shots: 0,
  fire: (ms, strength = 1) => {
    const hold = ms ?? get().holdMs;
    set((s) => ({
      rumbleUntil: performance.now() + hold,
      rumbleStrength: strength,
      shots: s.shots + 1,
    }));
  },
  setHealth: (health) => set({ health: Math.max(0, Math.min(100, health)) }),
  setHoldMs: (holdMs) => set({ holdMs: Math.max(80, Math.min(300, holdMs)) }),
}));

/** True while the Wiimote is currently rumbling (polled per frame). */
export function useRumbling(): boolean {
  const [on, setOn] = useState(false);
  useEffect(() => {
    let raf = 0;
    const tick = () => {
      const now = performance.now();
      const next = now < useHaptics.getState().rumbleUntil;
      setOn((prev) => (prev === next ? prev : next));
      raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  }, []);
  return on;
}

/** 4 LEDs lit from health %, same scaling as the relay's life bar. */
export function ledsFromHealth(health: number): boolean[] {
  const lit = health <= 0 ? 0 : Math.max(1, Math.ceil((health / 100) * 4));
  return [0, 1, 2, 3].map((i) => i < lit);
}
