import { shortDate, tokens, usd } from '../lib/format';

/** Props of {@link StatTile}: one period's so-far and forecast. */
export type StatTileProps = {
  actual: number;
  forecast: number;
  low: number;
  high: number;
  unit: 'usd' | 'tokens';
  /** A muted line under the scale, e.g. the token forecast. */
  secondary?: string;
  /** Models with no price; their cost is missing from the figures. */
  unpriced?: string[];
  /** When the fetched prices are from; `null` means the built-in table. Omit to hide. */
  pricesAsOf?: string | null;
};

function pct(value: number, max: number): string {
  return `${max > 0 ? Math.min(100, Math.max(0, (value / max) * 100)) : 0}%`;
}

/**
 * A forecast stat. The scale runs from zero to the high end of the band: the
 * solid fill is spent so far, the wash is the likely range, the tick the forecast.
 */
export function StatTile({
  actual,
  forecast,
  low,
  high,
  unit,
  secondary,
  unpriced,
  pricesAsOf,
}: StatTileProps) {
  const fmt = unit === 'usd' ? usd : tokens;
  const max = Math.max(high, actual);
  return (
    <div className="stat-tile">
      <p className="stat-value numeric">
        {fmt(forecast)}
        <span className="stat-unit muted"> forecast</span>
      </p>
      <div
        className="scale"
        role="img"
        aria-label={`${fmt(actual)} so far, forecast ${fmt(forecast)}, likely ${fmt(low)} to ${fmt(high)}`}
      >
        <span className="scale-band" style={{ left: pct(low, max), right: `calc(100% - ${pct(high, max)})` }} />
        <span className="scale-actual" style={{ width: pct(actual, max) }} />
        <span className="scale-tick" style={{ left: pct(forecast, max) }} />
      </div>
      <p className="muted numeric stat-caption">
        {fmt(actual)} so far · likely {fmt(low)}–{fmt(high)}
      </p>
      {secondary && <p className="subtle numeric stat-caption">{secondary}</p>}
      {unpriced && unpriced.length > 0 && (
        <p className="badge badge-accent" title={unpriced.join(', ')}>
          {unpriced.length} unpriced model{unpriced.length > 1 ? 's' : ''} not counted
        </p>
      )}
      {pricesAsOf !== undefined && (
        <p className="subtle stat-caption">
          {pricesAsOf ? `Prices from LiteLLM, ${shortDate(pricesAsOf)}` : 'Built-in prices'}
        </p>
      )}
    </div>
  );
}
