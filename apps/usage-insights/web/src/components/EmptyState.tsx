/** Props of {@link EmptyState}. */
export type EmptyStateProps = { dataDirs: string[]; storePath: string };

/** First run or no transcripts: where the dashboard looked, and what fills it. */
export function EmptyState({ dataDirs, storePath }: EmptyStateProps) {
  return (
    <div className="state-panel">
      <h2>No Claude Code usage yet</h2>
      <p className="muted">
        Use Claude Code, then press Refresh. The dashboard reads session transcripts from:
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
