---
artifact: iteration
title: Add a dark-mode toggle
status: proposed
created: 2026-06-29
scope: Add a persisted light/dark theme switch to the web-app shell.
---

# Add a dark-mode toggle

## Goal

Give the app a header toggle that switches between light and dark themes and
remembers the choice across reloads.

## Steps

1. Add a `data-theme` attribute on `<html>`, defaulting to the OS preference
   (`prefers-color-scheme`).
2. Add a toggle button in the header that flips `data-theme` between `light`
   and `dark`.
3. Persist the chosen theme in `localStorage` and re-apply it on load.
4. Define the dark palette as CSS custom properties scoped to
   `[data-theme="dark"]`.

## Done when

- Toggling flips the whole page between the two palettes.
- The choice survives a full page reload.
