"use server";

import { auth } from "@clerk/nextjs/server";
import { createHash } from "node:crypto";
import { eq } from "drizzle-orm";
import { revalidatePath } from "next/cache";
import { db } from "@/lib/db";
import { configSettings, eventLog } from "@/lib/db/schema";
import {
  editableSettingDefinitions,
  isEditableSettingKey,
  type EditableSettingKey,
} from "@/lib/settings";

type SaveSettingInput = {
  key: EditableSettingKey;
  value: boolean | string | string[] | Record<string, unknown>;
};

export async function saveSetting(input: SaveSettingInput) {
  const { userId } = await auth();

  if (!userId) {
    throw new Error("Unauthorized");
  }

  if (!isEditableSettingKey(input.key)) {
    throw new Error("Setting is not editable");
  }

  const definition = editableSettingDefinitions.find(
    (item) => item.key === input.key,
  );

  if (!definition) {
    throw new Error("Unknown setting definition");
  }

  const normalizedValue = normalizeSettingValue(definition.kind, input.value);

  const [existing] = await db
    .select({
      key: configSettings.key,
      value: configSettings.value,
    })
    .from(configSettings)
    .where(eq(configSettings.key, input.key))
    .limit(1);

  await db.transaction(async (tx) => {
    if (existing) {
      await tx
        .update(configSettings)
        .set({
          value: normalizedValue,
          updatedAt: new Date().toISOString(),
        })
        .where(eq(configSettings.key, input.key));
    } else {
      await tx.insert(configSettings).values({
        key: input.key,
        value: normalizedValue,
        updatedAt: new Date().toISOString(),
      });
    }

    await tx.insert(eventLog).values({
      type: "config_changed",
      payloadJson: {
        key: input.key,
        old_value_hash: existing
          ? sha256Json(existing.value)
          : null,
        new_value_hash: sha256Json(normalizedValue),
        clerk_user_id: userId,
      },
    });
  });

  revalidatePath("/settings");
}

function normalizeSettingValue(
  kind: (typeof editableSettingDefinitions)[number]["kind"],
  value: SaveSettingInput["value"],
) {
  switch (kind) {
    case "boolean":
      if (typeof value !== "boolean") {
        throw new Error("Expected boolean value");
      }
      return value;
    case "string":
      if (typeof value !== "string") {
        throw new Error("Expected string value");
      }
      return value;
    case "string-array":
      if (!Array.isArray(value) || value.some((item) => typeof item !== "string")) {
        throw new Error("Expected string array value");
      }
      return value;
    case "json":
      if (typeof value !== "object" || value === null || Array.isArray(value)) {
        throw new Error("Expected JSON object value");
      }
      return value;
    default:
      throw new Error("Unsupported setting kind");
  }
}

function sha256Json(value: unknown) {
  return createHash("sha256")
    .update(JSON.stringify(value))
    .digest("hex");
}
