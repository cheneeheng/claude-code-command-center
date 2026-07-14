// Centralized fetch wrapper: JSON in/out, error envelope, shared error banner.
window.RT = window.RT || {};

RT.banner = {
  show(msg) {
    const el = document.getElementById("banner");
    document.getElementById("banner-text").textContent = msg;
    el.hidden = false;
  },
  hide() { document.getElementById("banner").hidden = true; },
};

RT.api = {
  async request(method, path, body) {
    let res;
    try {
      res = await fetch(path, {
        method,
        headers: body !== undefined ? { "Content-Type": "application/json" } : {},
        body: body !== undefined ? JSON.stringify(body) : undefined,
      });
    } catch (exc) {
      RT.banner.show(`network error: ${exc.message}`);
      throw exc;
    }
    let payload = null;
    try { payload = await res.json(); } catch { /* non-JSON (empty) body */ }
    if (!res.ok) {
      const err = new Error((payload && payload.detail) || res.statusText);
      err.status = res.status;
      err.code = (payload && payload.error) || "error";
      err.payload = payload;
      // The shared banner shows every API failure; callers with a local surface
      // (e.g. stale-file dialog) hide it again via RT.banner.hide().
      RT.banner.show(`${err.code}: ${err.message}`);
      throw err;
    }
    return payload;
  },
  get(path) { return this.request("GET", path); },
  post(path, body) { return this.request("POST", path, body ?? {}); },
  put(path, body) { return this.request("PUT", path, body); },
  del(path) { return this.request("DELETE", path); },
};

document.addEventListener("DOMContentLoaded", () => {
  document.getElementById("banner-dismiss").addEventListener("click", RT.banner.hide);
});

// Tiny shared helpers (formatting, DOM building).
RT.h = function h(tag, attrs, ...children) {
  const el = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs || {})) {
    if (k === "class") el.className = v;
    else if (k.startsWith("on")) el.addEventListener(k.slice(2), v);
    else if (v !== undefined && v !== null) el.setAttribute(k, v);
  }
  for (const child of children.flat()) {
    if (child === null || child === undefined) continue;
    el.append(child.nodeType ? child : document.createTextNode(child));
  }
  return el;
};

// Inline icon: a single solid path on a 24px grid, drawn in currentColor.
RT.icon = function icon(pathD) {
  const NS = "http://www.w3.org/2000/svg";
  const svg = document.createElementNS(NS, "svg");
  svg.setAttribute("viewBox", "0 0 24 24");
  svg.setAttribute("class", "icon");
  svg.setAttribute("aria-hidden", "true");
  const path = document.createElementNS(NS, "path");
  path.setAttribute("d", pathD);
  path.setAttribute("fill", "currentColor");
  svg.append(path);
  return svg;
};
RT.icons = {
  trash: "M9 3v1H4v2h16V4h-5V3H9zM6 8v13h12V8H6zm3 2h2v9H9v-9zm4 0h2v9h-2v-9z",
};

// Project identity tile: initial letter on a data-ramp tint (stable name hash).
RT.monogram = function monogram(name) {
  const ramp = ([...name].reduce((a, c) => a + c.charCodeAt(0), 0) % 6) + 1;
  return RT.h("span", {
    class: "monogram", style: `--mono-c: var(--data-${ramp})`, "aria-hidden": "true",
  }, (name[0] || "?").toUpperCase());
};

RT.fmt = {
  ago(tsSeconds) {
    if (!tsSeconds) return "—";
    const s = Math.max(0, Math.floor(Date.now() / 1000 - tsSeconds));
    if (s < 60) return `${s}s ago`;
    if (s < 3600) return `${Math.floor(s / 60)}m ago`;
    if (s < 86400) return `${Math.floor(s / 3600)}h ago`;
    return `${Math.floor(s / 86400)}d ago`;
  },
  agoIso(iso) {
    if (!iso) return "—";
    return this.ago(Date.parse(iso) / 1000);
  },
  cost(est, reported) {
    const e = est === null || est === undefined ? "n/a" : `$${est.toFixed(4)}`;
    if (reported === null || reported === undefined) return `${e} est`;
    return `${e} est · $${reported.toFixed(4)} reported`;
  },
  costShort(est) {
    return est === null || est === undefined ? "n/a" : `$${est.toFixed(2)}`;
  },
};
