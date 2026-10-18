import { useState } from 'react';

import type { PaceDay } from '../lib/api';
import { shortDate, tokens, usd } from '../lib/format';

/** Props of {@link PaceStrip}. */
export type PaceStripProps = { days: PaceDay[] };

/** Daily bars for the given days (the server sends the last 30), tokens or cost. */
export function PaceStrip({ days }: PaceStripProps) {
  const [metric, setMetric] = useState<'cost_usd' | 'tokens'>('cost_usd');
  const fmt = metric === 'cost_usd' ? usd : tokens;
  const peak = Math.max(0, ...days.map((d) => d[metric]));
  const step = Math.max(1, Math.ceil(days.length / 6));
  return (
    <div className="pace">
      <div className="segmented" role="group" aria-label="Pace metric">
        {(['cost_usd', 'tokens'] as const).map((m) => (
          <button
            key={m}
            type="button"
            className="btn btn-ghost btn-sm"
            aria-pressed={metric === m}
            onClick={() => setMetric(m)}
          >
            {m === 'cost_usd' ? 'Cost' : 'Tokens'}
          </button>
        ))}
      </div>
      <ol className="pace-bars" aria-label={`Daily usage, last ${days.length} days`}>
        {days.map((d) => {
          const label = `${shortDate(d.date)}: ${fmt(d[metric])}`;
          const height = peak > 0 ? Math.max(2, Math.round((d[metric] / peak) * 100)) : 2;
          return (
            <li key={d.date} className="pace-day" title={label}>
              <span className="pace-bar" style={{ height: `${height}%` }} />
              <span className="sr-only">{label}</span>
            </li>
          );
        })}
      </ol>
      <div className="pace-axis subtle" aria-hidden="true">
        {/* One slot per bar; about six labels, counted back from the last day. */}
        {days.map((d, i) => (
          <span key={d.date}>{(days.length - 1 - i) % step === 0 ? shortDate(d.date) : ''}</span>
        ))}
      </div>
    </div>
  );
}
