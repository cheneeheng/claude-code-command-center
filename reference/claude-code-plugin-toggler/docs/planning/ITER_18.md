---
artifact: ITER_18
status: ready
created: 2026-06-06
scope: Visual redesign — "Tidewater" theme. Replaces the flat blue-accent palette with a teal/terracotta complementary system and adds depth, type, and motion. Introduces a `--secondary` (teal) token family and a font-token layer. The standalone HTML surface gets the full palette + web fonts; the VSCode surface adopts a HYBRID bridge — neutrals still derive from `--vscode-*` (so the panel matches the editor), brand colours are hardcoded. Still one canonical `styles.css`.
sections_changed: [02, 03, 05]
sections_unchanged: [01, 04]
depends_on: [SKELETON, ITER_01, ITER_02, ITER_03, ITER_04, ITER_05, ITER_06, ITER_07, ITER_08, ITER_09, ITER_10, ITER_11, ITER_12, ITER_13, ITER_14, ITER_15, ITER_16, ITER_17]
---

# ITER_18 · Tidewater visual redesign

> Presentational. No change to the data model, endpoints, webview messages, or JS render/handler **logic** — so `server.py`, `extension.js`, and the shared render functions are untouched. Two small non-logic touches are required: (a) the HTML templates (`index.html` + `panel.html`) gain one **static** header element (the logo mark, §05), and (b) the CSS re-points the existing control tokens and adds a `:has()`-driven enabled-row state (no class is added by JS). Because the UI is token-driven (ITER_01 §05), most components re-theme for free through their existing `var(--…)` references.
>
> **Audit note (2026-06-06):** reconciled against ITER_01–ITER_17. The colour model here was first drafted against the preview's Local/Global split; the live app is **three scopes — Local / Project / User** (ITER_13), all interactive (ITER_14). Corrections from that pass are folded in below; the **Reconciliation checklist** in §05 lists the live selectors/tokens that must be confirmed before implementing. **Update (2026-06-06b):** the checklist is now reconciled directly against the live `html/styles.css` — all four items resolved, the `var(--accent)` consumer list corrected (three missed consumers added), toggle selectors de-specified to `.toggle`, and `--toggle-on` marked for removal. See §02 and the resolved checklist in §05.

## §01 · Concept
> Unchanged — see SKELETON §01.

---

## §02 · Architecture

### Colour system (the rules the design enforces)

Two brand colours, two jobs, on a cool neutral foundation:

- **Terracotta (`--accent`)** — reserved for the **passive "enabled" row state** (wash + left edge) and the logo mark. It is *not* used on controls.
- **Teal (`--secondary`)** — **every interactive control** (toggle-on, primary/install buttons, theme switch, control hovers) **and identity/metadata** (marketplace badges, section counts, project-card edge, labels).
- **Neutrals** — cool petrol/off-white surfaces, replacing the current `#ffffff`/`#1e1e1e` flats.

> **Consequence (audit — reconciled 2026-06-06 against the live `styles.css`):** today `var(--accent)` *is* the single accent and every consumer is a control or control-adjacent indicator. The live grep returns **more** consumers than the original draft listed: `.skills-toggle-btn` (ITER_02), `.mp-install-btn` + its `:hover` (ITER_04), `.bulk-install-btn` + its `:hover` (ITER_04), the ThemeToggle active state `.theme-btn.active` (ITER_01), `.toggle:checked` (the toggle fill, via `--toggle-on`), **plus three the draft missed: `.project-change-btn:hover`, `.marketplace-refresh-btn:hover` (border-color + color), and `.loading-spinner` (border-top-color)**. Under the new model **every one of those moves to `--secondary`**, and `--accent` is then consumed **only** by the new enabled-row state and the mark. Simply giving `--accent` the terracotta value without re-pointing *all* of those selectors would turn the controls — including the three missed ones — orange, the opposite of the intent. The full re-point list is in §05.

