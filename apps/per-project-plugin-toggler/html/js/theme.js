// ---- theme ----
function setTheme(t) {
  if (t) document.documentElement.setAttribute("data-theme", t);
  else document.documentElement.removeAttribute("data-theme");
  localStorage.setItem("skills-theme", t ?? "");
  document.querySelectorAll(".theme-btn").forEach((b) => {
    b.classList.toggle("active", b.dataset.theme === t);
  });
}
(function initTheme() {
  const saved = localStorage.getItem("skills-theme");
  if (saved !== null) setTheme(saved);
})();
document.querySelectorAll(".theme-btn").forEach((b) => {
  b.addEventListener("click", () => setTheme(b.dataset.theme));
});
