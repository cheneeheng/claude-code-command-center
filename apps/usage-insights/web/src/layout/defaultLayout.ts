import type { ComponentProps } from 'react';

import { catalogue, type CatalogueName } from '../catalogue';
import type { Summary } from '../lib/api';
import { change, share, tokens, usd } from '../lib/format';

type Catalogue = typeof catalogue;

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
    /** Spans the full row instead of one column. */
    wide?: boolean;
    select: (s: Summary) => ComponentProps<Catalogue[K]>;
  };
}[CatalogueName];

/** A group of panels that answers one question. */
export type Section = { id: string; question: string; panels: Panel[] };

/**
 * The default dashboard. It is data, not JSX, so the AG-UI phase can replace or
 * rearrange it at runtime with the same catalogue.
 */
export const defaultLayout: Section[] = [
  {
    id: 'spend-ahead',
    question: 'What will I spend?',
    panels: [
      {
        id: 'week',
        component: 'StatTile',
        eyebrow: 'This week',
        caption: 'Monday to Sunday, at the pace of the last 14 days.',
        select: (s) => ({
          ...s.projection.week.cost_usd,
          unit: 'usd',
          secondary: `${tokens(s.projection.week.tokens.forecast)} tokens forecast`,
          unpriced: s.totals.unpriced_models,
        }),
      },
      {
        id: 'month',
        component: 'StatTile',
        eyebrow: 'This month',
        caption: 'Calendar month, at the pace of the last 14 days.',
        select: (s) => ({
          ...s.projection.month.cost_usd,
          unit: 'usd',
          secondary: `${tokens(s.projection.month.tokens.forecast)} tokens forecast`,
          unpriced: s.totals.unpriced_models,
        }),
      },
      {
        id: 'pace',
        component: 'PaceStrip',
        eyebrow: 'Pace',
        caption: 'Daily usage over the last 30 days: the pace behind the forecast.',
        wide: true,
        select: (s) => ({ days: s.projection.pace }),
      },
      {
        id: 'project-forecast',
        component: 'RankedBars',
        eyebrow: 'Month forecast by project',
        caption: 'Where this month is heading, per project.',
        count: (s) => s.projection.by_project.length,
        wide: true,
        select: (s) => ({
          rows: s.projection.by_project.map((p) => ({
            label: p.project,
            value: p.month_cost_forecast,
            display: usd(p.month_cost_forecast),
            secondary: `${usd(p.week_cost_forecast)} this week`,
          })),
          limit: 8,
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
        id: 'projects',
        component: 'RankedBars',
        eyebrow: 'Projects',
        caption: 'Cost in the selected range, with the change against the period before.',
        count: (s) => s.projects.length,
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
        component: 'RankedBars',
        eyebrow: 'Models',
        caption: 'Cost per model in the selected range.',
        count: (s) => s.models.length,
        select: (s) => ({
          rows: s.models.map((m) => ({
            label: m.model,
            value: m.cost_usd,
            display: usd(m.cost_usd),
            secondary: `${tokens(m.tokens)} tokens · ${m.sessions} sessions`,
          })),
          emptyText: 'No usage in this range.',
        }),
      },
      {
        id: 'sessions',
        component: 'SessionTable',
        eyebrow: 'Top sessions',
        caption: 'The heaviest sessions in the selected range.',
        count: (s) => s.sessions.length,
        wide: true,
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
        wide: true,
        select: (s) => ({ rows: s.skills, noun: 'skill' }),
      },
      {
        id: 'agents',
        component: 'HealthTable',
        eyebrow: 'Subagents',
        caption: 'Worst first, by the same rules as skills.',
        count: (s) => s.agents.length,
        wide: true,
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
