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
});
