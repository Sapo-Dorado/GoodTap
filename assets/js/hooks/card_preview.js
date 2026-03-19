const CardPreview = {
  mounted() {
    this.panel = document.getElementById("card-preview-panel");
    this.img = document.getElementById("card-preview-img");
    this._previewSrc = null;
    this._previewHideRaf = null;
    this._lastMouseX = 0;
    this._lastMouseY = 0;

    this._onMouseMove = (e) => {
      this._lastMouseX = e.clientX;
      this._lastMouseY = e.clientY;
    };
    document.addEventListener("mousemove", this._onMouseMove);

    this.onOver = (e) => {
      const el = e.target.closest("[data-card-img]");
      if (!el) return;
      const src = el.dataset.cardImg;
      if (!src || !this.panel || !this.img) return;

      if (this._previewHideRaf) {
        cancelAnimationFrame(this._previewHideRaf);
        this._previewHideRaf = null;
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
      const imgEl = e.target.closest("[data-card-img]");
      if (!imgEl) return;
      if (imgEl.contains(e.relatedTarget)) return;

      // Schedule a deferred hide. If this mouseout was triggered by a LiveView
      // patch (morphdom), updated() will fire before the next paint and cancel it.
      if (this._previewSrc) {
        if (this._previewHideRaf) cancelAnimationFrame(this._previewHideRaf);
        this._previewHideRaf = requestAnimationFrame(() => {
          this._previewHideRaf = null;
          this._recheckPreview();
        });
      }
    };

    this.el.addEventListener("mouseover", this.onOver);
    this.el.addEventListener("mouseout", this.onOut);
  },

  updated() {
    // A patch just happened. If we had a preview showing, cancel any pending
    // hide from mouseout (likely patch-triggered) and re-verify with elementFromPoint.
    if (this._previewSrc) {
      if (this._previewHideRaf) {
        cancelAnimationFrame(this._previewHideRaf);
        this._previewHideRaf = null;
      }
      this._recheckPreview();
    }
  },

  _recheckPreview() {
    const el = document.elementFromPoint(this._lastMouseX, this._lastMouseY);
    const cardImg = el && el.closest("[data-card-img]");
    if (cardImg && cardImg.dataset.cardImg) {
      const src = cardImg.dataset.cardImg;
      if (src !== this._previewSrc) {
        // Card changed (e.g. mouse moved to different card) — update preview
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
      // else: same image, preview already correct
    } else {
      this._previewSrc = null;
      if (this.panel) this.panel.style.display = "none";
    }
  },

  destroyed() {
    this.el.removeEventListener("mouseover", this.onOver);
    this.el.removeEventListener("mouseout", this.onOut);
    document.removeEventListener("mousemove", this._onMouseMove);
    if (this._previewHideRaf) cancelAnimationFrame(this._previewHideRaf);
    this._previewSrc = null;
    if (this.panel) this.panel.style.display = "none";
  }
};

export default CardPreview;
