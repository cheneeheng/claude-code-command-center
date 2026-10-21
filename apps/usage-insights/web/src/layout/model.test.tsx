import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { z } from 'zod';

import { App } from '../App';
import { defineComponent } from '../catalogue/define';
import { kinds } from '../catalogue/kinds';
import { Dashboard } from '../components/Dashboard';
import type { QueryResult } from '../lib/api';
import { summary } from '../test/fixture';
import { defaultLayout } from './defaultLayout';
import { parseLayout, resolve, toLayout } from './model';

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });
}

const result = (over: Partial<QueryResult> = {}): QueryResult => ({
  metric: 'cost_usd',
  group_by: 'project',
  range: '30d',
  unit: 'usd',
  rows: [
    { key: 'alpha', label: 'alpha', value: 12, previous: 6, change: 1 },
    { key: 'beta', label: 'beta', value: 3, previous: 0, change: null },
  ],
  total: 15,
  truncated: false,
  ...over,
});

const panel = (over: Record<string, unknown> = {}) => ({
  id: 'g-1',
  kind: 'bars',
  title: 'Cost by project',
  caption: 'Where it goes.',
  query: { metric: 'cost_usd', group_by: 'project', compare: 'previous' },
  ...over,
});

const layoutWith = (...panels: unknown[]) => ({
  version: 1,
  sections: [{ id: 'mine', question: 'My questions', panels }],
});

/** Answers `/api/query` with `answer` and records each query URL. */
function stubQuery(answer: QueryResult) {
  const urls: string[] = [];
  vi.stubGlobal('fetch', (input: RequestInfo | URL) => {
    urls.push(String(input));
    return Promise.resolve(json(answer));
  });
  return urls;
}

describe('layout model', () => {
  it('draws the default layout through refs exactly as before', () => {
    const { container: before } = render(<Dashboard layout={defaultLayout} data={summary} />);
    const html = before.innerHTML;
    cleanup();
    const { container: after } = render(<Dashboard layout={resolve(toLayout(defaultLayout))} data={summary} />);
    expect(after.innerHTML).toBe(html);
  });

  it('drops an unknown ref, an invalid generated panel, and a duplicate id', () => {
    const raw = {
      version: 1,
      sections: [
        { id: 's', question: 'Q', panels: [{ ref: 'week' }, { ref: 'nope' }, panel(), panel({ title: 'twin' })] },
        { id: 's', question: 'duplicate section', panels: [] },
        { id: 't', question: 'R', panels: [panel({ id: 'g-2', kind: 'pie' }), { ref: 'week' }] },
      ],
    };
    const layout = parseLayout(raw);
    expect(layout?.sections.map((s) => s.question)).toEqual(['Q', 'R']);
    expect(layout?.sections[0].panels).toEqual([{ ref: 'week' }, panel()]);
    expect(layout?.sections[1].panels).toEqual([]);
    expect(parseLayout({ version: 2, sections: [] })).toBeNull();
    expect(resolve('junk').map((s) => s.id)).toEqual(defaultLayout.map((s) => s.id));
  });

  it('keeps only schema fields of a generated panel', () => {
    const layout = parseLayout(layoutWith(panel({ style: { color: 'red' }, className: 'x' })));
    expect(layout?.sections[0].panels[0]).toEqual(panel());
  });
});