Net effect: you interact in teal; a row warming to terracotta is the one signal that "this is on." Terracotta is rare, so it reads as meaningful rather than decorative.

### Token model (extends ITER_01 §05)

The existing token contexts are unchanged in shape — `:root[data-theme="light"]`, `:root[data-theme="dark"]`, base `:root` + `@media (prefers-color-scheme: dark)`, and the `:root[data-context="vscode"]` bridge. This iteration **adds tokens** to each:

- Brand family: `--accent`, `--accent-hi`, `--accent-wash`, `--accent-glow`; `--secondary`, `--secondary-hi`, `--secondary-wash`, `--secondary-glow`; `--on-text` (text on a filled brand button).
- Depth: `--shadow-sm`, `--shadow-md`, `--shadow-lift`.
- Surface/border steps: `--surface-2`, `--border-strong`.
- Type: `--font-ui`, `--font-display`, `--font-mono` (so the HTML↔VSCode font split is a token override, see §03).
- `--accent` stops meaning "the one accent"; existing structural tokens (`--bg`, `--surface`, `--fg`, `--fg-muted`, `--border`, `--inherited-bg`, `--inherited-fg`) keep their names and just take new values.

> **Token preservation (audit — reconciled against the live `styles.css`):** the grep is now done. `--inherited-bg` and `--inherited-fg` are **still referenced** — `.plugin-row.inherited { background: var(--inherited-bg) }` and `.plugin-row.inherited .plugin-name { color: var(--inherited-fg) }` both survive in the live file, so the dimmed "inherited" treatment is **not** gone and both tokens are **kept** in every new block below. One token the original draft overlooked must also be accounted for: **`--toggle-on`** (declared `#22c55e` in every live block, consumed by `.toggle:checked`). The redesign re-points `.toggle:checked` to a `--secondary` gradient (§05), which **orphans `--toggle-on`** — so it is intentionally **dropped** from the new token blocks rather than re-declared. (`--error` appears only with an inline fallback — `var(--error, #c0392b)` in `.mp-install-btn--uninstall` — and is never declared as a token, so it needs no preservation.)

### HTML ↔ VSCode divergence (the ITER decision)

| Aspect | Standalone HTML | VSCode webview (HYBRID) |
|---|---|---|
| Neutrals (`--bg/--surface/--fg/--fg-muted/--border`) | Tidewater palette via `data-theme` | **Derived from `--vscode-*`** — panel matches the editor's theme + darkness |
| Brand (`--accent`, `--secondary`) | Tidewater values | **Hardcoded**, shade chosen per editor mode via `body.vscode-light` / `.vscode-dark`; high-contrast defers to `--vscode-textLink-foreground` |
| Atmosphere (`body::before/::after` glow + grain) | On | **Off** — a sidebar isn't a page |
| Fonts | Fraunces / Hanken Grotesk / JetBrains Mono (web) | **Editor fonts** via `--vscode-font-family` — no remote load (§03) |
| Depth | Full warm/cool shadows | Subtle, border-led (`--shadow-*` re-pointed to neutral rgba) |

> **Single canonical CSS preserved (ITER_05).** All of the above is expressed as overrides inside the one `html/styles.css` — chiefly an expanded `:root[data-context="vscode"]` block plus `body.vscode-light/.vscode-dark/.vscode-high-contrast` selectors. `vscode-extension/webview/styles.css` stays a generated copy; the sync target is unchanged. The only per-surface file difference is the web-font `<link>`, which lives in `index.html` only (§03).

---

## §03 · Tech Stack

**HTML version — new (CDN, standalone surface only):** Google Fonts — `Fraunces` (display), `Hanken Grotesk` (UI), `JetBrains Mono` (mono), loaded by a `<link>` in `index.html`'s `<head>`. No runtime/npm change; no Python change.

