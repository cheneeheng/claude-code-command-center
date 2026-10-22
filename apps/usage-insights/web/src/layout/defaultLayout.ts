import type { ComponentProps } from 'react';

import { catalogue, type CatalogueName } from '../catalogue';
import type { Summary } from '../lib/api';
import { change, share, tokens, usd } from '../lib/format';

/** Share of input-side tokens read from cache rather than sent fresh or written. */
function cacheShare(t: Summary['totals']['tokens']): number {
  const inputSide = t.input + t.cache_write + t.cache_read;
  return inputSide > 0 ? t.cache_read / inputSide : 0;
}

type Catalogue = typeof catalogue;

/** How much of a row a panel takes. */
export type PanelSize = 'third' | 'half' | 'two-thirds' | 'wide';

/** One placed component: which one, its header, and how it reads the payload. */
export type Panel = {
  [K in CatalogueName]: {
    id: string;
    component: K;
    /** Uppercase section label shown above the panel. */
    eyebrow: string;
    caption: string;
    /** Shown after the eyebrow, e.g. `PROJECTS · 7`. */
    count?: (s: Summary) => number;
    /** Share of the row, by importance. Default: half. */
    size?: PanelSize;
    select: (s: Summary) => ComponentProps<Catalogue[K]>;
  };
}[CatalogueName];

/** A group of panels that answers one question. */
export type Section = {
  id: string;
  question: string;
  /** One line under the question, e.g. what the range does not change. */
  note?: string;
  panels: Panel[];
};

/**
 * The default dashboard. It is data, not JSX, so the AG-UI phase can replace or
 * rearrange it at runtime with the same catalogue.
 */
