import Link from "next/link";
import { and, count, desc, eq, inArray, sql } from "drizzle-orm";
import { Badge } from "@/components/ui/badge";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import {
  formatAgeDays,
  formatTimestamp,
  getTicketStatusVariant,
  intentColorMap,
  maskPhone,
  openTicketStatuses,
} from "@/lib/console";
import { db } from "@/lib/db";
import { customers, eventLog, tickets } from "@/lib/db/schema";

type PageProps = {
  searchParams: Promise<{
    include_closed?: string;
  }>;
};

export default async function TicketsPage({ searchParams }: PageProps) {
  const { include_closed: includeClosedParam } = await searchParams;
  const includeClosed = includeClosedParam === "1";

  const [openTicketsResult, awaitingStaffResult, failedSendsResult, rows] =
    await Promise.all([
      db
        .select({ count: count() })
        .from(tickets)
        .where(inArray(tickets.status, openTicketStatuses)),
      db
        .select({ count: count() })
        .from(tickets)
        .where(eq(tickets.status, "awaiting_staff")),
      db
        .select({ count: count() })
        .from(eventLog)
        .where(
          and(
            eq(eventLog.type, "whatsapp_send_failed"),
            sql`${eventLog.createdAt} > now() - interval '24 hours'`,
          ),
        ),
      db
        .select({
          ticketId: tickets.ticketId,
          intent: tickets.intent,
          status: tickets.status,
          createdAt: tickets.createdAt,
          lastCustomerMessageAt: tickets.lastCustomerMessageAt,
          lastStaffReplyAt: tickets.lastStaffReplyAt,
          customerPhone: customers.phone,
        })
        .from(tickets)
        .innerJoin(customers, eq(tickets.customerId, customers.id))
        .where(includeClosed ? undefined : sql`${tickets.status} <> 'closed'`)
        .orderBy(
          sql`case when ${tickets.status} = 'closed' then 1 else 0 end`,
          desc(tickets.createdAt),
        ),
    ]);

  return (
    <div className="mx-auto flex w-full max-w-7xl flex-col gap-6 px-4 py-6 sm:px-6">
      <div className="flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between">
        <div className="space-y-1">
          <p className="text-sm font-medium text-zinc-500">Operator Console</p>
          <h1 className="text-2xl font-semibold text-zinc-50">Tickets</h1>
          <p className="text-sm text-zinc-400">
            Live queue pulled directly from the demo Postgres schema.
          </p>
        </div>
        <Link
          href={includeClosed ? "/tickets" : "/tickets?include_closed=1"}
          className="text-sm font-medium text-zinc-300 underline decoration-zinc-700 underline-offset-4 hover:text-zinc-50"
        >
          {includeClosed ? "Hide closed" : "Include closed"}
        </Link>
      </div>

      <section className="grid gap-4 md:grid-cols-3">
        <KpiCard
          label="Open tickets"
          value={openTicketsResult[0]?.count ?? 0}
          hint="Statuses: open, awaiting_staff, awaiting_customer, pending_reactivation"
        />
        <KpiCard
          label="Awaiting staff"
          value={awaitingStaffResult[0]?.count ?? 0}
          hint="Tickets currently waiting on a human reply"
        />
        <KpiCard
          label="Failed sends 24h"
          value={failedSendsResult[0]?.count ?? 0}
          hint="Recent send failures from the event log"
        />
      </section>

      <Card>
        <CardHeader className="border-b border-border">
          <CardTitle className="text-base">Ticket queue</CardTitle>
          <CardDescription>
            Default ordering keeps active tickets ahead of closed history.
          </CardDescription>
        </CardHeader>
        <CardContent className="p-0">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Ticket</TableHead>
                <TableHead>Customer</TableHead>
                <TableHead>Intent</TableHead>
                <TableHead>Status</TableHead>
                <TableHead>Last customer</TableHead>
                <TableHead>Last staff</TableHead>
                <TableHead>Age</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {rows.length === 0 ? (
                <TableRow>
                  <TableCell
                    colSpan={7}
                    className="py-10 text-center text-sm text-zinc-500"
                  >
                    No tickets found for the current filter.
                  </TableCell>
                </TableRow>
              ) : (
                rows.map((row) => (
                  <TableRow key={row.ticketId}>
                    <TableCell className="font-medium">
                      <Link
                        href={`/tickets/${row.ticketId}`}
                        className="text-zinc-100 hover:text-sky-300"
                      >
                        {row.ticketId}
                      </Link>
                    </TableCell>
                    <TableCell className="text-zinc-300">
                      {maskPhone(row.customerPhone)}
                    </TableCell>
                    <TableCell>
                      <span
                        className={`inline-flex items-center rounded-md border px-2 py-0.5 text-xs font-medium ${intentColorMap[row.intent] ?? "border-zinc-700 bg-zinc-900 text-zinc-200"}`}
                      >
                        {row.intent}
                      </span>
                    </TableCell>
                    <TableCell>
                      <Badge variant={getTicketStatusVariant(row.status)}>
                        {row.status}
                      </Badge>
                    </TableCell>
                    <TableCell className="text-zinc-300">
                      {formatTimestamp(row.lastCustomerMessageAt)}
                    </TableCell>
                    <TableCell className="text-zinc-300">
                      {formatTimestamp(row.lastStaffReplyAt)}
                    </TableCell>
                    <TableCell className="text-zinc-300">
                      {formatAgeDays(row.createdAt)}
                    </TableCell>
                  </TableRow>
                ))
              )}
            </TableBody>
          </Table>
        </CardContent>
      </Card>
    </div>
  );
}

function KpiCard({
  label,
  value,
  hint,
}: {
  label: string;
  value: number;
  hint: string;
}) {
  return (
    <Card>
      <CardHeader className="space-y-2">
        <CardDescription>{label}</CardDescription>
        <CardTitle className="text-3xl">{value}</CardTitle>
      </CardHeader>
      <CardContent>
        <p className="text-sm text-zinc-500">{hint}</p>
      </CardContent>
    </Card>
  );
}
