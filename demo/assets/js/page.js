// What the root layout's header does in the browser: the theme toggle,
// the theme select and the two switchers (actor, language). It is here and not in the
// layout, as the page's Content-Security-Policy runs no inline script
// and no inline event handler (`script-src 'self'`, DemoWeb.Router).
//
// app.js is loaded with `defer`, so the stored theme is put on the page
// once the document is parsed: a page asked for in a theme other than
// the system's may show the system's for a moment as it loads.

// The theme select (`Layouts.theme_select`) shows the theme in use,
// whichever of the two chose it.
const showTheme = theme => {
  const select = document.querySelector("select[data-theme-select]")
  if (select instanceof HTMLSelectElement) select.value = theme
}

const setTheme = theme => {
  if (theme === "system") {
    localStorage.removeItem("phx:theme")
    document.documentElement.removeAttribute("data-theme")
  } else {
    localStorage.setItem("phx:theme", theme)
    document.documentElement.setAttribute("data-theme", theme)
  }
  showTheme(theme)
}

if (document.documentElement.hasAttribute("data-theme")) {
  showTheme(document.documentElement.getAttribute("data-theme"))
} else {
  setTheme(localStorage.getItem("phx:theme") || "system")
}
window.addEventListener("storage", e => e.key === "phx:theme" && setTheme(e.newValue || "system"))
window.addEventListener("phx:set-theme", e => setTheme(e.target.dataset.phxTheme))

// The switchers (`Layouts.actor_switcher`, `Layouts.locale_switcher`): the
// root layout is not rendered again on live navigation, so a form takes
// the current address as it is submitted (`data-return-to-current`), and
// a choice in its list submits it (`data-submit-on-change`).
document.addEventListener("submit", e => {
  const form = e.target
  if (form instanceof HTMLFormElement && form.hasAttribute("data-return-to-current")) {
    form.elements.namedItem("return_to").value = location.pathname + location.search
  }
})
document.addEventListener("change", e => {
  const select = e.target
  if (select instanceof HTMLSelectElement && select.hasAttribute("data-submit-on-change")) {
    select.form.requestSubmit()
  }
  if (select instanceof HTMLSelectElement && select.hasAttribute("data-theme-select")) {
    setTheme(select.value)
  }
})
