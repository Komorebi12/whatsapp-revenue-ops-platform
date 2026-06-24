import http from 'k6/http';
import { check } from 'k6';
import { commonOptions, jsonHeaders, summaryOutput, uniqueId, uuidV4 } from './lib/options.js';

export const options = commonOptions(1, '20s');

const baseUrl = __ENV.SALES_AGENT_URL || 'http://localhost:8020';
const agentSecret = __ENV.AGENT_AUTH_SECRET || 'mock-agent-secret';

export default function () {
  const id = uniqueId('sales-agent');
  const messageId = uuidV4();
  const payload = JSON.stringify({
    customer_id: '11111111-1111-4111-8111-111111111111',
    customer_phone: '+15551234567',
    customer_display_name: 'Demo Buyer',
    message_id: messageId,
    inbound_text: 'I want pricing for CRM automation and pipeline follow-up.',
    intent: 'purchase',
    intent_confidence: 0.93,
    ticket_id: `TICKET-LOAD-SALES-${id}`,
  });

  const response = http.post(`${baseUrl}/agent/respond`, payload, {
    headers: jsonHeaders({ 'X-Agent-Secret': agentSecret }),
    timeout: '45s',
  });

  check(response, {
    'sales-agent returned 200': (r) => r.status === 200,
    'sales-agent returned qualification tier': (r) => {
      try {
        const body = r.json();
        return typeof body.qualification_tier === 'string' && body.qualification_tier.length > 0;
      }
      catch (_) {
        return false;
      }
    },
    'sales-agent returned reply text': (r) => {
      try {
        const body = r.json();
        return typeof body.reply_text === 'string' && body.reply_text.length > 0;
      }
      catch (_) {
        return false;
      }
    },
  });
}

export function handleSummary(data) {
  return summaryOutput(data);
}
