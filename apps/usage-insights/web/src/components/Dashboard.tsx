import type { ComponentType } from 'react';

import { catalogue } from '../catalogue';
import type { Panel, Section } from '../layout/defaultLayout';
import type { Summary } from '../lib/api';

/** Props of {@link Dashboard}. */
export type DashboardProps = { layout: Section[]; data: Summary };

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

/** Renders a layout: one titled section per question, its panels in a grid. */
export function Dashboard({ layout, data }: DashboardProps) {
  return (
    <>
      {layout.map((section) => (
        <section key={section.id} className="section" aria-labelledby={`q-${section.id}`}>
          <h2 id={`q-${section.id}`}>{section.question}</h2>
          <div className="grid">
            {section.panels.map((panel) => (
              <PanelBlock key={panel.id} panel={panel} data={data} />
            ))}
          </div>
        </section>
      ))}
    </>
  );
}
