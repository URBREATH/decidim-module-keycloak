document.addEventListener("DOMContentLoaded", () => {
  const urlParams = new URLSearchParams(window.location.search);
  let isEmbedded = urlParams.get("embedded") === "true";

  if (isEmbedded) applyEmbeddedStyles();

  function applyEmbeddedStyles() {
    document.querySelector("footer")?.setAttribute("hidden", true);
    document.querySelector("header")?.setAttribute("hidden", true);

    const searchElement = document.querySelector(".main-bar__search");
    const container = document.querySelector("#home__menu.home__menu");
    const searchInput = searchElement.querySelector("input#input-search");

    container.appendChild(searchElement);

    searchInput.style.borderRadius = "6px";
    searchInput.style.padding = "5px";

    container.style.gap = "1em";
    container.style.display = "flex";
    container.style.flexDirection = "column";
    container.style.justifyContent = "center";
    container.style.alignItems = "center";

    searchElement.style.borderRadius = "6px";

    const searchIcon = searchElement.querySelector('svg, .icon, [class*="icon"], [class*="search"]');
    if (searchIcon) {
      searchIcon.style.color = "white";
      searchIcon.style.fill = "white";
    }
  }

  window.addEventListener("message", (event) => {
    const { accessToken: token, refreshToken, language, embedded } = event.data || {};

    if (embedded) {
      isEmbedded = true;
      applyEmbeddedStyles();
    }

    if (!token) {
      console.warn("Token non ricevuto:", event.data);
      return;
    }

    const url = new URL(window.location.href);
    const params = url.searchParams;
    let reloadNeeded = false;

    if (language && params.get("locale") !== language) {
      params.set("locale", language);
      reloadNeeded = true;
    }

    if (isEmbedded && params.get("embedded") !== "true") {
      params.set("embedded", "true");
      reloadNeeded = true;
    }

    if (reloadNeeded) {
      const newUrl = `${url.pathname}?${params.toString()}`;
      window.location.href = newUrl;
      return;
    }

    alert("Token ricevuto: " + token);
    if (refreshToken) alert("Refresh token ricevuto: " + refreshToken);

    function loginWithToken(tkn) {
      return fetch("/keycloak_token_login", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector("[name='csrf-token']")?.content || "",
        },
        credentials: "include",
        body: JSON.stringify({ token: tkn }),
      }).then(res => res.text());
    }

    if (!sessionStorage.getItem("embedded_logged_in")) {
      loginWithToken(token)
        .then(text => {
          if (text.includes("success")) {
            sessionStorage.setItem("embedded_logged_in", "true");

            if (refreshToken) {
              setTimeout(() => {
                loginWithToken(refreshToken).catch(console.error);
              }, 55 * 60 * 1000);
            }

            window.location.reload();
          }
        })
        .catch(console.error);
    }
  });
});
