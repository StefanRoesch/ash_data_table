// The grid's hook: the message of a failed cell.
//
// These methods are part of the one hook object that grid/index.js
// puts together, and share its state through `this`.

export default {
  onPointer(cell) {
    if (cell === this.pointed) return
    this.pointed = cell
    this.showMessage()
    this.pointedWhole(cell)
  },

  // The message of a failed cell is a popover: shown under the cell
  // while the cell has the pointer or focus, without making the row
  // higher. The pointer wins, as it says where the person is looking.
  showMessage() {
    const failed = cell => cell && cell.isConnected && cell.hasAttribute("aria-invalid") ? cell : null
    const cell = failed(this.pointed) || failed(this.cellOf(document.activeElement))
    const message = cell && document.getElementById(cell.getAttribute("aria-describedby"))
    if (this.message && this.message !== message) {
      if (this.message.isConnected && this.message.matches(":popover-open")) this.message.hidePopover()
      this.message = null
    }
    if (!message || !message.showPopover) return
    if (!message.matches(":popover-open")) message.showPopover()
    const box = cell.getBoundingClientRect()
    message.style.top = `${box.bottom + 2}px`
    message.style.left = `${Math.max(0, box.left)}px`
    this.message = message
  },
}
