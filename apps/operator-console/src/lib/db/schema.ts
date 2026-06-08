import {
  type AnyPgColumn,
  bigint,
  bigserial,
  check,
  foreignKey,
  index,
  integer,
  jsonb,
  pgTable,
  text,
  timestamp,
  unique,
  uniqueIndex,
  uuid,
} from "drizzle-orm/pg-core";
import type { PgTableExtraConfigValue } from "drizzle-orm/pg-core";
import { sql } from "drizzle-orm";

export const ticketStatusValues = [
  "open",
  "closed",
  "awaiting_staff",
  "awaiting_customer",
  "pending_reactivation",
  "resolved",
  "abandoned",
] as const;

export const messageDirectionValues = ["inbound", "outbound"] as const;
export const messageSenderRoleValues = ["customer", "system", "staff"] as const;
export const inboundMessageTypeValues = [
  "text",
  "media",
  "unsupported",
  "unknown",
] as const;
export const staffMessageRoleValues = [
  "notification",
  "reply",
  "system",
] as const;

export type TicketStatus = (typeof ticketStatusValues)[number];
export type MessageDirection = (typeof messageDirectionValues)[number];
export type MessageSenderRole = (typeof messageSenderRoleValues)[number];
export type InboundMessageType = (typeof inboundMessageTypeValues)[number];
export type StaffMessageRole = (typeof staffMessageRoleValues)[number];

export const customers = pgTable(
  "customers",
  {
    id: uuid("id").defaultRandom().primaryKey().notNull(),
    phone: text("phone").notNull(),
    displayName: text("display_name"),
    firstSeenAt: timestamp("first_seen_at", {
      withTimezone: true,
      mode: "string",
    }).defaultNow().notNull(),
    lastSeenAt: timestamp("last_seen_at", {
      withTimezone: true,
      mode: "string",
    }).defaultNow().notNull(),
    metadataJson: jsonb("metadata_json").default({}).notNull(),
  },
  (table) => [unique("customers_phone_key").on(table.phone)],
);

export const messages = pgTable(
  "messages",
  {
    id: uuid("id").defaultRandom().primaryKey().notNull(),
    customerId: uuid("customer_id").notNull(),
    ticketId: text("ticket_id"),
    direction: text("direction", { enum: messageDirectionValues }).notNull(),
    channel: text("channel").default("whatsapp").notNull(),
    provider: text("provider").default("twilio").notNull(),
    providerMessageId: text("provider_message_id"),
    senderRole: text("sender_role", { enum: messageSenderRoleValues }).notNull(),
    messageType: text("message_type").default("text").notNull(),
    bodyText: text("body_text"),
    payloadJson: jsonb("payload_json").default({}).notNull(),
    status: text("status").default("accepted").notNull(),
    createdAt: timestamp("created_at", {
      withTimezone: true,
      mode: "string",
    }).defaultNow().notNull(),
    deliveredAt: timestamp("delivered_at", {
      withTimezone: true,
      mode: "string",
    }),
    failedAt: timestamp("failed_at", {
      withTimezone: true,
      mode: "string",
    }),
    idempotencyKey: text("idempotency_key"),
  },
  (table): PgTableExtraConfigValue[] => [
    index("idx_messages_customer_created_at").on(
      table.customerId,
      table.createdAt,
    ),
    index("idx_messages_ticket_created_at").on(table.ticketId, table.createdAt),
    foreignKey({
      columns: [table.customerId],
      foreignColumns: [customers.id],
      name: "messages_customer_id_fkey",
    }).onDelete("restrict"),
    foreignKey({
      columns: [table.ticketId],
      foreignColumns: [tickets.ticketId as AnyPgColumn],
      name: "messages_ticket_id_fkey",
    }).onDelete("set null"),
    unique("messages_provider_message_id_key").on(table.providerMessageId),
    check(
      "messages_direction_check",
      sql`direction = ANY (ARRAY['inbound'::text, 'outbound'::text])`,
    ),
    check(
      "messages_sender_role_check",
      sql`sender_role = ANY (ARRAY['customer'::text, 'system'::text, 'staff'::text])`,
    ),
  ],
);

