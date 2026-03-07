const DeckCardMenu = {
  mounted() {
    this._handler = (e) => {
      const card = e.target.closest("[data-deck-card-id]")
      if (!card) return
      e.preventDefault()
      this.pushEvent("deck_card_menu", {
        id: card.dataset.deckCardId,
        board: card.dataset.deckCardBoard,
      })
    }
    this.el.addEventListener("contextmenu", this._handler)
  },
  destroyed() {
    this.el.removeEventListener("contextmenu", this._handler)
  },
}

export default DeckCardMenu
