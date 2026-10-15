import { useCallback, useEffect, useState } from 'react';

import { apiClient, type Range, type Summary } from '../lib/api';

/** The summary for a range. Earlier data stays visible while a reload runs. */
export function useSummary(range: Range) {
  const [data, setData] = useState<Summary | undefined>(undefined);
  const [error, setError] = useState<string | undefined>(undefined);
  const [loading, setLoading] = useState(true);
  const [tick, setTick] = useState(0);

  useEffect(() => {
    let active = true;
    setLoading(true);
    apiClient
      .getSummary(range)
      .then((summary) => {
        if (!active) return;
        setData(summary);
        setError(undefined);
      })
      .catch((e: unknown) => {
        if (active) setError(e instanceof Error ? e.message : String(e));
      })
      .finally(() => {
        if (active) setLoading(false);
      });
    return () => {
      active = false;
    };
  }, [range, tick]);

  const reload = useCallback(() => setTick((t) => t + 1), []);
  return { data, error, loading, reload };
}
