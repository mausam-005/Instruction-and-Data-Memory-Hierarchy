const elements = {
  select: document.querySelector("#simulation-select"),
  description: document.querySelector("#simulation-description"),
  target: document.querySelector("#make-target"),
  run: document.querySelector("#run-button"),
  status: document.querySelector("#run-status"),
  badge: document.querySelector("#result-badge"),
  summary: document.querySelector("#result-summary"),
  output: document.querySelector("#simulation-output"),
  loadWave: document.querySelector("#load-waveform"),
  downloadWave: document.querySelector("#download-waveform"),
  waveEmpty: document.querySelector("#wave-empty"),
  waveContent: document.querySelector("#wave-content"),
  signalList: document.querySelector("#signal-list"),
  signalCount: document.querySelector("#signal-count"),
  waveInfo: document.querySelector("#wave-info"),
  waveChart: document.querySelector("#wave-chart"),
};

const svgNamespace = "http://www.w3.org/2000/svg";
let simulations = [];
let currentWaveform = null;
let selectedSignals = new Set();
let waveformId = "";

function currentSimulation() {
  return simulations.find((simulation) => simulation.id === elements.select.value);
}

async function loadSimulations() {
  const response = await fetch("/api/simulations");
  if (!response.ok) throw new Error("Could not load simulation targets.");
  const data = await response.json();
  simulations = data.simulations;
  elements.select.replaceChildren();

  for (const simulation of simulations) {
    const option = document.createElement("option");
    option.value = simulation.id;
    option.textContent = simulation.name;
    elements.select.append(option);
  }

  elements.select.disabled = false;
  elements.run.disabled = false;
  elements.loadWave.disabled = false;
  elements.select.addEventListener("change", updateSelectedSimulation);
  updateSelectedSimulation();
}

function updateSelectedSimulation() {
  const simulation = currentSimulation();
  if (!simulation) return;
  elements.description.textContent = simulation.description;
  elements.target.textContent = `make ${simulation.target}`;
  elements.downloadWave.href = `/api/waveform?id=${encodeURIComponent(simulation.id)}&download=1`;
  elements.downloadWave.classList.toggle("disabled-link", !simulation.waveform_available);
  elements.downloadWave.setAttribute("aria-disabled", String(!simulation.waveform_available));
  if (!simulation.waveform_available) {
    elements.loadWave.disabled = true;
    showEmptyWave("No waveform loaded", "Run this simulation to generate its VCD trace.");
  } else {
    elements.loadWave.disabled = false;
    showEmptyWave("Waveform available", "Load the existing VCD trace to inspect its signals.");
  }
}

function showEmptyWave(title, message) {
  elements.waveContent.hidden = true;
  elements.waveEmpty.hidden = false;
  elements.waveEmpty.querySelector("strong").textContent = title;
  elements.waveEmpty.querySelector("span").textContent = message;
}

function setRunState(kind, text) {
  elements.status.className = `run-status ${kind ? `status-${kind}` : ""}`;
  elements.status.textContent = text;
}

function setResultBadge(kind, text) {
  elements.badge.className = `tag ${kind ? `tag-${kind}` : "tag-neutral"}`;
  elements.badge.textContent = text;
}

function showRunOutput(data, httpOk) {
  const passed = httpOk && data.passed === true;
  const title = passed ? "Simulation passed" : "Simulation failed";
  const details = data.error || `${data.name || "Simulation"} · ${data.duration_seconds ?? "—"} s`;
  elements.summary.querySelector("span:last-child").textContent = `${title} — ${details}`;
  elements.output.textContent = data.output || data.error || "No output was produced.";
  elements.output.className = `simulation-output ${passed ? "output-passed" : "output-failed"}`;
  setResultBadge(passed ? "success" : "failure", passed ? "PASS" : "FAIL");
  setRunState(passed ? "passed" : "failed", passed ? "Completed" : "Check output");
}

async function runSimulation() {
  const simulation = currentSimulation();
  if (!simulation) return;
  elements.run.disabled = true;
  elements.select.disabled = true;
  elements.run.querySelector("span:last-child").textContent = "Running...";
  setRunState("running", "Compiling and simulating");
  setResultBadge("", "RUNNING");
  elements.output.textContent = `Running make ${simulation.target}...\nThis can take a few seconds.`;
  elements.output.className = "simulation-output";

  try {
    const response = await fetch("/api/run", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ id: simulation.id }),
    });
    const data = await response.json();
    showRunOutput(data, response.ok);

    const index = simulations.findIndex((entry) => entry.id === simulation.id);
    if (index >= 0 && data.waveform_available) simulations[index].waveform_available = true;
    updateSelectedSimulation();
    if (data.waveform_available) await loadWaveform(simulation.id);
  } catch (error) {
    showRunOutput({ error: error.message, passed: false }, false);
  } finally {
    elements.run.disabled = false;
    elements.select.disabled = false;
    elements.run.querySelector("span:last-child").textContent = "Run simulation";
  }
}

