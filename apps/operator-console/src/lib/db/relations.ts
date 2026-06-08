import { relations } from "drizzle-orm/relations";
import { customers, messages, tickets, staffMessages, eventLog, inboundRaw } from "./schema";

export const messagesRelations = relations(messages, ({one, many}) => ({
	customer: one(customers, {
		fields: [messages.customerId],
		references: [customers.id]
	}),
	ticket: one(tickets, {
		fields: [messages.ticketId],
		references: [tickets.ticketId],
		relationName: "messages_ticketId_tickets_ticketId"
	}),
	tickets: many(tickets, {
		relationName: "tickets_sourceMessageId_messages_id"
	}),
}));

export const customersRelations = relations(customers, ({many}) => ({
	messages: many(messages),
	eventLogs: many(eventLog),
	tickets: many(tickets),
}));

export const ticketsRelations = relations(tickets, ({one, many}) => ({
	messages: many(messages, {
		relationName: "messages_ticketId_tickets_ticketId"
	}),
	staffMessages: many(staffMessages),
	eventLogs: many(eventLog),
	customer: one(customers, {
		fields: [tickets.customerId],
		references: [customers.id]
	}),
	inboundRaw: one(inboundRaw, {
		fields: [tickets.sourceInboundRawId],
		references: [inboundRaw.id]
	}),
	message: one(messages, {
		fields: [tickets.sourceMessageId],
		references: [messages.id],
		relationName: "tickets_sourceMessageId_messages_id"
	}),
}));

export const staffMessagesRelations = relations(staffMessages, ({one}) => ({
	ticket: one(tickets, {
		fields: [staffMessages.ticketId],
		references: [tickets.ticketId]
	}),
}));

export const eventLogRelations = relations(eventLog, ({one}) => ({
	ticket: one(tickets, {
		fields: [eventLog.ticketId],
		references: [tickets.ticketId]
	}),
	customer: one(customers, {
		fields: [eventLog.customerId],
		references: [customers.id]
	}),
}));

export const inboundRawRelations = relations(inboundRaw, ({many}) => ({
	tickets: many(tickets),
}));