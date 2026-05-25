const API_URL = "https://readlater-pi.vercel.app/api/articles";

const urlDisplay = document.getElementById("url-display");
const saveBtn = document.getElementById("save-btn");
const status = document.getElementById("status");

function showStatus(type, message) {
  status.className = "status " + type;
  status.textContent = message;
}

async function getCurrentTab() {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  return tab;
}

async function getPageHtml(tabId) {
  const results = await chrome.scripting.executeScript({
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
        showStatus("success", "✓ Saved to Reader");
        saveBtn.textContent = "Saved";
      } else if (res.ok) {
        // 200 = already existed
        showStatus("already", "Already in your Reader");
        saveBtn.textContent = "Already saved";
      } else if (res.status === 401) {
        showStatus("error", "Sign in to Reader first");
        saveBtn.textContent = "Sign in required";
      } else {
        throw new Error(data.error || "Failed to save");
      }
    } catch (e) {
      showStatus("error", e.message || "Something went wrong");
      saveBtn.disabled = false;
      saveBtn.textContent = "Save to Reader";
    }
  });
}

init();