**VSCode webview — deliberately no remote fonts.** The default webview Content-Security-Policy blocks remote resources, and loading external fonts would break the native feel. `panel.html` adds **no** font `<link>`; the `--font-*` tokens fall back to the editor's fonts under `data-context="vscode"`. Bundling Fraunces as a packaged webview asset (so VSCode could share the serif display) is possible via `localResourceRoots` + a `font-src` CSP entry — **deferred** (adds `.vsix` weight; native fonts are the safer default).

No changes to Python, Node, or the build/sync tooling (ITER_05).

---

## §04 · Backend
> Unchanged. `server.py` already serves `styles.css` (ITER_04 §04) and needs no new route. Do **not** loosen the webview CSP in `extension.js` to admit remote fonts — see §03.

---

## §05 · Frontend

> All CSS below is in `html/styles.css` (canonical). Selectors not quoted in full re-theme automatically via their existing `var(--…)` references; the rules here are the deltas against the flat ITER_01/03/04 stylesheet. During the review pass, reconcile the component selectors against the live file (class names are those established in ITER_01–ITER_04 — `.toggle`, `.plugin-row`, `.mp-install-btn`, `.bulk-install-btn`, `.project-card`, `.mock-notice`, etc.).

### Token blocks (replace the ITER_01 §05 values)

```css
/* Foundation fonts (HTML); VSCode overrides these in the bridge */
:root {
  --font-ui:      "Hanken Grotesk", system-ui, sans-serif;
  --font-display: "Fraunces", Georgia, serif;
  --font-mono:    "JetBrains Mono", ui-monospace, monospace;
}

:root[data-theme="light"] {
  --bg:#F0F5F3; --surface:#FFFFFF; --surface-2:#F3F8F6;
  --fg:#143230; --fg-muted:#5F7E7A; --border:#DCEAE6; --border-strong:#C7DBD6;
  --inherited-fg:#7A938E; --inherited-bg:#E9F0EE;
  --accent:#CB6442; --accent-hi:#E27A50; --accent-wash:#FAEDE6; --accent-glow:rgba(203,100,66,.28);
  --secondary:#0E7E77; --secondary-hi:#14938C; --secondary-wash:#E2F1EF; --secondary-glow:rgba(14,126,119,.28);
  --on-text:#fff;
  --shadow-sm:0 1px 2px rgba(15,50,48,.06),0 1px 3px rgba(15,50,48,.05);
  --shadow-md:0 2px 4px rgba(15,50,48,.06),0 8px 24px rgba(15,50,48,.08);
  --shadow-lift:0 4px 10px rgba(15,50,48,.10),0 14px 40px rgba(15,50,48,.12);
}

:root[data-theme="dark"] {
  --bg:#0C1F1D; --surface:#122A27; --surface-2:#163230;
  --fg:#E7F1EE; --fg-muted:#7C9590; --border:#203F3A; --border-strong:#2D544D;
  --inherited-fg:#6E8782; --inherited-bg:#15302D;
  --accent:#E98A62; --accent-hi:#F4A37D; --accent-wash:rgba(233,138,98,.11); --accent-glow:rgba(233,138,98,.34);
  --secondary:#2FB3A8; --secondary-hi:#45C7BC; --secondary-wash:rgba(47,179,168,.12); --secondary-glow:rgba(47,179,168,.34);
  --on-text:#06201e;
  --shadow-sm:0 1px 2px rgba(0,0,0,.45);
  --shadow-md:0 2px 6px rgba(0,0,0,.45),0 10px 30px rgba(0,0,0,.5);
  --shadow-lift:0 6px 16px rgba(0,0,0,.55),0 18px 50px rgba(0,0,0,.6);
}

/* Base :root (Follow System, light) mirrors [data-theme="light"];
   @media (prefers-color-scheme: dark) :root:not([data-theme]) mirrors [data-theme="dark"]. */
```

### VSCode hybrid bridge (replaces the ITER_01 bridge)

