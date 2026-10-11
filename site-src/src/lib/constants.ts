import type { IconName } from "@/components/Icon";

export const REACTIONS: { id: string; icon: IconName; emoji: string }[] = [
  { id: "flame", icon: "flame", emoji: "🔥" },
  { id: "burst", icon: "burst", emoji: "💥" },
  { id: "target", icon: "target", emoji: "🎯" },
  { id: "rumble", icon: "vibrate", emoji: "📳" },
  { id: "gamepad", icon: "gamepad", emoji: "🕹️" },
];

export const REACTION_IDS = REACTIONS.map((r) => r.id);

export type FeedbackKind = "setup" | "idea" | "bug" | "question";
export const KINDS: FeedbackKind[] = ["setup", "idea", "bug", "question"];

export const KIND_ICON: Record<FeedbackKind, IconName> = {
  setup: "wrench",
  idea: "bulb",
  bug: "bug",
  question: "question",
};

export const KIND_COLOR: Record<FeedbackKind, string> = {
  setup: "#00b8ff",
  idea: "#ffc857",
  bug: "#ff4b3a",
  question: "#3ddc84",
};
