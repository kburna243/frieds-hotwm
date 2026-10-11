"use client";

import { createContext, useContext, type ReactNode } from "react";
import { dictionaries, type Dict, type Lang } from "./dictionaries";

const LangContext = createContext<{ lang: Lang; t: Dict }>({
  lang: "de",
  t: dictionaries.de,
});

export function LangProvider({
  lang,
  children,
}: {
  lang: Lang;
  children: ReactNode;
}) {
  return (
    <LangContext.Provider value={{ lang, t: dictionaries[lang] }}>
      {children}
    </LangContext.Provider>
  );
}

export function useLang() {
  return useContext(LangContext);
}
