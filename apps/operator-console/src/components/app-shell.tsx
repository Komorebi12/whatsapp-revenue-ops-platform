"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { UserButton } from "@clerk/nextjs";
import { Activity, MessageSquareText, Settings } from "lucide-react";
import { cn } from "@/lib/utils";

const navigationItems = [
  {
    href: "/tickets",
    label: "Tickets",
    icon: MessageSquareText,
    match: (pathname: string) => pathname.startsWith("/tickets"),
  },
  {
    href: "/settings",
    label: "Settings",
    icon: Settings,
    match: (pathname: string) => pathname.startsWith("/settings"),
  },
  {
    href: "/activity",
    label: "Activity",
    icon: Activity,
    match: (pathname: string) => pathname.startsWith("/activity"),
  },
] as const;

type AppShellProps = {
  children: React.ReactNode;
};

export function AppShell({ children }: AppShellProps) {
  const pathname = usePathname();

  if (pathname.startsWith("/sign-in") || pathname.startsWith("/sign-up")) {
    return <>{children}</>;
  }

  return (
    <div className="flex min-h-screen bg-background text-foreground">
      <aside className="hidden w-64 shrink-0 border-r border-border bg-zinc-950/95 lg:flex lg:flex-col">
        <div className="border-b border-border px-6 py-6">
          <p className="text-xs font-medium uppercase tracking-[0.18em] text-zinc-500">
            Operator Console
          </p>
          <h1 className="mt-3 text-xl font-semibold text-zinc-50">
            WhatsApp Support
          </h1>
        </div>
        <nav className="flex flex-1 flex-col gap-1 p-4">
          {navigationItems.map(({ href, label, icon: Icon, match }) => {
            const active = match(pathname);

            return (
              <Link
                key={href}
                href={href}
                className={cn(
                  "flex items-center gap-3 rounded-md px-3 py-2 text-sm font-medium transition-colors",
                  active
                    ? "bg-zinc-100 text-zinc-950"
                    : "text-zinc-400 hover:bg-zinc-900 hover:text-zinc-50",
                )}
              >
                <Icon className="h-4 w-4" />
                <span>{label}</span>
              </Link>
            );
          })}
        </nav>
      </aside>
      <div className="flex min-h-screen flex-1 flex-col">
        <header className="sticky top-0 z-20 flex h-16 items-center justify-between border-b border-border bg-zinc-950/85 px-4 backdrop-blur sm:px-6">
          <div className="flex items-center gap-3 lg:hidden">
            <p className="text-sm font-semibold text-zinc-100">Support Console</p>
          </div>
          <div className="hidden lg:block">
            <p className="text-sm text-zinc-400">
              Tickets, operator replies, configuration, and activity
            </p>
          </div>
          <UserButton />
        </header>
        <main className="flex-1">{children}</main>
      </div>
    </div>
  );
}
