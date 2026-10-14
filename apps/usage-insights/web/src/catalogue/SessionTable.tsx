import { useState } from 'react';

import type { SessionRow } from '../lib/api';
import { shortDate, tokens, usd } from '../lib/format';

/** Props of {@link SessionTable}. */
export type SessionTableProps = { sessions: SessionRow[] };

const FIRST = 10;

/** The heaviest sessions in range: title, project, date, tokens, cost. */
export function SessionTable({ sessions }: SessionTableProps) {
  const [all, setAll] = useState(false);
  if (sessions.length === 0) return <p className="muted empty-line">No sessions in this range.</p>;
  const shown = all ? sessions : sessions.slice(0, FIRST);
  return (
    <div className="table-wrap">
      <table className="table">
        <thead>
          <tr>
            <th scope="col">Session</th>
            <th scope="col">Project</th>
            <th scope="col">Last active</th>
            <th scope="col" className="num">
              Tokens
            </th>
            <th scope="col" className="num">
              Cost
            </th>
          </tr>
        </thead>
        <tbody>
          {shown.map((s) => (
            <tr key={s.id}>
              <td className="truncate" title={s.title}>
                {s.title}
              </td>
              <td className="truncate" title={s.project}>
                {s.project}
              </td>
              <td className="numeric">{shortDate(s.ended)}</td>
              <td className="num numeric">{tokens(s.tokens)}</td>
              <td className="num numeric">{usd(s.cost_usd)}</td>
            </tr>
          ))}
        </tbody>
      </table>
      {sessions.length > FIRST && (
        <button type="button" className="btn btn-ghost btn-sm" onClick={() => setAll(!all)}>
          {all ? 'Show fewer' : `Show ${sessions.length}`}
        </button>
      )}
    </div>
  );
}
