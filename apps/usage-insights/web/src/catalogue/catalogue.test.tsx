import { cleanup, fireEvent, render, screen, within } from '@testing-library/react';
import { afterEach, describe, expect, it } from 'vitest';

import { summary } from '../test/fixture';
import { HealthTable } from './HealthTable';
import { PaceStrip } from './PaceStrip';
import { RankedBars } from './RankedBars';
import { SessionTable } from './SessionTable';
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
  });
});

describe('PaceStrip', () => {
  it('draws 30 bars ending today and switches metric', () => {
    render(<PaceStrip days={summary.projection.pace} />);
    const bars = within(screen.getByRole('list', { name: /last 30 days/ })).getAllByRole('listitem');
    expect(bars).toHaveLength(30);
    const today = new Date().toLocaleDateString('en', { month: 'short', day: 'numeric' });
    expect(bars[29].getAttribute('aria-label')).toBe(`${today}: $30.00`);
    fireEvent.click(screen.getByRole('button', { name: 'Tokens' }));
    expect(bars[29].getAttribute('aria-label')).toBe(`${today}: 30K`);
  });
});

describe('RankedBars', () => {
  const rows = Array.from({ length: 12 }, (_, i) => ({ label: `r${i}`, value: 12 - i, display: `${12 - i}` }));

  it('keeps the given order and caps rows until "Show all"', () => {
    render(<RankedBars rows={rows} emptyText="none" />);
    expect(screen.getAllByRole('listitem').map((li) => li.textContent?.slice(0, 2))).toEqual(
      rows.slice(0, 10).map((r) => r.label.slice(0, 2)),
    );
    fireEvent.click(screen.getByRole('button', { name: 'Show all 12' }));
    expect(screen.getAllByRole('listitem')).toHaveLength(12);
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
});

describe('UnusedList', () => {
  it('lists names with their source', () => {
    render(<UnusedList items={[{ name: 'NotebookEdit', source: 'built-in' }]} emptyText="none" />);
    expect(screen.getByText('NotebookEdit')).toBeTruthy();
  });
});
