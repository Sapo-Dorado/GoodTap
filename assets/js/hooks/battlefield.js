// Battlefield hook: handles right-click context menu and drag-drop for cards on the battlefield
const Battlefield = {
  mounted() {
    const onContextmenu = (e) => {
      const card = e.target.closest("[data-draggable]");
      if (!card) return;
      e.preventDefault();

      const zone = card.dataset.zone || "battlefield";
      const owner = card.dataset.owner;

      // Only show context menu for own cards
      this.pushEvent("context_menu", {
        instance_id: card.dataset.instanceId,
        zone: zone,
        owner: owner,
        x: e.clientX,
        y: e.clientY
      });
    };

    const onContextmenuBattlefield = (e) => {
      const card = e.target.closest("[data-draggable]");
      if (card) return; // Handled above

      e.preventDefault();

      // Right-click on empty battlefield -> token search
      const rect = this.el.getBoundingClientRect();
      const relX = Math.round(((e.clientX - rect.left) / rect.width) * 100) / 100;
      const relY = Math.round(((e.clientY - rect.top) / rect.height) * 100) / 100;

      this.pushEvent("show_token_search", { x: relX, y: relY });
    };

    document.addEventListener("contextmenu", onContextmenu);
    this.el.addEventListener("contextmenu", onContextmenuBattlefield);

    this._cleanup = () => {
      document.removeEventListener("contextmenu", onContextmenu);
      this.el.removeEventListener("contextmenu", onContextmenuBattlefield);
    };
  },

  destroyed() {
    if (this._cleanup) this._cleanup();
  }
};

export default Battlefield;
