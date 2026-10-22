import { cleanup, fireEvent, render, screen, within } from '@testing-library/react';
import { afterEach, describe, expect, it } from 'vitest';

import { splitLabel } from '../lib/format';
import { summary } from '../test/fixture';
import { HealthTable } from './HealthTable';
import { burnPoints } from './MonthBurn';
import { PaceStrip } from './PaceStrip';
import { RankedBars } from './RankedBars';
import { SessionTable } from './SessionTable';
import { ShareBar } from './ShareBar';
import { StatTile } from './StatTile';
import { UnusedList } from './UnusedList';

afterEach(cleanup);

describe('StatTile', () => {
  it('shows the forecast, the band, and unpriced models', () => {
    render(<StatTile actual={40} forecast={90} low={85} high={95} unit="usd" unpriced={['m']} />);
    expect(screen.getByText('$90.00')).toBeTruthy();
    expect(
      screen.getByRole('img', { name: '$40.00 so far, forecast $90.00, likely $85.00 to $95.00' }),
    ).toBeTruthy();
    expect(screen.getByText(/1 unpriced model not counted/)).toBeTruthy();
    expect(screen.queryByText(/prices/i)).toBeNull();
  });

  it('says which price source the cost uses', () => {
    const props = { actual: 1, forecast: 2, low: 1, high: 3, unit: 'usd' } as const;
    const { rerender } = render(<StatTile {...props} pricesAsOf={null} />);
    expect(screen.getByText('Built-in prices')).toBeTruthy();
    rerender(<StatTile {...props} pricesAsOf="2026-10-21T08:00:00+00:00" />);
    expect(screen.getByText('Prices from LiteLLM, Oct 21')).toBeTruthy();
  });
});

describe('PaceStrip', () => {
  it('draws 30 bars ending today and switches metric', () => {
    render(<PaceStrip days={summary.projection.pace} />);
    const bars = within(screen.getByRole('list', { name: /last 30 days/ })).getAllByRole('listitem');
    expect(bars).toHaveLength(30);
    const today = new Date().toLocaleDateString('en', { month: 'short', day: 'numeric' });
    // The value is text inside each bar, so screen readers and keyboard users get it too.
    expect(bars[29].textContent).toBe(`${today}: $30.00`);
    fireEvent.click(screen.getByRole('button', { name: 'Tokens' }));
    expect(bars[29].textContent).toBe(`${today}: 30K`);
  });

  it('names its span and last day from the data, not a fixed 30 and "Today"', () => {
    const days = summary.projection.pace.slice(0, 7);
    render(<PaceStrip days={days} />);
    expect(screen.getByRole('list', { name: 'Daily usage, last 7 days' })).toBeTruthy();
    expect(screen.queryByText('Today')).toBeNull();
  });

  it('labels every fifth day on the axis, ending on the last day', () => {
    const { container } = render(<PaceStrip days={summary.projection.pace} />);
    const labels = [...container.querySelectorAll('.pace-axis span')]
      .map((s) => s.textContent)
      .filter(Boolean);
    expect(labels).toHaveLength(6);
    expect(labels.at(-1)).toBe(new Date().toLocaleDateString('en', { month: 'short', day: 'numeric' }));
  });
});

describe('RankedBars', () => {
  const rows = Array.from({ length: 12 }, (_, i) => ({ label: `r${i}`, value: 12 - i, display: `${12 - i}` }));

  it('keeps the given order and caps rows at 5 until "Show all", then "Show less"', () => {
    render(<RankedBars rows={rows} emptyText="none" />);
    expect(screen.getAllByRole('listitem').map((li) => li.textContent?.slice(0, 2))).toEqual(
      rows.slice(0, 5).map((r) => r.label.slice(0, 2)),
    );
    fireEvent.click(screen.getByRole('button', { name: 'Show all 12' }));
    expect(screen.getAllByRole('listitem')).toHaveLength(12);
    fireEvent.click(screen.getByRole('button', { name: 'Show less' }));
    expect(screen.getAllByRole('listitem')).toHaveLength(5);
  });

  it('has no toggle when every row fits', () => {
    render(<RankedBars rows={rows.slice(0, 5)} emptyText="none" />);
    expect(screen.queryByRole('button')).toBeNull();
  });

  it('shows the empty text', () => {
    render(<RankedBars rows={[]} emptyText="Nothing here." />);
    expect(screen.getByText('Nothing here.')).toBeTruthy();
  });
});

describe('SessionTable', () => {
  it('renders title, project, tokens, and cost', () => {
    render(<SessionTable sessions={summary.sessions} />);
    const row = screen.getByText('Fix the login flow').closest('tr');
    expect(row?.textContent).toContain('alpha');
    expect(row?.textContent).toContain('$80.00');
  });

  it('caps rows at 5 until "Show all"', () => {
    const sessions = Array.from({ length: 7 }, (_, i) => ({ ...summary.sessions[0], id: `s${i}` }));
    render(<SessionTable sessions={sessions} />);
    expect(screen.getAllByRole('row')).toHaveLength(6); // header + 5
    fireEvent.click(screen.getByRole('button', { name: 'Show all 7' }));
    expect(screen.getAllByRole('row')).toHaveLength(8);
    expect(screen.getByRole('button', { name: 'Show less' })).toBeTruthy();
  });
});

