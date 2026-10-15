import { useState } from 'react';

/** One ranked row. `value` sizes the bar; `display` is what the reader sees. */
export type RankedRow = { label: string; value: number; display: string; secondary?: string };

/** Props of {@link RankedBars}. */
export type RankedBarsProps = {
  rows: RankedRow[];
  /** Rows shown before "Show all". */
  limit?: number;
  emptyText: string;
};

/** A ranked list with a proportional bar per row. */
export function RankedBars({ rows, limit = 10, emptyText }: RankedBarsProps) {
  const [all, setAll] = useState(false);
  if (rows.length === 0) return <p className="muted empty-line">{emptyText}</p>;
  const peak = Math.max(...rows.map((r) => r.value));
  const shown = all ? rows : rows.slice(0, limit);
  return (
    <div>
      <ol className="ranked">
        {shown.map((r) => (
          <li key={r.label} className="ranked-row">
            <span className="ranked-label" title={r.label}>
              {r.label}
            </span>
            <span className="ranked-value numeric">{r.display}</span>
            <span className="bar-track ranked-bar">
              <span
                className="bar-fill is-1"
                style={{ width: `${peak > 0 ? Math.max(1, (r.value / peak) * 100) : 0}%` }}
              />
            </span>
            {r.secondary && <span className="ranked-secondary subtle numeric">{r.secondary}</span>}
          </li>
        ))}
      </ol>
      {rows.length > limit && (
        <button type="button" className="btn btn-ghost btn-sm" onClick={() => setAll(!all)}>
          {all ? 'Show fewer' : `Show all ${rows.length}`}
        </button>
      )}
    </div>
  );
}
