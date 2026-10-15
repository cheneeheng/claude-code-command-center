/** Skeleton blocks shaped like the three sections. */
export function LoadingState() {
  return (
    <div role="status" aria-busy="true" aria-label="Loading usage">
      {[0, 1, 2].map((s) => (
        <div key={s} className="section">
          <div className="skeleton skeleton-title" />
          <div className="grid">
            <div className="skeleton skeleton-card" />
            <div className="skeleton skeleton-card" />
          </div>
        </div>
      ))}
    </div>
  );
}
