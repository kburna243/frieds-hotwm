"use client";

import { useLang } from "@/i18n/LangProvider";
import { REPO } from "@/i18n/dictionaries";
import { Icon } from "@/components/Icon";

export function Footer() {
  const { t } = useLang();
  return (
    <footer className="relative border-t border-cream/10 bg-deep/60">
      <div className="mx-auto flex max-w-7xl flex-col items-center gap-6 px-5 py-12 md:flex-row md:justify-between">
        <div className="flex items-center gap-4">
          <img src="/brand/character-winking.svg" alt="" className="h-16 w-16" />
          <div>
            <div className="pixel-label text-gold">FRIED’S</div>
            <div className="display text-2xl leading-none">HotWM</div>
            <div className="font-mono text-[11px] text-cream/50">{t.footer.license}</div>
          </div>
        </div>
        <div className="flex flex-col items-center gap-2 text-sm text-cream/60 md:items-end">
          <a
            href={REPO}
            className="flex items-center gap-2 font-mono text-xs text-cream/70 transition hover:text-gold"
            target="_blank"
            rel="noreferrer"
          >
            <Icon name="github" size={16} /> github.com/kburna243/frieds-hotwm
          </a>
          <span className="font-mono text-[11px] text-cream/40">{t.footer.made}</span>
        </div>
      </div>
    </footer>
  );
}
