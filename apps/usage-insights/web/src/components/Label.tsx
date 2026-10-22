import { splitLabel } from '../lib/format';

/** A row label that truncates, with its parenthesised detail quieter after the name. */
export function Label({ text, className = '' }: { text: string; className?: string }) {
  const [name, detail] = splitLabel(text);
  return (
    <span className={`label ${className}`} title={text}>
      {name}
      {detail && <span className="label-detail subtle"> {detail}</span>}
    </span>
  );
}
