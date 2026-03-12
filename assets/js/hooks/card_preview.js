const CardPreview = {
  mounted() {
    this.panel = document.getElementById("card-preview-panel");
    this.img = document.getElementById("card-preview-img");
    this.currentEl = null;
    this.currentSrc = null;

    this.onOver = (e) => {
      const el = e.target.closest("[data-card-img]");
      if (!el) return;
      const src = el.dataset.cardImg;
      if (!src || !this.panel || !this.img) return;

      this.currentEl = el;
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
      this.currentEl = null;
      this.currentSrc = null;
      if (this.panel) this.panel.style.display = "none";
    };

    this.el.addEventListener("mouseover", this.onOver);
    this.el.addEventListener("mouseout", this.onOut);
  },

  updated() {
    // After a LiveView patch, hide preview only if the specific hovered element
    // is gone from the DOM (e.g. search results changed). Don't hide if the element
    // still exists — opponent actions should not interrupt your hover preview.
    if (!this.currentEl || !this.panel) return;
    if (!document.contains(this.currentEl)) {
      this.currentEl = null;
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
