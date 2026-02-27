const CopyToClipboard = {
  mounted() {
    this.el.addEventListener("click", () => {
      const text = this.el.dataset.copyText;
      if (!text) return;

      navigator.clipboard.writeText(text).then(() => {
        const original = this.el.textContent;
        this.el.textContent = "Copied!";
        setTimeout(() => {
          this.el.textContent = original;
        }, 2000);
      }).catch(() => {
        // Fallback for older browsers
        const ta = document.createElement("textarea");
        ta.value = text;
        ta.style.position = "fixed";
        ta.style.opacity = "0";
        document.body.appendChild(ta);
        ta.select();
        document.execCommand("copy");
        document.body.removeChild(ta);

        const original = this.el.textContent;
        this.el.textContent = "Copied!";
        setTimeout(() => {
          this.el.textContent = original;
        }, 2000);
      });
    });
  }
};

export default CopyToClipboard;
