/** Range keys the server accepts for `/api/summary`. */
export const RANGES = ['7d', '30d', '90d', 'all'] as const;
/** One of {@link RANGES}. */
export type Range = (typeof RANGES)[number];

/** So far plus forecast for one period, with the low/high band. */
export type Period = { actual: number; forecast: number; low: number; high: number };
/** Tokens and cost for one period. */
export type PeriodPair = { tokens: Period; cost_usd: Period };
/** One day of the pace strip. */
export type PaceDay = { date: string; tokens: number; cost_usd: number };
/** A skill or subagent health status, worst first. */
export type HealthStatus = 'never_used' | 'troubled' | 'declining' | 'unused_lately' | 'healthy';

/** One skill or subagent row. */
export type HealthRow = {
  name: string;
  source: string;
  status: HealthStatus;
  uses: number;
  last_used: string | null;
  trend: [number, number];
  trouble_rate: number;
  invoked: 'auto' | 'typed' | 'both' | null;
};

/** One session in the top-sessions table. */
export type SessionRow = {
  id: string;
  title: string;
  project: string;
  started: string | null;
  ended: string | null;
  tokens: number;
  cost_usd: number;
  models: string[];
};

/** The `/api/summary` payload; mirrors `usage_insights.aggregate.summary`. */
export type Summary = {
  range: Range;
  generated_at: string;
  data_dirs: string[];
  store_path: string;
  last_export: string | null;
  totals: {
    cost_usd: number;
    tokens: { input: number; output: number; cache_write: number; cache_read: number; total: number };
    sessions: number;
    unpriced_models: string[];
    /** When the LiteLLM prices were fetched; `null` = the built-in table. */
    prices_as_of: string | null;
  };
  projection: {
    week: PeriodPair;
    month: PeriodPair;
    by_project: { project: string; week_cost_forecast: number; month_cost_forecast: number }[];
    pace: PaceDay[];
  };
  projects: {
    project: string;
    tokens: number;
    cost_usd: number;
    share: number;
    change: number | null;
    sessions: number;
  }[];
  models: { model: string; tokens: number; cost_usd: number; sessions: number }[];
  sessions: SessionRow[];
  skills: HealthRow[];
  agents: HealthRow[];
  tools: {
    used: { name: string; calls: number }[];
    unused_builtin: string[];
    mcp_servers: { name: string; source: string; calls: number }[];
  };
  /** Whether `C4_USAGE_INSIGHTS_API_KEY` is set, so the chat can run. */
  chat: { enabled: boolean };
};

/** One row of a query result; `previous` and `change` only with `compare`. */
export type QueryRow = {
  key: string;
  label: string;
  value: number;
  previous?: number;
  change?: number | null;
};

/** The `/api/query` result; mirrors `usage_insights.query.run`. */
export type QueryResult = {
  metric: string;
  group_by: string;
  range: string;
  unit: 'usd' | 'tokens' | 'count';
  rows: QueryRow[];
  total: number;
  truncated: boolean;
};

/** Counts from one export run (`POST /api/refresh`). */
export type RefreshResult = {
  files_scanned: number;
  files_parsed: number;
  messages: number;
  events: number;
};

/** A non-2xx response; `message` is the server's `error` text. */
export class ApiRequestError extends Error {
  constructor(
    public readonly status: number,
    message: string,
  ) {
    super(message);
  }
}

async function request<T>(path: string, init?: RequestInit): Promise<T> {
  const response = await send(path, init);
  return (await response.json()) as T;
}

/** A 2xx response, or {@link ApiRequestError}. */
async function send(path: string, init?: RequestInit): Promise<Response> {
  const response = await fetch(path, init);
  if (!response.ok) {
    let message = `${response.status} ${response.statusText}`;
    try {
      const body = (await response.json()) as { error?: string };
      message = body.error ?? message;
    } catch {
      // Not JSON: keep the status line.
    }
    throw new ApiRequestError(response.status, message);
  }
  return response;
}

const JSON_HEADERS = { 'Content-Type': 'application/json' };

/** The one place the frontend talks to the server. */
export const apiClient = {
  /**
   * Fetch the dashboard payload for a range.
   * @throws {ApiRequestError} On non-2xx response.
   */
  getSummary(range: Range): Promise<Summary> {
    return request<Summary>(`/api/summary?range=${range}`);
  },
  /**
   * Export new transcripts into the store.
   * @throws {ApiRequestError} 409 while another export runs.
   */
  refresh(): Promise<RefreshResult> {
    return request<RefreshResult>('/api/refresh', { method: 'POST' });
  },
  /**
   * Run a typed query. `range` is the top bar's, used when the spec has none.
   * @throws {ApiRequestError} 400 on a bad spec.
   */
  query(spec: unknown, range: Range): Promise<QueryResult> {
    return request<QueryResult>(`/api/query?range=${range}`, {
      method: 'POST',
      headers: JSON_HEADERS,
      body: JSON.stringify(spec),
    });
  },
  /** The saved layout, or `null` when none is saved (204). */
  async getLayout(): Promise<unknown> {
    const response = await send('/api/layout');
    return response.status === 204 ? null : ((await response.json()) as unknown);
  },
  /** Save the layout. */
  async putLayout(layout: unknown): Promise<void> {
    await send('/api/layout', { method: 'PUT', headers: JSON_HEADERS, body: JSON.stringify(layout) });
  },
  /** Forget the saved layout (Reset). */
  async deleteLayout(): Promise<void> {
    await send('/api/layout', { method: 'DELETE' });
  },
};
