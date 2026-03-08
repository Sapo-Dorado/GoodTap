const CARD_W = 56;
const CARD_H = 78;

// Hide a card element immediately (before server confirms the move).
// LiveView will remove it from the DOM when the new state arrives.
function optimisticallyHideCard(instanceId, zone) {
  const el =
    document.getElementById(`card-${instanceId}`) ||
    document.getElementById(`hand-card-${instanceId}`) ||
    document.querySelector(`[data-instance-id="${instanceId}"]`);
  if (el) el.style.visibility = "hidden";
}

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
    this._insertGhostWrapper = null;
    this._insertIndex = null;
    this.lasso = null;
    this.lassoEl = null;
    this.myRole = this.el.dataset.myRole;
    this.previewPanel = document.getElementById("card-preview-panel");
    this.previewImg = document.getElementById("card-preview-img");

    const onMousedown = (e) => {
      if (e.target.closest("[data-no-hotkey]")) return;
      if (e.button !== 0) return;

      const card = e.target.closest("[data-draggable]");

      // Click not on a card — check if on battlefield bottom half for lasso
      if (!card) {
        const bf = e.target.closest("#battlefield");
        if (bf && !e.target.closest("[data-pile-zone]")) {
          const bfRect = bf.getBoundingClientRect();
          const inMyHalf = e.clientY > bfRect.top + bfRect.height / 2;
          this.pushEvent("clear_selection", {});
          if (inMyHalf) this.startLasso(bf, e);
        } else {
          this.pushEvent("clear_selection", {});
        }
        return;
      }

      // Click on opponent's card — ignore
      if (card.dataset.owner && card.dataset.owner !== this.myRole) return;

      // Click on unselected card — clear selection first
      if (card.dataset.selected !== "true") {
        this.pushEvent("clear_selection", {});
      }

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
      const card = e.target.closest("[data-draggable], [data-hoverable]");
      if (card) {
        this.hoveredCard = {
          instanceId: card.dataset.instanceId,
          zone: card.dataset.zone,
          owner: card.dataset.owner
        };
      }
      const imgEl = e.target.closest("[data-card-img]");
      if (!imgEl) return;
      if (imgEl.closest("[data-no-preview]")) return;
      const src = imgEl.dataset.cardImg;
      if (src) this.showPreview(src, imgEl.getBoundingClientRect());
    };

    const onMouseout = (e) => {
      const card = e.target.closest("[data-draggable], [data-hoverable]");
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

    // Keys that move a card out of its zone — we hide it optimistically
    const MOVE_KEYS = new Set(["d", "s", "t", "y"]);

    const onKeydown = (e) => {
      // Don't fire hotkeys when typing in inputs
      const tag = document.activeElement && document.activeElement.tagName;
      if (tag === "INPUT" || tag === "TEXTAREA") return;

      if (e.key === "Escape") {
        this.pushEvent("close_context_menu", {});
        return;
      }

      const key = e.key === " " ? "space" : e.key.toLowerCase();
      if (key === "space") e.preventDefault();
      const hovered = this.hoveredCard;

      // Optimistically hide the card before the server round-trip
      if (hovered && MOVE_KEYS.has(key) && hovered.owner === this.myRole) {
        optimisticallyHideCard(hovered.instanceId, hovered.zone);
      }

      this.pushEvent("hotkey", {
        key,
        instance_id: hovered ? hovered.instanceId : null,
        zone: hovered ? hovered.zone : null,
        owner: hovered ? hovered.owner : null
      });
    };

    const onDocMousedown = (e) => {
      const menu = document.getElementById("context-menu");
      if (menu && !menu.contains(e.target)) {
        this.pushEvent("close_context_menu", {});
      }
    };

    const handMenuBtn = document.getElementById("hand-menu-btn");
    const onHandMenuClick = (e) => {
      const rect = handMenuBtn.getBoundingClientRect();
      const menuW = 200;
      const x = Math.min(rect.left, window.innerWidth - menuW - 8);
      this.pushEvent("hand_menu", {x, y_from_bottom: window.innerHeight - rect.top + 4});
    };

    this.el.addEventListener("mousedown", onMousedown);
    this.el.addEventListener("mouseover", onMouseover);
    this.el.addEventListener("mouseout", onMouseout);
    document.addEventListener("keydown", onKeydown);
    document.addEventListener("mousedown", onDocMousedown);
    if (handMenuBtn) handMenuBtn.addEventListener("click", onHandMenuClick);

    this._cleanup = () => {
      this.el.removeEventListener("mousedown", onMousedown);
      this.el.removeEventListener("mouseover", onMouseover);
      this.el.removeEventListener("mouseout", onMouseout);
      document.removeEventListener("keydown", onKeydown);
      document.removeEventListener("mousedown", onDocMousedown);
      if (handMenuBtn) handMenuBtn.removeEventListener("click", onHandMenuClick);
    };
  },

  destroyed() {
    if (this._cleanup) this._cleanup();
    this.cleanupDrag();
    this.cleanupLasso();
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

  // ─── Lasso Selection ──────────────────────────────────────────────────────

  startLasso(bf, event) {
    const bfRect = bf.getBoundingClientRect();
    const startX = event.clientX - bfRect.left;
    const startY = event.clientY - bfRect.top;
    let lassoCommitted = false;

    const lassoEl = document.createElement("div");
    lassoEl.style.cssText = `
      position: absolute;
      border: 1px dashed rgba(96, 165, 250, 0.8);
      background: rgba(96, 165, 250, 0.1);
      pointer-events: none;
      z-index: 50;
      left: ${startX}px;
      top: ${startY}px;
      width: 0;
      height: 0;
    `;
    this.lassoEl = lassoEl;

    const onMove = (e) => {
      const curX = e.clientX - bfRect.left;
      const curY = e.clientY - bfRect.top;
      const x = Math.min(startX, curX);
      const y = Math.min(startY, curY);
      const w = Math.abs(curX - startX);
      const h = Math.abs(curY - startY);

      if (!lassoCommitted && (w > 4 || h > 4)) {
        lassoCommitted = true;
        bf.appendChild(lassoEl);
      }

      if (lassoCommitted) {
        lassoEl.style.left = x + "px";
        lassoEl.style.top = y + "px";
        lassoEl.style.width = w + "px";
        lassoEl.style.height = h + "px";
      }
    };

    const onUp = (e) => {
      document.removeEventListener("mousemove", onMove);
      document.removeEventListener("mouseup", onUp);

      if (!lassoCommitted) {
        this.cleanupLasso();
        return;
      }

      // Find the lasso rect in viewport coords
      const lassoRect = lassoEl.getBoundingClientRect();

      // Find all my battlefield cards that overlap (even partially) with the lasso
      const cards = Array.from(
        document.querySelectorAll(`[data-draggable][data-zone="battlefield"][data-owner="${this.myRole}"]`)
      );

      const selected = cards
        .filter(card => {
          const r = card.getBoundingClientRect();
          return (
            r.left < lassoRect.right &&
            r.right > lassoRect.left &&
            r.top < lassoRect.bottom &&
            r.bottom > lassoRect.top
          );
        })
        .map(card => card.dataset.instanceId);

      this.cleanupLasso();

      if (selected.length > 0) {
        this.pushEvent("set_selection", { instance_ids: selected });
      }
    };

    document.addEventListener("mousemove", onMove);
    document.addEventListener("mouseup", onUp);
  },

  cleanupLasso() {
    if (this.lassoEl) {
      this.lassoEl.remove();
      this.lassoEl = null;
    }
    this.lasso = null;
  },

  // ─── Drag ─────────────────────────────────────────────────────────────────

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

    // Collect other selected cards on the battlefield for multi-drag.
    // Also record their original % positions so we can reposition them optimistically.
    const isMulti = zone === "battlefield" && card.dataset.selected === "true";
    const otherSelected = isMulti
      ? Array.from(
          document.querySelectorAll(`[data-selected="true"][data-zone="battlefield"][data-owner="${this.myRole}"]`)
        ).filter(el => el.dataset.instanceId !== instanceId)
      : [];

    // Per-card ghost state for multi-drag: { el, ghost, dxFromPrimary, dyFromPrimary, origXPct, origYPct }
    this.extraGhosts = [];

    const commitDrag = (e) => {
      if (dragCommitted) return;
      dragCommitted = true;

      // Hide primary card
      card.style.display = "none";

      // Primary ghost
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

      // Extra ghosts for other selected cards — positioned relative to primary
      for (const otherEl of otherSelected) {
        const otherRect = otherEl.getBoundingClientRect();
        const dxFromPrimary = otherRect.left - rect.left;
        const dyFromPrimary = otherRect.top - rect.top;
        const otherTapped = otherEl.classList.contains("is-tapped");
        // Record current % position from style (e.g. "12%" -> 0.12)
        const origXPct = parseFloat(otherEl.style.left) / 100;
        const origYPct = parseFloat(otherEl.style.top) / 100;

        const g = document.createElement("img");
        g.src = otherEl.dataset.cardImg || "";
        g.style.cssText = `
          position: fixed;
          pointer-events: none;
          opacity: 0.9;
          z-index: 9998;
          width: ${CARD_W}px;
          height: ${CARD_H}px;
          object-fit: cover;
          border-radius: 4px;
          box-shadow: 0 8px 24px rgba(0,0,0,0.6);
          ${otherTapped ? "transform: rotate(90deg); transform-origin: center center;" : ""}
        `;
        document.body.appendChild(g);
        otherEl.style.display = "none";
        this.extraGhosts.push({ el: otherEl, ghost: g, dxFromPrimary, dyFromPrimary, origXPct, origYPct });
      }
    };

    const onMove = (e) => {
      const dx = e.clientX - startX;
      const dy = e.clientY - startY;
      if (!dragCommitted && Math.sqrt(dx * dx + dy * dy) >= DRAG_THRESHOLD) {
        commitDrag(e);
      }
      if (!dragCommitted) return;
      this.updateGhostPos(e.clientX, e.clientY, offsetX, offsetY);
      // Move extra ghosts in parallel
      const primaryLeft = e.clientX - offsetX;
      const primaryTop = e.clientY - offsetY;
      for (const { ghost, dxFromPrimary, dyFromPrimary } of this.extraGhosts) {
        ghost.style.left = (primaryLeft + dxFromPrimary) + "px";
        ghost.style.top = (primaryTop + dyFromPrimary) + "px";
      }
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

      const dropZone = dropInfo ? dropInfo.zone : null;

      const isSameZone = dropZone === zone;
      const isBattlefield = dropZone === "battlefield";
      const isListZone = dropZone in LIST_ZONES;

      if (dropInfo && (!isSameZone || isBattlefield || isListZone)) {
        const zoneRect = dropInfo.el.getBoundingClientRect();
        const cardLeft = e.clientX - offsetX;
        const cardTop = e.clientY - offsetY;
        let relX = Math.max(0, Math.min(0.98, (cardLeft - zoneRect.left) / zoneRect.width));
        let relY = Math.max(0, Math.min(0.98, (cardTop - zoneRect.top) / zoneRect.height));

        const insertIndex = isListZone ? (this._insertIndex ?? null) : null;
        this._insertIndex = null;
        this.cleanupDragGhost();

        // ── Optimistic rendering ──────────────────────────────────────────
        //
        // Immediately place the card at its destination so there is no gap
        // between drop and the server's LiveView patch.  We build the DOM to
        // match exactly what the server will render, so morphdom finds the
        // element already correct and makes no visible change.  On the rare
        // error path morphdom snap-corrects — acceptable.
        //
        // We use element ids that match the server template so morphdom tracks
        // them by identity, not by position, preventing any duplication.
        //
        // Skipped for: → graveyard / exile / deck (complex pile HTML),
        // tokens → hand (server silently drops them), and find-mode reorders.

        if (isBattlefield && zone === "battlefield") {
          // ── Battlefield reposition (staying on my side) ──
          card.style.left = Math.trunc(relX * 100) + "%";
          card.style.top = Math.trunc(relY * 100) + "%";
          card.style.display = "";
          this.draggedEl = null;

          // Reposition other selected cards by the same delta
          if (this.extraGhosts.length > 0) {
            const origPrimaryXPct = (rect.left - zoneRect.left) / zoneRect.width;
            const origPrimaryYPct = (rect.top - zoneRect.top) / zoneRect.height;
            const dx = relX - origPrimaryXPct;
            const dy = relY - origPrimaryYPct;

            for (const { el, origXPct: ox, origYPct: oy } of this.extraGhosts) {
              const nx = Math.max(0, Math.min(0.98, ox + dx));
              const ny = Math.max(0, Math.min(0.98, oy + dy));
              el.style.left = Math.trunc(nx * 100) + "%";
              el.style.top = Math.trunc(ny * 100) + "%";
              el.style.display = "";
            }
          }

        } else if (isSameZone && isListZone) {
          // ── List-zone reorder ──
          // insertIndex is the desired position computed by showInsertGhost,
          // matching the server's reorder_in_zone logic.
          // Skip optimistic render if in "find" mode (cards sorted alphabetically —
          // the visible index wouldn't match the actual deck position the server uses).
          const isFind = !!dropInfo.el.parentElement?.querySelector('[name="query"]');

          if (!isFind && insertIndex !== null) {
            const innerEl = dropInfo.el.firstElementChild || dropInfo.el;
            // All draggable siblings *including* the hidden dragged card
            const allCards = Array.from(innerEl.querySelectorAll("[data-draggable]"));
            const originalIndex = allCards.indexOf(card);
            // Replicate the server's index adjustment: if original position is before
            // the insert point, the insert point shifts left by one after removal.
            const adjustedIndex = (originalIndex !== -1 && originalIndex < insertIndex)
              ? insertIndex - 1
              : insertIndex;

            // Siblings without the dragged card
            const siblings = allCards.filter(c => c !== card);
            card.style.display = "";
            if (adjustedIndex >= siblings.length) {
              innerEl.appendChild(card);
            } else {
              innerEl.insertBefore(card, siblings[adjustedIndex]);
            }
            this.draggedEl = null;
          }
          // If isFind or insertIndex is null, draggedEl stays set; server re-render restores.

        } else if (isBattlefield && zone !== "battlefield") {
          // ── Cross-zone → my battlefield ──
          const bf = document.getElementById("battlefield");
          if (bf) {
            const el = document.createElement("div");
            el.id = `card-${instanceId}`;
            el.className = "card-on-battlefield absolute cursor-pointer transition-transform";
            el.style.left = Math.trunc(relX * 100) + "%";
            el.style.top = Math.trunc(relY * 100) + "%";
            el.setAttribute("data-draggable", "true");
            el.setAttribute("data-instance-id", instanceId);
            el.setAttribute("data-zone", "battlefield");
            el.setAttribute("data-owner", this.myRole);
            el.setAttribute("data-card-img", imgSrc);
            el.setAttribute("data-selected", "false");
            el.setAttribute("data-is-token", card.dataset.isToken || "false");
            el.innerHTML = `<div class="flex flex-col items-center"><div class="card-draggable"><img src="${imgSrc}" class="card-image rounded shadow-lg" draggable="false" /></div></div>`;
            bf.appendChild(el);
            this.draggedEl = null;
          }

        } else if (dropZone === "hand" && card.dataset.isToken !== "true") {
          // ── Cross-zone → hand ──
          // Tokens are silently dropped by the server, so skip them.
          // For real cards, build the hand card element at the insert position.
          const handInner = document.querySelector("#my-hand > div");
          if (handInner) {
            const el = document.createElement("div");
            el.id = `hand-card-${instanceId}`;
            el.className = "shrink-0 cursor-pointer hover:scale-110 transition-transform relative";
            el.setAttribute("data-draggable", "true");
            el.setAttribute("data-instance-id", instanceId);
            el.setAttribute("data-zone", "hand");
            el.setAttribute("data-owner", this.myRole);
            el.setAttribute("data-card-img", imgSrc);
            el.setAttribute("data-is-token", "false");
            el.innerHTML = `<img src="${imgSrc}" class="h-24 w-auto rounded shadow" draggable="false" />`;

            const siblings = Array.from(handInner.querySelectorAll("[data-draggable]"));
            const idx = insertIndex !== null ? insertIndex : siblings.length;
            if (idx >= siblings.length) {
              handInner.appendChild(el);
            } else {
              handInner.insertBefore(el, siblings[idx]);
            }
            // Original element (in source zone) stays hidden; server patch removes it.
            this.draggedEl = null;
          }
        }
        // For → graveyard, → exile, → deck: card stays hidden; server re-render restores.
        // draggedEl remains set so cleanupDrag() can restore if the drop fails.

        // Collect selected instance ids for multi-card battlefield moves
        const selectedIds = [instanceId, ...this.extraGhosts.map(eg => eg.el.dataset.instanceId)];

        this.pushEvent("drag_end", {
          instance_id: instanceId,
          from_zone: zone,
          owner: owner,
          target_zone: dropInfo.zone,
          x: relX,
          y: relY,
          insert_index: insertIndex,
          selected_instance_ids: selectedIds.length > 1 ? selectedIds : []
        });
      } else {
        // No valid drop zone or dropped on same non-list zone — restore
        this._insertIndex = null;
        this.cleanupDragGhost();
        if (draggedEl) {
          draggedEl.style.display = "";
        }
        for (const { el } of this.extraGhosts) {
          el.style.display = "";
        }
      }
      this.extraGhosts = [];
    };

    document.addEventListener("mousemove", onMove);
    document.addEventListener("mouseup", onUp);
  },

  // Shift relX right by 1% steps until no other battlefield card occupies the same
  // truncated position, or until the card's right edge would leave the battlefield.
  nudgeIfOccupied(relX, relY, excludeInstanceId) {
    const maxX = 95;

    const cards = Array.from(
      document.querySelectorAll(`[data-draggable][data-zone="battlefield"][data-owner="${this.myRole}"]`)
    ).filter(el => el.dataset.instanceId !== excludeInstanceId && el.style.display !== "none");

    // Use Math.round (not trunc) when reading back stored positions to avoid
    // float round-trip errors (e.g. trunc(0.57 * 100) = 56, not 57).
    const occupied = new Set(cards.map(el =>
      `${Math.round(parseFloat(el.style.left))},${Math.round(parseFloat(el.style.top))}`
    ));

    const ty = Math.round(relY * 100);
    const start = Math.trunc(relX * 100); // trunc for drop position matches server render

    // Search rightward first
    let right = start;
    while (occupied.has(`${right},${ty}`) && right < maxX) {
      right += 1;
    }

    // If rightward hit the boundary and that slot is still occupied, try leftward
    let tx = right;
    if (right >= maxX && occupied.has(`${right},${ty}`)) {
      let left = start - 1;
      while (occupied.has(`${left},${ty}`) && left > 0) {
        left -= 1;
      }
      if (!occupied.has(`${left},${ty}`)) tx = left;
    }

    return { relX: tx / 100, relY };
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
  // Only used for the open-zone popup — not for the small pile elements.
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

    const isRotated = zoneName === "graveyard" || zoneName === "exile";
    const ghostSrc = this.dragging
      ? (document.querySelector(`[data-instance-id="${this.dragging.instanceId}"]`)?.dataset?.cardImg || "")
      : "";

    this.insertGhost = document.createElement("img");
    this.insertGhost.src = ghostSrc;

    if (isRotated) {
      // Pile shows cards as 56×78 portrait rotated 90° (visually 78×56 landscape).
      // Use a wrapper div sized to the visual landscape footprint so the ghost
      // participates in the flex layout at the right visual width.
      const wrapper = document.createElement("div");
      wrapper.style.cssText = `
        width: 78px;
        height: 56px;
        flex-shrink: 0;
        align-self: center;
        position: relative;
        pointer-events: none;
        outline: 2px solid rgba(167, 139, 250, 0.8);
        border-radius: 4px;
        overflow: hidden;
      `;
      this.insertGhost.style.cssText = `
        position: absolute;
        top: 50%;
        left: 50%;
        width: 56px;
        height: 78px;
        object-fit: cover;
        transform: translate(-50%, -50%) rotate(90deg);
        opacity: 0.4;
        pointer-events: none;
        border-radius: 4px;
      `;
      wrapper.appendChild(this.insertGhost);
      // Re-use insertGhost to track the wrapper for cleanup
      this._insertGhostWrapper = wrapper;
      if (insertAfterEl) {
        insertAfterEl.after(wrapper);
      } else {
        innerEl.prepend(wrapper);
      }
    } else {
      const ghostHeight = LIST_ZONES[zoneName] || 96;
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
      this._insertGhostWrapper = null;
      if (insertAfterEl) {
        insertAfterEl.after(this.insertGhost);
      } else {
        innerEl.prepend(this.insertGhost);
      }
    }
  },

  updateDropZoneIndicator(x, y, fromZone) {
    if (this.dropZoneGhost) {
      this.dropZoneGhost.remove();
      this.dropZoneGhost = null;
    }
    if (this._insertGhostWrapper) {
      this._insertGhostWrapper.remove();
      this._insertGhostWrapper = null;
    }
    if (this.insertGhost) {
      this.insertGhost.remove();
      this.insertGhost = null;
    }

    const dropInfo = this.findDropZone(x, y);
    if (!dropInfo) return;

    const dZone = dropInfo.zone;
    const isPileEl = !!dropInfo.el.dataset.pileZone;

    if (dZone in LIST_ZONES && !isPileEl) {
      // Open-zone popup: show insert ghost at the appropriate position
      this.showInsertGhost(dZone, dropInfo.el, x);
      return;
    }

    if (isPileEl && dZone !== fromZone) {
      // Small pile element: show a card ghost image floating over the pile.
      // Reset _insertIndex so the drop sends null → server uses default (prepend/top).
      this._insertIndex = null;
      this.showPileGhost(dZone, dropInfo.el);
      return;
    }

    // Other non-battlefield zones: purple border overlay
    if (dZone !== "battlefield" && dZone !== fromZone) {
      const r = dropInfo.el.getBoundingClientRect();
      this.dropZoneGhost = document.createElement("div");
      this.dropZoneGhost.style.cssText = `
        position: fixed;
        left: ${r.left}px;
        top: ${r.top}px;
        width: ${r.width}px;
        height: ${r.height}px;
        border: 2px solid rgba(167, 139, 250, 0.8);
        border-radius: 4px;
        pointer-events: none;
        background: rgba(167, 139, 250, 0.1);
        z-index: 9998;
        box-sizing: border-box;
      `;
      document.body.appendChild(this.dropZoneGhost);
    }
  },

  // Show a card image ghost floating over a small pile element (deck/graveyard/exile).
  showPileGhost(zoneName, pileEl) {
    const ghostSrc = this.dragging
      ? (document.querySelector(`[data-instance-id="${this.dragging.instanceId}"]`)?.dataset?.cardImg || "")
      : "";

    const r = pileEl.getBoundingClientRect();
    const isRotated = zoneName === "graveyard" || zoneName === "exile";

    const img = document.createElement("img");
    img.src = ghostSrc;
    img.style.cssText = `
      position: fixed;
      width: 56px;
      height: 78px;
      object-fit: cover;
      border-radius: 4px;
      opacity: 0.7;
      pointer-events: none;
      outline: 2px solid rgba(167, 139, 250, 0.8);
      z-index: 9998;
      ${isRotated
        ? `left: ${r.left + r.width / 2 - 28}px; top: ${r.top + r.height / 2 - 39}px; transform: rotate(90deg);`
        : `left: ${r.left + r.width / 2 - 28}px; top: ${r.top + r.height / 2 - 39}px;`
      }
    `;
    document.body.appendChild(img);
    this.dropZoneGhost = img;
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
    if (this._insertGhostWrapper) {
      this._insertGhostWrapper.remove();
      this._insertGhostWrapper = null;
    }
    if (this.insertGhost) {
      this.insertGhost.remove();
      this.insertGhost = null;
    }
    for (const { ghost } of (this.extraGhosts || [])) {
      ghost.remove();
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
