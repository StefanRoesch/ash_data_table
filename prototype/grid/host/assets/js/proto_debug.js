// THROWAWAY PROTOTYPE (#11). Fills the debug strip: what the hook reports,
// the size of the last WebSocket frame received, and the server's last handle
// time and process memory (fetched, so they do not travel in LiveView diffs).
export function installProtoDebug(liveSocket) {
  const state = {focused: null, editing: null, event: null, bytes: 0, counts: {}, stats: {}}
  let timer = null

  const render = () => {
    const out = document.getElementById("proto-debug-client")
    if (!out) return
    const s = state.stats
    const last = s.last || {}
    const rows = document.querySelectorAll("#g > table > tbody > tr[data-pk]").length
    out.textContent =
      `rendered rows=${rows} | focused=${state.focused || "-"} | editing=${state.editing || "-"}` +
      ` | last event=${state.event || "-"} | server: ${last.event || "-"} handle ${last.handle_us ?? "-"}us` +
      ` render ${last.render_us ?? "-"}us | last frame=${state.bytes} B` +
      ` | LV memory=${s.memory ? Math.round(s.memory / 1024) + " KB" : "-"}` +
      ` | hook updated()=${state.counts.updated ?? 0} observer=${state.counts.observed ?? 0} focus restored=${state.counts.restored ?? 0}`
  }

  const fetchStats = () => {
    clearTimeout(timer)
    timer = setTimeout(async () => {
      const strip = document.getElementById("proto-debug")
      if (!strip) return
      try {
        const res = await fetch(`/prototype/grid/stats?pid=${encodeURIComponent(strip.dataset.pid)}`)
        state.stats = await res.json()
        render()
      } catch (_e) {}
    }, 150)
  }

  window.addEventListener("ash-table:debug", ({detail}) => {
    state.focused = detail.focused
    state.editing = detail.editing
    state.event = `${detail.grid}:${detail.event}`
    if (detail.grid === "g") state.counts = detail.counts
    render()
  })

  // The raw frame, before Phoenix decodes it.
  liveSocket.socket.onOpen(() => {
    const conn = liveSocket.socket.conn
    if (!conn || !conn.addEventListener) return
    conn.addEventListener("message", e => {
      if (typeof e.data !== "string" || e.data.includes('"phoenix"')) return // heartbeat
      state.bytes = new TextEncoder().encode(e.data).length
      render()
      fetchStats()
    })
  })
}
