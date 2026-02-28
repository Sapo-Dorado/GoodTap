const DragDrop = {
  mounted() {
    this.dragging = null;
    this.ghost = null;
    this.dropZoneGhost = null;

    const onMousedown = (e) => {
      const card = e.target.closest("[data-draggable]");
      if (!card) return;
      if (e.button !== 0) return;
      e.preventDefault();
      this.startDrag(card, e);
    };

    this.el.addEventListener("mousedown", onMousedown);
    this._cleanup = () => this.el.removeEventListener("mousedown", onMousedown);
  },

  destroyed() {
    if (this._cleanup) this._cleanup();
    this.cleanupDrag();
  },

  startDrag(card, event) {
    const instanceId = card.dataset.instanceId;
    const zone = card.dataset.zone;
    const owner = card.dataset.owner;

    const rect = card.getBoundingClientRect();

    // Track offset from card's top-left corner so it stays under cursor naturally
    const offsetX = event.clientX - rect.left;
    const offsetY = event.clientY - rect.top;

    // Create ghost clone following cursor
    this.ghost = card.cloneNode(true);
    const isTapped = card.classList.contains("rotate-90");
    this.ghost.style.cssText = `
      position: fixed;
      pointer-events: none;
      opacity: 0.85;
      z-index: 9999;
      width: ${rect.width}px;
      height: ${rect.height}px;
      ${isTapped ? "transform: rotate(90deg); transform-origin: center;" : ""}
    `;
    document.body.appendChild(this.ghost);

    this.dragging = { instanceId, zone, owner, offsetX, offsetY };
    this.updateGhostPos(event.clientX, event.clientY, offsetX, offsetY);

    const onMove = (e) => {
      if (!this.dragging) return;
      this.updateGhostPos(e.clientX, e.clientY, offsetX, offsetY);
      this.updateDropZoneIndicator(e.clientX, e.clientY, zone);
    };

    const onUp = (e) => {
      document.removeEventListener("mousemove", onMove);
      document.removeEventListener("mouseup", onUp);

      if (!this.dragging) return;

      const dropInfo = this.findDropZone(e.clientX, e.clientY);
      this.cleanupDrag();

      if (dropInfo) {
        // Use the top-left corner of where the card would land
        // so the server position matches exactly where you dropped it
        const zoneEl = document.querySelector(`[data-drop-zone="${dropInfo.zone}"]`);
        if (zoneEl) {
          const zoneRect = zoneEl.getBoundingClientRect();
          const cardLeft = e.clientX - offsetX;
          const cardTop = e.clientY - offsetY;
          const relX = Math.max(0, Math.min(0.98, (cardLeft - zoneRect.left) / zoneRect.width));
          const relY = Math.max(0, Math.min(0.98, (cardTop - zoneRect.top) / zoneRect.height));

          this.pushEvent("drag_end", {
            instance_id: instanceId,
            from_zone: zone,
            owner: owner,
            target_zone: dropInfo.zone,
            x: relX,
            y: relY
          });
        }
      }
      this.dragging = null;
    };

    document.addEventListener("mousemove", onMove);
    document.addEventListener("mouseup", onUp);
  },

  updateGhostPos(x, y, offsetX, offsetY) {
    if (!this.ghost) return;
    this.ghost.style.left = (x - offsetX) + "px";
    this.ghost.style.top = (y - offsetY) + "px";
  },

  findDropZone(x, y) {
    const zones = document.querySelectorAll("[data-drop-zone]");
    for (const zone of zones) {
      const rect = zone.getBoundingClientRect();
      if (x >= rect.left && x <= rect.right && y >= rect.top && y <= rect.bottom) {
        return { zone: zone.dataset.dropZone };
      }
    }
    return null;
  },

  updateDropZoneIndicator(x, y, fromZone) {
    if (this.dropZoneGhost) {
      this.dropZoneGhost.remove();
      this.dropZoneGhost = null;
    }

    const dropInfo = this.findDropZone(x, y);
    if (dropInfo && dropInfo.zone !== "battlefield" && dropInfo.zone !== "opp-battlefield" && dropInfo.zone !== fromZone) {
      const zoneEl = document.querySelector(`[data-drop-zone="${dropInfo.zone}"]`);
      if (zoneEl) {
        this.dropZoneGhost = document.createElement("div");
        this.dropZoneGhost.className = "zone-ghost-indicator";
        this.dropZoneGhost.style.cssText = `
          position: absolute;
          inset: 0;
          border: 2px solid rgba(167, 139, 250, 0.8);
          border-radius: 4px;
          pointer-events: none;
          background: rgba(167, 139, 250, 0.1);
          z-index: 100;
        `;
        if (getComputedStyle(zoneEl).position === "static") {
          zoneEl.style.position = "relative";
        }
        zoneEl.appendChild(this.dropZoneGhost);
      }
    }
  },

  cleanupDrag() {
    if (this.ghost) {
      this.ghost.remove();
      this.ghost = null;
    }
    if (this.dropZoneGhost) {
      this.dropZoneGhost.remove();
      this.dropZoneGhost = null;
    }
  }
};

export default DragDrop;
