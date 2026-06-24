import http from 'k6/http';
import { check } from 'k6';
import { commonOptions, jsonHeaders, summaryOutput, uniqueId } from './lib/options.js';

export const options = commonOptions(1, '20s');

const webhookUrl = __ENV.N8N_WEBHOOK_URL || 'http://localhost:5680/webhook/twilio/whatsapp/inbound';

export default function () {
  const id = uniqueId('n8n-rag');
  const payload = JSON.stringify({
    customer_id: '11111111-1111-4111-8111-111111111111',
    customer_phone: '+15551234567',
    customer_display_name: 'Demo Buyer',
    message_id: id,
    inbound_text: 'What is your return policy and support process?',
    intent: 'information_query',
    intent_confidence: 0.91,
    ticket_id: `TICKET-LOAD-RAG-${id}`,
  });

  const response = http.post(webhookUrl, payload, {
    headers: jsonHeaders(),
    timeout: '60s',
  });

  check(response, {
    'n8n inbound returned 200': (r) => r.status === 200,
    'n8n inbound returned mock rag answer': (r) => {
      try {
        const body = r.json();
        return typeof body.answer === 'string' && body.answer.includes('Mock RAG answer');
      }
      catch (_) {
        return false;
      }
    },
    'n8n inbound did not fallback': (r) => {
      try {
        const body = r.json();
        return body.fallback !== true;
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
