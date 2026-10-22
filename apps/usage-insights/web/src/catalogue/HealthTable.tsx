import { useState } from 'react';

import { FIRST_ROWS, ShowAll } from '../components/ShowAll';
import type { HealthRow, HealthStatus } from '../lib/api';
import { share, shortDate } from '../lib/format';

/** Props of {@link HealthTable}. */
export type HealthTableProps = { rows: HealthRow[]; noun: 'skill' | 'subagent' };

const STATUS_LABEL: Record<HealthStatus, string> = {
  never_used: 'Never used',
  troubled: 'Troubled',
  declining: 'Declining',
  unused_lately: 'Unused lately',
  healthy: 'Healthy',
};

const INVOKED_LABEL = { auto: 'Claude', typed: 'You', both: 'Both' } as const;

/** Why a row has its status, in words: the decision the reader should take. */
function reason(row: HealthRow, noun: string): string {
  switch (row.status) {
    case 'never_used':
      return `Installed but never invoked: check its description triggers this ${noun}.`;
    case 'troubled':
      return `You interrupted within 15 minutes after ${Math.round(row.trouble_rate * 100)}% of recent uses.`;
    case 'declining':
      return `Uses fell from ${row.trend[0]} to ${row.trend[1]} (previous 30 days → last 30).`;
    case 'unused_lately':
      return `Not used since ${shortDate(row.last_used)}.`;
    case 'healthy':
      return `${row.trend[1]} uses in the last 30 days.`;
  }
}

/**
 * Skills or subagents with a status pill and the reason behind it, worst first.
 * Status chips above the table give the counts at a glance and filter the rows.
 */
export function HealthTable({ rows, noun }: HealthTableProps) {
  const [all, setAll] = useState(false);
  const [picked, setStatus] = useState<HealthStatus | undefined>(undefined);
  if (rows.length === 0) return <p className="muted empty-line">No {noun}s installed or used.</p>;
  const counts = (Object.keys(STATUS_LABEL) as HealthStatus[])
    .map((s) => [s, rows.filter((r) => r.status === s).length] as const)
    .filter(([, n]) => n > 0);
  // A picked status with no rows left (after a range change) falls back to All.
  const status = counts.some(([s]) => s === picked) ? picked : undefined;
  const filtered = status ? rows.filter((r) => r.status === status) : rows;
  const shown = all ? filtered : filtered.slice(0, FIRST_ROWS);
  return (
    <div className="table-wrap">
      <div className="chips" role="group" aria-label={`Filter ${noun}s by status`}>
        <button
          type="button"
          className="badge chip"
          aria-pressed={status === undefined}
          onClick={() => setStatus(undefined)}
        >
          All {rows.length}
        </button>
        {counts.map(([s, n]) => (
          <button
            key={s}
            type="button"
            className={`badge chip status status-${s}`}
            aria-pressed={status === s}
            onClick={() => setStatus(status === s ? undefined : s)}
          >
            {STATUS_LABEL[s]} {n}
          </button>
        ))}
      </div>
      <table className="table health">
        <thead>
          <tr>
            <th scope="col">{noun === 'skill' ? 'Skill' : 'Subagent'}</th>
            <th scope="col">Status</th>
            <th scope="col">Why</th>
            <th scope="col" className="num">
              Uses
            </th>
            <th scope="col">Last used</th>
            <th scope="col" className="num" title="Uses in the previous 30 days → the last 30">
              Trend
            </th>
            <th scope="col" className="num" title="Share of recent uses you interrupted within 15 minutes">
              Trouble
            </th>
            <th scope="col">Called by</th>
          </tr>
        </thead>
        <tbody>
          {shown.map((r) => (
            <tr key={r.name}>
              <td className="truncate" title={`${r.name} (${r.source})`}>
                <span className="mono">{r.name}</span>
                <span className="subtle source"> {r.source}</span>
              </td>
              <td>
                <span className={`badge status status-${r.status}`}>{STATUS_LABEL[r.status]}</span>
              </td>
              <td className="muted reason">{reason(r, noun)}</td>
              <td className="num numeric">{r.uses > 0 ? r.uses : '—'}</td>
              <td className="nowrap">{shortDate(r.last_used)}</td>
              <td className="num numeric nowrap">
                {r.trend[0] + r.trend[1] > 0 ? `${r.trend[0]} → ${r.trend[1]}` : '—'}
              </td>
              <td className="num numeric">{share(r.trouble_rate)}</td>
              <td>{r.invoked ? INVOKED_LABEL[r.invoked] : '—'}</td>
            </tr>
          ))}
        </tbody>
      </table>
      <ShowAll total={filtered.length} all={all} onToggle={() => setAll(!all)} />
    </div>
  );
}
