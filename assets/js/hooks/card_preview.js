const CardPreview = {
  mounted() {
    this.panel = document.getElementById("card-preview-panel");
    this.img = document.getElementById("card-preview-img");
    this._previewSrc = null;

    // Drive preview entirely from mousemove — immune to morphdom patches
    // because we just check what's under the cursor right now.
    this.onMove = (e) => {
      const el = document.elementFromPoint(e.clientX, e.clientY);
      if (!el) { this._hidePreview(); return; }
      const cardImg = el.closest("[data-card-img]");
      if (cardImg && cardImg.dataset.cardImg) {
        const src = cardImg.dataset.cardImg;
        if (src !== this._previewSrc) {
          this._previewSrc = src;
          this.img.src = src;
          const rect = cardImg.getBoundingClientRect();
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
        }
      } else if (this._previewSrc) {
        this._hidePreview();
      }
    };

    this.el.addEventListener("mousemove", this.onMove);
  },

  _hidePreview() {
    this._previewSrc = null;
    if (this.panel) this.panel.style.display = "none";
  },

  destroyed() {
    this.el.removeEventListener("mousemove", this.onMove);
    this._hidePreview();
  }
};

export default CardPreview;
