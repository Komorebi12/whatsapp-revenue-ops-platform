import { defineConfig } from "drizzle-kit";

export default defineConfig({
  dialect: "postgresql",
  dbCredentials: {
    url: process.env.DATABASE_URL ?? "",
  },
  out: "./src/lib/db",
  schemaFilter: ["public"],
  tablesFilter: [
    "config_settings",
    "customers",
    "event_log",
    "inbound_raw",
    "messages",
    "staff_inbound_raw",
    "staff_messages",
    "tickets",
  ],
  verbose: true,
  strict: true,
});
