import { z } from 'zod';

import { byUnit, change } from '../lib/format';
import { assertNoStyleKeys, defineComponent, type KindProps, type PanelKind } from './define';
import { DayBars } from './PaceStrip';
import { RankedBars } from './RankedBars';
import { ShareBar } from './ShareBar';

const names = z.array(z.string()).max(50);

/** A typed query, as `POST /api/query` takes it. The server checks metric and grouping pairs. */
export const querySchema = z.object({
  metric: z.enum(['cost_usd', 'tokens', 'sessions', 'skill_uses', 'agent_uses', 'tool_calls', 'interrupts']),
  group_by: z.enum(['none', 'project', 'model', 'session', 'day', 'week', 'skill', 'agent', 'tool']).optional(),
  filters: z.object({ project: names.optional(), model: names.optional(), name: names.optional() }).optional(),
  range: z.enum(['7d', '30d', '90d', 'month', 'all']).optional(),
  compare: z.literal('previous').optional(),
  limit: z.number().int().min(1).max(100).optional(),
});
export type QuerySpec = z.infer<typeof querySchema>;

const base = {
  title: z.string().min(1).max(80),
  caption: z.string().max(240),
  wide: z.boolean().optional(),
};

const barsSchema = z.object({ kind: z.literal('bars'), ...base, query: querySchema });
const trendSchema = z.object({
  kind: z.literal('trend'),
  ...base,
  query: querySchema.extend({ group_by: z.enum(['day', 'week']) }),
});
const tableSchema = z.object({ kind: z.literal('table'), ...base, query: querySchema });
const shareSchema = z.object({
  kind: z.literal('share'),
  ...base,
  query: querySchema.extend({ group_by: z.enum(['project', 'model', 'skill', 'agent', 'tool']) }),
});
const statSchema = z.object({
  kind: z.literal('stat'),
  ...base,
  query: querySchema.extend({ group_by: z.literal('none').optional() }),
});

function vsPrevious(value: number | null | undefined): string {
  return `${change(value ?? null)} vs previous period`;
}

export const bars = defineComponent({
  name: 'bars',
  description: 'Ranked bars: one row per group, largest first. For "which X costs most" questions.',
  schema: barsSchema,
  example: {
    kind: 'bars',
    title: 'Cost by project',
    caption: 'Which projects cost more than last month.',
    query: { metric: 'cost_usd', group_by: 'project', range: 'month', compare: 'previous' },
  },
  Component: ({ panel, result }) => (
    <RankedBars
      rows={result.rows.map((r) => ({
        label: r.label,
        value: r.value,
        display: byUnit(r.value, result.unit),
        secondary: panel.query.compare ? vsPrevious(r.change) : undefined,
      }))}
      emptyText=""
    />
  ),
});

export const trend = defineComponent({
  name: 'trend',
  description: 'Bars over time, one per day or week. The query must group by day or week.',
  schema: trendSchema,
  example: {
    kind: 'trend',
    title: 'Daily cost this month',
    caption: 'How spend builds up over the month.',
    query: { metric: 'cost_usd', group_by: 'day', range: 'month' },
  },
  Component: ({ panel, result }) => (
    <DayBars
      bars={result.rows.map((r) => ({ date: r.key, value: r.value }))}
      fmt={(n) => byUnit(n, result.unit)}
      label={`${panel.title}, per ${panel.query.group_by}`}
    />
  ),
});

