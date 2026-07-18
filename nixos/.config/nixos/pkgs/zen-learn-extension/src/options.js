// Load saved settings
browser.storage.local
  .get({
    defaultAction: "claude",
    ollamaHost: "http://server.matthandzel.com:11434",
    ollamaModel: "gemma3:12b-it-qat",
    kmsCapture: true,
    kmsHost: "http://localhost:5391",
    ttsHost: "http://100.118.206.104:47773",
    ttsVoice: "en_US-lessac-high",
    ttsSpeed: 0.95,
    ttsHighlight: true,
  })
  .then((settings) => {
    document.getElementById("defaultAction").value = settings.defaultAction;
    document.getElementById("ollamaHost").value = settings.ollamaHost;
    document.getElementById("ollamaModel").value = settings.ollamaModel;
    document.getElementById("kmsCapture").checked = settings.kmsCapture;
    document.getElementById("kmsHost").value = settings.kmsHost;
    document.getElementById("ttsHost").value = settings.ttsHost;
    document.getElementById("ttsVoice").value = settings.ttsVoice;
    document.getElementById("ttsSpeed").value = settings.ttsSpeed;
    document.getElementById("ttsHighlight").checked = settings.ttsHighlight;
  });

// Auto-save on change
for (const id of [
  "defaultAction",
  "ollamaHost",
  "ollamaModel",
  "kmsCapture",
  "kmsHost",
  "ttsHost",
  "ttsVoice",
  "ttsSpeed",
  "ttsHighlight",
]) {
  document.getElementById(id).addEventListener("change", save);
  document.getElementById(id).addEventListener("input", save);
}

function save() {
  const settings = {
    defaultAction: document.getElementById("defaultAction").value,
    ollamaHost: document.getElementById("ollamaHost").value,
    ollamaModel: document.getElementById("ollamaModel").value,
    kmsCapture: document.getElementById("kmsCapture").checked,
    kmsHost: document.getElementById("kmsHost").value,
    ttsHost: document.getElementById("ttsHost").value,
    ttsVoice: document.getElementById("ttsVoice").value,
    ttsSpeed: parseFloat(document.getElementById("ttsSpeed").value) || 0.95,
    ttsHighlight: document.getElementById("ttsHighlight").checked,
  };
  browser.storage.local.set(settings).then(() => {
    const msg = document.getElementById("savedMsg");
    msg.classList.add("show");
    setTimeout(() => msg.classList.remove("show"), 1500);
  });
}
