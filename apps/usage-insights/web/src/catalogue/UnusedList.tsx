/** Props of {@link UnusedList}. */
export type UnusedListProps = { items: { name: string; source: string }[]; emptyText: string };

/** Names with nothing to rank: things installed but not called in range. */
export function UnusedList({ items, emptyText }: UnusedListProps) {
  if (items.length === 0) return <p className="muted empty-line">{emptyText}</p>;
  return (
    <ul className="unused">
      {items.map((i) => (
        <li key={`${i.source}:${i.name}`} className="badge badge-dashed" title={i.source}>
          <span className="mono">{i.name}</span>
          <span className="subtle"> {i.source}</span>
        </li>
      ))}
    </ul>
  );
}