```css
:root[data-context="vscode"] {
  /* neutrals follow the editor */
  --bg:        var(--vscode-editor-background);
  --surface:   var(--vscode-sideBar-background, var(--vscode-editor-background));
  --surface-2: var(--vscode-editorWidget-background, var(--vscode-sideBar-background));
  --fg:        var(--vscode-editor-foreground);
  --fg-muted:  var(--vscode-descriptionForeground);
  --border:        var(--vscode-panel-border, #8884);
  --border-strong: var(--vscode-contrastBorder, var(--vscode-panel-border, #8886));
  --inherited-fg:  var(--vscode-disabledForeground, var(--vscode-descriptionForeground));
  --inherited-bg:  var(--vscode-input-background, var(--vscode-sideBar-background));

  /* brand hardcoded — default = dark-editor shades */
  --accent:#E98A62; --accent-hi:#F4A37D; --accent-wash:rgba(233,138,98,.12); --accent-glow:rgba(233,138,98,.30);
  --secondary:#2FB3A8; --secondary-hi:#45C7BC; --secondary-wash:rgba(47,179,168,.14); --secondary-glow:rgba(47,179,168,.30);
  --on-text:#06201e;

  /* native fonts — no remote load (CSP) */
  --font-ui:      var(--vscode-font-family);
  --font-display: var(--vscode-font-family);
  --font-mono:    var(--vscode-editor-font-family, monospace);

  /* subtle, border-led depth */
  --shadow-sm:0 1px 2px rgba(0,0,0,.25);
  --shadow-md:0 2px 8px rgba(0,0,0,.28);
  --shadow-lift:0 6px 18px rgba(0,0,0,.32);
}

/* light editors → use the darker (light-mode) brand shades for contrast */
body.vscode-light {
  --accent:#CB6442; --accent-hi:#E27A50; --accent-wash:rgba(203,100,66,.12); --accent-glow:rgba(203,100,66,.28);
  --secondary:#0E7E77; --secondary-hi:#14938C; --secondary-wash:rgba(14,126,119,.12); --secondary-glow:rgba(14,126,119,.28);
  --on-text:#fff;
}

/* high-contrast themes → defer to the theme's own accent, drop tints/glows */
body.vscode-high-contrast {
  --secondary: var(--vscode-textLink-foreground);
  --secondary-hi: var(--vscode-textLink-activeForeground, var(--vscode-textLink-foreground));
  --accent: var(--vscode-textLink-foreground);
  --secondary-wash: transparent; --secondary-glow: transparent;
  --accent-wash: transparent;    --accent-glow: transparent;
}

/* no ambient glow/grain in the sidebar */
:root[data-context="vscode"] body::before,
:root[data-context="vscode"] body::after { display:none; }
```

### Component deltas

> **Reconciliation checklist — RESOLVED 2026-06-06 against the live `styles.css`.** All four items confirmed; the selectors in this section are updated to match the live file:
> 1. **Enable toggle** — class is **`.toggle`** (a checkbox styled with `appearance:none` + `:checked` + `:disabled`, so the checkbox assumption holds and `:has()` is valid). The established selector is the bare `.toggle` / `.toggle:checked`, **not** the over-specific `input[type="checkbox"].toggle` — the fill and `:has()` rules below use `.toggle:checked`.
> 2. **Row container** — confirmed **`.plugin-row`**. It currently has **no `position`**, so the `::before` edge requires adding `position: relative` (in the code below). Note `.plugin-row.inherited` is **still present** in the live file.
> 3. **Marketplace badge** — confirmed **`.marketplace-badge`** (distinct from `.version-badge`, `.not-installed-tag`, and `.mp-keyword`).
> 4. **Accent consumers** — grep complete; the full list incl. the three the draft missed is in §02 and re-pointed below. `--inherited-bg`/`--inherited-fg` still referenced (kept); `--toggle-on` orphaned by the new toggle fill (dropped).

