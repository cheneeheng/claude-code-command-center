/** One headline figure. */
export type Kpi = { label: string; value: string; caption?: string };

/** Props of {@link KpiStrip}. */
export type KpiStripProps = { items: Kpi[] };

/** A row of headline figures, each a value over a small label, split by hairlines. */
export function KpiStrip({ items }: KpiStripProps) {
  return (
    <dl className="kpis">
      {items.map((k) => (
        <div key={k.label} className="kpi">
          <dt className="eyebrow">{k.label}</dt>
          <dd className="kpi-value numeric">{k.value}</dd>
          {k.caption && <dd className="kpi-caption muted">{k.caption}</dd>}
        </div>
      ))}
    </dl>
  );
}
