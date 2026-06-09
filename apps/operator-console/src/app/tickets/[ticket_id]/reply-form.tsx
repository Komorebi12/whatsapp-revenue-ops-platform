"use client";

import { useEffect, useMemo, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import { cn } from "@/lib/utils";
import { sendStaffReply } from "./actions";

type ConversationMessage = {
  id: string;
  direction: "inbound" | "outbound";
  senderRole: "customer" | "system" | "staff";
  bodyText: string | null;
  createdAt: string;
  payloadJson: Record<string, unknown>;
  idempotencyKey: string | null;
};

type OptimisticMessage = {
  bodyText: string;
  createdAt: string;
  idempotencyKey: string;
  status: "queued" | "failed";
};

type ReplyFormProps = {
  ticketId: string;
  messages: ConversationMessage[];
};

export function ReplyForm({ ticketId, messages }: ReplyFormProps) {
  const router = useRouter();
  const [text, setText] = useState("");
  const [optimisticMessages, setOptimisticMessages] = useState<
    OptimisticMessage[]
  >([]);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [isPending, startTransition] = useTransition();

  const serverKeys = useMemo(
    () =>
      new Set(
        messages
          .map((message) => {
            const key =
              message.idempotencyKey ?? message.payloadJson?.idempotency_key;
            return typeof key === "string" ? key : null;
          })
          .filter((value): value is string => Boolean(value)),
      ),
    [messages],
  );

  useEffect(() => {
    setOptimisticMessages((current) =>
      current.filter((message) => !serverKeys.has(message.idempotencyKey)),
    );
  }, [serverKeys]);

  async function handleSubmit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();

    const trimmed = text.trim();
    if (!trimmed) {
      return;
    }

    setErrorMessage(null);

    startTransition(async () => {
      try {
        const { idempotencyKey } = await sendStaffReply(ticketId, trimmed);

        setText("");
        setOptimisticMessages((current) => [
          ...current,
          {
            bodyText: trimmed,
            createdAt: new Date().toISOString(),
            idempotencyKey,
            status: "queued",
          },
        ]);

        // n8n workflow delivery usually takes 2-5s; refresh at 3s and 6s
        window.setTimeout(() => {
          router.refresh();
        }, 3000);

        window.setTimeout(() => {
          router.refresh();
        }, 6000);

        window.setTimeout(() => {
          setOptimisticMessages((current) =>
            current.map((message) =>
              message.idempotencyKey === idempotencyKey &&
              !serverKeys.has(idempotencyKey)
                ? { ...message, status: "failed" }
                : message,
            ),
          );
        }, 12000);
      } catch (error) {
        setErrorMessage(
          error instanceof Error ? error.message : "Failed to send reply",
        );
      }
    });
  }

  return (
    <div className="flex h-full flex-col gap-4">
      <div className="flex min-h-[420px] flex-1 flex-col gap-3 rounded-lg border border-border bg-card p-4">
        {messages.map((message) => (
          <MessageBubble
            key={message.id}
            bodyText={message.bodyText}
            createdAt={message.createdAt}
            direction={message.direction}
            senderRole={message.senderRole}
          />
        ))}
        {optimisticMessages.map((message) => (
          <MessageBubble
            key={message.idempotencyKey}
            bodyText={message.bodyText}
            createdAt={message.createdAt}
            direction="outbound"
            senderRole="staff"
            status={message.status}
          />
        ))}
      </div>

      <form
        onSubmit={handleSubmit}
        className="rounded-lg border border-border bg-card p-4"
      >
        <div className="space-y-3">
          <Textarea
            value={text}
            onChange={(event) => setText(event.target.value)}
            placeholder="Write a staff reply"
            className="min-h-28"
          />
          <div className="flex items-center justify-between gap-3">
            <div className="min-h-5 text-sm text-red-300">
              {errorMessage ?? ""}
            </div>
            <Button type="submit" disabled={isPending || !text.trim()}>
              {isPending ? "Queueing..." : "Send reply"}
            </Button>
          </div>
        </div>
      </form>
    </div>
  );
}

function MessageBubble({
  bodyText,
  createdAt,
  direction,
  senderRole,
  status,
}: {
  bodyText: string | null;
  createdAt: string;
  direction: "inbound" | "outbound";
  senderRole: "customer" | "system" | "staff";
  status?: "queued" | "failed";
}) {
  const isInbound = direction === "inbound";
  const bubbleTone = isInbound
    ? "bg-zinc-800 text-zinc-100"
    : senderRole === "staff"
      ? "bg-sky-700 text-white"
      : "bg-zinc-700 text-zinc-100";

  return (
    <div
      className={cn(
        "flex w-full",
        isInbound ? "justify-start" : "justify-end",
      )}
    >
      <div className="flex max-w-[85%] flex-col gap-2">
        <div
          className={cn(
            "rounded-lg px-4 py-3 text-sm leading-6",
            bubbleTone,
            status === "queued" && "border border-dashed border-sky-300/50",
            status === "failed" && "border border-red-400/60 bg-red-950/70",
          )}
        >
          {bodyText || "No text payload"}
        </div>
        <div
          className={cn(
            "flex items-center gap-2 text-xs text-zinc-500",
            isInbound ? "justify-start" : "justify-end",
          )}
        >
          <span>{new Date(createdAt).toLocaleString("en-US")}</span>
          {status ? (
            <Badge variant={status === "queued" ? "outline" : "danger"}>
              {status === "queued" ? "queued" : "failed (retry)"}
            </Badge>
          ) : (
            <Badge variant="secondary">{isInbound ? "received" : "sent"}</Badge>
          )}
        </div>
      </div>
    </div>
  );
}
