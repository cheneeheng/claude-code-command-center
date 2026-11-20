// ---- static DOM wiring + bootstrap (loaded last) ----

// ---- project card ----
document.getElementById("project-change-btn").addEventListener("click", () => {
  const expand = document.getElementById("project-picker-expand");
  const btn = document.getElementById("project-change-btn");
  const isOpen = expand.classList.toggle("is-open");
  btn.innerHTML = isOpen ? "Change &#9650;" : "Change &#9660;";
});

document.getElementById("project-apply-btn").addEventListener("click", async () => {
  const input = document.getElementById("project-path-input");
  const applyBtn = document.getElementById("project-apply-btn");
  const errEl = document.getElementById("project-picker-error");
  const newPath = input.value.trim();

  input.disabled = true;
  applyBtn.disabled = true;
  errEl.classList.remove("visible");

  try {
    const res = await fetch("/api/set-project", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ path: newPath }),
    });
    const data = await res.json();
    if (data.ok) {
      document.getElementById("project-picker-expand").classList.remove("is-open");
      document.getElementById("project-change-btn").innerHTML = "Change &#9660;";
      await fetchPlugins();
      await fetchMarketplace();
    } else {
      errEl.textContent = data.error || "Unknown error";
      errEl.classList.add("visible");
    }
  } catch (err) {
    errEl.textContent = err.message;
    errEl.classList.add("visible");
  } finally {
    input.disabled = false;
    applyBtn.disabled = false;
  }
});

document.getElementById("btn-enable-all").addEventListener("click", () => bulkToggle(true));
document.getElementById("btn-disable-all").addEventListener("click", () => bulkToggle(false));

document.getElementById("btn-kill-server").addEventListener("click", async () => {
  const btn = document.getElementById("btn-kill-server");
  btn.disabled = true;
  btn.textContent = "Stopping...";
  try {
    await fetch("/api/shutdown", { method: "POST" });
  } catch (_) {
    // connection drop on shutdown is expected
  }
  document.body.innerHTML =
    '<p style="padding:1.25rem;font-family:sans-serif;color:#e05c5c">Server stopped.</p>';
});

fetchPlugins();
fetchMarketplace();
connectEventStream();
