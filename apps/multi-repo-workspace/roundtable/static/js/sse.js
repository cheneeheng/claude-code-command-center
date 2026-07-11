// Thin EventSource wrapper: auto-reconnect off (a turn/run is finite).
// All SSE endpoints are GET with path params only, so EventSource's
// GET-only/no-headers limitation never bites (addressed by design).
window.RT = window.RT || {};

RT.sse = {
  open(url, { onItem, onEnd, onError }) {
    const es = new EventSource(url);
    es.onmessage = (ev) => {
      try { onItem(JSON.parse(ev.data)); } catch { onItem({ kind: "line", text: ev.data }); }
    };
    es.addEventListener("end", (ev) => {
      es.close();
      let status = null;
      try { status = JSON.parse(ev.data).status; } catch { /* no status payload */ }
      if (onEnd) onEnd(status);
    });
    es.onerror = () => {
      es.close(); // finite streams: never auto-reconnect
      if (onError) onError();
    };
    return es;
  },
};
