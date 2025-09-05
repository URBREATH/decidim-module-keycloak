document.addEventListener("DOMContentLoaded", () => {
  const EMBEDDED_KEY = "embedded_logged_in";
  let isEmbedded = false;

  const applyEmbeddedStyles = () => {
    const footer = document.querySelector("footer");
    const header = document.querySelector("header");
    if (footer) footer.hidden = true;
    if (header) header.hidden = true;

    const searchElement = document.querySelector(".main-bar__search");
    const container = document.querySelector("#home__menu.home__menu");
    const searchInput = searchElement?.querySelector("input#input-search");

    if (searchElement && container) {
      container.appendChild(searchElement);

      if (searchInput) {
        searchInput.style.borderRadius = "6px";
        searchInput.style.padding = "5px";
      }

      container.style.cssText = "gap:1em;display:flex;flex-direction:column;justify-content:center;align-items:center;";
      searchElement.style.borderRadius = "6px";

      const searchIcon = searchElement.querySelector('svg, .icon, [class*="icon"], [class*="search"]');
      if (searchIcon) searchIcon.style.fill = "white";
    }
  };

  const handleEmbedded = (embeddedFlag) => {
    if (embeddedFlag && !isEmbedded) {
      isEmbedded = true;

      // applica stili quando il DOM è pronto
      const observer = new MutationObserver(() => {
        if (document.querySelector("#home__menu.home__menu")) {
          applyEmbeddedStyles();
          observer.disconnect();
        }
      });
      observer.observe(document.body, { childList: true, subtree: true });

      // prova ad applicare subito
      applyEmbeddedStyles();
    }
  };

  // usa lo stesso check della tua collega (postMessage o altro meccanismo interno)
  const handleMessage = (event) => {
    const { embedded } = event.data || {};
    handleEmbedded(embedded);
  };

  window.addEventListener("message", handleMessage);
  window.addEventListener("beforeunload", () => window.removeEventListener("message", handleMessage));
});