export const inboundRaw = pgTable(
  "inbound_raw",
  {
    id: bigserial("id", { mode: "bigint" }).primaryKey().notNull(),
    provider: text("provider").default("twilio").notNull(),
    channel: text("channel").default("whatsapp").notNull(),
    providerMessageId: text("provider_message_id").notNull(),
    rawPayload: jsonb("raw_payload").notNull(),
    payloadForm: jsonb("payload_form").default({}).notNull(),
    twilioSignature: text("twilio_signature"),
    fromAddress: text("from_address").notNull(),
    toAddress: text("to_address").notNull(),
    bodyText: text("body_text"),
    numMedia: integer("num_media").default(0).notNull(),
    messageType: text("message_type", { enum: inboundMessageTypeValues })
      .notNull(),
    receivedAt: timestamp("received_at", {
      withTimezone: true,
      mode: "string",
    }).defaultNow().notNull(),
    processedAt: timestamp("processed_at", {
      withTimezone: true,
      mode: "string",
    }),
  },
  (table): PgTableExtraConfigValue[] => [
    index("idx_inbound_raw_received_at").on(table.receivedAt),
    unique("inbound_raw_provider_message_id_key").on(table.providerMessageId),
    check(
      "inbound_raw_message_type_check",
      sql`message_type = ANY (ARRAY['text'::text, 'media'::text, 'unsupported'::text, 'unknown'::text])`,
    ),
  ],
);

export const tickets = pgTable(
  "tickets",
  {
    ticketId: text("ticket_id").primaryKey().notNull(),
    customerId: uuid("customer_id").notNull(),
    intent: text("intent").notNull(),
    status: text("status", { enum: ticketStatusValues })
      .default("open")
      .notNull(),
    summary: text("summary"),
    contextJson: jsonb("context_json").default({}).notNull(),
    pendingFreeForm: text("pending_free_form"),
    pendingFreeFormStaffId: text("pending_free_form_staff_id"),
    pendingFreeFormAt: timestamp("pending_free_form_at", {
      withTimezone: true,
      mode: "string",
    }),
    reactivationAttempts: integer("reactivation_attempts").default(0).notNull(),
    lastCustomerMessageAt: timestamp("last_customer_message_at", {
      withTimezone: true,
      mode: "string",
    }),
    lastStaffReplyAt: timestamp("last_staff_reply_at", {
      withTimezone: true,
      mode: "string",
    }),
    lastTemplateSentAt: timestamp("last_template_sent_at", {
      withTimezone: true,
      mode: "string",
    }),
    createdAt: timestamp("created_at", {
      withTimezone: true,
      mode: "string",
    }).defaultNow().notNull(),
    updatedAt: timestamp("updated_at", {
      withTimezone: true,
      mode: "string",
    }).defaultNow().notNull(),
    resolvedAt: timestamp("resolved_at", {
      withTimezone: true,
      mode: "string",
    }),
    sourceInboundRawId: bigint("source_inbound_raw_id", { mode: "number" }),
    sourceMessageId: uuid("source_message_id"),
    subject: text("subject"),
    closedAt: timestamp("closed_at", {
      withTimezone: true,
      mode: "string",
    }),
    closedByStaffId: text("closed_by_staff_id"),
  },
  (table) => [
    uniqueIndex("idx_tickets_one_active_per_customer")
      .on(table.customerId)
      .where(
        sql`status = ANY (ARRAY['open'::text, 'awaiting_staff'::text, 'awaiting_customer'::text, 'pending_reactivation'::text])`,
      ),
    index("idx_tickets_status_created_at").on(table.status, table.createdAt),
    foreignKey({
      columns: [table.customerId],
      foreignColumns: [customers.id],
      name: "tickets_customer_id_fkey",
    }).onDelete("restrict"),
    foreignKey({
      columns: [table.sourceInboundRawId],
      foreignColumns: [inboundRaw.id],
      name: "tickets_source_inbound_raw_id_fkey",
    }).onDelete("restrict"),
    foreignKey({
      columns: [table.sourceMessageId],
      foreignColumns: [messages.id as AnyPgColumn],
      name: "tickets_source_message_id_fkey",
    }).onDelete("set null"),
    check(
      "tickets_status_check",
      sql`status = ANY (ARRAY['open'::text, 'closed'::text, 'awaiting_staff'::text, 'awaiting_customer'::text, 'pending_reactivation'::text, 'resolved'::text, 'abandoned'::text])`,
    ),
  ],
);

