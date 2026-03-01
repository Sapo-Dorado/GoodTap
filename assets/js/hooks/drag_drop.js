const CARD_W = 56;
const CARD_H = 78;

// Zones that show an insert-ghost indicator and support index-based reordering.
// Maps drop-zone name -> ghost card height in px.
const LIST_ZONES = { hand: 96, deck: 128, graveyard: 128, exile: 128 };

const DragDrop = {
  mounted() {
    this.dragging = null;
    this.ghost = null;
    this.draggedEl = null;
    this.dropZoneGhost = null;
    this.hoveredCard = null;
    this.insertGhost = null;
    this._insertIndex = null;
    this.previewPanel = document.getElementById("card-preview-panel");
    this.previewImg = document.getElementById("card-preview-img");

    const onMousedown = (e) => {
      if (e.target.closest("[data-no-hotkey]")) return;
      const card = e.target.closest("[data-draggable]");
      if (!card) return;
      if (e.button !== 0) return;
      this.hidePreview();
      this.startDrag(card, e);
    };

    const onMouseover = (e) => {
      if (this.dragging) return;
      // Ignore events from counter/tracker interactive areas
      if (e.target.closest("[data-no-hotkey]")) {
        this.hoveredCard = null;
        return;
      }
      const card = e.target.closest("[data-draggable]");
      if (card) {
        this.hoveredCard = {
          instanceId: card.dataset.instanceId,
          zone: card.dataset.zone,
          owner: card.dataset.owner
        };
      }
      const imgEl = e.target.closest("[data-card-img]");
      if (!imgEl) return;
      const src = imgEl.dataset.cardImg;
      if (src) this.showPreview(src, imgEl.getBoundingClientRect());
    };

    const onMouseout = (e) => {
      const card = e.target.closest("[data-draggable]");
      if (card) {
        const leavingCard = !card.contains(e.relatedTarget);
        const enteringNoHotkey = e.relatedTarget && e.relatedTarget.closest("[data-no-hotkey]");
        if (leavingCard || enteringNoHotkey) {
          this.hoveredCard = null;
        }
      }
      const imgEl = e.target.closest("[data-card-img]");
      if (!imgEl) return;
      if (!imgEl.contains(e.relatedTarget)) {
        this.hidePreview();
      }
    };

    const onKeydown = (e) => {
      // Don't fire hotkeys when typing in inputs
      const tag = document.activeElement && document.activeElement.tagName;
      if (tag === "INPUT" || tag === "TEXTAREA") return;

      const key = e.key === " " ? "space" : e.key.toLowerCase();
      if (key === "space") e.preventDefault();
      const hovered = this.hoveredCard;

      this.pushEvent("hotkey", {
        key,
        instance_id: hovered ? hovered.instanceId : null,
        zone: hovered ? hovered.zone : null,
        owner: hovered ? hovered.owner : null
      });
    };

    this.el.addEventListener("mousedown", onMousedown);
    this.el.addEventListener("mouseover", onMouseover);
    this.el.addEventListener("mouseout", onMouseout);
    document.addEventListener("keydown", onKeydown);

    this._cleanup = () => {
      this.el.removeEventListener("mousedown", onMousedown);
      this.el.removeEventListener("mouseover", onMouseover);
      this.el.removeEventListener("mouseout", onMouseout);
      document.removeEventListener("keydown", onKeydown);
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
    const isTapped = card.classList.contains("is-tapped");

    const rect = card.getBoundingClientRect();
    const offsetX = event.clientX - rect.left;
    const offsetY = event.clientY - rect.top;
    const startX = event.clientX;
    const startY = event.clientY;
    const DRAG_THRESHOLD = 5;
    let dragCommitted = false;

    this.draggedEl = card;

    const commitDrag = (e) => {
      if (dragCommitted) return;
      dragCommitted = true;

      // Hide original and collapse its space in the layout
      card.style.display = "none";

      // Ghost
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
        ${isTapped ? "transform: rotate(90deg); transform-origin: center center;" : ""}
      `;
      document.body.appendChild(this.ghost);
      this.dragging = { instanceId, zone, owner, offsetX, offsetY };
      this.updateGhostPos(e.clientX, e.clientY, offsetX, offsetY);
    };

    const onMove = (e) => {
      const dx = e.clientX - startX;
      const dy = e.clientY - startY;
      if (!dragCommitted && Math.sqrt(dx * dx + dy * dy) >= DRAG_THRESHOLD) {
        commitDrag(e);
      }
      if (!dragCommitted) return;
      this.updateGhostPos(e.clientX, e.clientY, offsetX, offsetY);
      this.updateDropZoneIndicator(e.clientX, e.clientY, zone);
    };

    const onUp = (e) => {
      document.removeEventListener("mousemove", onMove);
      document.removeEventListener("mouseup", onUp);

      if (!dragCommitted) {
        // Was just a click — restore and let click event propagate
        this.draggedEl = null;
        return;
      }

      if (!this.dragging) return;

      const dropInfo = this.findDropZone(e.clientX, e.clientY);
      const draggedEl = this.draggedEl;
      this.dragging = null;

      const isSameZone = dropInfo && dropInfo.zone === zone;
      const isBattlefield = dropInfo && dropInfo.zone === "battlefield";
      const isListZone = dropInfo && dropInfo.zone in LIST_ZONES;

      if (dropInfo && (!isSameZone || isBattlefield || isListZone)) {
        const zoneRect = dropInfo.el.getBoundingClientRect();
        const cardLeft = e.clientX - offsetX;
        const cardTop = e.clientY - offsetY;
        const relX = Math.max(0, Math.min(0.98, (cardLeft - zoneRect.left) / zoneRect.width));
        const relY = Math.max(0, Math.min(0.98, (cardTop - zoneRect.top) / zoneRect.height));

        const insertIndex = isListZone ? (this._insertIndex ?? null) : null;
        this._insertIndex = null;
        this.cleanupDragGhost();

        this.pushEvent("drag_end", {
          instance_id: instanceId,
          from_zone: zone,
          owner: owner,
          target_zone: dropInfo.zone,
          x: relX,
          y: relY,
          insert_index: insertIndex
        });
      } else {
        // No valid drop zone or dropped on same non-list zone — restore
        this._insertIndex = null;
        this.cleanupDragGhost();
        if (draggedEl) {
          draggedEl.style.display = "";
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
    // Sort zones smallest-first so more specific (smaller) zones win over parent zones
    const zones = Array.from(document.querySelectorAll("[data-drop-zone]")).sort((a, b) => {
      const ra = a.getBoundingClientRect();
      const rb = b.getBoundingClientRect();
      return (ra.width * ra.height) - (rb.width * rb.height);
    });
    for (const el of zones) {
      const rect = el.getBoundingClientRect();
      if (x >= rect.left && x <= rect.right && y >= rect.top && y <= rect.bottom) {
        return { zone: el.dataset.dropZone, el };
      }
    }
    return null;
  },

  // Show an insert-ghost indicator for horizontal list zones (hand, deck, graveyard, exile).
  showInsertGhost(zoneName, zoneEl, x) {
    // Cards are inside the inner flex wrapper (first child of the scroll container)
    const innerEl = zoneEl.firstElementChild || zoneEl;
    const cards = Array.from(innerEl.querySelectorAll("[data-draggable]"));

    let insertAfterEl = null;
    let insertIndex = 0;

    for (let i = 0; i < cards.length; i++) {
      const r = cards[i].getBoundingClientRect();
      if (x > r.left + r.width / 2) {
        insertAfterEl = cards[i];
        insertIndex = i + 1;
      } else {
        break;
      }
    }

    this._insertIndex = insertIndex;

    const ghostHeight = LIST_ZONES[zoneName] || 96;
    const ghostSrc = this.dragging
      ? (document.querySelector(`[data-instance-id="${this.dragging.instanceId}"]`)?.dataset?.cardImg || "")
      : "";

    this.insertGhost = document.createElement("img");
    this.insertGhost.src = ghostSrc;
    this.insertGhost.style.cssText = `
      height: ${ghostHeight}px;
      width: auto;
      border-radius: 4px;
      opacity: 0.4;
      pointer-events: none;
      flex-shrink: 0;
      align-self: center;
      outline: 2px solid rgba(167, 139, 250, 0.8);
    `;

    if (insertAfterEl) {
      insertAfterEl.after(this.insertGhost);
    } else {
      innerEl.prepend(this.insertGhost);
    }
  },

  updateDropZoneIndicator(x, y, fromZone) {
    if (this.dropZoneGhost) {
      this.dropZoneGhost.remove();
      this.dropZoneGhost = null;
    }
    if (this.insertGhost) {
      this.insertGhost.remove();
      this.insertGhost = null;
    }

    const dropInfo = this.findDropZone(x, y);
    if (!dropInfo) return;

    if (dropInfo.zone in LIST_ZONES) {
      this.showInsertGhost(dropInfo.zone, dropInfo.el, x);
      return;
    }

    if (dropInfo.zone !== "battlefield" && dropInfo.zone !== "opp-battlefield" && dropInfo.zone !== fromZone) {
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
      if (getComputedStyle(dropInfo.el).position === "static") {
        dropInfo.el.style.position = "relative";
      }
      dropInfo.el.appendChild(this.dropZoneGhost);
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
    if (this.insertGhost) {
      this.insertGhost.remove();
      this.insertGhost = null;
    }
    // draggedEl intentionally left for the caller to handle
  },

  cleanupDrag() {
    this.cleanupDragGhost();
    if (this.draggedEl) {
      this.draggedEl.style.display = "";
      this.draggedEl = null;
    }
  }
};

export default DragDrop;
