import type { ComponentType } from 'react';

import { catalogue } from '../catalogue';
import type { GeneratedPanel } from '../catalogue/kinds';
import type { Panel } from '../layout/defaultLayout';
import type { ResolvedSection } from '../layout/model';
import type { Range, Summary } from '../lib/api';
import { QueryPanel } from './QueryPanel';

/** Props of {@link Dashboard}. */
export type DashboardProps = {
  layout: ResolvedSection[];
  data: Summary;
  /** The top bar's range, which generated panels without their own follow. Default: the data's. */
  range?: Range;
};

function PanelBlock({ panel, data }: { panel: Panel; data: Summary }) {
  // Each panel's select() returns exactly its component's props (see Panel).
  const Component = catalogue[panel.component] as ComponentType<object>;
  const count = panel.count?.(data);
  return (
    <div className={panel.wide ? 'panel panel-wide' : 'panel'}>
      <p className="eyebrow">
        {panel.eyebrow}
        {count !== undefined && ` · ${count}`}
      </p>
      <p className="panel-caption muted">{panel.caption}</p>
      <div className="card">
        <Component {...(panel.select(data) as object)} />
      </div>
    </div>
  );
}

function GeneratedBlock({ panel, range }: { panel: GeneratedPanel; range: Range }) {
  return (
    <div className={panel.wide ? 'panel panel-wide' : 'panel'}>
      <p className="eyebrow">{panel.title}</p>
      <p className="panel-caption muted">{panel.caption}</p>
      <div className="card">
        <QueryPanel panel={panel} range={range} />
      </div>
    </div>
  );
}

/** Renders a layout: one titled section per question, its panels in a grid. */
export function Dashboard({ layout, data, range = data.range }: DashboardProps) {
  return (
    <>
      {layout.map((section) => (
        <section key={section.id} className="section" aria-labelledby={`q-${section.id}`}>
          <h2 id={`q-${section.id}`}>{section.question}</h2>
          {section.note && <p className="section-note muted">{section.note}</p>}
          <div className="grid">
            {section.panels.map((panel) =>
              'kind' in panel ? (
                <GeneratedBlock key={panel.id} panel={panel} range={range} />
              ) : (
                <PanelBlock key={panel.id} panel={panel} data={data} />
              ),
            )}
          </div>
        </section>
      ))}
    </>
  );
}
