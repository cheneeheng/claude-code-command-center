---
artifact: ITER_19
status: ready
created: 2026-06-09
scope: "Tidewater refinement — de-generification pass + brand mark. Strips the ITER_18 garnish layer (atmosphere, gradients, glows, entrance motion, hover-lift, uniform large radii) while keeping the Tidewater palette, colour roles, and hybrid bridge intact. Moves the 'premium' signal into typography and density. Promotes the fader glyph to a two-tone brand mark used in the header of both surfaces, as a favicon (HTML), and as the marketplace icon (VSCode). CSS + static markup + one committed PNG asset; no JS, no Python, no message-protocol change."
sections_changed: [02, 03, 04, 05]
sections_unchanged: [01]
depends_on: [SKELETON, ITER_01, ITER_02, ITER_03, ITER_04, ITER_05, ITER_06, ITER_07, ITER_08, ITER_09, ITER_10, ITER_11, ITER_12, ITER_13, ITER_14, ITER_15, ITER_16, ITER_17, ITER_18]
---

# ITER_19 · Tidewater refinement — de-generification + brand mark

> **Premise.** ITER_18 is implemented and the palette works. What remains is that the design reads as "generated": it carries all the stock tells at once — corner glows + grain, gradient fills with glow rings, staggered entrance animation, hover-lift on every row, uniform 14–16px radii, serif display on multiple elements. This iteration removes the garnish and concentrates the identity into three things: the palette (unchanged), the typography (tightened), and **one signature detail** — the terracotta enabled-edge.
>
> **What is explicitly kept from ITER_18:** the teal/terracotta colour roles (§02 of ITER_18), the full token-context shape, the `:has()` enabled-row mechanism, the hybrid VSCode bridge, the web-font stack, the reduced-motion guard, and the single-canonical-stylesheet rule (ITER_05). This is a *subtraction* iteration — every change below is expressed as a delta against the **implemented** ITER_18 state of `html/styles.css`.

## §01 · Concept
> Unchanged — see SKELETON §01.

---

## §02 · Architecture

### Design rules this iteration enforces

1. **One decorated element.** The terracotta enabled-state (flat wash + solid left edge) is the only ornamental moment on the page. Everything else is flat surfaces, hairline borders, and type.
2. **No gradients, no glows.** Brand colours appear only as flat fills and flat washes. Gradient fills in 16–20px components never resolve visually; they only read as "shimmer."
3. **Motion carries meaning or doesn't exist.** The only animated things are state changes the user caused: the toggle thumb, the disclosure expand/collapse (ITER_05), and hover/focus colour transitions (~130ms ease-out). No entrance choreography.
4. **Depth is border-led.** At most one floating container (the install panel). Rows are flat list items separated by hairline dividers — density and flatness are what make a sidebar tool read as "built by someone who uses it daily."
5. **Typography is the premium signal.** Fraunces appears exactly **once** (the app title). Hierarchy below that is built from weight, size, uppercase micro-labels, and tabular numerals — not from more serif.

### Token model changes (delta vs ITER_18 §02)

| Token | Fate | Reason |
|---|---|---|
| `--accent-glow`, `--secondary-glow` | **Dropped** from all four contexts; the HC-override lines that zeroed them are deleted too | Glow rings removed (rule 2). See reconciliation item R1 for stray consumers. |
| `--accent-hi` | **Dropped** | Only consumer was the enabled-edge gradient, now a flat `--accent` fill (confirm — R2). |
| `--secondary-hi` | **Kept, re-purposed** | Now the *flat hover fill* for filled controls (`.mp-install-btn:hover`, `.bulk-install-btn:hover`, `.skills-toggle-btn:hover`). No longer a gradient stop. |
| `--shadow-md`, `--shadow-lift` | **Dropped** | One shadow tier remains (rule 4). |
| `--shadow-sm` | **Kept** | Sole consumer: the install panel. |
| `--radius-lg: 10px`, `--radius-md: 6px`, `--radius-sm: 4px` | **Added** (base `:root`, theme-independent — same placement as the `--font-*` tokens) | Replaces the uniform 14–16px radii with a hierarchy. |
| All other ITER_18 tokens | Unchanged | Palette, neutrals, `--on-text`, washes, `--inherited-*`, `--font-*` all survive. |

> **Bridge note.** The `:root[data-context="vscode"]` block and `body.vscode-light` / `.vscode-high-contrast` overrides keep their structure; they only lose their `-glow` lines (and the HC block loses its two `*-glow: transparent` lines). The radius tokens are theme-independent and need no bridge override.

