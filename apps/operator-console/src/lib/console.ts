import type { TicketStatus } from "@/lib/db/schema";

export const openTicketStatuses: TicketStatus[] = [
  "open",
  "awaiting_staff",
  "awaiting_customer",
  "pending_reactivation",
];

export const intentColorMap: Record<string, string> = {
  purchase: "border-emerald-500/30 bg-emerald-500/15 text-emerald-300",
  order_status: "border-sky-500/30 bg-sky-500/15 text-sky-300",
  support_issue: "border-amber-500/30 bg-amber-500/15 text-amber-300",
  request_report: "border-violet-500/30 bg-violet-500/15 text-violet-300",
};

export function getTicketStatusVariant(status: TicketStatus) {
  switch (status) {
    case "open":
      return "info";
    case "awaiting_staff":
      return "warning";
    case "awaiting_customer":
      return "secondary";
    case "pending_reactivation":
      return "outline";
    case "resolved":
      return "success";
    case "abandoned":
      return "danger";
    case "closed":
      return "secondary";
    default:
      return "outline";
  }
}

export function maskPhone(phone: string) {
  const [prefix, rawValue] = phone.includes(":")
    ? phone.split(":", 2)
    : [null, phone];
  const value = rawValue ?? phone;

  if (value.length <= 7) {
    return prefix ? `${prefix}:${value}` : value;
  }

  const masked = `${value.slice(0, 3)}****${value.slice(-4)}`;
  return prefix ? `${prefix}:${masked}` : masked;
}

export function formatTimestamp(value: string | null | undefined) {
  if (!value) {
    return "—";
  }

  return new Intl.DateTimeFormat("en-US", {
    month: "short",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit",
  }).format(new Date(value));
}

export function formatAgeDays(value: string) {
  const createdAt = new Date(value).getTime();
  const now = Date.now();
  const ageInDays = Math.max(
    0,
    Math.floor((now - createdAt) / (1000 * 60 * 60 * 24)),
  );

  return `${ageInDays}d`;
}

export function redactSensitiveText(value: string) {
  return value.replace(/whatsapp:\+\d{7,}/g, (match) => maskPhone(match));
}

export type EventFamily = "all" | "dispatch" | "send" | "staff" | "config" | "other";

export function getEventFamily(eventType: string): EventFamily {
  if (eventType === "intent_classified" || eventType === "auto_reply_requested") {
    return "dispatch";
  }

  if (eventType.startsWith("whatsapp_send_")) {
    return "send";
  }

  if (eventType.startsWith("staff_") || eventType.startsWith("ticket_")) {
    return "staff";
  }

  if (eventType === "config_changed" || eventType === "customer_id_revealed") {
    return "config";
  }

  return "other";
}

export function getEventFamilyClasses(family: EventFamily) {
  switch (family) {
    case "dispatch":
      return "border-violet-500/30 bg-violet-500/15 text-violet-300";
    case "send":
      return "border-sky-500/30 bg-sky-500/15 text-sky-300";
    case "staff":
      return "border-amber-500/30 bg-amber-500/15 text-amber-300";
    case "config":
      return "border-emerald-500/30 bg-emerald-500/15 text-emerald-300";
    default:
      return "border-zinc-700 bg-zinc-900 text-zinc-200";
  }
}
