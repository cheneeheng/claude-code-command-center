import type { ComponentType } from 'react';
import { z } from 'zod';

import type { QueryResult } from '../lib/api';

// Ported from the ceh-ag-ui canvas template's define.ts. Props that would hand styling
// to the agent: the look is fixed by the theme, so no schema may expose them.
const STYLE_KEY = /^(style|class(name)?|css|theme|colou?r|background|font.*|size|width|height|variant)$/i;

/** What a generated panel kind's component receives: its validated panel and the server's result. */
export type KindProps<P> = { panel: P; result: QueryResult };

/** One generated panel kind. Unlike the template, a kind is not a tool of its own. */
export type PanelKind = {
  name: string;
  description: string;
  schema: z.ZodObject;
  example: Record<string, unknown>;
  // Each kind's panel type differs; the schema has parsed the panel before render.
  Component: ComponentType<KindProps<any>>;
};

/** Throws when a JSON schema exposes a style-like key anywhere in it. */
export function assertNoStyleKeys(name: string, node: unknown): void {
  if (!node || typeof node !== 'object') return;
  const props = (node as { properties?: Record<string, unknown> }).properties ?? {};
  for (const [key, child] of Object.entries(props)) {
    if (STYLE_KEY.test(key)) throw new Error(`${name}: "${key}" lets the agent style the component`);
    assertNoStyleKeys(name, child);
  }
  assertNoStyleKeys(name, (node as { items?: unknown }).items);
  for (const branch of (node as { anyOf?: unknown[]; oneOf?: unknown[] }).anyOf ??
    (node as { oneOf?: unknown[] }).oneOf ??
    []) {
    assertNoStyleKeys(name, branch);
  }
}

/**
 * One generated panel kind. Fails at startup, not in front of a user, when the name is
 * not snake_case, the schema exposes styling, or the example no longer fits the schema.
 */
export function defineComponent<S extends z.ZodObject>(entry: {
  name: string;
  description: string;
  schema: S;
  example: z.input<S>;
  Component: ComponentType<KindProps<z.output<S>>>;
}): PanelKind {
  if (!/^[a-z][a-z0-9_]*$/.test(entry.name)) throw new Error(`${entry.name}: use snake_case`);
  assertNoStyleKeys(entry.name, z.toJSONSchema(entry.schema));
  entry.schema.parse(entry.example);
  return { ...entry, example: entry.example as Record<string, unknown> };
}