describe('HealthTable', () => {
  it('shows a status pill and the reason in words', () => {
    render(<HealthTable rows={summary.skills} noun="skill" />);
    const flaky = screen.getByText('flaky-skill').closest('tr');
    expect(flaky?.textContent).toContain('Troubled');
    expect(flaky?.textContent).toContain('after 60% of recent uses');
    const never = screen.getByText('never-skill').closest('tr');
    expect(never?.textContent).toContain('check its description');
    expect(never?.textContent).toContain('—');
  });

  it('filters rows by a status chip that shows its count', () => {
    render(<HealthTable rows={summary.skills} noun="skill" />);
    fireEvent.click(screen.getByRole('button', { name: 'Troubled 1' }));
    expect(screen.getAllByRole('row')).toHaveLength(2); // header + flaky-skill
    expect(screen.getByText('flaky-skill')).toBeTruthy();
    fireEvent.click(screen.getByRole('button', { name: 'All 3' }));
    expect(screen.getAllByRole('row')).toHaveLength(4);
  });

  it('shows last used, the 30-day trend, and the trouble rate for every row', () => {
    render(<HealthTable rows={summary.skills} noun="skill" />);
    const headers = screen.getAllByRole('columnheader').map((th) => th.textContent);
    expect(headers).toEqual(expect.arrayContaining(['Last used', 'Trend', 'Trouble']));
    const good = screen.getByText('good-skill').closest('tr') as HTMLElement;
    const cells = within(good).getAllByRole('cell').map((td) => td.textContent);
    expect(cells).toEqual(expect.arrayContaining(['8 → 9', '0%']));
  });

  it('drops a status filter whose status no longer has rows', () => {
    const { rerender } = render(<HealthTable rows={summary.skills} noun="skill" />);
    fireEvent.click(screen.getByRole('button', { name: 'Troubled 1' }));
    const calm = summary.skills.filter((r) => r.status !== 'troubled');
    rerender(<HealthTable rows={calm} noun="skill" />);
    expect(screen.getByRole('button', { name: 'All 2' }).getAttribute('aria-pressed')).toBe('true');
    expect(screen.getAllByRole('row')).toHaveLength(3);
  });

  it('caps rows at 5 until "Show all"', () => {
    const rows = Array.from({ length: 7 }, (_, i) => ({ ...summary.skills[0], name: `skill-${i}` }));
    render(<HealthTable rows={rows} noun="skill" />);
    expect(screen.getAllByRole('row')).toHaveLength(6);
    fireEvent.click(screen.getByRole('button', { name: 'Show all 7' }));
    expect(screen.getAllByRole('row')).toHaveLength(8);
  });
});

describe('ShareBar', () => {
  const parts = Array.from({ length: 7 }, (_, i) => ({ label: `m${i}`, value: 7 - i, display: `$${7 - i}` }));

  it('colours the five largest parts and folds the rest into one', () => {
    render(<ShareBar parts={parts} emptyText="none" />);
    const rows = screen.getAllByRole('listitem').map((li) => li.textContent);
    expect(rows).toHaveLength(6);
    expect(rows[0]).toBe('m0$725%'); // 7 of 28
    expect(rows[5]).toBe('2 others11%'); // 2 + 1 of 28
  });

  it('shows the empty text when nothing is above zero', () => {
    render(<ShareBar parts={[{ label: 'a', value: 0, display: '$0' }]} emptyText="Nothing here." />);
    expect(screen.getByText('Nothing here.')).toBeTruthy();
  });
});

describe('MonthBurn', () => {
  it('builds the month so far and ends on the actual figure', () => {
    const days = [
      { date: '2026-09-30', tokens: 0, cost_usd: 50 },
      { date: '2026-10-01', tokens: 0, cost_usd: 10 },
      { date: '2026-10-02', tokens: 0, cost_usd: 5 },
    ];
    expect(burnPoints(days, 15)).toEqual({ points: [[0, 0], [1, 10], [2, 15]], monthDays: 31 });
  });

  it('folds a month day older than the pace window into the start', () => {
    const days = [{ date: '2026-10-31', tokens: 0, cost_usd: 4 }];
    expect(burnPoints(days, 100).points).toEqual([[30, 96], [31, 100]]);
  });
});

describe('DayBars', () => {
  it('states the average and the peak day', () => {
    render(<PaceStrip days={summary.projection.pace} />);
    const today = new Date().toLocaleDateString('en', { month: 'short', day: 'numeric' });
    expect(screen.getByText(/^Average/).textContent).toBe(`Average $15.50 · peak $30.00 on ${today}`);
  });
});

describe('splitLabel', () => {
  it('splits a disambiguated project name from its detail', () => {
    expect(splitLabel('app (C--Users-x-app)')).toEqual(['app', 'C--Users-x-app']);
    expect(splitLabel('claude-opus-5-5')).toEqual(['claude-opus-5-5', undefined]);
  });
});

describe('UnusedList', () => {
  it('lists names with their source', () => {
    render(<UnusedList items={[{ name: 'NotebookEdit', source: 'built-in' }]} emptyText="none" />);
    expect(screen.getByText('NotebookEdit')).toBeTruthy();
  });
});
