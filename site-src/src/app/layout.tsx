import type { Metadata } from "next";
import type { ReactNode } from "react";
import {
  Bangers,
  Inter,
  JetBrains_Mono,
  Press_Start_2P,
} from "next/font/google";
import { assetUrl } from "@/lib/asset";
import "./globals.css";

const bangers = Bangers({
  weight: "400",
  subsets: ["latin"],
  variable: "--font-bangers",
  display: "swap",
});
const press = Press_Start_2P({
  weight: "400",
  subsets: ["latin"],
  variable: "--font-press",
  display: "swap",
});
const inter = Inter({
  subsets: ["latin"],
  variable: "--font-inter",
  display: "swap",
});
const jb = JetBrains_Mono({
  subsets: ["latin"],
  variable: "--font-jb",
  display: "swap",
});

export const metadata: Metadata = {
  title: "Fried’s HotWM – Hook of the Wiimote",
  description:
    "Recoil rumble & LED haptics relay for Gunmote and Wiimotes. Rückstoß-Rumble & LED-Haptik für Wiimotes hinter Gunmote.",
  icons: {
    icon: assetUrl("/brand/character-friendly.svg"),
  },
};

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html
      lang="de"
      suppressHydrationWarning
      className={`${bangers.variable} ${press.variable} ${inter.variable} ${jb.variable}`}
    >
      <body className="crt antialiased">{children}</body>
    </html>
  );
}
