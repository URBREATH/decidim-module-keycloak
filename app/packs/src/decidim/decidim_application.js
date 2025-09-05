document.addEventListener("DOMContentLoaded", () => {
  const EMBEDDED_KEY = "embedded_logged_in";
  const url = new URL(window.location.href);
  const urlParams = url.searchParams;
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

  const loginWithToken = (token) =>
    fetch("/keycloak_token_login", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": document.querySelector("[name='csrf-token']")?.content || "",
      },
      credentials: "include",
      body: JSON.stringify({ token }),
    }).then(res => res.text());

  const handleEmbedded = (embeddedFlag) => {
    if (embeddedFlag && !isEmbedded) {
      isEmbedded = true;
      sessionStorage.setItem(EMBEDDED_KEY, "true");

      // aspetta che gli elementi siano renderizzati
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

  // Controlla query param
  handleEmbedded(urlParams.get("embedded") === "true");

  // Listener postMessage
  const handleMessage = (event) => {
    const allowedOrigin = "https://dashboard-dev.urbreath.tech/tools/e-participation"; // sostituisci con il dominio autorizzato
    if (event.origin !== allowedOrigin) return;

    const { embedded, language, accessToken, refreshToken } = event.data || {};

    handleEmbedded(embedded);

    if (language && urlParams.get("locale") !== language) {
      urlParams.set("locale", language);
      window.history.replaceState(null, "", `${window.location.pathname}?${urlParams}`);
    }

    if (accessToken && !sessionStorage.getItem(EMBEDDED_KEY)) {
      loginWithToken(accessToken)
        .then(text => {
          if (text.includes("success")) {
            sessionStorage.setItem(EMBEDDED_KEY, "true");

            if (refreshToken) {
              setTimeout(() => loginWithToken(refreshToken).catch(console.error), 55 * 60 * 1000);
            }
          }
        })
        .catch(console.error);
    }
  };

  window.addEventListener("message", handleMessage);
  window.addEventListener("beforeunload", () => window.removeEventListener("message", handleMessage));
});
