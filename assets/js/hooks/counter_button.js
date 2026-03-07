// CounterButton hook: accumulates rapid clicks into a single batched event.
//
// Usage on a button:
//   phx-hook="CounterButton"
//   data-event="adjust_life"        (the phx event to push)
//   data-delta="1"                  (the per-click delta, positive or negative)
//   data-params='{"key": "val"}'    (optional extra params to merge)
//
// Each click increments an internal counter. After 150ms of inactivity the
// accumulated delta is pushed as a single event, preventing the server from
// receiving partial results from fast-clicking.

const CounterButton = {
  mounted() {
    this.pending = 0
    this.timer = null

    this.el.addEventListener("click", (e) => {
      e.preventDefault()
      const delta = parseInt(this.el.dataset.delta || "1", 10)
      this.pending += delta

      clearTimeout(this.timer)
      this.timer = setTimeout(() => {
        const event = this.el.dataset.event
        let params
        try {
          params = JSON.parse(this.el.dataset.params || "{}")
        } catch (_) {
          params = {}
        }
        params.delta = String(this.pending)
        this.pushEvent(event, params)
        this.pending = 0
      }, 150)
    })
  },

  destroyed() {
    clearTimeout(this.timer)
  }
}

export default CounterButton