### Resolution of the ITER_18 open question — inherited + enabled rows

ITER_18 left unconfirmed whether `.plugin-row:has(.toggle:checked)` (0,3,0) beating `.plugin-row.inherited` (0,2,0) — i.e. enabled inherited rows receiving the terracotta treatment — was intentional. **Resolved: it is intentional and is now the spec.** The wash/edge signals *"this plugin is enabled here, in this project"* regardless of which scope the enablement comes from; hiding it on inherited rows would make the page lie about effective state. The inherited *identity* treatment is preserved independently: `.plugin-row.inherited .plugin-name { color: var(--inherited-fg) }` targets the name element, not the row, so it is untouched by the row-level `:has()` rule. Net rendering for an enabled inherited row: terracotta wash + edge, dimmed name. `--inherited-bg` remains the background for *disabled* inherited rows only. No CSS change is required to enact this — this section exists so the behaviour is documented as chosen, not accidental.

### Brand mark (architecture of the asset)

One glyph — the three-fader mark — in three renditions, all sharing geometry with the existing activity-bar `icon.svg`:

| Rendition | Surface | Colour source | File |
|---|---|---|---|
| **Header mark** | `index.html` + `panel.html` (the ITER_18 `.mark` element) | Inline SVG, fills via CSS custom properties — adapts to theme/bridge/HC automatically | Markup inside the templates (no new file) |
| **Favicon** | `index.html` only | Inline `data:image/svg+xml` `<link rel="icon">`, **static hexes** (light-palette values) | Markup only — deliberately no `server.py` route |
| **Marketplace icon** | `package.json` `"icon"` | Static PNG, dark-petrol tile (vsce requires PNG; see §04) | `vscode-extension/media/icon.png`, committed |

The **activity-bar `icon.svg` is unchanged** — VSCode recolours activity icons via the theme foreground, so it must stay monochrome `currentColor`. The two-tone treatment applies only to the renditions above.

Colour semantics of the mark: tracks in muted neutral-teal, knobs in `--secondary`, and **exactly one knob in `--accent`** — the mark itself encodes the product's colour rule (terracotta = enabled).

---

## §03 · Tech Stack

**Google Fonts link (in `index.html` only) — trimmed, not removed.** Fraunces now has a single consumer (the app title), so the `<link>` request is slimmed to the weights actually used: Fraunces `opsz,wght` 600 only; Hanken Grotesk 400 + 600; JetBrains Mono 400. No other §03 change — no new runtime, npm, or Python dependency. The marketplace PNG is a **one-time committed binary asset**, not a build step: no change to the Makefile, the CSS sync guard, or CI packaging beyond the `package.json` field in §04.

---

## §04 · Backend

> `server.py` unchanged — the favicon is a data-URI in `index.html` precisely so no new route is needed. `extension.js` unchanged (CSP untouched; the marketplace icon is not a webview resource).

**`vscode-extension/package.json` — one field added:**

```json
{
  "icon": "media/icon.png"
}
```

- vsce requires the marketplace icon to be a **PNG** (SVG is rejected); 128×128 minimum.
- Asset spec for `media/icon.png` (one-time export, any tool): 128×128, rounded-square tile (corner radius ≈ 28px) filled with dark petrol `#0C1F1D`; the fader mark centred at ~72×72 using the **dark-mode** brand shades — tracks `#2D544D` (dark `--border-strong`), knobs `#2FB3A8`, top knob `#E98A62`.
- Verify `.vscodeignore` does **not** exclude `media/` (reconciliation item R5) — an excluded icon fails the `vsce package` step in the release workflow (ITER_06/07 CI).

---

## §05 · Frontend

> All CSS in `html/styles.css` (canonical), synced to the webview copy as ever (ITER_05). Changes are grouped as **removals** (delete ITER_18 rules), **replacements** (rule survives, value changes), and **additions**. Selectors are the live ones confirmed in the ITER_18 resolved checklist (`.toggle`, `.plugin-row`, `.marketplace-badge`, …).

### A · Removals (delete outright)

