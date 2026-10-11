import { NextResponse } from "next/server";
import { desc } from "drizzle-orm";
import { db } from "@/db";
import { feedback } from "@/db/schema";

export const dynamic = "force-dynamic";

const KINDS = ["setup", "idea", "bug", "question"] as const;

export async function GET() {
  if (!db) {
    return NextResponse.json([
      {
        id: 1,
        name: "RetroArcadeFan",
        message: "Der Puls-Strecker auf 150ms macht Wiimote-Recoil in Time Crisis endlich richtig spürbar!",
        kind: "setup",
        rating: 5,
        lang: "de",
        createdAt: new Date().toISOString(),
      },
      {
        id: 2,
        name: "GunmoteUser99",
        message: "LEDs als Lebensbalken funktionieren 1A in TeknoParrot. Großes Lob an Fried!",
        kind: "idea",
        rating: 5,
        lang: "de",
        createdAt: new Date().toISOString(),
      },
    ]);
  }
  try {
    const rows = await db.select().from(feedback).orderBy(desc(feedback.createdAt)).limit(60);
    return NextResponse.json(rows);
  } catch {
    return NextResponse.json([]);
  }
}

export async function POST(req: Request) {
  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return NextResponse.json({ error: "invalid json" }, { status: 400 });
  }

  const name = String(body.name ?? "").trim().slice(0, 60);
  const message = String(body.message ?? "").trim().slice(0, 600);
  const kind = KINDS.includes(body.kind as (typeof KINDS)[number])
    ? String(body.kind)
    : "setup";
  const rating = Math.min(5, Math.max(1, Number(body.rating) || 5));
  const lang = body.lang === "en" ? "en" : "de";

  if (!name || !message) {
    return NextResponse.json({ error: "name and message required" }, { status: 400 });
  }

  if (!db) {
    return NextResponse.json(
      {
        id: Date.now(),
        name,
        message,
        kind,
        rating,
        lang,
        createdAt: new Date().toISOString(),
      },
      { status: 201 },
    );
  }

  try {
    const [row] = await db
      .insert(feedback)
      .values({ name, message, kind, rating, lang })
      .returning();

    return NextResponse.json(row, { status: 201 });
  } catch {
    return NextResponse.json(
      {
        id: Date.now(),
        name,
        message,
        kind,
        rating,
        lang,
        createdAt: new Date().toISOString(),
      },
      { status: 201 },
    );
  }
}

