document.addEventListener("DOMContentLoaded", () => {
  const urlParams = new URLSearchParams(window.location.search);
  const isEmbedded = urlParams.get("embedded") === "true";

  if (!isEmbedded) return;

  // Nascondi footer
  document.querySelector("footer")?.setAttribute("hidden", true);
  document.querySelector("header")?.setAttribute("hidden", true);

 const searchElement = document.querySelector(".main-bar__search");
const container = document.querySelector("#home__menu .home__menu__container");

if (searchElement && container) {
  container.appendChild(searchElement);
  
  // Aggiungi padding e border radius
  searchElement.style.cssText = `
    margin: 1em
    border-radius: 6px;
  `;
  
  // Trova e stilizza l'icona di ricerca
  const searchIcon = searchElement.querySelector('svg, .icon, [class*="icon"], [class*="search"]');
  if (searchIcon) {
    searchIcon.style.cssText = `
      color: white;
      fill: white;
    `;
  }
}
 window.addEventListener("message", (event) => {

  const token = event.data?.accessToken;
  if (!token) {
    console.warn("Token non ricevuto:", event.data);
    return;
  }


  

  alert("Token ricevuto: " + token);

  if (!sessionStorage.getItem("embedded_logged_in")) {
    fetch("/keycloak_token_login", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": document.querySelector("[name='csrf-token']")?.content || "",
      },
      credentials: "include",
      body: JSON.stringify({ token }),
    })
      .then(res => res.text())
      .then(text => {
        if (text.includes("success")) {
          sessionStorage.setItem("embedded_logged_in", "true");
          window.location.reload();
        }
      })
      .catch(console.error);
  }
});

});
