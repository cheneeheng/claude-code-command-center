---
artifact: iteration
title: Add a /health endpoint
status: proposed
created: 2026-06-29
scope: Expose a liveness check on the api-service.
---

# Add a /health endpoint

## Goal

Expose `GET /health` returning `200 {"status": "ok"}` so a load balancer can
check liveness without hitting a real route.

## Steps

1. Register a `GET /health` route.
2. Return `{"status": "ok"}` with HTTP 200 and no auth required.
3. Keep it dependency-free — it must not touch the database.

## Done when

- `curl localhost:PORT/health` returns `{"status": "ok"}`.
