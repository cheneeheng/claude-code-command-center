/** Rows a list or table shows before "Show all". */
export const FIRST_ROWS = 5;

/** Props of {@link ShowAll}. */
export type ShowAllProps = { total: number; all: boolean; onToggle: () => void; limit?: number };

/** The "Show all N" / "Show less" toggle under a capped list. Nothing when every row fits. */
export function ShowAll({ total, all, onToggle, limit = FIRST_ROWS }: ShowAllProps) {
  if (total <= limit) return null;
  return (
    <button type="button" className="btn btn-ghost btn-sm" onClick={onToggle}>
      {all ? 'Show less' : `Show all ${total}`}
    </button>
  );
}
