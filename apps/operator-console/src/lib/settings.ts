export type EditableSettingKey =
  | "template.utility_content_sid"
  | "template.utility_content_variables"
  | "whitelist.staff_telegram_from_ids"
  | "whitelist.staff_telegram_chat_ids"
  | "runtime.twilio_account_sid"
  | "runtime.twilio_from_number"
  | "runtime.twilio_enable_send";

export type EditableSettingKind = "string" | "json" | "string-array" | "boolean";

export const editableSettingDefinitions: Array<{
  key: EditableSettingKey;
  kind: EditableSettingKind;
}> = [
  { key: "template.utility_content_sid", kind: "string" },
  { key: "template.utility_content_variables", kind: "json" },
  { key: "whitelist.staff_telegram_from_ids", kind: "string-array" },
  { key: "whitelist.staff_telegram_chat_ids", kind: "string-array" },
  { key: "runtime.twilio_account_sid", kind: "string" },
  { key: "runtime.twilio_from_number", kind: "string" },
  { key: "runtime.twilio_enable_send", kind: "boolean" },
] as const;

export const readonlySettingKeys = [
  "secret.twilio_webhook_auth_token",
  "secret.console_reply_webhook_secret",
] as const;

export function isEditableSettingKey(value: string): value is EditableSettingKey {
  return editableSettingDefinitions.some((definition) => definition.key === value);
}
