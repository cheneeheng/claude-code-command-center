import type { PanelFields } from '../catalogue/kinds';
import { defaultLayout } from './defaultLayout';
import type { Layout, PanelEntry } from './model';

/** An edit's outcome: the new layout and what the agent is told, or an error for the agent. */
export type EditResult = { layout: Layout; message: string } | { error: string };

const eyebrows = new Map(defaultLayout.flatMap((s) => s.panels.map((p) => [p.id, p.eyebrow] as const)));

const panelId = (p: PanelEntry) => ('ref' in p ? p.ref : p.id);
const title = (p: PanelEntry) => ('ref' in p ? (eyebrows.get(p.ref) ?? p.ref) : p.title);

/** What the agent sees of the layout: section ids and questions, panel ids and titles. */
export function layoutState(layout: Layout) {
  return {
    sections: layout.sections.map((s) => ({
      id: s.id,
      question: s.question,
      panels: s.panels.map((p) => ({ id: panelId(p), title: title(p) })),
    })),
  };
}

function find(layout: Layout, id: string): [number, number] | null {
  for (const [si, s] of layout.sections.entries()) {
    const pi = s.panels.findIndex((p) => panelId(p) === id);
    if (pi >= 0) return [si, pi];
  }
  return null;
}

function withPanels(layout: Layout, si: number, panels: PanelEntry[]): Layout {
  return { ...layout, sections: layout.sections.map((s, i) => (i === si ? { ...s, panels } : s)) };
}

/** Place a new generated panel at the end of a section. The canvas sets its id. */
export function addPanel(layout: Layout, sectionId: string, fields: PanelFields, id: string): EditResult {
  const si = layout.sections.findIndex((s) => s.id === sectionId);
  if (si < 0) return { error: `error: no section with id ${sectionId}` };
  const panel = { ...fields, id } as PanelEntry;
  return { layout: withPanels(layout, si, [...layout.sections[si].panels, panel]), message: `added panel ${id}` };
}

/** Add an empty section at the end. */
export function addSection(layout: Layout, question: string, note: string | undefined, id: string): EditResult {
  const section = { id, question, ...(note ? { note } : {}), panels: [] };
  return { layout: { ...layout, sections: [...layout.sections, section] }, message: `added section ${id}` };
}

/** Move a panel to a position in a section (clamped to its length). */
export function movePanel(layout: Layout, id: string, sectionId: string, index: number): EditResult {
  const at = find(layout, id);
  if (!at) return { error: `error: no panel with id ${id}` };
  const to = layout.sections.findIndex((s) => s.id === sectionId);
  if (to < 0) return { error: `error: no section with id ${sectionId}` };
  const panel = layout.sections[at[0]].panels[at[1]];
  const removed = withPanels(layout, at[0], layout.sections[at[0]].panels.filter((_, i) => i !== at[1]));
  const target = [...removed.sections[to].panels];
  target.splice(Math.max(0, Math.min(index, target.length)), 0, panel);
  return { layout: withPanels(removed, to, target), message: `moved panel ${id}` };
}

/** Remove a panel; Reset brings back a removed default. */
export function removePanel(layout: Layout, id: string): EditResult {
  const at = find(layout, id);
  if (!at) return { error: `error: no panel with id ${id}` };
  const panels = layout.sections[at[0]].panels.filter((_, i) => i !== at[1]);
  return { layout: withPanels(layout, at[0], panels), message: `removed panel ${id}` };
}
