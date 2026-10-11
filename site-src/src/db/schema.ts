import {
  integer,
  pgTable,
  serial,
  text,
  timestamp,
  varchar,
} from "drizzle-orm/pg-core";

export const feedback = pgTable("feedback", {
  id: serial("id").primaryKey(),
  name: varchar("name", { length: 60 }).notNull(),
  message: text("message").notNull(),
  kind: varchar("kind", { length: 16 }).notNull().default("praise"),
  rating: integer("rating").notNull().default(5),
  lang: varchar("lang", { length: 2 }).notNull().default("de"),
  createdAt: timestamp("created_at", { withTimezone: true })
    .notNull()
    .defaultNow(),
});

export const reactions = pgTable("reactions", {
  id: serial("id").primaryKey(),
  emoji: varchar("emoji", { length: 16 }).notNull().unique(),
  count: integer("count").notNull().default(0),
});

export type Feedback = typeof feedback.$inferSelect;
export type Reaction = typeof reactions.$inferSelect;
