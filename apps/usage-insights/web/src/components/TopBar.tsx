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
  /** Whether the chat key is set; `undefined` (still loading) shows no Chat button. */
  chatEnabled?: boolean;
  onChat?: () => void;
  chatOpen?: boolean;
};

/** Why the Chat button is disabled; matches the server's 503 message. */
export const CHAT_HINT = 'Set C4_USAGE_INSIGHTS_API_KEY and restart usage-insights to use the chat';

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
  chatEnabled,
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
        {chatEnabled !== undefined && (
          // aria-disabled, not disabled: keyboard users can still focus it and hear the hint.
          <button
            type="button"
            className="btn btn-outline"
            aria-pressed={chatEnabled ? chatOpen : undefined}
            aria-disabled={chatEnabled ? undefined : true}
            title={chatEnabled ? undefined : CHAT_HINT}
            onClick={chatEnabled ? onChat : undefined}
          >
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
