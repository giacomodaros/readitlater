const APP_ORIGIN = "https://readitlater-theta.vercel.app";
const API_URL = `${APP_ORIGIN}/api/articles`;
const extensionAPI = globalThis.browser ?? globalThis.chrome;

const urlDisplay = document.getElementById("url-display");
const saveBtn = document.getElementById("save-btn");
const status = document.getElementById("status");
const openLink = document.getElementById("open-link");

openLink.href = APP_ORIGIN;

function showStatus(type, message) {
  status.className = "status " + type;
  status.textContent = message;
}

async function getCurrentTab() {
  const [tab] = await extensionAPI.tabs.query({ active: true, currentWindow: true });
  return tab;
}

async function getPageHtml(tabId) {
  const results = await extensionAPI.scripting.executeScript({
    target: { tabId },
    func: () => document.documentElement.outerHTML,
  });
  return results?.[0]?.result ?? null;
}

async function init() {
  const tab = await getCurrentTab();
  const url = tab.url ?? "";

  urlDisplay.textContent = url;
  urlDisplay.title = url;

  // Disable on non-http pages
  if (!url.startsWith("http")) {
    saveBtn.disabled = true;
    showStatus("error", "Not a web page.");
    return;
  }

  saveBtn.addEventListener("click", async () => {
    saveBtn.disabled = true;
    saveBtn.textContent = "Saving...";
    status.className = "status";

    try {
      const html = await getPageHtml(tab.id);

      const res = await fetch(API_URL, {
        method: "POST",
        credentials: "include",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ url, html }),
      });

      const data = await res.json();

      if (res.status === 201) {
        showStatus("success", "Saved");
        saveBtn.textContent = "Saved";
      } else if (res.ok) {
        // 200 = already existed
        showStatus("already", "Already saved");
        saveBtn.textContent = "Already saved";
      } else if (res.status === 401) {
        showStatus("error", "Sign in first");
        saveBtn.textContent = "Sign in required";
        openLink.href = `${APP_ORIGIN}/login`;
      } else {
        throw new Error(data.error || "Failed to save");
      }
    } catch (e) {
      showStatus("error", e.message || "Something went wrong");
      saveBtn.disabled = false;
      saveBtn.textContent = "Save article";
    }
  });
}

init();
