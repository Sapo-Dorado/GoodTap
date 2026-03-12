// SideboardButton hook: batches rapid clicks so no clicks are lost.
//
// Usage on a button:
//   phx-hook="SideboardButton"
//   data-id="deck_card_id"
//   data-to-board="sideboard" (or "main")
//
// Accumulates clicks for 150ms then sends a single sideboard_move event
// with a count param. The server caps the move at the available quantity.

const SideboardButton = {
  mounted() {
    this.pending = 0;
    this.timer = null;

    this.el.addEventListener("click", (e) => {
      e.preventDefault();
      this.pending += 1;

      clearTimeout(this.timer);
      this.timer = setTimeout(() => {
        this.pushEvent("sideboard_move", {
          id: this.el.dataset.id,
          to_board: this.el.dataset.toBoard,
          count: String(this.pending)
        });
        this.pending = 0;
      }, 150);
    });
  },

  destroyed() {
    clearTimeout(this.timer);
  }
};

export default SideboardButton;
