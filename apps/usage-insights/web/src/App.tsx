import { useState } from 'react';

import { Dashboard } from './components/Dashboard';
import { EmptyState } from './components/EmptyState';
import { ErrorState } from './components/ErrorState';
import { LoadingState } from './components/LoadingState';
import { TopBar } from './components/TopBar';
import { useRefresh } from './hooks/useRefresh';
import { useSummary } from './hooks/useSummary';
import { defaultLayout } from './layout/defaultLayout';
import type { Range, Summary } from './lib/api';

/** No store yet, or a store with no usage at all. */
export function isEmpty(data: Summary): boolean {
  return (
    data.last_export === null ||
    (data.sessions.length === 0 && data.projection.pace.every((d) => d.tokens === 0))
  );
}

/** The page: top bar, then the dashboard or the state that stands in for it. */
export function App() {
  const [range, setRange] = useState<Range>('30d');
  const { data, error, reload } = useSummary(range);
  const refresh = useRefresh(reload);

  let body;
  if (error && !data) body = <ErrorState message={error} onRetry={reload} />;
  else if (!data) body = <LoadingState />;
  else if (isEmpty(data)) body = <EmptyState dataDirs={data.data_dirs} storePath={data.store_path} />;
  else body = <Dashboard layout={defaultLayout} data={data} />;

  return (
    <>
      <TopBar
        range={range}
        onRange={setRange}
        lastExport={data?.last_export}
        refreshing={refresh.busy}
        refreshMessage={refresh.message ?? (error && data ? `Could not reload: ${error}` : undefined)}
        onRefresh={() => void refresh.run()}
      />
      <main className="content">{body}</main>
    </>
  );
}