function TableKind({ panel, result }: KindProps<{ query: QuerySpec }>) {
  const compare = Boolean(panel.query.compare);
  return (
    <div className="table-wrap">
      <table className="table">
        <thead>
          <tr>
            <th scope="col">Label</th>
            <th scope="col" className="num">
              Value
            </th>
            {compare && (
              <>
                <th scope="col" className="num">
                  Previous
                </th>
                <th scope="col" className="num">
                  Change
                </th>
              </>
            )}
          </tr>
        </thead>
        <tbody>
          {result.rows.map((r) => (
            <tr key={r.key}>
              <td className="truncate" title={r.label}>
                {r.label}
              </td>
              <td className="num numeric">{byUnit(r.value, result.unit)}</td>
              {compare && (
                <>
                  <td className="num numeric">{byUnit(r.previous ?? 0, result.unit)}</td>
                  <td className="num numeric">{change(r.change ?? null)}</td>
                </>
              )}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

export const table = defineComponent({
  name: 'table',
  description: 'A table of label and value, plus previous and change columns when compare is set.',
  schema: tableSchema,
  example: {
    kind: 'table',
    title: 'Skill uses',
    caption: 'Which skills run most often.',
    query: { metric: 'skill_uses', group_by: 'skill' },
  },
  Component: TableKind,
});

export const stat = defineComponent({
  name: 'stat',
  description: 'One figure, the query total, with its change when compare is set. Group by none.',
  schema: statSchema,
  example: {
    kind: 'stat',
    title: 'Opus spend this month',
    caption: 'Opus cost against the same days last month.',
    query: { metric: 'cost_usd', filters: { model: ['claude-opus'] }, range: 'month', compare: 'previous' },
  },
  Component: ({ panel, result }) => (
    <div className="stat-tile">
      <p className="stat-value numeric">{byUnit(result.total, result.unit)}</p>
      {panel.query.compare && <p className="muted numeric stat-caption">{vsPrevious(result.rows[0]?.change)}</p>}
    </div>
  ),
});

export const shareKind = defineComponent({
  name: 'share',
  description:
    'One bar split into each group\'s share of the total, with a legend. For "what is the mix" questions; ' +
    'the five largest groups get a colour, the rest fold into one.',
  schema: shareSchema,
  example: {
    kind: 'share',
    title: 'Model mix this month',
    caption: 'Each model\'s share of this month\'s cost.',
    query: { metric: 'cost_usd', group_by: 'model', range: 'month' },
  },
  Component: ({ result }) => (
    <ShareBar
      parts={result.rows.map((r) => ({ label: r.label, value: r.value, display: byUnit(r.value, result.unit) }))}
      totalDisplay={`${byUnit(result.total, result.unit)} in total`}
      emptyText=""
    />
  ),
});

/** Every generated panel kind, by `kind`. */
export const kinds: Record<GeneratedPanel['kind'], PanelKind> = { bars, trend, table, stat, share: shareKind };

/** A new panel's fields (no id: the canvas sets it). */
export const panelSchema = z.discriminatedUnion('kind', [
  barsSchema,
  trendSchema,
  tableSchema,
  statSchema,
  shareSchema,
]);
export type PanelFields = z.infer<typeof panelSchema>;

const sectionId = { section_id: z.string().min(1) };
/** The agent's `add_panel` arguments: a panel's fields plus the section to add it to. */
export const addPanelSchema = z.discriminatedUnion('kind', [
  barsSchema.extend(sectionId),
  trendSchema.extend(sectionId),
  tableSchema.extend(sectionId),
  statSchema.extend(sectionId),
  shareSchema.extend(sectionId),
]);

const id = { id: z.string().min(1) };
/** A generated panel as the layout stores it: a kind's fields plus the id the canvas set. */
export const generatedPanelSchema = z.discriminatedUnion('kind', [
  barsSchema.extend(id),
  trendSchema.extend(id),
  tableSchema.extend(id),
  statSchema.extend(id),
  shareSchema.extend(id),
]);
export type GeneratedPanel = z.infer<typeof generatedPanelSchema>;
/**
 * `add_panel` as the model sees it: one object, because the Claude API refuses a tool schema
 * without a top-level `type: "object"` and refuses a top-level union. Each call is still
 * validated against the stricter {@link addPanelSchema}, whose error names what a kind requires.
 */
export const addPanelToolSchema = z.object({
  ...sectionId,
  kind: z.enum(['bars', 'trend', 'table', 'stat', 'share']),
  ...base,
  query: querySchema,
});
assertNoStyleKeys('add_panel', z.toJSONSchema(addPanelSchema));
assertNoStyleKeys('add_panel', z.toJSONSchema(addPanelToolSchema));
