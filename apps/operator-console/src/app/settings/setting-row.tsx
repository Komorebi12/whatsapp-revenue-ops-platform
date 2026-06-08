"use client";

import { useState, useTransition } from "react";
import { Save } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Switch } from "@/components/ui/switch";
import { Textarea } from "@/components/ui/textarea";
import { saveSetting } from "./actions";

type SettingRowProps = {
  settingKey: string;
  kind: "string" | "json" | "string-array" | "boolean";
  value: unknown;
  exists: boolean;
};

export function SettingRow({
  settingKey,
  kind,
  value,
  exists,
}: SettingRowProps) {
  const [isPending, startTransition] = useTransition();
  const [statusMessage, setStatusMessage] = useState<string | null>(null);
  const [stringValue, setStringValue] = useState(
    kind === "string" && typeof value === "string" ? value : "",
  );
  const [jsonValue, setJsonValue] = useState(
    kind === "json" ? JSON.stringify(value ?? {}, null, 2) : "",
  );
  const [arrayValue, setArrayValue] = useState(
    kind === "string-array" && Array.isArray(value)
      ? value.map((item) => String(item)).join("\n")
      : "",
  );
  const [booleanValue, setBooleanValue] = useState(
    kind === "boolean" ? Boolean(value) : false,
  );

  async function handleSave() {
    setStatusMessage(null);

    try {
      const nextValue = parseValue();

      startTransition(async () => {
        try {
          await saveSetting({
            key: settingKey as never,
            value: nextValue,
          });
          setStatusMessage("Saved");
        } catch (error) {
          setStatusMessage(
            error instanceof Error ? error.message : "Save failed",
          );
        }
      });
    } catch (error) {
      setStatusMessage(error instanceof Error ? error.message : "Invalid value");
    }
  }

  function parseValue() {
    switch (kind) {
      case "string":
        return stringValue;
      case "boolean":
        return booleanValue;
      case "string-array":
        return arrayValue
          .split(/\r?\n/)
          .map((item) => item.trim())
          .filter(Boolean);
      case "json":
        return JSON.parse(jsonValue) as Record<string, unknown>;
      default:
        throw new Error("Unsupported setting kind");
    }
  }

  return (
    <div className="grid gap-4 rounded-lg border border-border bg-zinc-950/70 p-4 lg:grid-cols-[minmax(0,280px)_minmax(0,1fr)_auto] lg:items-start">
      <div className="space-y-1">
        <p className="text-sm font-medium text-zinc-100">{settingKey}</p>
        <p className="text-xs text-zinc-500">
          {exists ? "Existing row" : "Missing row: first save creates it"}
        </p>
      </div>

      <div className="space-y-2">
        {kind === "string" ? (
          <Input
            value={stringValue}
            onChange={(event) => setStringValue(event.target.value)}
          />
        ) : null}

        {kind === "json" ? (
          <Textarea
            value={jsonValue}
            onChange={(event) => setJsonValue(event.target.value)}
            className="min-h-28 font-mono text-xs"
          />
        ) : null}

        {kind === "string-array" ? (
          <Textarea
            value={arrayValue}
            onChange={(event) => setArrayValue(event.target.value)}
            className="min-h-28 font-mono text-xs"
          />
        ) : null}

        {kind === "boolean" ? (
          <div className="flex min-h-9 items-center">
            <Switch
              checked={booleanValue}
              onCheckedChange={setBooleanValue}
            />
          </div>
        ) : null}

        <p className="min-h-5 text-xs text-zinc-500">{statusMessage ?? ""}</p>
      </div>

      <Button
        type="button"
        variant="outline"
        onClick={handleSave}
        disabled={isPending}
      >
        <Save className="h-4 w-4" />
        {isPending ? "Saving..." : "Save"}
      </Button>
    </div>
  );
}
