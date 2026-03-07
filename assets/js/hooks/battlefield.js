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

// Show a red target reticle on a card for 5 seconds
function showTargetReticle(instanceId) {
  // Try own card first, then opponent card
  const el = document.getElementById(`card-${instanceId}`) ||
             document.getElementById(`opp-card-${instanceId}`);
  if (!el) return;

  const existing = el.querySelector(".target-reticle");
  if (existing) {
    clearTimeout(existing._timer);
    existing.remove();
  }

  const reticle = document.createElement("div");
  reticle.className = "target-reticle";
  reticle.style.cssText = `
    position: absolute; inset: 0; z-index: 20; pointer-events: none;
    display: flex; align-items: center; justify-content: center;
  `;
  reticle.innerHTML = `
    <svg viewBox="0 0 100 100" style="width: 60%; height: 60%; opacity: 0.9;">
      <circle cx="50" cy="50" r="40" fill="none" stroke="#ef4444" stroke-width="5"/>
      <line x1="50" y1="5"  x2="50" y2="25" stroke="#ef4444" stroke-width="5"/>
      <line x1="50" y1="75" x2="50" y2="95" stroke="#ef4444" stroke-width="5"/>
      <line x1="5"  y1="50" x2="25" y2="50" stroke="#ef4444" stroke-width="5"/>
      <line x1="75" y1="50" x2="95" y2="50" stroke="#ef4444" stroke-width="5"/>
    </svg>
  `;

  el.style.position = "absolute"; // ensure parent is positioned
  el.appendChild(reticle);

  reticle._timer = setTimeout(() => reticle.remove(), 5000);
}

// Battlefield hook: handles right-click context menu and target reticle
const Battlefield = {
  mounted() {
    const onContextmenu = (e) => {
      const card = e.target.closest("[data-draggable], [data-hoverable]");
      if (!card) return;
      e.preventDefault();

      const zone = card.dataset.zone || "battlefield";
      const owner = card.dataset.owner;
      const pos = clampMenuPos(e.clientX, e.clientY);

      this.pushEvent("context_menu", {
        instance_id: card.dataset.instanceId,
        zone: zone,
        owner: owner,
        x: pos.x,
        y: pos.y
      });
    };

    const onContextmenuBattlefield = (e) => {
      const card = e.target.closest("[data-draggable], [data-hoverable]");
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

    this.handleEvent("target_card", ({ instance_id }) => {
      showTargetReticle(instance_id);
    });

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
