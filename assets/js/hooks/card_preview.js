const CardPreview = {
  mounted() {
    this.panel = document.getElementById("card-preview-panel");
    this.img = document.getElementById("card-preview-img");
    this.currentSrc = null;

    this.onOver = (e) => {
      const el = e.target.closest("[data-card-img]");
      if (!el) return;
      const src = el.dataset.cardImg;
      if (!src || !this.panel || !this.img) return;

      this.currentSrc = src;
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
      if (!e.target.closest("[data-card-img]")) return;
      this.currentSrc = null;
      if (this.panel) this.panel.style.display = "none";
    };

    this.el.addEventListener("mouseover", this.onOver);
    this.el.addEventListener("mouseout", this.onOut);
  },

  updated() {
    // After a LiveView patch, the hovered card may have disappeared (e.g. search
    // results changed while mouse was hovering). Hide preview if its card is gone.
    if (!this.currentSrc || !this.panel) return;
    const still_present = this.el.querySelector(`[data-card-img="${this.currentSrc}"]`);
    if (!still_present) {
      this.currentSrc = null;
      this.panel.style.display = "none";
    }
  },

  destroyed() {
    this.el.removeEventListener("mouseover", this.onOver);
    this.el.removeEventListener("mouseout", this.onOut);
    if (this.panel) this.panel.style.display = "none";
  }
};

export default CardPreview;