- **Typography** — `body { font-family: var(--font-ui); }`; title/project-name/install-title `→ var(--font-display)`; paths/badges/version `→ var(--font-mono)`.
- **Atmosphere (HTML only)** — `body::before` = two faint radial gradients (teal at one corner, terracotta at the other, using `--secondary-wash`/`--accent-wash`); `body::after` = low-opacity SVG `feTurbulence` grain. Both disabled in the VSCode bridge above.
- **Controls → teal.** Re-point **all current `var(--accent)` consumers** to `--secondary`: `.skills-toggle-btn` (ITER_02); `.mp-install-btn` + `:hover` (ITER_04); `.bulk-install-btn` + `:hover` (ITER_04); the ThemeToggle active state `.theme-btn.active` (ITER_01); `.project-change-btn:hover`; `.marketplace-refresh-btn:hover` (border-color **and** color); `.loading-spinner` (border-top-color); and the toggle's checked fill. For the install buttons' filled `:hover`, set text to `color: var(--on-text)` (not hardcoded `#fff`) so the bright dark-mode teal stays legible. Toggle (replaces the live `.toggle:checked { background: var(--toggle-on) }` rule — which orphans `--toggle-on`):
  ```css
  .toggle:checked {
    background: linear-gradient(140deg, var(--secondary-hi), var(--secondary));
    box-shadow: 0 0 0 4px var(--secondary-glow);
  }
  ```
- **Enabled row → terracotta**, driven by `:has()` so **no JS adds a class** (keys off the toggle's `:checked`; survives the ITER_14 optimistic-update/revert for free). Confirm the row + toggle selectors from the checklist, then:
  ```css
  .plugin-row { position: relative; }   /* live .plugin-row has no position; required for ::before */
  .plugin-row:has(.toggle:checked) {
    background: linear-gradient(100deg, var(--accent-wash), var(--surface) 60%);
  }
  .plugin-row:has(.toggle:checked)::before {
    content:""; position:absolute; left:0; top:0; bottom:0; width:3px;
    background: linear-gradient(var(--accent-hi), var(--accent));
  }
  ```
  > The row needs `position: relative` for the `::before` edge. `:has()` is the only modern-baseline feature this iteration relies on — fine for a developer tool, but note it as the one compatibility assumption.
- **Logo mark (new element).** The current header has no mark (ITER_01: title + path + picker + theme toggle). Add a **static** `.mark` element to the header in both `index.html` and `panel.html` (markup only, no JS); it uses `--accent`. This is the one new DOM node in the iteration.
- **Metadata → teal.** Marketplace badge (confirm class), section counts, project-card left edge, project label all read `--secondary` / `--secondary-wash`.
- **Depth.** `.project-card`, `.plugin-row`, install panel: rounded radii (14–16px), `box-shadow: var(--shadow-sm/md)`; row hover `transform: translateY(-2px); box-shadow: var(--shadow-lift)`.
- **Motion.** `@keyframes rise` (opacity + 14px translate) on header/card/rows with a small staggered `animation-delay`; disclosures keep the ITER_05 expand/collapse. Guard:
  ```css
  @media (prefers-reduced-motion: reduce) {
    *, *::before, *::after { animation: none !important; transition: none !important; }
  }
  ```
- **`.mock-notice`** (ITER_03) — retint to the teal/terracotta neutrals; keep its `data-theme` / `data-context` triad.

---

## Deferred

- **Bundle Fraunces (+UI/mono) as packaged webview font assets** so VSCode shares the serif display — needs `localResourceRoots` + a `font-src` CSP entry; deferred for `.vsix` weight (§03).
- **Brand-contrast QA across popular VSCode themes** (Dark+, Light+, Solarized Light/Dark, and at least one high-contrast) — verify teal/terracotta legibility under the hybrid bridge. Recommended as a smoke-test extension to ITER_11.
- **Logo mark refresh** — the mark is a generic glyph today; a dedicated branding pass is out of scope.
- **Manual light/dark override inside VSCode** — by design not offered; the panel follows the editor. Not deferred, intentional.
