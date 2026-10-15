import type { HealthRow, PaceDay, Summary } from '../lib/api';

function isoDay(daysAgo: number): string {
  const d = new Date();
  d.setDate(d.getDate() - daysAgo);
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

/** 30 pace days ending today, today the busiest. */
export const pace: PaceDay[] = Array.from({ length: 30 }, (_, i) => ({
  date: isoDay(29 - i),
  tokens: (i + 1) * 1000,
  cost_usd: i + 1,
}));

const health = (name: string, status: HealthRow['status'], extra: Partial<HealthRow> = {}): HealthRow => ({
  name,
  source: 'user',
  status,
  uses: 0,
  last_used: null,
  trend: [0, 0],
  trouble_rate: 0,
  invoked: null,
  ...extra,
});

const period = (actual: number, forecast: number) => ({ actual, forecast, low: forecast - 5, high: forecast + 5 });

/** A small but complete `/api/summary` payload, in the server's sort order. */
export const summary: Summary = {
  range: '30d',
  generated_at: '2026-10-14T12:00:00+00:00',
  data_dirs: ['/home/x/.claude'],
  store_path: '/home/x/.usage-insights/usage.db',
  last_export: '2026-10-14T11:55:00+00:00',
  totals: {
    cost_usd: 120,
    tokens: { input: 10, output: 20, cache_write: 30, cache_read: 40, total: 100 },
    sessions: 3,
    unpriced_models: ['mystery-model'],
  },
  projection: {
    week: { tokens: period(1000, 3000), cost_usd: period(40, 90) },
    month: { tokens: period(5000, 9000), cost_usd: period(120, 300) },
    by_project: [
      { project: 'alpha', week_cost_forecast: 60, month_cost_forecast: 200 },
      { project: 'beta', week_cost_forecast: 30, month_cost_forecast: 100 },
    ],
    pace,
  },
  projects: [
    { project: 'alpha', tokens: 70, cost_usd: 80, share: 0.67, change: 0.25, sessions: 2 },
    { project: 'beta', tokens: 30, cost_usd: 40, share: 0.33, change: null, sessions: 1 },
  ],
  models: [{ model: 'claude-opus-5-5', tokens: 100, cost_usd: 120, sessions: 3 }],
  sessions: [
    {
      id: 's1',
      title: 'Fix the login flow',
      project: 'alpha',
      started: '2026-10-13T09:00:00+00:00',
      ended: '2026-10-13T10:00:00+00:00',
      tokens: 70,
      cost_usd: 80,
      models: ['claude-opus-5-5'],
    },
  ],
  skills: [
    health('never-skill', 'never_used'),
    health('flaky-skill', 'troubled', { uses: 5, trend: [2, 5], trouble_rate: 0.6, invoked: 'auto' }),
    health('good-skill', 'healthy', { uses: 9, trend: [8, 9], invoked: 'both' }),
  ],
  agents: [health('Explore', 'healthy', { source: 'built-in', uses: 4, trend: [3, 4], invoked: 'auto' })],
  tools: {
    used: [
      { name: 'Read', calls: 50 },
      { name: 'Bash', calls: 20 },
    ],
    unused_builtin: ['NotebookEdit'],
    mcp_servers: [
      { name: 'github', source: 'user', calls: 0 },
      { name: 'claude-in-chrome', source: 'unknown', calls: 3 },
    ],
  },
};
