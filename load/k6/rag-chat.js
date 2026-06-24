import http from 'k6/http';
import { check } from 'k6';
import { commonOptions, jsonHeaders, summaryOutput, uniqueId } from './lib/options.js';

export const options = commonOptions(1, '20s');

const baseUrl = __ENV.RAG_API_URL || 'http://localhost:8000';

export default function () {
  const payload = JSON.stringify({
    question: `What is the return policy? ${uniqueId('rag')}`,
    filename: 'demo-company-policy.pdf',
    history: [],
  });

  const response = http.post(`${baseUrl}/chat`, payload, {
    headers: jsonHeaders(),
    timeout: '30s',
  });

  check(response, {
    'rag chat returned 200': (r) => r.status === 200,
    'rag chat returned deterministic mock answer': (r) => {
      try {
        const body = r.json();
        return typeof body.answer === 'string' && body.answer.includes('Mock RAG answer');
      }
      catch (_) {
        return false;
      }
    },
    'rag chat returned sources': (r) => {
      try {
        const body = r.json();
        return Array.isArray(body.sources) && body.sources.length > 0;
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
