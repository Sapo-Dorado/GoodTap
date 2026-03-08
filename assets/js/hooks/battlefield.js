// Returns x clamped to viewport width, and y_from_bottom so menu opens upward from cursor.
function menuPos(x, y) {
  const menuW = 200;
  const vw = window.innerWidth;
  return {
    x: Math.min(x, vw - menuW - 8),
    y_from_bottom: window.innerHeight - y
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
      const pos = menuPos(e.clientX, e.clientY);

      this.pushEvent("context_menu", {
        instance_id: card.dataset.instanceId,
        zone: zone,
        owner: owner,
        x: pos.x,
        y_from_bottom: pos.y_from_bottom
      });
    };

    const onContextmenuBattlefield = (e) => {
      const card = e.target.closest("[data-draggable], [data-hoverable]");
      if (card) return; // Handled above

      e.preventDefault();

      // Right-click on a pile zone (deck/graveyard/exile)
      const pile = e.target.closest("[data-pile-zone]");
      if (pile) {
        const pos = menuPos(e.clientX, e.clientY);
        this.pushEvent("context_menu", {
          instance_id: null,
          zone: pile.dataset.pileZone,
          owner: null,
          x: pos.x,
          y_from_bottom: pos.y_from_bottom
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

    // After every LiveView patch, clamp the context menu to the viewport.
    // Uses rAF so layout is complete before measuring.
    // Also flips any submenus that would go off the right edge.
    this._menuObserver = new MutationObserver(() => {
      requestAnimationFrame(() => {
        const menu = document.getElementById("context-menu");
        if (!menu) return;
        const rect = menu.getBoundingClientRect();
        const pad = 8;
        if (rect.right > window.innerWidth - pad) {
          menu.style.left = Math.max(0, window.innerWidth - rect.width - pad) + "px";
        }
        if (rect.top < pad) {
          menu.style.bottom = Math.max(0, window.innerHeight - rect.height - pad) + "px";
        }

        // Wire up submenu show/hide with gap-crossing delay
        menu.querySelectorAll(".submenu-panel").forEach(sub => {
          const row = sub.parentElement;
          if (!row || row._submenuBound) return;
          row._submenuBound = true;
          let hideTimer = null;

          const show = () => {
            clearTimeout(hideTimer);
            sub.style.display = "block";
            // Flip to left if it overflows the right edge
            sub.style.left = "";
            sub.style.right = "";
            const subRect = sub.getBoundingClientRect();
            if (subRect.right > window.innerWidth - pad) {
              sub.style.left = "auto";
              sub.style.right = "100%";
            }
          };
          const hide = () => {
            hideTimer = setTimeout(() => { sub.style.display = "none"; }, 100);
          };

          row.addEventListener("mouseenter", show);
          row.addEventListener("mouseleave", hide);
          sub.addEventListener("mouseenter", () => clearTimeout(hideTimer));
          sub.addEventListener("mouseleave", hide);
        });
      });
    });
    this._menuObserver.observe(document.body, { childList: true, subtree: true });

    this._cleanup = () => {
      document.removeEventListener("contextmenu", onContextmenu);
      this.el.removeEventListener("contextmenu", onContextmenuBattlefield);
      this._menuObserver.disconnect();
    };
  },

  destroyed() {
    if (this._cleanup) this._cleanup();
  }
};

export default Battlefield;
