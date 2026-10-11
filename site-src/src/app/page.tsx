"use client";

import { useEffect } from "react";
import { useRouter } from "next/navigation";
import { assetUrl } from "@/lib/asset";

export default function RootPage() {
  const router = useRouter();

  useEffect(() => {
    router.replace("/de");
  }, [router]);

  return (
    <div className="flex min-h-screen items-center justify-center bg-[#0b1823] p-5 text-center font-mono text-sm text-[#f4f1e9]">
      <meta httpEquiv="refresh" content={`0;url=${assetUrl("/de")}`} />
      <div>
        <div className="h-8 w-8 mx-auto mb-4 animate-spin rounded-full border-2 border-[#3ddc84] border-t-transparent" />
        <p className="text-cream/80">Weiterleitung zu Fried’s HotWM...</p>
        <p className="mt-3">
          <a href={assetUrl("/de")} className="text-[#3ddc84] underline underline-offset-4">
            Hier klicken, falls die Weiterleitung nicht automatisch startet
          </a>
        </p>
      </div>
    </div>
  );
}
