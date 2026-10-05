defmodule AshTableProto.Hook do
  @moduledoc """
  THROWAWAY PROTOTYPE (#11). The ONE JS hook of the grid, as a colocated hook
  shipped from this dependency.

  The `<script>` is extracted at compile time into
  `_build/$MIX_ENV/phoenix-colocated/ash_table_proto/` and exported from that
  folder's `index.js` under the key `"AshTableProto.Hook.Grid"`. Other modules
  of this library refer to it by that full name (the `.Grid` shorthand only
  works inside this module).

  `script/1` is never rendered; it only exists to carry the script.
  """
  use Phoenix.Component

  def script(assigns) do
    ~H"""
    <script :type={Phoenix.LiveView.ColocatedHook} name=".Grid">
      // Keyboard, focus and edit state for one grid (a nested grid gets its own
      // instance). Nothing here talks to the server except: save, clear, toggle, sort.
      const PRINTABLE = e => e.key.length === 1 && !e.ctrlKey && !e.metaKey && !e.altKey

      export default {
        mounted() {
          const el = this.el
          el._ashHook = this
          this.editing = null
          this.pos = {r: 1, c: 0}
          this.col = 0
          this.counts = {updated: 0, observed: 0, restored: 0}
          el.addEventListener("keydown", e => this.owns(e.target) && this.onKeydown(e))
          el.addEventListener("focusin", e => this.owns(e.target) && this.onFocusin(e))
          el.addEventListener("focusout", e => this.owns(e.target) && this.onFocusout(e))
          el.addEventListener("click", e => this.owns(e.target) && this.onClick(e))
          el.addEventListener("dblclick", e => this.owns(e.target) && this.onDblclick(e))
          el.addEventListener("change", e => this.owns(e.target) && this.onChange(e))
          // Safety net next to updated(): a patch that does not include this
          // element (a row LiveComponent, a nested grid) never calls updated().
          if (!window.ashTableNoObserver) {
            this.observer = new MutationObserver(() => { this.counts.observed++; this.sync() })
            this.observer.observe(el, {subtree: true, childList: true, attributes: true, attributeFilter: ["tabindex"]})
          }
          this.sync()
          this.debug("mounted")
        },

        updated() { this.counts.updated++; this.sync() },

        destroyed() { this.observer && this.observer.disconnect() },

        // ---- structure -------------------------------------------------------

        top() {
          let top = this.el
          for (let p; (p = top.parentElement && top.parentElement.closest("[data-grid]"));) top = p
          return top
        },
        // State shared by a top-level grid and all grids nested in it: there is
        // exactly ONE active cell (tabindex=0) in the whole tree.
        state() {
          const top = this.top()
          return top._ash || (top._ash = {activeId: null, hadFocus: false, owner: null})
        },
        owns(node) { return !!node.closest && node.closest("[data-grid]") === this.el },
        table() { return this.el.querySelector(":scope > table") },
        rows() { return this.table().rows },
        cellOf(node) { return node.closest("td,th") },
        meta(cell) {
          const th = this.rows()[0].cells[cell.cellIndex]
          return {ci: th.dataset.ci, name: th.dataset.col, type: th.dataset.type, editable: th.dataset.edit === "true"}
        },
        pk(cell) { return cell.parentElement.dataset.pk },
        shown(cell) {
          const v = cell.querySelector("[data-v]")
          return v ? v.textContent : cell.textContent
        },

        // ---- the active cell and focus ---------------------------------------

        setActive(cell) {
          const st = this.state()
          const prev = st.activeId && document.getElementById(st.activeId)
          if (prev && prev !== cell && prev.tabIndex !== -1) prev.tabIndex = -1
          st.activeId = cell.id
          st.owner = this
          this.pos = {r: cell.parentElement.rowIndex, c: cell.cellIndex}
          const want = this.editing && this.editing.cell === cell ? -1 : 0
          if (cell.tabIndex !== want) cell.tabIndex = want
        },

        // Runs after every patch: the server renders every cell with
        // tabindex=-1, so the roving tabindex has to be put back, and focus has
        // to be put back when the focused element did not survive the patch.
        sync() {
          const top = this.top()
          const st = this.state()
          let cell = st.activeId && document.getElementById(st.activeId)
          if (cell && !top.contains(cell)) cell = null
          if (!cell) {
            const owner = st.owner && st.owner.el.isConnected ? st.owner : top._ashHook
            if (!owner) return
            cell = owner.cellAt(owner.pos.r, owner.pos.c)
            if (!cell) return
            owner.setActive(cell)
          }
          const editingHere = st.owner && st.owner.editing && st.owner.editing.cell === cell
          const want = editingHere ? -1 : 0
          if (cell.tabIndex !== want) cell.tabIndex = want
          if (st.hadFocus && !top.contains(document.activeElement)) {
            this.counts.restored++
            cell.focus({preventScroll: true})
            this.debug("focus-restored")
          }
        },

        cellAt(r, c) {
          const rows = this.rows()
          const row = rows[Math.max(0, Math.min(r, rows.length - 1))]
          return row && row.cells[Math.max(0, Math.min(c, row.cells.length - 1))]
        },

        move(r, c) {
          const cell = this.cellAt(r, c)
          if (cell) cell.focus()
        },

        onFocusin(e) {
          const cell = this.cellOf(e.target)
          const st = this.state()
          if (!cell) { st.hadFocus = false; return }
          st.hadFocus = true
          // the column vertical moves aim for; a detail cell spans all columns and keeps it
          if (!("detail" in cell.dataset)) this.col = cell.cellIndex
          this.setActive(cell)
          this.debug("focus")
        },

        onFocusout(e) {
          if (e.target.dataset && "editor" in e.target.dataset) return
          const st = this.state()
          const top = this.top()
          if (e.relatedTarget) {
            if (!top.contains(e.relatedTarget)) st.hadFocus = false
          } else {
            // No new target: either the person clicked on nothing (then focus is
            // really gone) or a patch removed the focused element (then sync()
            // puts it back).
            const target = e.target
            setTimeout(() => {
              if (target.isConnected && !top.contains(document.activeElement)) st.hadFocus = false
            }, 0)
          }
        },

        // ---- keyboard --------------------------------------------------------

        onKeydown(e) {
          if (this.editing) return
          const cell = this.cellOf(e.target)
          if (!cell) return
          const rows = this.rows()
          const r = cell.parentElement.rowIndex
          const c = cell.cellIndex
          const lastC = cell.parentElement.cells.length - 1
          const ctrl = e.ctrlKey || e.metaKey
          const isX = "x" in cell.dataset
          let handled = true
          switch (e.key) {
            case "ArrowRight":
              if (isX && !this.isOpen(cell)) this.toggle(cell)
              else { this.col = Math.min(c + 1, lastC); this.move(r, c + 1) }
              break
            case "ArrowLeft":
              if (isX && this.isOpen(cell)) this.toggle(cell)
              else { this.col = Math.max(c - 1, 0); this.move(r, c - 1) }
              break
            case "ArrowDown": this.move(r + 1, this.col); break
            case "ArrowUp": this.move(r - 1, this.col); break
            case "PageDown": this.move(r + this.pageRows(cell), this.col); break
            case "PageUp": this.move(r - this.pageRows(cell), this.col); break
            case "Home":
              this.col = 0
              this.move(ctrl ? Math.min(1, rows.length - 1) : r, 0)
              break
            case "End": {
              const row = ctrl ? rows[rows.length - 1] : cell.parentElement
              this.col = row.cells.length - 1
              this.move(row.rowIndex, this.col)
              break
            }
            case "Enter":
            case "F2": this.activate(cell); break
            case "Escape":
              if (cell.hasAttribute("aria-invalid")) this.clear(cell)
              else {
                // inside a nested grid: back to the cell of the parent grid that holds it
                const parentCell = this.el.parentElement && this.el.parentElement.closest("td")
                if (parentCell) parentCell.focus()
                else handled = false
              }
              break
            case " ": break // reserved for row selection; swallowed so the page does not scroll
            default:
              // Typing starts editing: the editor is focused empty during keydown
              // and the browser then delivers the character to it. (A select
              // would take the character as type-ahead and save, so it only opens.)
              handled = false
              if (PRINTABLE(e) && cell.tagName === "TD" && this.canEdit(cell)) {
                const type = this.meta(cell).type
                this.startEdit(cell, type !== "enum")
                handled = type === "enum"
              }
          }
          if (handled) e.preventDefault()
        },

        pageRows(cell) {
          return Math.max(1, Math.floor(window.innerHeight / (cell.offsetHeight || 24)) - 2)
        },

        canEdit(cell) {
          if ("x" in cell.dataset || "detail" in cell.dataset) return false
          const m = this.meta(cell)
          return m.editable && m.type !== "boolean"
        },

        isOpen(cell) {
          const b = cell.querySelector("button")
          return !!b && b.getAttribute("aria-expanded") === "true"
        },

        // Enter / F2 / double click
        activate(cell) {
          if (cell.tagName === "TH") {
            if (cell.dataset.col) this.sort(cell)
          } else if ("x" in cell.dataset) {
            this.toggle(cell)
          } else if ("detail" in cell.dataset) {
            const nested = cell.querySelector("[data-grid]")
            if (nested && nested._ashHook) nested._ashHook.move(nested._ashHook.pos.r, nested._ashHook.pos.c)
          } else {
            const m = this.meta(cell)
            if (!m.editable) return
            if (m.type === "boolean") cell.querySelector("input").click()
            else this.startEdit(cell)
          }
        },

        onClick(e) {
          if (e.target.dataset && "editor" in e.target.dataset) return
          const cell = this.cellOf(e.target)
          if (!cell) return
          this.col = cell.cellIndex
          if (cell.tagName === "TH" && cell.dataset.col) this.sort(cell)
          else if (e.target.closest("button") && "x" in cell.dataset) this.toggle(cell)
          // a click on a checkbox or a button focuses that control: keep focus on the cell
          if (document.activeElement !== cell && !(this.editing && this.editing.cell === cell)) cell.focus()
        },

        onDblclick(e) {
          const cell = this.cellOf(e.target)
          if (cell && cell.tagName === "TD" && !this.editing && this.canEdit(cell)) this.startEdit(cell)
        },

        // checkbox: saves on toggle
        onChange(e) {
          if (e.target.type !== "checkbox") return
          const cell = this.cellOf(e.target)
          this.save(cell, this.meta(cell), String(e.target.checked), null)
        },

        // ---- server events ---------------------------------------------------

        sort(cell) {
          this.debug("sort")
          this.pushEventTo(this.el, "sort", {col: cell.dataset.col}, () => this.debug("sort-reply"))
        },

        toggle(cell) {
          this.debug("toggle")
          this.pushEventTo(cell, "toggle", {row: this.pk(cell)})
        },

        clear(cell) {
          this.debug("clear")
          this.pushEventTo(cell, "clear", {row: this.pk(cell), col: this.meta(cell).name})
        },

        // `restore` puts the pre-edit content back if the server accepted the
        // value but no patch touched the cell (the saved value renders the same).
        save(cell, m, value, restore) {
          cell.setAttribute("aria-busy", "true") // save in progress; the patch removes it
          this.debug("save")
          this.pushEventTo(cell, "save", {row: this.pk(cell), col: m.name, value}, () => {
            if (cell.isConnected && cell.hasAttribute("aria-busy")) {
              cell.removeAttribute("aria-busy")
              if (restore) restore()
            }
            this.debug("save-reply")
          })
        },

        // ---- editing: state lives here, not on the server ----------------------

        startEdit(cell, typing) {
          const m = this.meta(cell)
          const tpl = this.el.querySelector(`:scope > [data-editors] > template[data-ci="${m.ci}"]`)
          if (!tpl) return
          const input = tpl.content.firstElementChild.cloneNode(true)
          const shown = this.shown(cell)
          // on an invalid cell `shown` is the rejected value and data-old the saved one
          const old = cell.dataset.old !== undefined ? cell.dataset.old : shown
          const saved = Array.from(cell.childNodes)
          // Freeze the cell: LiveView skips elements that carry phx-update="ignore"
          // in the DOM, so a patch arriving while typing cannot remove the editor.
          cell.setAttribute("phx-update", "ignore")
          cell.replaceChildren(input)
          input.value = typing ? "" : this.toEditor(m.type, shown)
          cell.tabIndex = -1
          this.editing = {cell, input, old, saved, m, done: false}
          input.addEventListener("keydown", e => {
            if (e.key === "Enter") { e.preventDefault(); this.finish(true, true) }
            else if (e.key === "Escape") { e.preventDefault(); this.finish(false, true) }
          })
          if (m.type === "enum") input.addEventListener("change", () => this.finish(true, true))
          input.addEventListener("blur", e => {
            // Focus is on its way somewhere else. If that is another cell, its
            // focusin says so; until then nothing may pull focus back here.
            this.state().hadFocus = false
            this.finish(true, false)
          })
          input.focus()
          if (!typing && input.select && m.type === "text") input.select()
          this.debug("edit-start")
        },

        toEditor(type, text) { return type === "datetime" ? text.replace(" ", "T") : text },
        fromEditor(type, value) { return type === "datetime" ? value.replace("T", " ") : value },

        finish(save, refocus) {
          const ed = this.editing
          if (!ed || ed.done) return
          ed.done = true
          this.editing = null
          const {cell, input, old, saved, m} = ed
          const text = this.fromEditor(m.type, input.value)
          const invalid = cell.hasAttribute("aria-invalid")
          const restore = () => cell.replaceChildren(...saved)
          cell.removeAttribute("phx-update")
          if (!save || text === old) {
            // cancelled or unchanged: nothing is saved; an invalid cell goes back to its saved value
            restore()
            if (invalid) this.clear(cell)
          } else {
            // optimistic: show what was typed until the server answers
            cell.replaceChildren(document.createTextNode(text))
            this.save(cell, m, input.value, restore)
          }
          if (refocus) { cell.tabIndex = 0; cell.focus() }
          this.debug(save ? "edit-commit" : "edit-cancel")
        },

        debug(event) {
          const st = this.state()
          const owner = st.owner
          window.dispatchEvent(new CustomEvent("ash-table:debug", {detail: {
            grid: this.el.id,
            event,
            focused: st.hadFocus ? st.activeId : null,
            active: st.activeId,
            editing: owner && owner.editing ? owner.editing.cell.id : null,
            counts: this.counts,
            t: performance.now()
          }}))
        }
      }
    </script>
    """
  end
end
