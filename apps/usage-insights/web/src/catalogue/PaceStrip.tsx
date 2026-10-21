import { useState } from 'react';

import type { PaceDay } from '../lib/api';
import { shortDate, tokens, usd } from '../lib/format';

/** Props of {@link PaceStrip}. */
export type PaceStripProps = { days: PaceDay[] };

/** One bar of {@link DayBars}: a `YYYY-MM-DD` key and its value. */
export type DayBar = { date: string; value: number };

/** Bars per day (or week), oldest first, the last one highlighted, with about six date labels. */
export function DayBars({ bars, fmt, label }: { bars: DayBar[]; fmt: (n: number) => string; label: string }) {
  const peak = Math.max(0, ...bars.map((d) => d.value));
  const step = Math.max(1, Math.ceil(bars.length / 6));
  return (
    <>
      <ol className="pace-bars" aria-label={label}>
        {bars.map((d) => {
          const text = `${shortDate(d.date)}: ${fmt(d.value)}`;
          const height = peak > 0 ? Math.max(2, Math.round((d.value / peak) * 100)) : 2;
          return (
            <li key={d.date} className="pace-day" title={text}>
              <span className="pace-bar" style={{ height: `${height}%` }} />
              <span className="sr-only">{text}</span>
            </li>
          );
        })}
      </ol>
      <div className="pace-axis subtle" aria-hidden="true">
        {/* One slot per bar; about six labels, counted back from the last day. */}
        {bars.map((d, i) => (
          <span key={d.date}>{(bars.length - 1 - i) % step === 0 ? shortDate(d.date) : ''}</span>
        ))}
      </div>
    </>
  );
}

/** Daily bars for the given days (the server sends the last 30), tokens or cost. */
export function PaceStrip({ days }: PaceStripProps) {
  const [metric, setMetric] = useState<'cost_usd' | 'tokens'>('cost_usd');
  const fmt = metric === 'cost_usd' ? usd : tokens;
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
      <DayBars
        bars={days.map((d) => ({ date: d.date, value: d[metric] }))}
        fmt={fmt}
        label={`Daily usage, last ${days.length} days`}
      />
    </div>
  );
}
