import type { Range } from '../lib/api';

/** Props of {@link EmptyState}. */
export type EmptyStateProps = {
  dataDirs: string[];
  storePath: string;
  /** The selected range, or `null` when there is no history at all. */
  quietRange: Range | null;
};

/** No usage: none at all, or none in the selected range. Says where the dashboard looked. */
export function EmptyState({ dataDirs, storePath, quietRange }: EmptyStateProps) {
  const days = quietRange && quietRange !== 'all' ? Number.parseInt(quietRange, 10) : null;
  return (
    <div className="state-panel">
      <h2>{days ? `No usage in the last ${days} days` : 'No Claude Code usage yet'}</h2>
      <p className="muted">
        {days ? 'Pick a longer range above, or use Claude Code and press Refresh.' : 'Use Claude Code, then press Refresh.'}{' '}
        The dashboard reads session transcripts from:
      </p>
      <ul className="mono">
        {dataDirs.map((d) => (
          <li key={d}>{d}</li>
        ))}
      </ul>
      <p className="subtle">
        Store: <span className="mono">{storePath}</span>
      </p>
    </div>
  );
}
