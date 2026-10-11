import type { ReactNode } from "react";
import { notFound } from "next/navigation";
import { LANGS, isLang } from "@/i18n/dictionaries";
import { LangProvider } from "@/i18n/LangProvider";
import { Header } from "@/components/Header";
import { Footer } from "@/components/Footer";

export function generateStaticParams() {
  return LANGS.map((lang) => ({ lang }));
}

export default async function LangLayout({
  children,
  params,
}: {
  children: ReactNode;
  params: Promise<{ lang: string }>;
}) {
  const { lang } = await params;
  if (!isLang(lang)) notFound();

  return (
    <LangProvider lang={lang}>
      <Header />
      <main className="relative">{children}</main>
      <Footer />
    </LangProvider>
  );
}
