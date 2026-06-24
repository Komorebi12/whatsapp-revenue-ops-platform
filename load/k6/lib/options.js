export function parseNumberEnv(name, fallback) {
  const value = __ENV[name];
  if (value === undefined || value === null || `${value}`.trim() === '') {
    return fallback;
  }
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed <= 0) {
    throw new Error(`${name} must be a positive number, received '${value}'`);
  }
  return parsed;
}

export function commonOptions(defaultVus = 1, defaultDuration = '20s') {
  const vus = parseNumberEnv('K6_VUS', defaultVus);
  const duration = __ENV.K6_DURATION || defaultDuration;
  return {
    vus,
    duration,
    summaryTrendStats: ['min', 'avg', 'med', 'p(50)', 'p(95)', 'p(99)', 'max'],
    thresholds: {
      http_req_failed: ['rate<0.01'],
      checks: ['rate>0.99'],
    },
  };
}

export function jsonHeaders(extra = {}) {
  return Object.assign(
    {
      'Content-Type': 'application/json',
    },
    extra,
  );
}

export function emitSummary(data) {
  const metrics = data.metrics || {};
  const duration = metrics.http_req_duration || {};
  const durationValues = duration.values || {};
  const failed = metrics.http_req_failed || {};
  const failedValues = failed.values || {};
  const requests = metrics.http_reqs || {};
  const requestValues = requests.values || {};
  const checks = metrics.checks || {};
  const checkValues = checks.values || {};

  return {
    root_group: data.root_group?.name || '',
    http_reqs: requestValues.count || 0,
    rps: requestValues.rate || 0,
    error_rate: failedValues.rate || 0,
    checks_rate: checkValues.rate || 0,
    p50_ms: durationValues['p(50)'] || durationValues.med || 0,
    p95_ms: durationValues['p(95)'] || 0,
    p99_ms: durationValues['p(99)'] || 0,
    max_ms: durationValues.max || 0,
  };
}

export function summaryOutput(data) {
  const body = JSON.stringify(emitSummary(data), null, 2);
  const outputs = {
    stdout: `${body}\n`,
  };
  if (__ENV.K6_SUMMARY_PATH) {
    outputs[__ENV.K6_SUMMARY_PATH] = `${body}\n`;
  }
  return outputs;
}

export function uniqueId(prefix) {
  const random = Math.random().toString(36).slice(2, 10);
  return `${prefix}-${Date.now()}-${__VU}-${__ITER}-${random}`;
}

export function uuidV4() {
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (char) => {
    const value = Math.floor(Math.random() * 16);
    const variant = char === 'x' ? value : (value & 0x3) | 0x8;
    return variant.toString(16);
  });
}