export const staffInboundRaw = pgTable(
  "staff_inbound_raw",
  {
    id: bigserial("id", { mode: "bigint" }).primaryKey().notNull(),
    provider: text("provider").default("telegram").notNull(),
    telegramUpdateId: bigint("telegram_update_id", { mode: "number" })
      .notNull(),
    rawPayload: jsonb("raw_payload").notNull(),
    chatId: bigint("chat_id", { mode: "number" }),
    fromId: bigint("from_id", { mode: "number" }),
    replyToMessageId: bigint("reply_to_message_id", { mode: "number" }),
    commandText: text("command_text"),
    receivedAt: timestamp("received_at", {
      withTimezone: true,
      mode: "string",
    }).defaultNow().notNull(),
    processedAt: timestamp("processed_at", {
      withTimezone: true,
      mode: "string",
    }),
  },
  (table) => [
    index("idx_staff_inbound_raw_received_at").on(table.receivedAt),
    unique("staff_inbound_raw_telegram_update_id_key").on(table.telegramUpdateId),
  ],
);

export const staffMessages = pgTable(
  "staff_messages",
  {
    id: bigserial("id", { mode: "bigint" }).primaryKey().notNull(),
    ticketId: text("ticket_id")
      .notNull()
      .references(() => tickets.ticketId, { onDelete: "cascade" }),
    telegramChatId: bigint("telegram_chat_id", { mode: "number" }).notNull(),
    telegramMessageId: bigint("telegram_message_id", { mode: "number" })
      .notNull(),
    messageRole: text("message_role", { enum: staffMessageRoleValues })
      .default("notification")
      .notNull(),
    bodyText: text("body_text"),
    payloadJson: jsonb("payload_json").default({}).notNull(),
    createdAt: timestamp("created_at", {
      withTimezone: true,
      mode: "string",
    }).defaultNow().notNull(),
  },
  (table) => [
    unique("staff_messages_telegram_chat_id_telegram_message_id_key").on(
      table.telegramChatId,
      table.telegramMessageId,
    ),
    check(
      "staff_messages_message_role_check",
      sql`message_role = ANY (ARRAY['notification'::text, 'reply'::text, 'system'::text])`,
    ),
  ],
);

export const eventLog = pgTable(
  "event_log",
  {
    id: bigserial("id", { mode: "bigint" }).primaryKey().notNull(),
    type: text("type").notNull(),
    ticketId: text("ticket_id").references(() => tickets.ticketId, {
      onDelete: "set null",
    }),
    customerId: uuid("customer_id").references(() => customers.id, {
      onDelete: "set null",
    }),
    payloadJson: jsonb("payload_json").default({}).notNull(),
    createdAt: timestamp("created_at", {
      withTimezone: true,
      mode: "string",
    }).defaultNow().notNull(),
  },
  (table) => [
    index("idx_event_log_customer_created_at").on(
      table.customerId,
      table.createdAt,
    ),
    index("idx_event_log_ticket_created_at").on(table.ticketId, table.createdAt),
  ],
);

export const configSettings = pgTable("config_settings", {
  key: text("key").primaryKey().notNull(),
  value: jsonb("value").notNull(),
  description: text("description"),
  updatedAt: timestamp("updated_at", {
    withTimezone: true,
    mode: "string",
  }).defaultNow().notNull(),
});
