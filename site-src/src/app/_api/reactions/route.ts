import { NextResponse } from "next/server";
import { sql } from "drizzle-orm";
import { db } from "@/db";
import { reactions } from "@/db/schema";
import { REACTION_IDS } from "@/lib/constants";

export const dynamic = "force-dynamic";

export async function GET() {
  const counts: Record<string, number> = {
    flame: 42,
    burst: 28,
    target: 35,
    rumble: 19,
    gamepad: 51,
  };
  if (!db) {
    return NextResponse.json(counts);
  }
  try {
    const rows = await db.select().from(reactions);
    for (const r of rows) {
      if (r.emoji in counts) counts[r.emoji] = r.count;
    }
  } catch {
    /* fallback to defaults */
  }
  return NextResponse.json(counts);
}

export async function POST(req: Request) {
  let body: { emoji?: string };
  try {
    body = await req.json();
  } catch {
    return NextResponse.json({ error: "invalid json" }, { status: 400 });
  }
  const id = body.emoji ?? "";
  if (!REACTION_IDS.includes(id)) {
    return NextResponse.json({ error: "unknown reaction" }, { status: 400 });
  }

  if (!db) {
    return NextResponse.json({ emoji: id, count: 1 });
  }

  try {
    const [row] = await db
      .insert(reactions)
      .values({ emoji: id, count: 1 })
      .onConflictDoUpdate({
        target: reactions.emoji,
        set: { count: sql`${reactions.count} + 1` },
      })
      .returning();

    return NextResponse.json(row);
  } catch {
    return NextResponse.json({ emoji: id, count: 1 });
  }
}

