#!/usr/bin/env node
import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { execFileSync } from "node:child_process";

const args = new Map();
for (const arg of process.argv.slice(2)) {
  const match = arg.match(/^--([^=]+)=(.*)$/);
  if (match) args.set(match[1], match[2]);
}

const root = path.resolve(args.get("root") || process.cwd());
const host = args.get("host") || "127.0.0.1";
const requestedPort = Number(args.get("port") || process.env.GOAL_WITH_CODEX_DASHBOARD_PORT || 3762);
const maxPortAttempts = Number(args.get("max-port-attempts") || 20);

function safeRead(rel, fallback = "") {
  try {
    return fs.readFileSync(path.join(root, rel), "utf8");
  } catch {
    return fallback;
  }
}

function readJson(rel, fallback = null) {
  try {
    return JSON.parse(safeRead(rel, "null"));
  } catch {
    return fallback;
  }
}

function safeWriteJson(rel, value) {
  try {
    const file = path.join(root, rel);
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, JSON.stringify(value, null, 2) + "\n");
  } catch {
    // Dashboard metadata is advisory. Do not crash the server if it cannot be written.
  }
}

function readEvents() {
  const text = safeRead(".goal-with-codex/events.jsonl", "");
  return text
    .split(/\r?\n/)
    .filter(Boolean)
    .slice(-200)
    .map((line) => {
      try {
        return JSON.parse(line);
      } catch {
        return { type: "parse_error", raw: line };
      }
    });
}

function gitSummary() {
  const state = readJson(".goal-with-codex/state.json", {});
  let currentBranch = null;
  try {
    currentBranch = execFileSync("git", ["branch", "--show-current"], {
      cwd: root,
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"]
    }).trim() || null;
  } catch {
    currentBranch = null;
  }
  return {
    branch: state?.branch || currentBranch,
    base_branch: state?.base_branch || null,
    no_git: Boolean(state?.no_git)
  };
}

function currentData() {
  const state = readJson(".goal-with-codex/state.json", null);
  const dashboard = readJson(".goal-with-codex/state/dashboard.json", null);
  const evidence = readJson(".goal-with-codex/state/evidence-latest.json", null);
  return {
    now: new Date().toISOString(),
    has_run: Boolean(state),
    dashboard,
    state,
    evidence,
    git: gitSummary(),
    progress_tail: safeRead(".goal-with-codex/progress.md", "").split(/\r?\n/).slice(-120).join("\n"),
    events: readEvents()
  };
}

function sendJson(res, data) {
  const body = JSON.stringify(data, null, 2);
  res.writeHead(200, {
    "content-type": "application/json; charset=utf-8",
    "cache-control": "no-store"
  });
  res.end(body);
}

