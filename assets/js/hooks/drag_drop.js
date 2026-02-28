const CARD_W = 56;
const CARD_H = 78;

const DragDrop = {
  mounted() {
    this.dragging = null;
    this.ghost = null;
    this.draggedEl = null;
    this.dropZoneGhost = null;
    this.previewPanel = document.getElementById("card-preview-panel");
    this.previewImg = document.getElementById("card-preview-img");

    const onMousedown = (e) => {
      const card = e.target.closest("[data-draggable]");
      if (!card) return;
      if (e.button !== 0) return;
      e.preventDefault();
      this.hidePreview();
      this.startDrag(card, e);
    };

    const onMouseover = (e) => {
      if (this.dragging) return;
      const card = e.target.closest("[data-card-img]");
      if (!card) return;
      const src = card.dataset.cardImg;
      if (src) this.showPreview(src, card.getBoundingClientRect());
    };

    const onMouseout = (e) => {
      const card = e.target.closest("[data-card-img]");
      if (!card) return;
      if (!card.contains(e.relatedTarget)) {
        this.hidePreview();
      }
    };

    this.el.addEventListener("mousedown", onMousedown);
    this.el.addEventListener("mouseover", onMouseover);
    this.el.addEventListener("mouseout", onMouseout);

    this._cleanup = () => {
      this.el.removeEventListener("mousedown", onMousedown);
      this.el.removeEventListener("mouseover", onMouseover);
      this.el.removeEventListener("mouseout", onMouseout);
    };
  },

  destroyed() {
    if (this._cleanup) this._cleanup();
    this.cleanupDrag();
    this.hidePreview();
  },

  showPreview(src, cardRect) {
    if (!this.previewPanel || !this.previewImg) return;
    this.previewImg.src = src;

    const previewWidth = 300; // approx width of a 420px tall MTG card
    const margin = 12;
    const viewportWidth = window.innerWidth;

    // If the card's right edge is close enough to the right that the preview would overlap it, show on the left
    if (cardRect && (viewportWidth - cardRect.right) < previewWidth + margin) {
      this.previewPanel.style.right = "auto";
      this.previewPanel.style.left = margin + "px";
    } else {
      this.previewPanel.style.left = "auto";
      this.previewPanel.style.right = margin + "px";
    }

    this.previewPanel.style.display = "block";
  },

  hidePreview() {
    if (!this.previewPanel) return;
    this.previewPanel.style.display = "none";
  },

  startDrag(card, event) {
    const instanceId = card.dataset.instanceId;
    const zone = card.dataset.zone;
    const owner = card.dataset.owner;
    const imgSrc = card.dataset.cardImg;
    const isTapped = card.classList.contains("rotate-90");

    // Measure the card's rendered position to track offset
    const rect = card.getBoundingClientRect();
    const offsetX = event.clientX - rect.left;
    const offsetY = event.clientY - rect.top;

    // Hide the original card so it appears to move
    card.style.opacity = "0";
    card.style.pointerEvents = "none";
    this.draggedEl = card;

    // Ghost: a plain card-sized image, same size as battlefield cards
    this.ghost = document.createElement("img");
    this.ghost.src = imgSrc || "";
    this.ghost.style.cssText = `
      position: fixed;
      pointer-events: none;
      opacity: 0.9;
      z-index: 9999;
      width: ${CARD_W}px;
      height: ${CARD_H}px;
      object-fit: cover;
      border-radius: 4px;
      box-shadow: 0 8px 24px rgba(0,0,0,0.6);
      ${isTapped ? "transform: rotate(90deg) translateY(-100%); transform-origin: top left;" : ""}
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
      const draggedEl = this.draggedEl;
      this.dragging = null;

      if (dropInfo) {
        const zoneEl = document.querySelector(`[data-drop-zone="${dropInfo.zone}"]`);
        if (zoneEl) {
          const zoneRect = zoneEl.getBoundingClientRect();
          const cardLeft = e.clientX - offsetX;
          const cardTop = e.clientY - offsetY;
          const relX = Math.max(0, Math.min(0.98, (cardLeft - zoneRect.left) / zoneRect.width));
          const relY = Math.max(0, Math.min(0.98, (cardTop - zoneRect.top) / zoneRect.height));

          this.cleanupDragGhost();

          this.pushEvent("drag_end", {
            instance_id: instanceId,
            from_zone: zone,
            owner: owner,
            target_zone: dropInfo.zone,
            x: relX,
            y: relY
          });
        }
      } else {
        // No valid drop zone — restore the card immediately
        this.cleanupDragGhost();
        if (draggedEl) {
          draggedEl.style.opacity = "";
          draggedEl.style.pointerEvents = "";
        }
      }
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

  cleanupDragGhost() {
    if (this.ghost) {
      this.ghost.remove();
      this.ghost = null;
    }
    if (this.dropZoneGhost) {
      this.dropZoneGhost.remove();
      this.dropZoneGhost = null;
    }
    // draggedEl intentionally left for the caller to handle
  },

  cleanupDrag() {
    this.cleanupDragGhost();
    if (this.draggedEl) {
      this.draggedEl.style.opacity = "";
      this.draggedEl.style.pointerEvents = "";
      this.draggedEl = null;
    }
  }
};

export default DragDrop;
