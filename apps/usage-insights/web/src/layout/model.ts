import { type GeneratedPanel, generatedPanelSchema } from '../catalogue/kinds';
import { defaultLayout, type Panel, type Section } from './defaultLayout';

/** A layout entry: a reference to a default panel by id, or a generated panel. */
export type PanelEntry = { ref: string } | GeneratedPanel;
/** One section of a serialisable layout. */
export type LayoutSection = { id: string; question: string; note?: string; panels: PanelEntry[] };
/** What `layout.json` holds. */
export type Layout = { version: 1; sections: LayoutSection[] };

/** A section ready to render: refs replaced by their default {@link Panel}. */
export type ResolvedSection = {
  id: string;
  question: string;
  note?: string;
  panels: (Panel | GeneratedPanel)[];
};

const defaults = new Map(defaultLayout.flatMap((s) => s.panels.map((p) => [p.id, p] as const)));

/** The default layout as refs: what the page shows before any edit, and after Reset. */
export function toLayout(sections: Section[] = defaultLayout): Layout {
  return {
    version: 1,
    sections: sections.map(({ id, question, note, panels }) => ({
      id,
      question,
      ...(note === undefined ? {} : { note }),
      panels: panels.map((p) => ({ ref: p.id })),
    })),
  };
}

function isObject(v: unknown): v is Record<string, unknown> {
  return typeof v === 'object' && v !== null && !Array.isArray(v);
}

/**
 * A clean {@link Layout} from anything read back. Unknown refs, generated panels failing
 * their schema, and later duplicates of a section or panel id are dropped, so a bad file
 * never blanks the page. Not a layout at all gives `null`.
 */
export function parseLayout(raw: unknown): Layout | null {
  if (!isObject(raw) || raw.version !== 1 || !Array.isArray(raw.sections)) return null;
  const sectionIds = new Set<string>();
  const panelIds = new Set<string>();
  const sections: LayoutSection[] = [];
  for (const s of raw.sections) {
    if (!isObject(s) || typeof s.id !== 'string' || typeof s.question !== 'string') continue;
    if (sectionIds.has(s.id)) continue;
    sectionIds.add(s.id);
    const panels: PanelEntry[] = [];
    for (const p of Array.isArray(s.panels) ? s.panels : []) {
      let entry: PanelEntry | null = null;
      if (isObject(p) && typeof p.ref === 'string') entry = defaults.has(p.ref) ? { ref: p.ref } : null;
      else {
        const parsed = generatedPanelSchema.safeParse(p);
        entry = parsed.success ? parsed.data : null;
      }
      const id = entry && ('ref' in entry ? entry.ref : entry.id);
      if (entry && id && !panelIds.has(id)) {
        panelIds.add(id);
        panels.push(entry);
      }
    }
    sections.push({
      id: s.id,
      question: s.question,
      ...(typeof s.note === 'string' ? { note: s.note } : {}),
      panels,
    });
  }
  return { version: 1, sections };
}

/** A layout ready to render; see {@link parseLayout} for what is dropped. */
export function resolve(raw: unknown): ResolvedSection[] {
  const layout = parseLayout(raw) ?? toLayout();
  return layout.sections.map((s) => ({
    ...s,
    panels: s.panels.map((p) => ('ref' in p ? (defaults.get(p.ref) as Panel) : p)),
  }));
}
