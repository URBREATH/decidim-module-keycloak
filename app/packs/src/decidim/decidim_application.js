alert("test js compiler")

window.addEventListener("message", (event) => {
  console.log("Messaggio ricevuto:", event.data, "da:", event.origin);

  if (event.data && event.data.embedded === true) {
    // Applica l'embedding
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
  }
});
