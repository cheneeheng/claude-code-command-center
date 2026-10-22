import type { PaceDay, Period } from '../lib/api';
import { shortDate, usd } from '../lib/format';

/** Props of {@link MonthBurn}: the pace days (the last one today) and this month's cost. */
export type MonthBurnProps = { days: PaceDay[]; month: Period };

/** A point on the month: day of month (0 = before the 1st) and cost so far. */
export type BurnPoint = [day: number, cost: number];

/**
 * Cost so far for each day of this month up to today. It ends on `actual`, so a month
 * day older than the pace window (the 1st, on the 31st) is folded into the start.
 */
export function burnPoints(days: PaceDay[], actual: number): { points: BurnPoint[]; monthDays: number } {
  const today = days.at(-1)?.date ?? '';
  const [year, month] = today.split('-').map(Number);
  const inMonth = days.filter((d) => d.date.startsWith(today.slice(0, 7)));
  let cost = actual - inMonth.reduce((sum, d) => sum + d.cost_usd, 0);
  const first = Number(inMonth[0]?.date.slice(8) ?? 1);
  const points: BurnPoint[] = [[first - 1, cost]];
  for (const d of inMonth) {
    cost += d.cost_usd;
    points.push([Number(d.date.slice(8)), cost]);
  }
  return { points, monthDays: new Date(year, month, 0).getDate() };
}

/**
 * This month's cost building up day by day, then the forecast to the month's end:
 * a solid line for spent, a dashed one to the forecast, and the likely band behind it.
 */
export function MonthBurn({ days, month }: MonthBurnProps) {
  if (days.length === 0) return <p className="muted empty-line">No usage yet this month.</p>;
  const { points, monthDays } = burnPoints(days, month.actual);
  const [today] = points.at(-1) as BurnPoint;
  const top = Math.max(month.high, month.forecast, month.actual) || 1;
  const xy = ([d, v]: BurnPoint) => `${((d / monthDays) * 100).toFixed(2)},${(100 - (v / top) * 100).toFixed(2)}`;
  const now: BurnPoint = [today, month.actual];
  const end = `${days.at(-1)?.date.slice(0, 8)}${String(monthDays).padStart(2, '0')}`;
  return (
    <div className="burn">
      <svg
        className="burn-chart"
        viewBox="0 0 100 100"
        preserveAspectRatio="none"
        role="img"
        aria-label={`${usd(month.actual)} spent so far, forecast ${usd(month.forecast)} by ${shortDate(end)}, likely ${usd(month.low)} to ${usd(month.high)}`}
      >
        <polygon className="burn-band" points={`${xy(now)} ${xy([monthDays, month.high])} ${xy([monthDays, month.low])}`} />
        <polyline className="burn-forecast" points={`${xy(now)} ${xy([monthDays, month.forecast])}`} />
        <polyline className="burn-actual" points={points.map(xy).join(' ')} />
      </svg>
      <div className="burn-axis subtle numeric" aria-hidden="true">
        <span>{shortDate(`${end.slice(0, 8)}01`)}</span>
        <span>{shortDate(end)}</span>
      </div>
      <p className="burn-caption muted numeric">
        <span className="burn-key burn-key-actual" aria-hidden="true" /> {usd(month.actual)} so far
        <span className="burn-key burn-key-forecast" aria-hidden="true" /> {usd(month.forecast)} forecast
      </p>
    </div>
  );
}
