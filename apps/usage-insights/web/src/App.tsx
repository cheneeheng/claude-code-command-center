import { useState } from 'react';

import { ChatDrawer } from './components/ChatDrawer';
import { Dashboard } from './components/Dashboard';
import { EmptyState } from './components/EmptyState';
import { ErrorState } from './components/ErrorState';
import { LoadingState } from './components/LoadingState';
import { TopBar } from './components/TopBar';
import { useAgent } from './hooks/useAgent';
import { useLayout } from './hooks/useLayout';
import { useRefresh } from './hooks/useRefresh';
import { useSummary } from './hooks/useSummary';
import { resolve } from './layout/model';
import type { Range, Summary } from './lib/api';

/** No store yet, or no sessions in the range and no usage in the last 30 days. */
export function isEmpty(data: Summary): boolean {
  return (
    data.last_export === null ||
    (data.sessions.length === 0 && data.projection.pace.every((d) => d.tokens === 0))
  );
}

/** The page: top bar, then the dashboard or the state that stands in for it. */
export function App() {
  const [range, setRange] = useState<Range>('30d');
  // Before useSummary: the layout request goes out first.
  const layout = useLayout();
  const { data, error, loading, reload } = useSummary(range);
  const refresh = useRefresh(reload);
  const chat = useAgent(layout.layout, layout.apply);
  const [chatOpen, setChatOpen] = useState(false);
  const chatEnabled = data?.chat?.enabled === true;
  // Figures from another range (or being replaced) are dimmed and marked busy.
  const stale = data !== undefined && (loading || data.range !== range);

  let body;
  if (!data) body = error && !loading ? <ErrorState message={error} onRetry={reload} /> : <LoadingState />;
  else if (layout.loading) body = <LoadingState />;
  else if (isEmpty(data))
    body = (
      <EmptyState
        dataDirs={data.data_dirs}
        storePath={data.store_path}
        quietRange={data.last_export === null ? null : data.range}
      />
    );
  else body = <Dashboard layout={resolve(layout.layout)} data={data} range={range} />;

  const drawerOpen = chatEnabled && chatOpen;
  return (
    <div className={drawerOpen ? 'page with-drawer' : 'page'}>
      <TopBar
        range={range}
        onRange={setRange}
        lastExport={data?.last_export}
        refreshing={refresh.busy}
        refreshMessage={
          refresh.message ?? (error && data ? `Could not reload: ${error}` : undefined) ?? layout.message
        }
        refreshFailed={refresh.failed}
        onRefresh={() => void refresh.run()}
        onResetLayout={layout.saved ? () => void layout.reset() : undefined}
        chatEnabled={data?.chat?.enabled}
        onChat={() => setChatOpen(!chatOpen)}
        chatOpen={chatOpen}
      />
      <main className={stale ? 'content stale' : 'content'} aria-busy={stale}>
        {body}
      </main>
      {drawerOpen && <ChatDrawer chat={chat} saveError={layout.saveError} onClose={() => setChatOpen(false)} />}
    </div>
  );
}
