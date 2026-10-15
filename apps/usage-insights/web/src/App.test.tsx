import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';

import { App } from './App';
import type { Summary } from './lib/api';
import { summary } from './test/fixture';

function respond(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });
}

function mockFetch(...responses: Response[]) {
  const fn = vi.fn<typeof fetch>();
  for (const r of responses) fn.mockResolvedValueOnce(r);
  vi.stubGlobal('fetch', fn);
  return fn;
}

/** A fetch response the test resolves when it chooses. */
function deferred() {
  let resolve!: (r: Response) => void;
  const promise = new Promise<Response>((r) => {
    resolve = r;
  });
  return { promise, resolve };
}

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
});

describe('App states', () => {
  it('shows a skeleton, then the dashboard', async () => {
    mockFetch(respond(200, summary));
    render(<App />);
    expect(screen.getByLabelText('Loading usage')).toBeTruthy();
    expect(await screen.findByText('What will I spend?')).toBeTruthy();
  });

  it('shows the error in place and retries', async () => {
    const fetchMock = mockFetch(respond(500, { error: 'store unreadable' }), respond(200, summary));
    render(<App />);
    expect((await screen.findByRole('alert')).textContent).toContain('store unreadable');
    fireEvent.click(screen.getByRole('button', { name: 'Retry' }));
    expect(await screen.findByText('What will I spend?')).toBeTruthy();
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  it('shows the empty state with the folders searched', async () => {
    const empty: Summary = { ...summary, last_export: null, sessions: [] };
    mockFetch(respond(200, empty));
    render(<App />);
    expect(await screen.findByText('No Claude Code usage yet')).toBeTruthy();
    expect(screen.getByText('/home/x/.claude')).toBeTruthy();
  });

  it('refreshes, and says so when an export is already running', async () => {
    const fetchMock = mockFetch(
      respond(200, summary),
      respond(409, { error: 'export already running' }),
      respond(200, { files_scanned: 1, files_parsed: 1, messages: 1, events: 1 }),
      respond(200, summary),
    );
    render(<App />);
    await screen.findByText('What will I spend?');
    fireEvent.click(screen.getByRole('button', { name: 'Refresh' }));
    expect(await screen.findByText('Export already running, try again shortly.')).toBeTruthy();
    fireEvent.click(screen.getByRole('button', { name: 'Refresh' }));
    await waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(4));
    expect(fetchMock.mock.calls[2][1]).toEqual({ method: 'POST' });
  });

  it('refetches when the range changes', async () => {
    const fetchMock = mockFetch(respond(200, summary), respond(200, { ...summary, range: '7d' }));
    render(<App />);
    await screen.findByText('What will I spend?');
    fireEvent.click(screen.getByRole('button', { name: '7 days' }));
    await waitFor(() => expect(fetchMock).toHaveBeenLastCalledWith('/api/summary?range=7d', undefined));
  });

  it('says a quiet range is quiet instead of claiming there is no usage at all', async () => {
    const quiet: Summary = {
      ...summary,
      sessions: [],
      projection: { ...summary.projection, pace: summary.projection.pace.map((d) => ({ ...d, tokens: 0 })) },
    };
    mockFetch(respond(200, quiet));
    render(<App />);
    expect(await screen.findByText('No usage in the last 30 days')).toBeTruthy();
    expect(screen.queryByText('No Claude Code usage yet')).toBeNull();
  });

  it('marks the old range busy until the new range arrives', async () => {
    const next = deferred();
    const fetchMock = mockFetch(respond(200, summary));
    fetchMock.mockReturnValueOnce(next.promise);
    render(<App />);
    await screen.findByText('What will I spend?');
    fireEvent.click(screen.getByRole('button', { name: '7 days' }));
    await waitFor(() => expect(screen.getByRole('main').getAttribute('aria-busy')).toBe('true'));
    next.resolve(respond(200, { ...summary, range: '7d' }));
    await waitFor(() => expect(screen.getByRole('main').getAttribute('aria-busy')).toBe('false'));
  });

  it('keeps the latest range when an earlier response lands last', async () => {
    const first = deferred();
    const second = deferred();
    const fetchMock = vi.fn<typeof fetch>().mockReturnValueOnce(first.promise).mockReturnValueOnce(second.promise);
    vi.stubGlobal('fetch', fetchMock);
    render(<App />);
    fireEvent.click(screen.getByRole('button', { name: '7 days' }));
    second.resolve(respond(200, { ...summary, range: '7d', projects: summary.projects.slice(0, 1) }));
    expect(await screen.findByText('Projects · 1')).toBeTruthy();
    first.resolve(respond(200, summary)); // the stale 30-day answer
    await new Promise((r) => setTimeout(r, 0));
    expect(screen.getByText('Projects · 1')).toBeTruthy();
    expect(screen.queryByText('Projects · 2')).toBeNull();
  });

  it('shows a failed refresh with a Retry that runs the export again', async () => {
    const fetchMock = mockFetch(
      respond(200, summary),
      respond(500, { error: 'disk full' }),
      respond(200, { files_scanned: 1, files_parsed: 1, messages: 1, events: 1 }),
      respond(200, summary),
    );
    render(<App />);
    await screen.findByText('What will I spend?');
    fireEvent.click(screen.getByRole('button', { name: 'Refresh' }));
    expect(await screen.findByText(/Refresh failed: .*disk full/)).toBeTruthy();
    fireEvent.click(screen.getByRole('button', { name: 'Retry' }));
    await waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(4));
    expect(fetchMock.mock.calls[2][1]).toEqual({ method: 'POST' });
    await waitFor(() => expect(screen.queryByRole('button', { name: 'Retry' })).toBeNull());
  });

  it('keeps the data and says so when a reload fails', async () => {
    mockFetch(respond(200, summary), respond(500, { error: 'store unreadable' }));
    render(<App />);
    await screen.findByText('What will I spend?');
    fireEvent.click(screen.getByRole('button', { name: '7 days' }));
    expect(await screen.findByText(/Could not reload: .*store unreadable/)).toBeTruthy();
    expect(screen.getByText('What will I spend?')).toBeTruthy();
  });

  it('shows the skeleton again while a retry from the error state runs', async () => {
    const retry = deferred();
    const fetchMock = mockFetch(respond(500, { error: 'store unreadable' }));
    fetchMock.mockReturnValueOnce(retry.promise);
    render(<App />);
    await screen.findByRole('alert');
    fireEvent.click(screen.getByRole('button', { name: 'Retry' }));
    expect(await screen.findByRole('status', { name: 'Loading usage' })).toBeTruthy();
    retry.resolve(respond(200, summary));
    expect(await screen.findByText('What will I spend?')).toBeTruthy();
  });
});