1. **Atmosphere layer** — the `body::before` corner-glow rule, the `body::after` `feTurbulence` grain rule (including its data-URI), **and** the now-pointless bridge override `:root[data-context="vscode"] body::before, …::after { display:none }`.
2. **Entrance motion** — `@keyframes rise` and every `animation` / `animation-delay` declaration that references it (header, project-card, rows). The `prefers-reduced-motion` guard **stays** — it still governs the remaining transitions.
3. **Hover lift** — the `.plugin-row:hover { transform: translateY(-2px); box-shadow: var(--shadow-lift) }` rule.
4. **Glow tokens** — all `--accent-glow` / `--secondary-glow` declarations in the light, dark, system-dark, and vscode-bridge blocks, plus the two `*-glow: transparent` lines in `body.vscode-high-contrast` (R1 first).
5. **Dropped tokens** — `--accent-hi` (R2 first), `--shadow-md`, `--shadow-lift` declarations in every block.

### B · Replacements

**Toggle — flat fill, no ring** (replaces the ITER_18 gradient + glow):

```css
.toggle:checked {
  background: var(--secondary);
}
```

Thumb-slide transition is kept as-is. Focus visibility must not regress when the glow ring goes: if the live file has no explicit focus style on `.toggle`, add `.toggle:focus-visible { outline: 2px solid var(--secondary); outline-offset: 2px; }` (R1).

**Enabled row — flat wash, solid edge** (replaces both ITER_18 gradients; `position: relative` on `.plugin-row` stays):

```css
.plugin-row:has(.toggle:checked) {
  background: var(--accent-wash);
}
.plugin-row:has(.toggle:checked)::before {
  content:""; position:absolute; left:0; top:0; bottom:0; width:3px;
  background: var(--accent);
}
```

**Rows — from cards to a dense list.** `.plugin-row` drops its per-row `border-radius` and `box-shadow`; rows become flat items separated by a hairline:

```css
.plugin-row {
  border-radius: 0;
  box-shadow: none;
  border-bottom: 1px solid var(--border);
  padding: 6px 10px;            /* target — confirm current values first, R3 */
}
.plugin-row:last-child { border-bottom: none; }
.plugin-row:hover { background: var(--surface-2); }
```

(The enabled wash and `:hover` interplay: hover on an enabled row keeps the wash — the `:has()` rule's specificity already guarantees this; do not add a combined selector.)

**Containers — radius hierarchy, border-led depth:**

- `.project-card` — `border-radius: var(--radius-lg); border: 1px solid var(--border); box-shadow: none;` padding tightened to 12px (R3). Its teal left edge (ITER_18 metadata rule) stays.
- Install panel — `border-radius: var(--radius-lg); box-shadow: var(--shadow-sm);` — the **only** shadowed element.
- `.marketplace-badge`, `.version-badge`, `.not-installed-tag`, `.mp-keyword` — `border-radius: var(--radius-sm)`.
- Buttons (`.skills-toggle-btn`, `.mp-install-btn`, `.bulk-install-btn`, `.project-change-btn`, `.marketplace-refresh-btn`, theme buttons) — `border-radius: var(--radius-md)`.
- Filled-button hovers re-point from any gradient/`-glow` styling to flat `background: var(--secondary-hi); color: var(--on-text);`.

**Typography — Fraunces narrowed to one consumer:**

- App title (header `h1`) — keeps `var(--font-display)`, adds `font-optical-sizing: auto; font-weight: 600;`. No italic (under the bridge, `--font-display` is the editor font; italicising it would look broken).
- `.project-name` and the install-panel title — **revert to `var(--font-ui)`**, `font-weight: 600`. This undoes part of the ITER_18 typography delta deliberately.
- Section counts / scope micro-labels — `text-transform: uppercase; letter-spacing: .06em; font-size: 11px; color: var(--fg-muted); font-variant-numeric: tabular-nums;`.
- `.version-badge` and any count element — `font-variant-numeric: tabular-nums`.
- Mono elements (paths, badges already on `--font-mono`) — one step smaller (e.g. `font-size: 11px`) and `color: var(--fg-muted)` where they aren't already.

### C · Additions

**Radius tokens** (base `:root`, alongside the `--font-*` declarations):

```css
:root { --radius-lg: 10px; --radius-md: 6px; --radius-sm: 4px; }
```

**Header mark — replace the `.mark` element's inner content** in *both* `index.html` and `panel.html` with the two-tone inline SVG (static markup, no JS — same constraint as ITER_18's mark):

