document.addEventListener("DOMContentLoaded", () => {
  const urlParams = new URLSearchParams(window.location.search);
  const isEmbedded = urlParams.get("embedded") === "true";

  if (!isEmbedded) return;

  // Nascondi footer
  document.querySelector("footer")?.setAttribute("hidden", true);
  document.querySelector("header")?.setAttribute("hidden", true);

  window.addEventListener("message", (event) => {
    if (event.origin !== "http://localhost:8080") return;

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
