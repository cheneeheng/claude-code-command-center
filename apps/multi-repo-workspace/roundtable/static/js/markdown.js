// The single markdown entry point: render(mdText) -> sanitized HTML.
// Every markdown surface goes through here — no second renderer, ever.
window.RT = window.RT || {};

RT.md = {
  render(mdText) {
    const raw = marked.parse(mdText || "", { gfm: true, async: false });
    return DOMPurify.sanitize(raw); // default allowlist
  },
  into(el, mdText) {
    el.innerHTML = this.render(mdText);
  },
};
