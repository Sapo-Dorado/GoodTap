const CardPreview = {
  mounted() {
    this.panel = document.getElementById("card-preview-panel");
    this.img = document.getElementById("card-preview-img");
    this._previewSrc = null;
    this._lastMouseX = 0;
    this._lastMouseY = 0;

    this.onMove = (e) => {
      this._lastMouseX = e.clientX;
      this._lastMouseY = e.clientY;
    };

    this.onOver = (e) => {
      const el = e.target.closest("[data-card-img]");
      if (!el) return;
      const src = el.dataset.cardImg;
      if (!src || !this.panel || !this.img) return;

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
      // Check what's actually under the cursor — DOM patches can trigger
      // mouseout even though the mouse hasn't moved
      const elUnder = document.elementFromPoint(this._lastMouseX, this._lastMouseY);
      const cardImgUnder = elUnder && elUnder.closest("[data-card-img]");
      if (cardImgUnder && cardImgUnder.dataset.cardImg) {
        // Still over a card — keep preview, update if src changed
        if (cardImgUnder.dataset.cardImg !== this._previewSrc) {
          this._previewSrc = cardImgUnder.dataset.cardImg;
          this.img.src = this._previewSrc;
        }
      } else {
        this._previewSrc = null;
        if (this.panel) this.panel.style.display = "none";
      }
    };

    this.el.addEventListener("mouseover", this.onOver);
    this.el.addEventListener("mouseout", this.onOut);
    document.addEventListener("mousemove", this.onMove);
  },

  updated() {
    // After a LiveView patch, re-check if cursor is still over a card
    if (this._previewSrc && this.panel) {
      const elUnder = document.elementFromPoint(this._lastMouseX, this._lastMouseY);
      const cardImgUnder = elUnder && elUnder.closest("[data-card-img]");
      if (cardImgUnder && cardImgUnder.dataset.cardImg) {
        const newSrc = cardImgUnder.dataset.cardImg;
        if (newSrc !== this._previewSrc) {
          this._previewSrc = newSrc;
          this.img.src = newSrc;
        }
      } else {
        this._previewSrc = null;
        this.panel.style.display = "none";
      }
    }
  },

  destroyed() {
    this.el.removeEventListener("mouseover", this.onOver);
    this.el.removeEventListener("mouseout", this.onOut);
    document.removeEventListener("mousemove", this.onMove);
    this._previewSrc = null;
    if (this.panel) this.panel.style.display = "none";
  }
};

export default CardPreview;
