const CardPreview = {
  mounted() {
    this.panel = document.getElementById("card-preview-panel");
    this.img = document.getElementById("card-preview-img");

    this.onOver = (e) => {
      const el = e.target.closest("[data-card-img]");
      if (!el) return;
      const src = el.dataset.cardImg;
      if (!src || !this.panel || !this.img) return;

      this.img.src = src;
      const rect = el.getBoundingClientRect();
      const previewWidth = 300;
      const margin = 12;
      if ((window.innerWidth - rect.right) < previewWidth + margin) {
        this.panel.style.left = margin + "px";
        this.panel.style.right = "auto";
      } else {
        this.panel.style.left = "auto";
        this.panel.style.right = margin + "px";
      }
      this.panel.style.display = "block";
    };

    this.onOut = (e) => {
      const imgEl = e.target.closest("[data-card-img]");
      if (!imgEl) return;
      if (imgEl.contains(e.relatedTarget)) return;

      // When LiveView patches the DOM, morphdom removes the old element and inserts
      // a new one. This fires mouseout with relatedTarget === null (element removed,
      // not mouse moving). In that case, keep the preview — the card is still there,
      // just replaced. A real mouseout (user moved mouse) will have a relatedTarget.
      if (!e.relatedTarget) return;

      // Real mouseout — check if we're moving to another card-img element
      const nextCardImg = e.relatedTarget.closest("[data-card-img]");
      if (nextCardImg) return;

      // Moving to non-card area — hide preview
      if (this.panel) this.panel.style.display = "none";
    };

    this.el.addEventListener("mouseover", this.onOver);
    this.el.addEventListener("mouseout", this.onOut);
  },

  updated() {
    // Preview stays as-is through DOM patches. The mouseout handler ignores
    // patch-triggered mouseouts (relatedTarget === null), so nothing to do here.
  },

  destroyed() {
    this.el.removeEventListener("mouseover", this.onOver);
    this.el.removeEventListener("mouseout", this.onOut);
    if (this.panel) this.panel.style.display = "none";
  }
};

export default CardPreview;
