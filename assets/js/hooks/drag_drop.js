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

    // Create ghost clone following cursor
    const rect = card.getBoundingClientRect();
    this.ghost = card.cloneNode(true);
    this.ghost.style.cssText = `
      position: fixed;
      pointer-events: none;
      opacity: 0.85;
      z-index: 9999;
      width: ${rect.width}px;
      transform: rotate(${zone === "battlefield" && card.classList.contains("rotate-90") ? "90deg" : "0deg"});
    `;
    document.body.appendChild(this.ghost);

    this.dragging = { instanceId, zone, owner, startX: event.clientX, startY: event.clientY };
    this.updateGhostPos(event.clientX, event.clientY, rect.width, rect.height);

    const onMove = (e) => {
      if (!this.dragging) return;
      this.updateGhostPos(e.clientX, e.clientY, rect.width, rect.height);
      this.updateDropZoneIndicator(e.clientX, e.clientY, zone);
    };

    const onUp = (e) => {
      document.removeEventListener("mousemove", onMove);
      document.removeEventListener("mouseup", onUp);

      if (!this.dragging) return;

      const dropInfo = this.findDropZone(e.clientX, e.clientY);
      this.cleanupDrag();

      if (dropInfo) {
        this.pushEvent("drag_end", {
          instance_id: instanceId,
          from_zone: zone,
          owner: owner,
          target_zone: dropInfo.zone,
          x: dropInfo.relX,
          y: dropInfo.relY
        });
      }
      this.dragging = null;
    };

    document.addEventListener("mousemove", onMove);
    document.addEventListener("mouseup", onUp);
  },

  updateGhostPos(x, y, w, h) {
    if (!this.ghost) return;
    this.ghost.style.left = (x - w / 2) + "px";
    this.ghost.style.top = (y - h / 2) + "px";
  },

  findDropZone(x, y) {
    const zones = document.querySelectorAll("[data-drop-zone]");
    for (const zone of zones) {
      const rect = zone.getBoundingClientRect();
      if (x >= rect.left && x <= rect.right && y >= rect.top && y <= rect.bottom) {
        const relX = Math.round(((x - rect.left) / rect.width) * 100) / 100;
        const relY = Math.round(((y - rect.top) / rect.height) * 100) / 100;
        return { zone: zone.dataset.dropZone, relX, relY };
      }
    }
    return null;
  },

  updateDropZoneIndicator(x, y, fromZone) {
    // Remove existing ghost indicator
    if (this.dropZoneGhost) {
      this.dropZoneGhost.remove();
      this.dropZoneGhost = null;
    }

    const dropInfo = this.findDropZone(x, y);
    if (dropInfo && dropInfo.zone !== "battlefield" && dropInfo.zone !== fromZone) {
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
        const parent = zoneEl;
        if (getComputedStyle(parent).position === "static") {
          parent.style.position = "relative";
        }
        parent.appendChild(this.dropZoneGhost);
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
