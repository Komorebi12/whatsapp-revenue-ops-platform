import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { db } from "@/lib/db";
import { configSettings } from "@/lib/db/schema";
import {
  editableSettingDefinitions,
  readonlySettingKeys,
} from "@/lib/settings";
import { SettingRow } from "./setting-row";

export default async function SettingsPage() {
  const editableKeys = editableSettingDefinitions.map((definition) => definition.key);
  const rows = await db.query.configSettings.findMany({
    where: (table, { inArray }) => inArray(table.key, editableKeys),
    orderBy: (table, { asc }) => [asc(table.key)],
  });

  const settingsMap = new Map(rows.map((row) => [row.key, row.value]));

  return (
    <div className="mx-auto flex w-full max-w-6xl flex-col gap-6 px-4 py-6 sm:px-6">
      <div className="space-y-1">
        <p className="text-sm font-medium text-zinc-500">Operator Console</p>
        <h1 className="text-2xl font-semibold text-zinc-50">Settings</h1>
        <p className="text-sm text-zinc-400">
          Whitelisted runtime configuration only. Secrets stay redacted.
        </p>
      </div>

      <Card>
        <CardHeader>
          <CardTitle className="text-base">Editable configuration</CardTitle>
          <CardDescription>
            Each row saves independently and writes a hashed audit event.
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          {editableSettingDefinitions.map((definition) => (
            <SettingRow
              key={definition.key}
              settingKey={definition.key}
              kind={definition.kind}
              value={settingsMap.get(definition.key)}
              exists={settingsMap.has(definition.key)}
            />
          ))}
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle className="text-base">Secret values</CardTitle>
          <CardDescription>
            These keys are visible by name only.
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-3">
          {readonlySettingKeys.map((key) => (
            <div
              key={key}
              className="flex items-center justify-between rounded-lg border border-border bg-zinc-950/70 px-4 py-3"
            >
              <span className="text-sm text-zinc-100">{key}</span>
              <span className="text-sm text-zinc-500">[redacted]</span>
            </div>
          ))}
        </CardContent>
      </Card>
    </div>
  );
}
