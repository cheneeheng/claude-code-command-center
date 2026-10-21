import { HttpAgent, randomUUID } from '@ag-ui/client';
import { useMemo, useRef, useState } from 'react';
import { z } from 'zod';

import { addPanelSchema, addPanelToolSchema, kinds, type PanelFields } from '../catalogue/kinds';
import { addPanel, addSection, type EditResult, layoutState, movePanel, removePanel } from '../layout/edits';
import type { Layout } from '../layout/model';

/** One line of the chat transcript. */
export type ChatLine = { id: string; kind: 'user' | 'assistant' | 'note'; text: string };

// Stops an agent that keeps calling tools from looping forever.
const MAX_TOOL_ROUNDS = 5;

type Tool = {
  name: string;
  description: string;
  schema: z.ZodType;
  /** What the model is sent, when it differs from `schema` (which validates each call). */
  parameters?: z.ZodObject;
  /** Applies validated arguments; a note is shown in the chat. */
  apply: (args: never, layout: Layout) => EditResult & { note?: string };
};

const kindHelp = Object.values(kinds)
  .map((k) => `${k.name}: ${k.description} Example: ${JSON.stringify(k.example)}`)
  .join('\n');

const TOOLS: Tool[] = [
  {
    name: 'add_panel',
    description:
      'Add a panel to the end of a section. The panel shows the server-computed result of its ' +
      `query; never put figures in its title or caption. Kinds:\n${kindHelp}`,
    schema: addPanelSchema,
    parameters: addPanelToolSchema,
    apply: (args: z.infer<typeof addPanelSchema>, layout) => {
      const { section_id, ...fields } = args;
      const result = addPanel(layout, section_id, fields as PanelFields, `g-${randomUUID()}`);
      return 'error' in result ? result : { ...result, note: `Added panel: ${fields.title}` };
    },
  },
  {
    name: 'add_section',
    description: 'Add an empty section at the end, titled by the question it answers. Returns its id.',
    schema: z.object({ question: z.string().min(1).max(120), note: z.string().max(240).optional() }),
    apply: (args: { question: string; note?: string }, layout) =>
      addSection(layout, args.question, args.note, `s-${randomUUID()}`),
  },
  {
    name: 'move_panel',
    description: 'Move a panel to a position (0 = first) in a section.',
    schema: z.object({ panel_id: z.string(), section_id: z.string(), index: z.number().int().min(0) }),
    apply: (args: { panel_id: string; section_id: string; index: number }, layout) =>
      movePanel(layout, args.panel_id, args.section_id, args.index),
  },
  {
    name: 'remove_panel',
    description: 'Remove a panel. Reset layout brings back removed default panels.',
    schema: z.object({ panel_id: z.string() }),
    apply: (args: { panel_id: string }, layout) => removePanel(layout, args.panel_id),
  },
];

const toolDefs = TOOLS.map(({ name, description, schema, parameters }) => ({
  name,
  description,
  parameters: z.toJSONSchema(parameters ?? schema) as Record<string, unknown>,
}));

/**
 * The chat: one `HttpAgent` per thread, the layout edits as frontend tools. Only parsed
 * arguments reach an edit, so unknown keys (a `style`, say) are dropped; invalid
 * arguments or an unknown id return an `error:` tool result the agent can correct from.
 */
export function useAgent(layout: Layout, onLayout: (next: Layout) => void) {
  const [threadId, setThreadId] = useState(() => randomUUID());
  const agent = useMemo(() => new HttpAgent({ url: '/api/agent', threadId }), [threadId]);
  const [lines, setLines] = useState<ChatLine[]>([]);
  const [running, setRunning] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const current = useRef(layout);
  current.current = layout;
  const lastUser = useRef<string | null>(null);
  const stopped = useRef(false);

  const say = (kind: ChatLine['kind'], text: string) =>
    setLines((l) => [...l, { id: randomUUID(), kind, text }]);

  function apply(name: string, rawArgs: string): string {
    const tool = TOOLS.find((t) => t.name === name)!;
    let args: unknown;
    try {
      args = JSON.parse(rawArgs || '{}');
    } catch {
      return 'error: arguments were not valid JSON';
    }
    const parsed = tool.schema.safeParse(args);
    if (!parsed.success) return `error: ${z.prettifyError(parsed.error)}`;
    const result = tool.apply(parsed.data as never, current.current);
    if ('error' in result) return result.error;
    current.current = result.layout;
    onLayout(result.layout);
    if (result.note) say('note', result.note);
    return result.message;
  }

  // One user message = runs until the agent stops calling the layout tools.
  async function drive() {
    setRunning(true);
    setError(null);
    stopped.current = false;
    try {
      for (let round = 0; round < MAX_TOOL_ROUNDS; round++) {
        agent.setState(layoutState(current.current));
        let runError: string | null = null;
        const { newMessages } = await agent.runAgent(
          { tools: toolDefs },
          // RUN_ERROR resolves the run instead of rejecting it.
          { onRunErrorEvent: ({ event }) => void (runError = event.message) },
        );
        if (runError !== null) throw new Error(runError);
        for (const m of newMessages) {
          if (m.role === 'assistant' && typeof m.content === 'string' && m.content.trim()) say('assistant', m.content);
        }
        const calls = newMessages
          .flatMap((m) => (m.role === 'assistant' ? (m.toolCalls ?? []) : []))
          .filter((c) => TOOLS.some((t) => t.name === c.function.name));
        if (calls.length === 0) break;
        for (const call of calls) {
          const content = apply(call.function.name, call.function.arguments);
          agent.addMessage({ id: randomUUID(), role: 'tool', toolCallId: call.id, content });
        }
      }
    } catch (e) {
      if (!stopped.current) setError(e instanceof Error ? e.message : String(e));
    } finally {
      setRunning(false);
    }
  }

  async function send(text: string) {
    lastUser.current = text;
    say('user', text);
    agent.addMessage({ id: randomUUID(), role: 'user', content: text });
    await drive();
  }

  return {
    lines,
    running,
    error,
    send,
    /** Resend the last user message after a failed run. */
    retry: () => (lastUser.current ? send(lastUser.current) : Promise.resolve()),
    /** Abort the run; panels already placed stay. */
    stop: () => {
      stopped.current = true;
      agent.abortRun();
    },
    newChat: () => {
      stopped.current = true;
      agent.abortRun();
      setThreadId(randomUUID());
      setLines([]);
      setError(null);
    },
  };
}

/** What {@link useAgent} returns. */
export type Chat = ReturnType<typeof useAgent>;
