const compact = new Intl.NumberFormat('en', { notation: 'compact', maximumFractionDigits: 1 });
const whole = new Intl.NumberFormat('en', { maximumFractionDigits: 0 });

/** Dollars: whole above $100, cents below. */
export function usd(value: number): string {
  return value >= 100 ? `$${whole.format(value)}` : `$${value.toFixed(2)}`;
}

/** Token counts: compact (`1.2M`). */
export function tokens(value: number): string {
  return compact.format(value);
}

/** A query value in its unit: dollars, compact tokens, or a whole count. */
export function byUnit(value: number, unit: 'usd' | 'tokens' | 'count'): string {
  if (unit === 'usd') return usd(value);
  return unit === 'tokens' ? tokens(value) : whole.format(value);
}

/** A signed percentage change, or an em dash when there is nothing to compare. */
export function change(value: number | null): string {
  if (value === null) return '—';
  const pct = Math.round(value * 100);
  return `${pct > 0 ? '+' : ''}${pct}%`;
}

/** A share of a whole as a percentage, `<1%` for small nonzero shares. */
export function share(value: number): string {
  return value > 0 && value < 0.01 ? '<1%' : `${Math.round(value * 100)}%`;
}

/** A short local date (`Oct 3`) for an ISO timestamp or `YYYY-MM-DD`. */
export function shortDate(iso: string | null): string {
  if (!iso) return '—';
  const date = iso.length === 10 ? new Date(`${iso}T00:00:00`) : new Date(iso);
  return date.toLocaleDateString('en', { month: 'short', day: 'numeric' });
}

/** How long ago an ISO timestamp was, relative to `now`. */
export function ago(iso: string, now: Date = new Date()): string {
  const minutes = Math.round((now.getTime() - new Date(iso).getTime()) / 60000);
  if (minutes < 1) return 'just now';
  if (minutes < 60) return `${minutes} min ago`;
  const hours = Math.round(minutes / 60);
  return hours < 48 ? `${hours} h ago` : `${Math.round(hours / 24)} days ago`;
}
