---
status: fixed
date: 2026-10-21
---

# The chat's first message fails: the API rejects the add_panel tool schema

**Symptom:** sending any chat message → `Error code: 400 - {'type': 'error', 'error': {'type':
'invalid_request_error', 'message': 'tools.0.custom.input_schema.type: Field required'}}`
(reported by the user on the first live run).

## Diagnosis

Cause known from the report: `tools.0` is `add_panel`, the first frontend tool the canvas sends.

**Cause:** `web/src/hooks/useAgent.ts` (`toolDefs`): `add_panel`'s parameters were
`z.toJSONSchema(addPanelSchema)`, a zod discriminated union on `kind`. That serialises to a
top-level `oneOf` with no `type`, and the Claude API requires `type: "object"` at the top of a
tool's `input_schema` (and refuses a top-level `oneOf`/`anyOf`/`allOf`). The server passed the
schema through unchanged.

**Prediction:** the tools in the page's first `/api/agent` request → `add_panel` has `type`
undefined; seen in the new test's failure ("Expected type: object, Received type: undefined").

## Fix

`add_panel` now sends the model one flat object schema (`addPanelToolSchema`: section id, `kind`
enum, title, caption, query, wide). Each call is still validated against the strict per-kind
union, so `trend`'s day-or-week rule and `stat`'s `none` grouping still hold, and a call that
breaks them gets an `error:` tool result the agent can correct from.

**Tests:**

- `ChatDrawer.test.tsx` "sends every tool with an object schema the Claude API accepts" —
  protects: every frontend tool reaches the API with `type: "object"` at the top and no top-level
  union; fails_when: a tool's schema is built from a union again (checked: red with the fix
  stashed, green with it); why_new: the Python tests drive the loop with a scripted client that
  never validates schemas, and the web tests never looked at the tool definitions sent.

**Unverified:** a live request with the fixed schema; the user reruns the live check. That the
API accepts the `$schema` and `additionalProperties` keys zod adds is inferred, not run.
