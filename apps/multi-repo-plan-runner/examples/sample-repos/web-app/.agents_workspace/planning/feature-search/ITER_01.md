---
artifact: iteration
title: Search box — filter the list client-side
status: proposed
created: 2026-06-29
scope: First iteration of in-page search over the already-loaded item list.
---

# Search — iteration 1: client-side filter

A nested plan (slug `feature-search/ITER_01`) — docket discovers plans in
sub-folders too, so this demonstrates a multi-iteration feature laid out under
its own directory.

## Goal

Add a search input that filters the visible item list as the user types, with
no network round-trip.

## Steps

1. Add a text input above the list, labelled for screen readers.
2. On input, case-insensitively filter the rendered rows by their title text.
3. Show an empty-state message when nothing matches.

## Done when

- Typing narrows the list live; clearing the box restores it.
