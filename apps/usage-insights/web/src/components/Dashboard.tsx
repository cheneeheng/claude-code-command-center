import type { ComponentType, ReactNode } from 'react';

import { catalogue } from '../catalogue';
import type { Panel, PanelSize } from '../layout/defaultLayout';
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

/** The element id of a section, for the top bar's links. */
export const sectionAnchor = (id: string) => `section-${id}`;

/** A panel's frame: eyebrow and caption above, the body in a card. */
function Frame({ size, eyebrow, caption, children }: { size: PanelSize; eyebrow: string; caption: string; children: ReactNode }) {
  return (
    <div className={`panel panel-${size}`}>
      <p className="eyebrow">{eyebrow}</p>
      <p className="panel-caption muted">{caption}</p>
      <div className="card">{children}</div>
    </div>
  );
}

function PanelBlock({ panel, data }: { panel: Panel; data: Summary }) {
  // Each panel's select() returns exactly its component's props (see Panel).
  const Component = catalogue[panel.component] as ComponentType<object>;
  const count = panel.count?.(data);
  return (
    <Frame
      size={panel.size ?? 'half'}
      eyebrow={count === undefined ? panel.eyebrow : `${panel.eyebrow} · ${count}`}
      caption={panel.caption}
    >
      <Component {...(panel.select(data) as object)} />
    </Frame>
  );
}

/** Renders a layout: one titled section per question, its panels in a grid. */
export function Dashboard({ layout, data, range = data.range }: DashboardProps) {
  return (
    <>
      {layout.map((section) => (
        <section
          key={section.id}
          id={sectionAnchor(section.id)}
          className="section"
          aria-labelledby={`q-${section.id}`}
        >
          <h2 id={`q-${section.id}`}>{section.question}</h2>
          {section.note && <p className="section-note muted">{section.note}</p>}
          <div className="grid">
            {section.panels.map((panel) =>
              'kind' in panel ? (
                <Frame key={panel.id} size={panel.wide ? 'wide' : 'half'} eyebrow={panel.title} caption={panel.caption}>
                  <QueryPanel panel={panel} range={range} />
                </Frame>
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
