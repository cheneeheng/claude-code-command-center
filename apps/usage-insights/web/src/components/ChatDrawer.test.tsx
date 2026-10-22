import { cleanup, fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';

import { App } from '../App';
import type { QueryResult, Summary } from '../lib/api';
import { summary } from '../test/fixture';

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
});

type Event = Record<string, unknown>;
/** One scripted agent run: its events, or `'hang'` to stay open until aborted. */
type Script = ((input: { threadId: string; runId: string }) => Event[]) | 'hang';

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });

const sse = (events: Event[]) =>
  new Response(events.map((e) => `data: ${JSON.stringify(e)}\n\n`).join(''), {
    headers: { 'Content-Type': 'text/event-stream' },
  });

/** A run that calls one frontend tool with these arguments. */
const call = (name: string, args: unknown, id = 'c1'): Script => ({ threadId, runId }) => [
  { type: 'RUN_STARTED', threadId, runId },
  { type: 'TOOL_CALL_START', toolCallId: id, toolCallName: name },
  { type: 'TOOL_CALL_ARGS', toolCallId: id, delta: JSON.stringify(args) },
  { type: 'TOOL_CALL_END', toolCallId: id },
  { type: 'RUN_FINISHED', threadId, runId },
];

const say = (text: string): Script => ({ threadId, runId }) => [
  { type: 'RUN_STARTED', threadId, runId },
  { type: 'TEXT_MESSAGE_START', messageId: `m-${runId}`, role: 'assistant' },
  { type: 'TEXT_MESSAGE_CONTENT', messageId: `m-${runId}`, delta: text },
  { type: 'TEXT_MESSAGE_END', messageId: `m-${runId}` },
  { type: 'RUN_FINISHED', threadId, runId },
];

const fail = (message: string): Script => ({ threadId, runId }) => [
  { type: 'RUN_STARTED', threadId, runId },
  { type: 'RUN_ERROR', message },
];

const result: QueryResult = {
  metric: 'cost_usd',
  group_by: 'project',
  range: '30d',
  unit: 'usd',
  rows: [{ key: 'alpha', label: 'alpha', value: 12 }],
  total: 12,
  truncated: false,
};

const BARS = {
  section_id: 'spend-where',
  kind: 'bars',
  title: 'Cost by project',
  caption: 'Where the money goes.',
  query: { metric: 'cost_usd', group_by: 'project' },
};

/** Routes every request; returns what the page sent. */
function stubServer(scripts: Script[], opts: { chat?: boolean; putStatus?: number } = {}) {
  const runs: { messages: { role: string; content?: unknown; toolCallId?: string }[]; state: unknown }[] = [];
  const puts: unknown[] = [];
  const data: Summary = { ...summary, chat: { enabled: opts.chat ?? true } };
  vi.stubGlobal('fetch', (input: RequestInfo | URL, init?: RequestInit) => {
    const url = String(input);
    const method = init?.method ?? 'GET';
    if (url === '/api/layout' && method === 'GET') return Promise.resolve(new Response(null, { status: 204 }));
    if (url === '/api/layout' && method === 'PUT') {
      puts.push(JSON.parse(String(init?.body)));
      return Promise.resolve(new Response(null, { status: opts.putStatus ?? 204 }));
    }
    if (url.startsWith('/api/query')) return Promise.resolve(json(result));
    if (url === '/api/agent') {
      const body = JSON.parse(String(init?.body));
      runs.push(body);
      const script = scripts.shift();
      if (!script) throw new Error('no scripted run left');
      if (script === 'hang')
        return new Promise<Response>((_, reject) =>
          init?.signal?.addEventListener('abort', () => reject(new DOMException('aborted', 'AbortError'))),
        );
      return Promise.resolve(sse(script(body)));
    }
    return Promise.resolve(json(data));
  });
  return { runs, puts };
}

async function openChat() {
  render(<App />);
  fireEvent.click(await screen.findByRole('button', { name: 'Chat' }));
  return screen.getByRole('complementary', { name: 'Chat' });
}

function ask(drawer: HTMLElement, text: string) {
  fireEvent.change(within(drawer).getByLabelText('Message'), { target: { value: text } });
  fireEvent.click(within(drawer).getByRole('button', { name: 'Send' }));
}

/** The content of the last tool message the page sent to the agent. */
const lastToolResult = (runs: ReturnType<typeof stubServer>['runs']) =>
  String(runs.at(-1)?.messages.filter((m) => m.role === 'tool').at(-1)?.content);

