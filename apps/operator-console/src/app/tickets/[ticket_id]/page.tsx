import { auth } from "@clerk/nextjs/server";
import { and, desc, eq, inArray, sql } from "drizzle-orm";
import Link from "next/link";
import { notFound } from "next/navigation";
import { Badge } from "@/components/ui/badge";
import { buttonVariants } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import {
  formatTimestamp,
  getTicketStatusVariant,
  maskPhone,
  redactSensitiveText,
} from "@/lib/console";
import { db } from "@/lib/db";
import { customers, eventLog, messages, tickets } from "@/lib/db/schema";
import { cn } from "@/lib/utils";
import { ReplyForm } from "./reply-form";

const conversationTimelineTypes = [
  "intent_classified",
  "ticket_created",
  "staff_notification_sent",
  "staff_reply_relayed",
  "whatsapp_send_failed",
] as const;

type PageProps = {
  params: Promise<{
    ticket_id: string;
  }>;
  searchParams: Promise<{
    reveal?: string;
  }>;
};

export default async function TicketConversationPage({
  params,
  searchParams,
}: PageProps) {
  const { ticket_id: ticketId } = await params;
  const { reveal: revealParam } = await searchParams;
  const phoneVisible = revealParam === "1";

  const [ticket, conversationMessages, recentEvents] = await Promise.all([
    db
      .select({
        ticketId: tickets.ticketId,
        customerId: tickets.customerId,
        intent: tickets.intent,
        status: tickets.status,
        createdAt: tickets.createdAt,
        customerPhone: customers.phone,
        displayName: customers.displayName,
      })
      .from(tickets)
      .innerJoin(customers, eq(tickets.customerId, customers.id))
      .where(eq(tickets.ticketId, ticketId))
      .limit(1),
    db
      .select({
        id: messages.id,
        direction: messages.direction,
        senderRole: messages.senderRole,
        bodyText: messages.bodyText,
        createdAt: messages.createdAt,
        payloadJson: messages.payloadJson,
        idempotencyKey: messages.idempotencyKey,
      })
      .from(messages)
      .where(eq(messages.ticketId, ticketId))
      .orderBy(messages.createdAt),
    db
      .select({
        id: eventLog.id,
        type: eventLog.type,
        createdAt: eventLog.createdAt,
        payloadJson: eventLog.payloadJson,
      })
      .from(eventLog)
      .where(
        and(
          eq(eventLog.ticketId, ticketId),
          inArray(
            eventLog.type,
            [...conversationTimelineTypes, "customer_id_revealed"] as string[],
          ),
        ),
      )
      .orderBy(desc(eventLog.createdAt))
      .limit(5),
  ]);

  const currentTicket = ticket[0];

  if (!currentTicket) {
    notFound();
  }

  if (phoneVisible) {
    const { userId } = await auth();

    if (userId) {
      const recentReveal = await db
        .select({ id: eventLog.id })
        .from(eventLog)
        .where(
          and(
            eq(eventLog.ticketId, ticketId),
            eq(eventLog.type, "customer_id_revealed"),
            sql`${eventLog.createdAt} > now() - interval '5 minutes'`,
            sql`${eventLog.payloadJson}->>'clerk_user_id' = ${userId}`,
          ),
        )
        .limit(1);

      if (recentReveal.length === 0) {
        await db.insert(eventLog).values({
          type: "customer_id_revealed",
          ticketId,
          customerId: currentTicket.customerId,
          payloadJson: {
            customer_id: currentTicket.customerId,
            ticket_id: ticketId,
            clerk_user_id: userId,
          },
        });
      }
    }
  }

  return (
    <div className="mx-auto flex w-full max-w-7xl flex-col gap-6 px-4 py-6 sm:px-6">
      <div className="flex flex-col gap-3 lg:flex-row lg:items-start lg:justify-between">
        <div className="space-y-2">
          <div className="flex items-center gap-3">
            <h1 className="text-2xl font-semibold text-zinc-50">
              {currentTicket.ticketId}
            </h1>
            <Badge variant={getTicketStatusVariant(currentTicket.status)}>
              {currentTicket.status}
            </Badge>
          </div>
          <div className="flex flex-wrap items-center gap-3 text-sm text-zinc-400">
            <span>
              {currentTicket.displayName || "Unknown customer"} {" • "}
              {phoneVisible
                ? currentTicket.customerPhone
                : maskPhone(currentTicket.customerPhone)}
            </span>
            {!phoneVisible ? (
              <Link
                href={`/tickets/${currentTicket.ticketId}?reveal=1`}
                prefetch={false}
                className={cn(buttonVariants({ variant: "outline", size: "sm" }))}
              >
                Reveal
              </Link>
            ) : (
              <Link
                href={`/tickets/${currentTicket.ticketId}`}
                prefetch={false}
                className={cn(buttonVariants({ variant: "outline", size: "sm" }))}
              >
                Hide
              </Link>
            )}
          </div>
        </div>
      </div>

      <div className="grid gap-6 xl:grid-cols-[minmax(0,2fr)_minmax(320px,1fr)]">
        <ReplyForm
          ticketId={currentTicket.ticketId}
          messages={conversationMessages.map((message) => ({
            ...message,
            payloadJson:
              typeof message.payloadJson === "object" && message.payloadJson
                ? (message.payloadJson as Record<string, unknown>)
                : {},
          }))}
        />

        <div className="space-y-6">
          <Card>
            <CardHeader>
              <CardTitle className="text-base">Ticket metadata</CardTitle>
              <CardDescription>
                Core attributes pulled from the existing ticket row.
              </CardDescription>
            </CardHeader>
            <CardContent className="space-y-4">
              <MetadataRow label="Intent" value={currentTicket.intent} />
              <MetadataRow
                label="Status"
                value={
                  <Badge variant={getTicketStatusVariant(currentTicket.status)}>
                    {currentTicket.status}
                  </Badge>
                }
              />
              <MetadataRow
                label="Created"
                value={formatTimestamp(currentTicket.createdAt)}
              />
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle className="text-base">Recent events</CardTitle>
              <CardDescription>
                Latest 5 timeline events relevant to this ticket.
              </CardDescription>
            </CardHeader>
            <CardContent className="space-y-3">
              {recentEvents.length === 0 ? (
                <p className="text-sm text-zinc-500">No matching events yet.</p>
              ) : (
                recentEvents.map((item) => (
                  <div
                    key={`${item.id}`}
                    className="rounded-md border border-border bg-zinc-950/70 p-3"
                  >
                    <div className="flex items-center justify-between gap-3">
                      <Badge variant="outline">{item.type}</Badge>
                      <span className="text-xs text-zinc-500">
                        {formatTimestamp(item.createdAt)}
                      </span>
                    </div>
                    <p className="mt-2 break-all text-xs leading-5 text-zinc-400">
                      {truncatePayload(item.payloadJson)}
                    </p>
                  </div>
                ))
              )}
            </CardContent>
          </Card>
        </div>
      </div>
    </div>
  );
}

function MetadataRow({
  label,
  value,
}: {
  label: string;
  value: React.ReactNode;
}) {
  return (
    <div className="flex items-center justify-between gap-4 text-sm">
      <span className="text-zinc-500">{label}</span>
      <div className="text-right text-zinc-100">{value}</div>
    </div>
  );
}

function truncatePayload(payloadJson: unknown) {
  const serialized = JSON.stringify(payloadJson);
  if (!serialized) {
    return "—";
  }

  const redacted = redactSensitiveText(serialized);

  return redacted.length > 160
    ? `${redacted.slice(0, 157)}...`
    : redacted;
}
