import { type ComponentType, useEffect, useState } from 'react';

import type { KindProps } from '../catalogue/define';
import { type GeneratedPanel, kinds } from '../catalogue/kinds';
import { apiClient, type QueryResult, type Range } from '../lib/api';

/** Props of {@link QueryPanel}. */
export type QueryPanelProps = { panel: GeneratedPanel; range: Range };

function emptyText(range: string): string {
  if (range === 'all') return 'No data for this query.';
  if (range === 'month') return 'No data for this query this month.';
  return `No data for this query in the last ${Number.parseInt(range, 10)} days.`;
}

/**
 * A generated panel's body: fetches `/api/query` for its spec and draws the result with
 * its kind. Without its own range the query follows the top bar's, and refetches with it.
 */
export function QueryPanel({ panel, range }: QueryPanelProps) {
  const [result, setResult] = useState<QueryResult | undefined>(undefined);
  const [error, setError] = useState<string | undefined>(undefined);
  const [tick, setTick] = useState(0);
  const spec = JSON.stringify(panel.query);

  useEffect(() => {
    let active = true;
    setResult(undefined);
    setError(undefined);
    apiClient
      .query(JSON.parse(spec), range)
      .then((r) => active && setResult(r))
      .catch((e: unknown) => active && setError(e instanceof Error ? e.message : String(e)));
    return () => {
      active = false;
    };
  }, [spec, range, tick]);

  if (error)
    return (
      <div role="alert">
        <p className="text-danger">Could not load this panel: {error}</p>
        <button type="button" className="btn btn-outline btn-sm" onClick={() => setTick((t) => t + 1)}>
          Retry
        </button>
      </div>
    );
  if (!result) return <div className="skeleton skeleton-card" role="status" aria-label="Loading panel" />;
  if (result.rows.every((r) => r.value === 0) && result.total === 0)
    return <p className="muted empty-line">{emptyText(result.range)}</p>;
  const Kind = kinds[panel.kind].Component as ComponentType<KindProps<GeneratedPanel>>;
  return <Kind panel={panel} result={result} />;
}
