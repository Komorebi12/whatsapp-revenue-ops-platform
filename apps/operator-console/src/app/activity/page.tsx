import Link from "next/link";
import { and, desc, eq, inArray, like, lt, or } from "drizzle-orm";
import { Badge } from "@/components/ui/badge";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import {
  formatTimestamp,
  getEventFamily,
  getEventFamilyClasses,
  redactSensitiveText,
  type EventFamily,
} from "@/lib/console";
import { db } from "@/lib/db";
import { eventLog } from "@/lib/db/schema";

const familyOptions: Array<{
  key: EventFamily;
  label: string;
}> = [
  { key: "all", label: "All" },
  { key: "dispatch", label: "Dispatch" },
  { key: "send", label: "Send" },
  { key: "staff", label: "Staff" },
  { key: "config", label: "Config" },
];

type PageProps = {
  searchParams: Promise<{
    family?: string;
    cursor?: string;
  }>;
};

export default async function ActivityPage({ searchParams }: PageProps) {
  const { family: familyParam, cursor: cursorParam } = await searchParams;
  const family = normalizeFamily(familyParam);
  const cursor = cursorParam ? Number(cursorParam) : null;

  const filters = [];

  if (cursor && Number.isFinite(cursor)) {
    filters.push(lt(eventLog.id, BigInt(cursor)));
  }

  const familyFilter = buildFamilyFilter(family);
  if (familyFilter) {
    filters.push(familyFilter);
  }

  const rows = await db
    .select({
      id: eventLog.id,
      type: eventLog.type,
      ticketId: eventLog.ticketId,
      payloadJson: eventLog.payloadJson,
      createdAt: eventLog.createdAt,
    })
    .from(eventLog)
    .where(filters.length > 0 ? and(...filters) : undefined)
    .orderBy(desc(eventLog.createdAt), desc(eventLog.id))
    .limit(200);

  const nextCursor =
    rows.length === 200 ? rows[rows.length - 1]?.id.toString() : null;

  return (
    <div className="mx-auto flex w-full max-w-7xl flex-col gap-6 px-4 py-6 sm:px-6">
      <div className="space-y-1">
        <p className="text-sm font-medium text-zinc-500">Operator Console</p>
        <h1 className="text-2xl font-semibold text-zinc-50">Activity</h1>
        <p className="text-sm text-zinc-400">
          Latest 200 events from the audit and delivery stream.
        </p>
      </div>

      <div className="flex flex-wrap gap-2">
        {familyOptions.map((option) => {
          const active = option.key === family;
          const href =
            option.key === "all"
              ? "/activity"
              : `/activity?family=${option.key}`;

          return (
            <Link key={option.key} href={href}>
              <Badge
                className={active ? "border-zinc-100 bg-zinc-100 text-zinc-950" : ""}
                variant={active ? "default" : "outline"}
              >
                {option.label}
              </Badge>
            </Link>
          );
        })}
      </div>

      <Card>
        <CardHeader>
          <CardTitle className="text-base">Event feed</CardTitle>
          <CardDescription>
            Family filters narrow the view without exposing raw secret values.
          </CardDescription>
        </CardHeader>
        <CardContent className="p-0">
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-border">
                  <th className="px-4 py-3 text-left text-xs font-medium uppercase tracking-[0.16em] text-zinc-500">
                    Created
                  </th>
                  <th className="px-4 py-3 text-left text-xs font-medium uppercase tracking-[0.16em] text-zinc-500">
                    Type
                  </th>
                  <th className="px-4 py-3 text-left text-xs font-medium uppercase tracking-[0.16em] text-zinc-500">
                    Ticket
                  </th>
                  <th className="px-4 py-3 text-left text-xs font-medium uppercase tracking-[0.16em] text-zinc-500">
                    Payload
                  </th>
                </tr>
              </thead>
              <tbody>
                {rows.length === 0 ? (
                  <tr>
                    <td
                      colSpan={4}
                      className="px-4 py-10 text-center text-sm text-zinc-500"
                    >
                      No events found for this filter.
                    </td>
                  </tr>
                ) : (
                  rows.map((row) => {
                    const rowFamily = getEventFamily(row.type);
                    return (
                      <tr
                        key={`${row.id}`}
                        className="border-b border-border align-top hover:bg-zinc-950/60"
                      >
                        <td className="px-4 py-3 text-zinc-300">
                          {formatTimestamp(row.createdAt)}
                        </td>
                        <td className="px-4 py-3">
                          <span
                            className={`inline-flex items-center rounded-md border px-2 py-0.5 text-xs font-medium ${getEventFamilyClasses(rowFamily)}`}
                          >
                            {row.type}
                          </span>
                        </td>
                        <td className="px-4 py-3">
                          {row.ticketId ? (
                            <Link
                              href={`/tickets/${row.ticketId}`}
                              className="text-zinc-100 hover:text-sky-300"
                            >
                              {row.ticketId}
                            </Link>
                          ) : (
                            <span className="text-zinc-500">—</span>
                          )}
                        </td>
                        <td className="px-4 py-3 font-mono text-xs text-zinc-400">
                          {formatPayloadSnippet(row.payloadJson)}
                        </td>
                      </tr>
                    );
                  })
                )}
              </tbody>
            </table>
          </div>
        </CardContent>
      </Card>

      {nextCursor ? (
        <div>
          <Link
            href={
              family === "all"
                ? `/activity?cursor=${nextCursor}`
                : `/activity?family=${family}&cursor=${nextCursor}`
            }
            className="inline-flex h-9 items-center justify-center rounded-md border border-border px-4 text-sm font-medium text-zinc-100 hover:bg-zinc-900"
          >
            Load 200 more
          </Link>
        </div>
      ) : null}
    </div>
  );
}

function normalizeFamily(value: string | undefined): EventFamily {
  if (!value) {
    return "all";
  }

  return familyOptions.some((option) => option.key === value)
    ? (value as EventFamily)
    : "all";
}

function buildFamilyFilter(family: EventFamily) {
  switch (family) {
    case "dispatch":
      return inArray(eventLog.type, ["intent_classified", "auto_reply_requested"]);
    case "send":
      return like(eventLog.type, "whatsapp_send_%");
    case "staff":
      return or(like(eventLog.type, "staff_%"), like(eventLog.type, "ticket_%"));
    case "config":
      return inArray(eventLog.type, ["config_changed", "customer_id_revealed"]);
    default:
      return undefined;
  }
}

function formatPayloadSnippet(payloadJson: unknown) {
  const serialized = redactSensitiveText(JSON.stringify(payloadJson) || "—");
  return serialized.length > 80 ? `${serialized.slice(0, 77)}...` : serialized;
}