function sendHtml(res) {
  res.writeHead(200, {
    "content-type": "text/html; charset=utf-8",
    "cache-control": "no-store"
  });
  res.end(`<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>goal-with-codex dashboard</title>
  <style>
    :root {
      color-scheme: light dark;
      --bg: #f7f7f3;
      --panel: #ffffff;
      --text: #1f2328;
      --muted: #69707a;
      --line: #d8d8d0;
      --good: #1b7f4c;
      --warn: #a55f00;
      --bad: #b42318;
      --info: #2456a6;
      --mono: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
      font-family: ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    }
    @media (prefers-color-scheme: dark) {
      :root {
        --bg: #111315;
        --panel: #1b1e21;
        --text: #eef0f2;
        --muted: #a4abb3;
        --line: #33383e;
        --good: #54c78a;
        --warn: #f1a33c;
        --bad: #ff6b5f;
        --info: #77a7ff;
      }
    }
    * { box-sizing: border-box; }
    body { margin: 0; background: var(--bg); color: var(--text); }
    header {
      display: flex; align-items: center; justify-content: space-between;
      padding: 16px 20px; border-bottom: 1px solid var(--line); background: var(--panel);
      position: sticky; top: 0; z-index: 5;
    }
    h1 { font-size: 18px; margin: 0; letter-spacing: 0; }
    .sub { color: var(--muted); font-size: 13px; }
    main { padding: 18px; display: grid; gap: 16px; grid-template-columns: 1.1fr .9fr; }
    @media (max-width: 900px) { main { grid-template-columns: 1fr; padding: 12px; } }
    section { background: var(--panel); border: 1px solid var(--line); border-radius: 8px; padding: 14px; min-width: 0; }
    h2 { font-size: 14px; margin: 0 0 10px; }
    .grid { display: grid; gap: 8px; grid-template-columns: repeat(2, minmax(0, 1fr)); }
    @media (max-width: 520px) { .grid { grid-template-columns: 1fr; } }
    .metric { border: 1px solid var(--line); border-radius: 6px; padding: 10px; min-height: 64px; }
    .label { color: var(--muted); font-size: 12px; margin-bottom: 4px; }
    .value { font-size: 16px; font-weight: 650; overflow-wrap: anywhere; }
    .pill { display: inline-flex; align-items: center; gap: 6px; border: 1px solid var(--line); border-radius: 999px; padding: 4px 8px; font-size: 12px; }
    .good { color: var(--good); }
    .warn { color: var(--warn); }
    .bad { color: var(--bad); }
    .info { color: var(--info); }
    pre {
      margin: 0; white-space: pre-wrap; word-break: break-word;
      font-family: var(--mono); font-size: 12px; line-height: 1.45;
      max-height: 420px; overflow: auto; background: color-mix(in srgb, var(--panel), var(--bg) 45%);
      border: 1px solid var(--line); border-radius: 6px; padding: 10px;
    }
    .events { display: grid; gap: 8px; max-height: 460px; overflow: auto; }
    .event { border: 1px solid var(--line); border-radius: 6px; padding: 8px; }
    .event-top { display: flex; justify-content: space-between; gap: 10px; font-size: 12px; }
    .event-type { font-weight: 700; }
    .event-time { color: var(--muted); font-family: var(--mono); }
    .empty { color: var(--muted); font-size: 14px; }
  </style>
</head>
<body>
  <header>
    <div>
      <h1>goal-with-codex dashboard</h1>
      <div class="sub" id="root"></div>
    </div>
    <div class="pill" id="refresh">refreshing...</div>
  </header>
  <main>
    <div style="display:grid;gap:16px">
      <section>
        <h2>Run</h2>
        <div class="grid" id="metrics"></div>
      </section>
      <section>
        <h2>Progress</h2>
        <pre id="progress"></pre>
      </section>
      <section>
        <h2>Codex summary</h2>
        <pre id="report"></pre>
      </section>
    </div>
    <div style="display:grid;gap:16px">
      <section>
        <h2>Latest verdict</h2>
        <pre id="verdict"></pre>
      </section>
      <section>
        <h2>Events</h2>
        <div class="events" id="events"></div>
      </section>
      <section>
        <h2>Scope violations</h2>
        <pre id="scope"></pre>
      </section>
    </div>
  </main>
  <script>
    const root = ${JSON.stringify(root)};
    document.getElementById("root").textContent = root;

    function esc(value) {
      return String(value ?? "").replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
    }
    function metric(label, value, cls = "") {
      return '<div class="metric"><div class="label">' + esc(label) + '</div><div class="value ' + cls + '">' + esc(value) + '</div></div>';
    }
    function reasonClass(reason) {
      if (reason === "COMPLETE") return "good";
      if (String(reason || "").startsWith("STOP")) return reason === "STOP_HUMAN" ? "warn" : "bad";
      return "info";
    }
    async function load() {
      const res = await fetch("/api/state", { cache: "no-store" });
      const data = await res.json();
      const s = data.state || {};
      const evidence = data.evidence || {};
      const codex = evidence.codex || {};
      const evalInfo = evidence.eval || {};
      document.getElementById("refresh").textContent = "updated " + new Date(data.now).toLocaleTimeString();
      document.getElementById("metrics").innerHTML = [
        metric("Goal", data.has_run ? (s.technical_goal || s.user_goal) : "No active run"),
        metric("Iteration", data.has_run ? s.iteration : "0"),
        metric("Step", evidence.status || s.last_step_status || "unknown", evidence.status === "stopped" ? "bad" : "info"),
        metric("Codex", (codex.status || "unknown") + " / risk=" + (codex.risk || "unknown")),
        metric("Eval", evalInfo.label || s.eval_cmd || "none"),
        metric("Status", data.has_run ? (s.completed ? "completed" : s.loop_phase || "running") : "idle", data.has_run && s.completed ? "good" : "info"),
        metric("Stop reason", s.stop_reason || "running", reasonClass(s.stop_reason)),
        metric("Scope mode", s.scope_mode || "enforce"),
        metric("Branch", data.git?.branch || "unknown")
      ].join("");
      document.getElementById("progress").textContent = data.progress_tail || "No progress log yet.";
      document.getElementById("report").textContent = data.evidence?.codex ? JSON.stringify(data.evidence.codex, null, 2) : "No Codex result yet.";
      document.getElementById("verdict").textContent = data.evidence ? JSON.stringify(data.evidence, null, 2) : "No evidence yet.";
      document.getElementById("scope").textContent = "goal-with-codex does not enforce a static scope file. Claude decides from evidence, changed files, and Codex review output.";
      const events = data.events || [];
      document.getElementById("events").innerHTML = events.length ? events.slice().reverse().map(e => {
        const body = { ...e };
        delete body.time; delete body.type;
        return '<div class="event"><div class="event-top"><span class="event-type">' + esc(e.type || "event") + '</span><span class="event-time">' + esc(e.time || "") + '</span></div><pre>' + esc(JSON.stringify(body, null, 2)) + '</pre></div>';
      }).join("") : '<div class="empty">No events yet.</div>';
    }
    load().catch(err => {
      document.getElementById("progress").textContent = String(err);
    });
    setInterval(load, 2000);
  </script>
</body>
</html>`);
}

let activePort = requestedPort;

const server = http.createServer((req, res) => {
  const url = new URL(req.url || "/", `http://${host}:${activePort}`);
  if (url.pathname === "/api/state") return sendJson(res, currentData());
  if (url.pathname === "/" || url.pathname === "/index.html") return sendHtml(res);
  res.writeHead(404, { "content-type": "text/plain; charset=utf-8" });
  res.end("not found");
});

function writeDashboardState() {
  safeWriteJson(".goal-with-codex/state/dashboard.json", {
    pid: process.pid,
    host,
    port: activePort,
    url: `http://${host}:${activePort}`,
    root,
    started_at: new Date().toISOString()
  });
}

function listenWithRetry(port, remaining) {
  activePort = port;
  server.once("error", (error) => {
    if (error.code === "EADDRINUSE" && remaining > 0) {
      listenWithRetry(port + 1, remaining - 1);
      return;
    }
    console.error(`goal-with-codex dashboard failed to listen on ${host}:${port}`);
    console.error(error.message);
    process.exit(1);
  });
  server.listen(port, host, () => {
    writeDashboardState();
    console.log(`goal-with-codex dashboard: http://${host}:${port}`);
    console.log(`root: ${root}`);
    if (port !== requestedPort) {
      console.log(`requested port ${requestedPort} was unavailable; using ${port}`);
    }
  });
}

process.on("SIGINT", () => {
  server.close(() => process.exit(0));
});

listenWithRetry(requestedPort, maxPortAttempts);
