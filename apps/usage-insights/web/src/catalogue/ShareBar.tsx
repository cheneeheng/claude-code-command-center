import { Label } from '../components/Label';
import { share } from '../lib/format';

/** One part of the whole. `value` sizes it; `display` is what the reader sees. */
export type SharePart = { label: string; value: number; display: string };

/** Props of {@link ShareBar}. */
export type ShareBarProps = {
  parts: SharePart[];
  /** Shows the total in this form; omit when a sum would mislead. */
  totalDisplay?: string;
  emptyText: string;
};

/** Parts drawn in their own colour; the rest fold into one "N others" part. */
export const MAX_PARTS = 5;

/**
 * How a whole splits: one bar of coloured segments, then a legend row per part with its
 * figure and share. Parts past {@link MAX_PARTS} fold into one, so colours stay readable.
 */
export function ShareBar({ parts, totalDisplay, emptyText }: ShareBarProps) {
  const positive = parts.filter((p) => p.value > 0);
  const total = positive.reduce((sum, p) => sum + p.value, 0);
  if (total === 0) return <p className="muted empty-line">{emptyText}</p>;
  const head = positive.slice(0, MAX_PARTS).map((p, i) => ({ ...p, tone: `is-${i + 1}` }));
  const rest = positive.slice(MAX_PARTS);
  const other = rest.reduce((sum, p) => sum + p.value, 0);
  const shown =
    other > 0
      ? [...head, { label: `${rest.length} others`, value: other, display: '', tone: 'is-other' }]
      : head;
  return (
    <div className="share">
      {totalDisplay && <p className="share-total numeric">{totalDisplay}</p>}
      <div className="share-bar" role="img" aria-label={shown.map((p) => `${p.label} ${share(p.value / total)}`).join(', ')}>
        {shown.map((p) => (
          <span key={p.label} className={`share-seg ${p.tone}`} style={{ flexGrow: p.value }} title={p.label} />
        ))}
      </div>
      <ul className="share-legend">
        {shown.map((p) => (
          <li key={p.label} className="share-row">
            <span className={`legend-dot ${p.tone}`} aria-hidden="true" />
            <Label text={p.label} className="share-label" />
            <span className="muted numeric">{p.display}</span>
            <span className="share-pct numeric">{share(p.value / total)}</span>
          </li>
        ))}
      </ul>
    </div>
  );
}