function parseVcd(source) {
  const lines = source.split(/\r?\n/);
  const scope = [];
  const variables = [];
  const aliases = new Map();
  let dataStart = 0;

  for (let index = 0; index < lines.length; index += 1) {
    const line = lines[index].trim();
    if (line.startsWith("$scope ")) {
      const match = line.match(/^\$scope\s+\S+\s+(\S+)/);
      if (match) scope.push(match[1]);
    } else if (line.startsWith("$upscope")) {
      scope.pop();
    } else if (line.startsWith("$var ")) {
      const match = line.match(/^\$var\s+(\S+)\s+(\d+)\s+(\S+)\s+(.+?)\s+\$end$/);
      if (match) {
        const [, type, width, id, reference] = match;
        if (type !== "parameter") {
          const variable = {
            id,
            width: Number(width),
            name: [...scope, reference.trim().split(/\s+/)[0]].join("."),
            scopeDepth: scope.length,
          };
          variables.push(variable);
          if (!aliases.has(id)) aliases.set(id, []);
          aliases.get(id).push(variable);
        }
      }
    } else if (line.startsWith("$enddefinitions")) {
      dataStart = index + 1;
      break;
    }
  }

  const scaleMatch = source.match(/\$timescale\s+([\s\S]*?)\s+\$end/);
  const timescale = scaleMatch ? scaleMatch[1].trim().replace(/\s+/g, " ") : "ticks";
  const histories = new Map();
  let time = 0;
  let endTime = 0;

  for (let index = dataStart; index < lines.length; index += 1) {
    const line = lines[index].trim();
    if (!line) continue;
    if (line[0] === "#") {
      const nextTime = Number(line.slice(1));
      if (Number.isFinite(nextTime)) {
        time = nextTime;
        endTime = Math.max(endTime, time);
      }
      continue;
    }

    let id;
    let value;
    const vector = line.match(/^b([01xXzZ]+)\s+(\S+)$/);
    const scalar = line.match(/^([01xXzZ])(\S+)$/);
    if (vector) {
      value = vector[1].toLowerCase();
      id = vector[2];
    } else if (scalar) {
      value = scalar[1].toLowerCase();
      id = scalar[2];
    } else {
      continue;
    }

    if (!aliases.has(id)) continue;
    if (!histories.has(id)) histories.set(id, []);
    histories.get(id).push({ time, value });
  }

  const unique = [...aliases.entries()].map(([id, names]) => {
    const variable = [...names].sort((a, b) => a.scopeDepth - b.scopeDepth)[0];
    return { ...variable, id };
  });
  const priority = (variable) => {
    const leaf = variable.name.split(".").pop().toLowerCase();
    let score = variable.scopeDepth === 1 ? 30 : 0;
    if (/clk|clock|rst|reset|pc|instr|data|read|write|stall|simultaneous|grant|addr|wdata|rdata|opcode|cycle/.test(leaf)) {
      score += 20;
    }
    if (variable.width === 1) score += 4;
    return score;
  };
  const displayVariables = unique
    .sort((a, b) => priority(b) - priority(a) || a.name.localeCompare(b.name))
    .slice(0, 64);
  const defaults = displayVariables.filter((variable) => priority(variable) >= 30).slice(0, 16);

  return { variables: displayVariables, histories, endTime, timescale, defaults };
}

function signalLabel(variable) {
  const parts = variable.name.split(".");
  return `${parts.slice(-2).join(".")} [${variable.width}]`;
}

function formatVector(value, width) {
  if (/[xz]/.test(value)) return value.length > 12 ? `${value.slice(0, 10)}...` : value;
  try {
    const hex = BigInt(`0b${value}`).toString(16).padStart(Math.ceil(width / 4), "0");
    return `0x${hex}`;
  } catch {
    return value;
  }
}

function svgElement(tag, attributes = {}, text = "") {
  const element = document.createElementNS(svgNamespace, tag);
  for (const [key, value] of Object.entries(attributes)) element.setAttribute(key, value);
  if (text) element.textContent = text;
  return element;
}