describe('generated panel kinds', () => {
  it('rejects a trend that is not grouped by day or week', () => {
    expect(kinds.trend.schema.safeParse({ ...panel({ kind: 'trend' }) }).success).toBe(false);
    expect(
      kinds.trend.schema.safeParse(panel({ kind: 'trend', query: { metric: 'tokens', group_by: 'week' } })).success,
    ).toBe(true);
  });

  it('refuses a schema with a style key', () => {
    expect(() =>
      defineComponent({
        name: 'styled',
        description: 'x',
        schema: z.object({ title: z.string(), style: z.string() }),
        example: { title: 't', style: 's' },
        Component: () => null,
      }),
    ).toThrow(/style/);
  });

  it('draws bars with the change against the previous period', async () => {
    const urls = stubQuery(result());
    render(<Dashboard layout={resolve(layoutWith(panel()))} data={summary} range="7d" />);
    expect(await screen.findByText('$12.00')).toBeTruthy();
    expect(screen.getByText('+100% vs previous period')).toBeTruthy();
    expect(screen.getByText('Cost by project')).toBeTruthy();
    expect(urls).toEqual(['/api/query?range=7d']);
  });

  it('draws a trend, a table, and a stat', async () => {
    stubQuery(result({ group_by: 'day', rows: [{ key: '2026-10-01', label: '2026-10-01', value: 4 }], total: 4 }));
    render(
      <Dashboard
        layout={resolve(layoutWith(panel({ kind: 'trend', query: { metric: 'cost_usd', group_by: 'day' } })))}
        data={summary}
      />,
    );
    expect(await screen.findByText('Oct 1: $4.00')).toBeTruthy();
    cleanup();

    stubQuery(result());
    render(<Dashboard layout={resolve(layoutWith(panel({ kind: 'table' })))} data={summary} />);
    expect(await screen.findByRole('columnheader', { name: 'Previous' })).toBeTruthy();
    expect(screen.getByRole('cell', { name: '$6.00' })).toBeTruthy();
    cleanup();

    stubQuery(result({ group_by: 'none', rows: [{ key: 'all', label: 'All', value: 15, previous: 10, change: 0.5 }] }));
    render(
      <Dashboard
        layout={resolve(layoutWith(panel({ kind: 'stat', query: { metric: 'cost_usd', compare: 'previous' } })))}
        data={summary}
      />,
    );
    expect(await screen.findByText('$15.00')).toBeTruthy();
    expect(screen.getByText('+50% vs previous period')).toBeTruthy();
  });

  it('says when a query has no data, and retries after an error', async () => {
    stubQuery(result({ rows: [], total: 0, range: '7d' })); // the server echoes the range it ran
    render(<Dashboard layout={resolve(layoutWith(panel()))} data={summary} range="7d" />);
    expect(await screen.findByText('No data for this query in the last 7 days.')).toBeTruthy();
    cleanup();

    const fn = vi.fn<typeof fetch>()
      .mockResolvedValueOnce(json({ error: 'group_by for interrupts must be one of none' }, 400))
      .mockResolvedValueOnce(json(result()));
    vi.stubGlobal('fetch', fn);
    render(<Dashboard layout={resolve(layoutWith(panel()))} data={summary} />);
    expect((await screen.findByRole('alert')).textContent).toContain('group_by for interrupts');
    fireEvent.click(screen.getByRole('button', { name: 'Retry' }));
    expect(await screen.findByText('$12.00')).toBeTruthy();
  });
});

describe('App with a saved layout', () => {
  function stubApp(saved: unknown) {
    const calls: [string, string][] = [];
    vi.stubGlobal('fetch', (input: RequestInfo | URL, init?: RequestInit) => {
      const url = String(input);
      const method = init?.method ?? 'GET';
      calls.push([method, url]);
      if (url === '/api/layout') return Promise.resolve(method === 'GET' ? json(saved) : new Response(null, { status: 204 }));
      if (url.startsWith('/api/query')) return Promise.resolve(json(result()));
      const range = new URL(url, 'http://x').searchParams.get('range');
      return Promise.resolve(json({ ...summary, range }));
    });
    return calls;
  }

  it('refetches a generated panel when the top bar range changes', async () => {
    const calls = stubApp(layoutWith(panel()));
    render(<App />);
    expect(await screen.findByText('My questions')).toBeTruthy();
    expect(screen.queryByText('What will I spend?')).toBeNull();
    await screen.findByText('$12.00');
    fireEvent.click(screen.getByRole('button', { name: '7 days' }));
    await waitFor(() => expect(calls).toContainEqual(['POST', '/api/query?range=7d']));
  });

  it('resets to the default layout', async () => {
    const calls = stubApp(layoutWith(panel()));
    render(<App />);
    fireEvent.click(await screen.findByRole('button', { name: 'Reset layout' }));
    expect(await screen.findByText('What will I spend?')).toBeTruthy();
    expect(calls).toContainEqual(['DELETE', '/api/layout']);
    expect(screen.queryByRole('button', { name: 'Reset layout' })).toBeNull();
  });
});
