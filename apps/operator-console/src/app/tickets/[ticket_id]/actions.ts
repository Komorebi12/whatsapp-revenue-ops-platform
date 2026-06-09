"use server";

import { auth } from "@clerk/nextjs/server";
import { eq } from "drizzle-orm";
import { revalidatePath } from "next/cache";
import { db } from "@/lib/db";
import { tickets } from "@/lib/db/schema";

export async function sendStaffReply(ticketId: string, text: string) {
  const trimmedText = text.trim();

  if (!trimmedText) {
    throw new Error("Reply text is required");
  }

  const { userId } = await auth();

  if (!userId) {
    throw new Error("Unauthorized");
  }

  const [ticket] = await db
    .select({
      ticketId: tickets.ticketId,
      customerId: tickets.customerId,
    })
    .from(tickets)
    .where(eq(tickets.ticketId, ticketId))
    .limit(1);

  if (!ticket) {
    throw new Error("Ticket not found");
  }

  const idempotencyKey = crypto.randomUUID();

  // Production path
  const webhookUrl = process.env.MVP_REPLY_WEBHOOK_URL;
  const webhookSecret = process.env.MVP_REPLY_WEBHOOK_SECRET;

  if (!webhookUrl || !webhookSecret) {
    throw new Error("MVP webhook configuration is missing");
  }

  const response = await fetch(webhookUrl, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${webhookSecret}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      ticket_id: ticket.ticketId,
      body_text: trimmedText,
      idempotency_key: idempotencyKey,
      clerk_user_id: userId,
    }),
  });

  if (!response.ok) {
    throw new Error(`MVP webhook returned ${response.status}`);
  }

  revalidatePath(`/tickets/${ticketId}`);

  return { idempotencyKey };
}