describe('chat drawer', () => {
  it('shows a disabled Chat button that names the key when the chat is not enabled', async () => {
    stubServer([], { chat: false });
    render(<App />);
    await screen.findByRole('heading', { name: 'What will I spend?' });
    const button = screen.getByRole('button', { name: 'Chat' });
    expect(button.getAttribute('aria-disabled')).toBe('true');
    expect(button.getAttribute('title')).toContain('C4_USAGE_INSIGHTS_API_KEY');
    fireEvent.click(button);
    expect(screen.queryByRole('complementary', { name: 'Chat' })).toBeNull();
  });

  it('places a panel from add_panel and saves the layout', async () => {
    const { runs, puts } = stubServer([call('add_panel', BARS), say('Placed it.')]);
    const drawer = await openChat();
    ask(drawer, 'Which projects cost most?');
    expect(await within(drawer).findByText('Placed it.')).toBeTruthy();
    expect(within(drawer).getByText('Added panel: Cost by project')).toBeTruthy();
    expect(screen.getByText('Cost by project', { selector: '.eyebrow' })).toBeTruthy();
    expect(lastToolResult(runs)).toMatch(/^added panel g-/);
    const saved = puts.at(-1) as { sections: { id: string; panels: Record<string, unknown>[] }[] };
    const panel = saved.sections.find((s) => s.id === 'spend-where')!.panels.at(-1)!;
    expect(panel).toMatchObject({ kind: 'bars', title: 'Cost by project' });
    expect(panel).not.toHaveProperty('section_id');
    // The agent sees the layout as state on every run.
    expect(JSON.stringify(runs[0].state)).toContain('"id":"spend-where"');
  });

  it('sends every tool with an object schema the Claude API accepts', async () => {
    const { runs } = stubServer([say('Hi.')]);
    const drawer = await openChat();
    ask(drawer, 'Hello');
    await within(drawer).findByText('Hi.');
    const tools = (runs[0] as unknown as { tools: { name: string; parameters: Record<string, unknown> }[] }).tools;
    expect(tools.map((t) => t.name)).toEqual(['add_panel', 'add_section', 'move_panel', 'remove_panel']);
    for (const { name, parameters } of tools) {
      // The API needs `type: "object"` at the top and refuses a top-level oneOf, anyOf, or allOf.
      expect({ name, type: parameters.type }).toEqual({ name, type: 'object' });
      for (const key of ['oneOf', 'anyOf', 'allOf']) expect(parameters).not.toHaveProperty(key);
    }
  });

  it('drops a style key the agent sends', async () => {
    const { puts } = stubServer([call('add_panel', { ...BARS, style: { color: 'red' } }), say('ok')]);
    const drawer = await openChat();
    ask(drawer, 'Make it red');
    await within(drawer).findByText('ok');
    expect(JSON.stringify(puts.at(-1))).not.toContain('color');
    expect(screen.getByText('Cost by project', { selector: '.eyebrow' })).toBeTruthy();
  });

  it('answers invalid arguments with an error result and places nothing', async () => {
    const { runs, puts } = stubServer([call('add_panel', { ...BARS, kind: 'pie' }), say('Sorry.')]);
    const drawer = await openChat();
    ask(drawer, 'A pie chart');
    await within(drawer).findByText('Sorry.');
    expect(lastToolResult(runs)).toMatch(/^error:/);
    expect(puts).toEqual([]);
    expect(screen.queryByText('Cost by project')).toBeNull();
  });

  it('answers remove_panel with an unknown id with an error result', async () => {
    const { runs } = stubServer([call('remove_panel', { panel_id: 'nope' }), say('It was not there.')]);
    const drawer = await openChat();
    ask(drawer, 'Remove it');
    await within(drawer).findByText('It was not there.');
    expect(lastToolResult(runs)).toBe('error: no panel with id nope');
  });

  it('disables the input while a run goes, and Stop keeps placed panels', async () => {
    stubServer([call('add_panel', BARS), 'hang']);
    const drawer = await openChat();
    expect(within(drawer).queryByRole('button', { name: 'Stop' })).toBeNull();
    ask(drawer, 'Which projects cost most?');
    await within(drawer).findByText('Added panel: Cost by project');
    expect(within(drawer).getByText(/Working/)).toBeTruthy();
    expect((within(drawer).getByLabelText('Message') as HTMLInputElement).disabled).toBe(true);
    fireEvent.click(within(drawer).getByRole('button', { name: 'Stop' }));
    await waitFor(() => expect(within(drawer).queryByRole('button', { name: 'Stop' })).toBeNull());
    expect((within(drawer).getByLabelText('Message') as HTMLInputElement).disabled).toBe(false);
    expect(within(drawer).queryByRole('alert')).toBeNull();
    expect(screen.getByText('Cost by project', { selector: '.eyebrow' })).toBeTruthy();
  });

  it('shows a failed save and keeps the edit on screen', async () => {
    stubServer([call('add_panel', BARS), say('Done.')], { putStatus: 500 });
    const drawer = await openChat();
    ask(drawer, 'Which projects cost most?');
    expect(await within(drawer).findByText('Could not save the layout')).toBeTruthy();
    expect(screen.getByText('Cost by project', { selector: '.eyebrow' })).toBeTruthy();
  });

  it('shows a run error with a Retry that resends the message', async () => {
    const { runs } = stubServer([fail('Too many steps, try a narrower question'), say('Second try.')]);
    const drawer = await openChat();
    ask(drawer, 'Everything at once');
    expect((await within(drawer).findByRole('alert')).textContent).toContain('Too many steps');
    fireEvent.click(within(drawer).getByRole('button', { name: 'Retry' }));
    expect(await within(drawer).findByText('Second try.')).toBeTruthy();
    expect(runs.at(-1)?.messages.filter((m) => m.role === 'user').at(-1)?.content).toBe('Everything at once');
  });

  it('starts with starter prompts and clears on New chat', async () => {
    const { runs } = stubServer([say('Here.')]);
    const drawer = await openChat();
    fireEvent.click(within(drawer).getByRole('button', { name: 'Show my daily cost this month' }));
    await within(drawer).findByText('Here.');
    const firstThread = (runs[0] as unknown as { threadId: string }).threadId;
    fireEvent.click(within(drawer).getByRole('button', { name: 'New chat' }));
    expect(within(drawer).queryByText('Here.')).toBeNull();
    expect(within(drawer).getByRole('button', { name: 'Which skills do I use most?' })).toBeTruthy();
    expect(firstThread).toBeTruthy();
  });
});