export const defaultLayout: Section[] = [
  {
    id: 'spend-ahead',
    question: 'What will I spend?',
    note: 'Based on the last 14 days, not affected by the range.',
    panels: [
      {
        id: 'week',
        component: 'StatTile',
        eyebrow: 'This week',
        caption: 'Monday to Sunday, at the pace of the last 14 days.',
        size: 'third',
        select: (s) => ({
          ...s.projection.week.cost_usd,
          unit: 'usd',
          secondary: `${tokens(s.projection.week.tokens.forecast)} tokens forecast`,
          unpriced: s.totals.unpriced_models,
          pricesAsOf: s.totals.prices_as_of,
        }),
      },
      {
        id: 'month',
        component: 'StatTile',
        eyebrow: 'This month',
        caption: 'Calendar month, at the pace of the last 14 days.',
        size: 'third',
        select: (s) => ({
          ...s.projection.month.cost_usd,
          unit: 'usd',
          secondary: `${tokens(s.projection.month.tokens.forecast)} tokens forecast`,
          unpriced: s.totals.unpriced_models,
          pricesAsOf: s.totals.prices_as_of,
        }),
      },
      {
        id: 'month-burn',
        component: 'MonthBurn',
        eyebrow: 'Month so far',
        caption: 'Cost building up this month, then the forecast to its end.',
        size: 'third',
        select: (s) => ({ days: s.projection.pace, month: s.projection.month.cost_usd }),
      },
      {
        id: 'pace',
        component: 'PaceStrip',
        eyebrow: 'Pace',
        caption: 'Daily usage over the last 30 days: the pace behind the forecast.',
        size: 'two-thirds',
        select: (s) => ({ days: s.projection.pace }),
      },
      {
        id: 'project-forecast',
        component: 'RankedBars',
        eyebrow: 'Month forecast by project',
        caption: 'Where this month is heading, per project.',
        count: (s) => s.projection.by_project.length,
        size: 'third',
        select: (s) => ({
          rows: s.projection.by_project.map((p) => ({
            label: p.project,
            value: p.month_cost_forecast,
            display: usd(p.month_cost_forecast),
            secondary: `${usd(p.week_cost_forecast)} this week`,
          })),
          emptyText: 'No spend this month yet.',
        }),
      },
    ],
  },
  {
    id: 'spend-where',
    question: 'Where does it go?',
    panels: [
      {
        id: 'totals',
        component: 'KpiStrip',
        eyebrow: 'In this range',
        caption: 'Totals for the selected range.',
        size: 'wide',
        select: (s) => ({
          items: [
            { label: 'Cost', value: usd(s.totals.cost_usd), caption: 'estimated at list price' },
            { label: 'Tokens', value: tokens(s.totals.tokens.total), caption: `${tokens(s.totals.tokens.output)} output` },
            { label: 'Sessions', value: String(s.totals.sessions), caption: `in ${s.projects.length} projects` },
            {
              label: 'Per session',
              value: s.totals.sessions > 0 ? usd(s.totals.cost_usd / s.totals.sessions) : '—',
              caption: 'average cost',
            },
            { label: 'Cache reads', value: share(cacheShare(s.totals.tokens)), caption: 'of input from cache' },
          ],
        }),
      },
      {
        id: 'projects',
        component: 'RankedBars',
        eyebrow: 'Projects',
        caption: 'Cost in the selected range, with the change against the period before.',
        count: (s) => s.projects.length,
        size: 'third',
        select: (s) => ({
          rows: s.projects.map((p) => ({
            label: p.project,
            value: p.cost_usd,
            display: usd(p.cost_usd),
            secondary: [
              `${share(p.share)} of spend`,
              p.change === null ? undefined : `${change(p.change)} vs previous`,
              `${p.sessions} session${p.sessions === 1 ? '' : 's'}`,
            ]
              .filter(Boolean)
              .join(' · '),
          })),
          emptyText: 'No usage in this range.',
        }),
      },
      {
        id: 'models',
        component: 'ShareBar',
        eyebrow: 'Models',
        caption: 'Share of cost per model in the selected range.',
        count: (s) => s.models.length,
        size: 'third',
        select: (s) => ({
          parts: s.models.map((m) => ({ label: m.model, value: m.cost_usd, display: usd(m.cost_usd) })),
          emptyText: 'No usage in this range.',
        }),
      },
      {
        id: 'token-mix',
        component: 'ShareBar',
        eyebrow: 'Token mix',
        caption: 'Where the tokens went. Cache reads are the cheapest kind.',
        size: 'third',
        select: (s) => ({
          parts: [
            { label: 'Cache read', value: s.totals.tokens.cache_read },
            { label: 'Cache write', value: s.totals.tokens.cache_write },
            { label: 'Input', value: s.totals.tokens.input },
            { label: 'Output', value: s.totals.tokens.output },
          ].map((p) => ({ ...p, display: tokens(p.value) })),
          emptyText: 'No usage in this range.',
        }),
      },
      {
        id: 'sessions',
        component: 'SessionTable',
        eyebrow: 'Top sessions',
        caption: 'The heaviest sessions in the selected range.',
        count: (s) => s.sessions.length,
        size: 'wide',
        select: (s) => ({ sessions: s.sessions }),
      },
    ],
  },
  {
    id: 'fix',
    question: 'What should I fix?',
    panels: [
      {
        id: 'skills',
        component: 'HealthTable',
        eyebrow: 'Skills',
        caption: 'Worst first. Never-used skills usually need a better description.',
        count: (s) => s.skills.length,
        size: 'wide',
        select: (s) => ({ rows: s.skills, noun: 'skill' }),
      },
      {
        id: 'agents',
        component: 'HealthTable',
        eyebrow: 'Subagents',
        caption: 'Worst first, by the same rules as skills.',
        count: (s) => s.agents.length,
        size: 'wide',
        select: (s) => ({ rows: s.agents, noun: 'subagent' }),
      },
      {
        id: 'tools',
        component: 'RankedBars',
        eyebrow: 'Tools',
        caption: 'Tool calls in the selected range.',
        count: (s) => s.tools.used.length,
        select: (s) => ({
          rows: s.tools.used.map((t) => ({
            label: t.name,
            value: t.calls,
            display: tokens(t.calls),
          })),
          emptyText: 'No tool calls in this range.',
        }),
      },
      {
        id: 'unused-tools',
        component: 'UnusedList',
        eyebrow: 'Not called',
        caption: 'Built-in tools and MCP servers with no calls in the selected range.',
        count: (s) =>
          s.tools.unused_builtin.length + s.tools.mcp_servers.filter((m) => m.calls === 0).length,
        select: (s) => ({
          items: [
            ...s.tools.unused_builtin.map((name) => ({ name, source: 'built-in' })),
            ...s.tools.mcp_servers
              .filter((m) => m.calls === 0)
              .map((m) => ({ name: m.name, source: `MCP · ${m.source}` })),
          ],
          emptyText: 'Every built-in tool and MCP server was called.',
        }),
      },
    ],
  },
];
