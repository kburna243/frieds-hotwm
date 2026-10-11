"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { motion, useScroll, useTransform } from "framer-motion";
import { useLang } from "@/i18n/LangProvider";
import { RELEASE, VERSION, type Lang } from "@/i18n/dictionaries";
import { assetUrl } from "@/lib/asset";
import { Icon } from "@/components/Icon";

export function Header() {
  const { lang, t } = useLang();
  const pathname = usePathname();
  const { scrollY } = useScroll();
  const bg = useTransform(scrollY, [0, 120], ["rgba(11,24,35,0)", "rgba(11,24,35,0.85)"]);
  const other: Lang = lang === "de" ? "en" : "de";
  const switchHref = pathname.replace(/^\/(de|en)/, `/${other}`) || `/${other}`;

  const links: [string, string][] = [
    ["#flow", t.nav.flow],
    ["#lab", t.nav.lab],
    ["#setup", t.nav.setup],
    ["#ecosystem", t.nav.ecosystem],
    ["#feedback", t.nav.feedback],
  ];

  return (
    <motion.header
      style={{ backgroundColor: bg }}
      className="fixed inset-x-0 top-0 z-40 backdrop-blur-md border-b border-cream/5"
    >
      <div className="mx-auto flex max-w-7xl items-center justify-between gap-4 px-5 py-3">
        <Link href={`/${lang}`} className="flex items-center gap-3">
          <motion.img
            src={assetUrl("/brand/character-friendly.svg")}
            alt="Fried"
            className="h-10 w-10 shrink-0"
            whileHover={{ rotate: [0, -8, 8, 0] }}
            transition={{ duration: 0.5 }}
          />
          <div className="leading-tight">
            <div className="pixel-label text-gold">FRIED’S</div>
            <div className="display text-2xl leading-none">
              HotWM{" "}
              <span className="pixel-sm ml-1.5 align-middle bg-mint/15 px-2 py-0.5 font-mono text-[9px] tracking-wider text-mint whitespace-nowrap">
                {VERSION}
              </span>
            </div>
          </div>
        </Link>

        <nav className="hidden items-center gap-1 md:flex">
          {links.map(([href, label]) => (
            <a
              key={href}
              href={href}
              className="pixel-sm px-3 py-2 font-mono text-[11px] uppercase tracking-wider text-cream/60 transition hover:bg-gold/10 hover:text-gold"
            >
              {label}
            </a>
          ))}
        </nav>

        <div className="flex items-center gap-2">
          <Link
            href={switchHref}
            className="pixel-sm flex items-center gap-1 bg-cream/5 p-1 text-xs font-bold"
            aria-label="Switch language"
          >
            <span
              className={`pixel-sm px-2.5 py-1 transition ${
                lang === "de" ? "bg-gold text-deep" : "text-cream/60"
              }`}
            >
              DE
            </span>
            <span
              className={`pixel-sm px-2.5 py-1 transition ${
                lang === "en" ? "bg-gold text-deep" : "text-cream/60"
              }`}
            >
              EN
            </span>
          </Link>
          <a
            href={RELEASE}
            target="_blank"
            rel="noreferrer"
            className="btn btn-primary btn-sm pixel hidden sm:inline-flex"
          >
            <Icon name="download" size={12} /> {t.nav.download}
          </a>
        </div>
      </div>
    </motion.header>
  );
}
