import { cleanup, render, screen, within } from '@testing-library/react';
import { afterEach, describe, expect, it } from 'vitest';

import { Dashboard } from '../components/Dashboard';
import { summary } from '../test/fixture';
import { defaultLayout } from './defaultLayout';

afterEach(cleanup);

describe('defaultLayout', () => {
  it('asks the three questions in order', () => {
    render(<Dashboard layout={defaultLayout} data={summary} />);
    expect(screen.getAllByRole('heading', { level: 2 }).map((h) => h.textContent)).toEqual([
      'What will I spend?',
      'Where does it go?',
      'What should I fix?',
    ]);
  });

  it('labels each section with an eyebrow count', () => {
    render(<Dashboard layout={defaultLayout} data={summary} />);
    for (const label of ['Projects · 2', 'Models · 1', 'Skills · 3', 'Tools · 2', 'Not called · 2']) {
      expect(screen.getByText(label)).toBeTruthy();
    }
  });

  it('keeps the server ranking and puts troubled skills right after never-used', () => {
    render(<Dashboard layout={defaultLayout} data={summary} />);
    const projects = screen.getByText('Projects · 2').parentElement as HTMLElement;
    const items = within(projects).getAllByRole('listitem').map((li) => li.textContent ?? '');
    expect(items.map((t) => t.match(/^(alpha|beta)/)?.[1])).toEqual(['alpha', 'beta']);
    const skills = screen.getByText('Skills · 3').parentElement as HTMLElement;
    const firstCells = within(skills)
      .getAllByRole('row')
      .slice(1)
      .map((tr) => within(tr).getAllByRole('cell')[0].textContent ?? '');
    expect(firstCells.map((t) => t.split(' ')[0])).toEqual(['never-skill', 'flaky-skill', 'good-skill']);
  });

  it('lists only MCP servers without calls as not called', () => {
    render(<Dashboard layout={defaultLayout} data={summary} />);
    const notCalled = screen.getByText('Not called · 2').parentElement as HTMLElement;
    expect(notCalled.textContent).toContain('github');
    expect(notCalled.textContent).not.toContain('claude-in-chrome');
  });
});