```html
<span class="mark" aria-hidden="true">
  <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" width="18" height="18" fill="none">
    <rect x="2" y="3"  width="12" height="2" rx="1" fill="var(--border-strong)"/>
    <rect x="2" y="7"  width="12" height="2" rx="1" fill="var(--border-strong)"/>
    <rect x="2" y="11" width="12" height="2" rx="1" fill="var(--border-strong)"/>
    <circle cx="12" cy="4"  r="2" fill="var(--accent)"/>
    <circle cx="5"  cy="8"  r="2" fill="var(--secondary)"/>
    <circle cx="10" cy="12" r="2" fill="var(--secondary)"/>
  </svg>
</span>
```

- Tracks use `--border-strong` (a teal-tinted neutral in the Tidewater palette) rather than `--secondary-wash`, so the mark stays visible under `body.vscode-high-contrast` where washes were transparent and is robust now that washes are unchanged but HC themes vary. Under HC, `--accent` and `--secondary` both resolve to the theme link colour (ITER_18 bridge) — the mark degrades to monochrome, which is correct for HC.
- Any ITER_18-era CSS that coloured the old `.mark` glyph via `color`/`background` is removed; the SVG is self-coloured.

**Favicon — `index.html` `<head>` only**, data-URI with static light-palette hexes (no theme switching, no server route):

```html
<link rel="icon" type="image/svg+xml"
  href="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 16 16'%3E%3Crect x='2' y='3' width='12' height='2' rx='1' fill='%23C7DBD6'/%3E%3Crect x='2' y='7' width='12' height='2' rx='1' fill='%23C7DBD6'/%3E%3Crect x='2' y='11' width='12' height='2' rx='1' fill='%23C7DBD6'/%3E%3Ccircle cx='12' cy='4' r='2' fill='%23CB6442'/%3E%3Ccircle cx='5' cy='8' r='2' fill='%230E7E77'/%3E%3Ccircle cx='10' cy='12' r='2' fill='%230E7E77'/%3E%3C/svg%3E">
```

`panel.html` gets **no** favicon (webviews have no tab).

### Reconciliation checklist (verify against the live, ITER_18-implemented `styles.css` before coding)

> Same protocol as ITER_18's checklist — these are confirmations, not open design decisions; every behaviour above is already decided.

- **R1 — Glow consumers.** Grep `--accent-glow` / `--secondary-glow`. Expected consumers: the toggle's checked `box-shadow` only. If the implementation added focus rings on any control using a glow token, replace each with `outline: 2px solid var(--secondary); outline-offset: 2px;` on `:focus-visible`. If `.toggle` ends up with no focus affordance at all, add the focus rule given in §B.
- **R2 — `--accent-hi` consumers.** Expected: only the enabled-edge gradient. If anything else consumes it, re-point that consumer to `--accent`, then drop the token.
- **R3 — Current padding values.** Record the implemented paddings on `.plugin-row`, `.project-card`, and the install panel before applying the density targets (6px 10px / 12px), so the delta is reviewable in the diff.
- **R4 — Old `.mark` styling.** Identify how the ITER_18 mark glyph was rendered (text glyph? CSS shape?) and remove its colour rules when swapping in the SVG.
- **R5 — Packaging.** Confirm `.vscodeignore` includes `media/icon.png` in the package, and that the ITER_06/07 release workflow's `vsce package` step picks up the `"icon"` field without further config.

---

## Deferred

- **Bundled webview fonts** — still deferred (ITER_18). Worth revisiting only if the single Fraunces title proves worth the `.vsix` weight.
- **Brand-contrast QA across VSCode themes** — still deferred (ITER_18); now also covers the header-mark renditions under Dark+/Light+/Solarized/HC.
- **Animated mark** (e.g. a knob sliding on hover) — explicitly out of scope; it would reintroduce decorative motion this iteration exists to remove.
- **README / repo branding** (badges, social-preview image reusing the tile) — out of scope; revisit if/when the extension is published.

---

## Cross-references

- ITER_18 §02 — colour roles and token contexts this iteration inherits; §05 resolved checklist — source of the confirmed live selectors.
- ITER_14 — optimistic toggle update/revert; unaffected because the enabled state still keys off `:checked` with no JS class.
- ITER_13 — three-scope model; the inherited-row resolution in §02 is the closure of the specificity question raised against it.
- ITER_05 — single canonical stylesheet + sync guard; unchanged and binding.
- ITER_06/07 — CI release packaging touched only via the `package.json` `"icon"` field (R5).
- ITER_01 — activity-bar `icon.svg` contribution; explicitly unchanged.
