const api = typeof browser !== "undefined" ? browser : chrome;
const show = document.getElementById("show");
const status = document.getElementById("status");

api.storage.local.get({ showButton: true }).then((value) => { show.checked = value.showButton !== false; });
show.addEventListener("change", () => api.storage.local.set({ showButton: show.checked }));

document.getElementById("float").addEventListener("click", async () => {
  try {
    const [tab] = await api.tabs.query({ active: true, currentWindow: true });
    const reply = await api.tabs.sendMessage(tab.id, { type: "cod-float-largest" });
    if (reply && reply.found) { window.close(); return; }
    status.textContent = "No video found on this page.";
  } catch (_) {
    status.textContent = "Allow this extension on this website in Safari, then try again.";
  }
});
