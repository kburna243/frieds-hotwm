import { Hero } from "@/components/sections/Hero";
import { SignalFlow } from "@/components/sections/SignalFlow";
import { HapticsLab } from "@/components/sections/HapticsLab";
import { Setup } from "@/components/sections/Setup";
import { Ecosystem } from "@/components/sections/Ecosystem";
import { Feedback } from "@/components/sections/Feedback";

export default function LangPage() {
  return (
    <>
      <Hero />
      <SignalFlow />
      <HapticsLab />
      <Setup />
      <Ecosystem />
      <Feedback />
    </>
  );
}
