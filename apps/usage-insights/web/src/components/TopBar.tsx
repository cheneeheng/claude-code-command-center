import { RANGES, type Range } from '../lib/api';
import { ago } from '../lib/format';

/** Props of {@link TopBar}. */
export type TopBarProps = {
  range: Range;
  onRange: (range: Range) => void;
  lastExport: string | null | undefined;
  refreshing: boolean;
  refreshMessage: string | undefined;
  /** The last refresh failed (not "already running"): show a Retry beside the message. */
  refreshFailed: boolean;
  onRefresh: () => void;
  /** Return to the default layout; the button shows only when a saved layout exists. */
  onResetLayout?: () => void;
  /** Open or close the chat; the button shows only when the chat is enabled. */
  onChat?: () => void;
  chatOpen?: boolean;
};

const RANGE_LABEL: Record<Range, string> = { '7d': '7 days', '30d': '30 days', '90d': '90 days', all: 'All' };

/** Product name, range control, last export time, and the one primary action. */
export function TopBar({
  range,
  onRange,
  lastExport,
  refreshing,
  refreshMessage,
  refreshFailed,
  onRefresh,
  onResetLayout,
  onChat,
  chatOpen = false,
}: TopBarProps) {
  return (
    <header className="topbar">
      <h1 className="brand">usage-insights</h1>
      <div className="topbar-controls">
        <div className="segmented" role="group" aria-label="Range">
          {RANGES.map((r) => (
            <button
              key={r}
              type="button"
              className="btn btn-ghost btn-sm"
              aria-pressed={range === r}
              onClick={() => onRange(r)}
            >
              {RANGE_LABEL[r]}
            </button>
          ))}
        </div>
        {lastExport && <span className="subtle">Exported {ago(lastExport)}</span>}
        {onResetLayout && (
          <button type="button" className="btn btn-ghost" onClick={onResetLayout}>
            Reset layout
          </button>
        )}
        {onChat && (
          <button type="button" className="btn btn-outline" aria-pressed={chatOpen} onClick={onChat}>
            Chat
          </button>
        )}
        <button type="button" className="btn btn-primary" onClick={onRefresh} disabled={refreshing}>
          {refreshing && <span className="spinner" aria-hidden="true" />}
          {refreshing ? 'Refreshing…' : 'Refresh'}
        </button>
      </div>
      <p className="refresh-message" role="status" aria-live="polite">
        {refreshMessage}
        {refreshFailed && !refreshing && (
          <>
            {' '}
            <button type="button" className="btn btn-ghost btn-sm" onClick={onRefresh}>
              Retry
            </button>
          </>
        )}
      </p>
    </header>
  );
}