function renderWaveform() {
  if (!currentWaveform) return;
  const selected = currentWaveform.variables.filter((variable) => selectedSignals.has(variable.id));
  elements.signalCount.textContent = `${selected.length} selected`;
  elements.waveChart.replaceChildren();
  if (selected.length === 0) {
    elements.waveChart.textContent = "Select at least one signal.";
    return;
  }

  const width = 1000;
  const labelWidth = 250;
  const rightPad = 14;
  const chartWidth = width - labelWidth - rightPad;
  const top = 27;
  const rowHeight = 32;
  const height = top + selected.length * rowHeight + 20;
  const svg = svgElement("svg", { viewBox: `0 0 ${width} ${height}`, role: "img", "aria-label": "Digital waveform chart" });
  const endTime = Math.max(currentWaveform.endTime, 1);
  const xAt = (value) => labelWidth + (Math.max(0, Math.min(endTime, value)) / endTime) * chartWidth;
  const ticks = 5;

  for (let tick = 0; tick <= ticks; tick += 1) {
    const time = (endTime * tick) / ticks;
    const x = xAt(time);
    svg.append(svgElement("line", { x1: x, y1: 12, x2: x, y2: height - 12, class: "grid-line" }));
    svg.append(svgElement("text", { x, y: 10, "text-anchor": "middle", class: "axis-label" }, Math.round(time).toString()));
  }

  selected.forEach((variable, row) => {
    const y = top + row * rowHeight;
    svg.append(svgElement("line", { x1: 0, y1: y + rowHeight - 1, x2: width, y2: y + rowHeight - 1, class: "row-line" }));
    svg.append(svgElement("text", { x: 8, y: y + 18, class: "signal-label" }, signalLabel(variable)));

    const history = currentWaveform.histories.get(variable.id) || [];
    let value = "x";
    let lastTime = 0;
    const points = [];
    for (const change of history) {
      if (change.time > endTime) break;
      if (change.time === 0) {
        value = change.value;
      } else {
        points.push({ time: change.time, oldValue: value, newValue: change.value });
        value = change.value;
      }
    }

    if (variable.width === 1) {
      const level = (bit) => (bit === "1" ? y + 7 : bit === "0" ? y + 24 : y + 16);
      let path = `M ${xAt(0)} ${level(history.find((change) => change.time === 0)?.value || "x")}`;
      let current = history.find((change) => change.time === 0)?.value || "x";
      for (const point of points) {
        path += ` H ${xAt(point.time)} V ${level(point.newValue)}`;
        current = point.newValue;
      }
      path += ` H ${xAt(endTime)}`;
      svg.append(svgElement("path", { d: path, class: "digital-wave" }));
      return;
    }

    const changes = history.filter((change) => change.time <= endTime);
    if (changes.length === 0 || changes[0].time > 0) changes.unshift({ time: 0, value: "x" });
    for (let index = 0; index < changes.length; index += 1) {
      const start = changes[index].time;
      const end = index + 1 < changes.length ? changes[index + 1].time : endTime;
      const x1 = xAt(start);
      const x2 = xAt(end);
      if (x2 - x1 < 1) continue;
      svg.append(svgElement("rect", {
        x: x1,
        y: y + 5,
        width: x2 - x1,
        height: 19,
        rx: 3,
        class: "vector-box",
      }));
      if (x2 - x1 > 28) {
        svg.append(svgElement("text", {
          x: (x1 + x2) / 2,
          y: y + 18,
          "text-anchor": "middle",
          class: "vector-value",
        }, formatVector(changes[index].value, variable.width)));
      }
    }
  });

  elements.waveChart.append(svg);
}

function renderSignalOptions() {
  elements.signalList.replaceChildren();
  for (const variable of currentWaveform.variables) {
    const label = document.createElement("label");
    label.className = "signal-option";
    const checkbox = document.createElement("input");
    checkbox.type = "checkbox";
    checkbox.checked = selectedSignals.has(variable.id);
    checkbox.addEventListener("change", () => {
      if (checkbox.checked) selectedSignals.add(variable.id);
      else selectedSignals.delete(variable.id);
      renderWaveform();
    });
    const name = document.createElement("span");
    name.textContent = signalLabel(variable);
    name.title = variable.name;
    label.append(checkbox, name);
    elements.signalList.append(label);
  }
}

async function loadWaveform(id = currentSimulation()?.id) {
  if (!id) return;
  elements.loadWave.disabled = true;
  elements.loadWave.textContent = "Loading...";
  try {
    const response = await fetch(`/api/waveform?id=${encodeURIComponent(id)}`);
    if (!response.ok) {
      const data = await response.json();
      throw new Error(data.error || "Could not load waveform.");
    }
    currentWaveform = parseVcd(await response.text());
    waveformId = id;
    selectedSignals = new Set(currentWaveform.defaults.map((variable) => variable.id));
    elements.waveInfo.textContent = `${currentWaveform.timescale} · ${currentWaveform.endTime} ticks · ${currentWaveform.variables.length} signals available`;
    elements.waveEmpty.hidden = true;
    elements.waveContent.hidden = false;
    renderSignalOptions();
    renderWaveform();
    elements.downloadWave.href = `/api/waveform?id=${encodeURIComponent(id)}&download=1`;
    elements.downloadWave.classList.remove("disabled-link");
    elements.downloadWave.setAttribute("aria-disabled", "false");
  } catch (error) {
    currentWaveform = null;
    elements.waveContent.hidden = true;
    elements.waveEmpty.hidden = false;
    showEmptyWave("Could not load waveform", error.message);
  } finally {
    elements.loadWave.disabled = false;
    elements.loadWave.textContent = "Load waveform";
  }
}

elements.run.addEventListener("click", runSimulation);
elements.loadWave.addEventListener("click", () => loadWaveform());
loadSimulations().catch((error) => {
  elements.description.textContent = error.message;
  setRunState("failed", "Dashboard unavailable");
  setResultBadge("failure", "OFFLINE");
});
