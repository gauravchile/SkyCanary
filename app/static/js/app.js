document.getElementById("start-rollout").addEventListener("click", () => {
  const log = document.getElementById("log");
  const progress = document.getElementById("progress");
  log.innerHTML += "Starting canary rollout...<br>";

  const source = new EventSource("/api/stream");
  source.onmessage = (event) => {
    const data = JSON.parse(event.data);
    const step = data.step;
    progress.style.width = step + "%";
    document.getElementById("weights").innerHTML = 
      `Stable: ${data.weights.stable}% | Canary: ${data.weights.canary}%`;
    log.innerHTML += `→ Canary rollout: ${step}%<br>`;
    log.scrollTop = log.scrollHeight;
    if (step === 100) {
      log.innerHTML += "✅ Rollout complete!<br>";
      source.close();
    }
  };
});
