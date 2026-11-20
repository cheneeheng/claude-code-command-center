// ---- SSE event stream (ITER_06) ----
function setLiveIndicator(state) {
  const el = document.getElementById("live-indicator");
  el.className = "live-dot" + (state !== "off" ? ` ${state}` : "");
}

function connectEventStream() {
  const es = new EventSource("/api/events");

  es.onopen = () => setLiveIndicator("connected");

  es.onmessage = (event) => {
    if (event.data === "refresh") {
      // While a streamed install/uninstall is finishing, defer the refresh so the
      // result log stays visible for its 3s window. _streamOp re-fetches plugins +
      // marketplace itself once that window closes.
      if (operationInProgress) return;
      fetchPlugins();
      if (installPanelOpen) fetchMarketplace();
    }
  };

  es.onerror = () => {
    setLiveIndicator("reconnecting");
    es.close();
    setTimeout(connectEventStream, 3000);
  };
}
