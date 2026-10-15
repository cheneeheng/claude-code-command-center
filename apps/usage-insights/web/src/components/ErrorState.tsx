/** Props of {@link ErrorState}. */
export type ErrorStateProps = { message: string; onRetry: () => void };

/** What failed and a way to try again, in place of the dashboard. */
export function ErrorState({ message, onRetry }: ErrorStateProps) {
  return (
    <div className="state-panel" role="alert">
      <p className="eyebrow text-danger">Could not load usage</p>
      <p>{message}</p>
      <button type="button" className="btn btn-outline" onClick={onRetry}>
        Retry
      </button>
    </div>
  );
}
