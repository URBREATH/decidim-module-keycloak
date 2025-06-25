// Images
require.context("../../images", true)


document.addEventListener("DOMContentLoaded", () => {

const embeddedToken = "eyJhbGciOiJSUzI1NiIsInR5cCIgOiAiSldUIiwia2lkIiA6ICJOQjlvc3hpb1hqNGdlRmdBdW5wUGNqT2JTZlZYbmtNMDZiUjRzS0x0UXBvIn0.eyJleHAiOjE3NTA4NTg4ODMsImlhdCI6MTc1MDg1ODU4MywianRpIjoiNjIzZWQzM2EtYTUzYS00MzliLWIzOWItNjgwYTczY2MzM2U0IiwiaXNzIjoiaHR0cHM6Ly9rZXljbG9hay1kZXYudXJicmVhdGgudGVjaC9hdXRoL3JlYWxtcy9kZWNpZGltIiwiYXVkIjoiYWNjb3VudCIsInN1YiI6IjcyODViOTEwLTBhMGYtNDY3Yy1hZmY5LTdiMGY3Y2UyZDliOCIsInR5cCI6IkJlYXJlciIsImF6cCI6ImRlY2lkaW1fZGV2Iiwic2Vzc2lvbl9zdGF0ZSI6IjE5ODJhNDhiLTNmMTUtNDJiZi1iMDM1LTM2MTJiOTdlNzdhYSIsImFjciI6IjEiLCJhbGxvd2VkLW9yaWdpbnMiOlsiKiJdLCJyZWFsbV9hY2Nlc3MiOnsicm9sZXMiOlsib2ZmbGluZV9hY2Nlc3MiLCJkZWZhdWx0LXJvbGVzLWRlY2lkaW0iLCJ1bWFfYXV0aG9yaXphdGlvbiJdfSwicmVzb3VyY2VfYWNjZXNzIjp7ImFjY291bnQiOnsicm9sZXMiOlsibWFuYWdlLWFjY291bnQiLCJtYW5hZ2UtYWNjb3VudC1saW5rcyIsInZpZXctcHJvZmlsZSJdfX0sInNjb3BlIjoicHJvZmlsZSBlbWFpbCIsInNpZCI6IjE5ODJhNDhiLTNmMTUtNDJiZi1iMDM1LTM2MTJiOTdlNzdhYSIsImVtYWlsX3ZlcmlmaWVkIjpmYWxzZSwibmFtZSI6IkRhbmllbGUgTm90byIsInByZWZlcnJlZF91c2VybmFtZSI6ImRhbmllbGUubm90b0BvdXRsb29rLmNvbSIsImdpdmVuX25hbWUiOiJEYW5pZWxlIiwiZmFtaWx5X25hbWUiOiJOb3RvIiwiZW1haWwiOiJkYW5pZWxlLm5vdG9Ab3V0bG9vay5jb20ifQ.FGT2nVI64-7VVHkhdU8a3Gu3Jhb2og-MbLCGEov5lMFrg61L7gH8h6SCbtb9PW7dg-Mz2cjn_oWLEhJW_IPP7nsHd6z3PXY0mAqohPIu7xrgz5wm9X-byX0LcUl7bZOT8nJHKmqgx3MM7JZ6N8Dkk0GK8LZfK9G9sk-53ajtFadDQUfOm2mnQIPj3f_XJQ7Ur93sTeketrzbAMzfDoTAdYIvsM3Cy9Ia9fmPHWGcb4cz8JoLgwHcqcrFhFJnALTmCbSG5QhT1HAVNLU3UjmpMB1RlCy64uTkv-ivZL6Kl9-f5Yjbe8lsAWxQskdulAka0BjzyY7WEFutPEpWC0Uqfg";

const urlParams = new URLSearchParams(window.location.search);
const isEmbedded = urlParams.get("embedded") === "true";


if (isEmbedded) {

    document.querySelector("footer")?.setAttribute("hidden", true);

  if (!sessionStorage.getItem("embedded_logged_in")) {
    fetch("/keycloak_token_login", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": document.querySelector("[name='csrf-token']").content,
      },
      body: JSON.stringify({ token: embeddedToken }),
    })
      .then(res => res.text())
      .then(text => {
        if (text.includes("success")) {
          sessionStorage.setItem("embedded_logged_in", "true");
          window.location.reload(); // ricarica normale, senza parametri
        }
      })
      .catch(e => console.error(e));
  } else {
    // Loggato, nessun reload
    // eventualmente nascondi elementi, ecc.
  }
}
});
          
