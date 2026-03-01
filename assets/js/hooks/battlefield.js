// Clamp context menu position so it stays within viewport
function clampMenuPos(x, y) {
  const menuW = 200;
  const menuH = 280;
  const vw = window.innerWidth;
  const vh = window.innerHeight;
  return {
    x: Math.min(x, vw - menuW - 8),
    y: Math.min(y, vh - menuH - 8)
  };
}

// Battlefield hook: handles right-click context menu and drag-drop for cards on the battlefield
const Battlefield = {
  mounted() {
    const onContextmenu = (e) => {
      const card = e.target.closest("[data-draggable]");
      if (!card) return;
      e.preventDefault();

      const zone = card.dataset.zone || "battlefield";
      const owner = card.dataset.owner;
      const pos = clampMenuPos(e.clientX, e.clientY);

      // Only show context menu for own cards
      this.pushEvent("context_menu", {
        instance_id: card.dataset.instanceId,
        zone: zone,
        owner: owner,
        x: pos.x,
        y: pos.y
      });
    };

    const onContextmenuBattlefield = (e) => {
      const card = e.target.closest("[data-draggable]");
      if (card) return; // Handled above

      e.preventDefault();

      // Right-click on a pile zone (deck/graveyard/exile)
      const pile = e.target.closest("[data-pile-zone]");
      if (pile) {
        const pos = clampMenuPos(e.clientX, e.clientY);
        this.pushEvent("context_menu", {
          instance_id: null,
          zone: pile.dataset.pileZone,
          owner: null,
          x: pos.x,
          y: pos.y
        });
        return;
      }

      // Right-click on empty battlefield -> clear selection + token search
      this.pushEvent("clear_selection", {});
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
