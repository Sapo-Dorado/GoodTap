const CardPreview = {
  mounted() {
    this.panel = document.getElementById("card-preview-panel");
    this.img = document.getElementById("card-preview-img");
    this._previewSrc = null;
    this._lastMouseX = 0;
    this._lastMouseY = 0;
    this._hideRaf = null;

    this.onMove = (e) => {
      this._lastMouseX = e.clientX;
      this._lastMouseY = e.clientY;
    };

    this.onOver = (e) => {
      const el = e.target.closest("[data-card-img]");
      if (!el) return;
      const src = el.dataset.cardImg;
      if (!src || !this.panel || !this.img) return;

      // Cancel any pending hide — we're on a card
      if (this._hideRaf) {
        cancelAnimationFrame(this._hideRaf);
        this._hideRaf = null;
      }

      this._previewSrc = src;
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
      // Defer check — LiveView patches replace elements, triggering mouseout
      // before new elements are laid out
      if (this._hideRaf) cancelAnimationFrame(this._hideRaf);
      this._hideRaf = requestAnimationFrame(() => {
        this._hideRaf = null;
        this._recheckPreview();
      });
    };

    this.el.addEventListener("mouseover", this.onOver);
    this.el.addEventListener("mouseout", this.onOut);
    document.addEventListener("mousemove", this.onMove);
  },

  _recheckPreview() {
    const elUnder = document.elementFromPoint(this._lastMouseX, this._lastMouseY);
    const cardImgUnder = elUnder && elUnder.closest("[data-card-img]");
    if (cardImgUnder && cardImgUnder.dataset.cardImg) {
      const newSrc = cardImgUnder.dataset.cardImg;
      if (newSrc !== this._previewSrc) {
        this._previewSrc = newSrc;
        if (this.img) this.img.src = newSrc;
      }
    } else {
      this._previewSrc = null;
      if (this.panel) this.panel.style.display = "none";
    }
  },

  updated() {
    // After a LiveView patch, re-check preview after browser layout
    if (this._previewSrc) {
      if (this._hideRaf) cancelAnimationFrame(this._hideRaf);
      this._hideRaf = requestAnimationFrame(() => {
        this._hideRaf = null;
        this._recheckPreview();
      });
    }
  },

  destroyed() {
    this.el.removeEventListener("mouseover", this.onOver);
    this.el.removeEventListener("mouseout", this.onOut);
    document.removeEventListener("mousemove", this.onMove);
    if (this._hideRaf) cancelAnimationFrame(this._hideRaf);
    this._previewSrc = null;
    if (this.panel) this.panel.style.display = "none";
  }
};

export default CardPreview;
