FROM python:3.11-slim

ENV PIP_NO_CACHE_DIR=1 \
    PYTHONUNBUFFERED=1 \
    FLASK_RUN_PORT=10000

RUN apt-get update && apt-get install -y --no-install-recommends \
    git ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN printf "Flask==3.0.2\nmaigret==0.5.0\n" > requirements.txt \
 && pip install --upgrade pip \
 && pip install -r requirements.txt

RUN cat << 'EOF' > app.py
import subprocess
from flask import Flask, request, jsonify, render_template_string

app = Flask(__name__)

HTML = """
<!DOCTYPE html>
<html>
<head>
<title>Maigret CRT Matrix Console</title>

<style>
    html, body {
        margin: 0;
        padding: 0;
        height: 100%;
        overflow: hidden;
        background: black;
        font-family: "Lucida Console", monospace;
        color: #00ff66;
    }

    canvas#matrix {
        position: fixed;
        top:0;
        left:0;
        width:100%;
        height:100%;
        z-index: 0;
        background: black;
    }

    #boot-screen {
        position: fixed;
        z-index: 3;
        top:0;
        left:0;
        right:0;
        bottom:0;
        background: black;
        color:#00ff66;
        padding: 30px;
        font-size: 14px;
        overflow-y: auto;
        white-space: pre-wrap;
        text-shadow: 0 0 6px #00ff66;
    }

    #app {
        position: relative;
        z-index: 2;
        display: none;
        height: 100%;
        padding: 20px;
        box-sizing: border-box;
        display: flex;
        flex-direction: column;
    }

    #tabs {
        display: flex;
        gap: 10px;
        margin-bottom: 10px;
    }

    .tab-btn {
        background: rgba(0,20,0,0.8);
        border: 1px solid #00ff66;
        color: #00ff66;
        padding: 8px 14px;
        cursor: pointer;
        text-shadow: 0 0 6px #00ff66;
    }

    .tab-btn.active {
        background: #003300;
        box-shadow: 0 0 15px #00ff66;
    }

    #tab-contents {
        flex: 1;
        display: flex;
        flex-direction: column;
        min-height: 0;
    }

    #terminal-tab, #json-tab {
        flex: 1;
        display: none;
        flex-direction: column;
        min-height: 0;
    }

    #terminal-tab.active, #json-tab.active {
        display: flex;
    }

    #terminal {
        flex: 1;
        overflow-y: auto;
        white-space: pre-wrap;
        font-size: 16px;
        line-height: 1.3em;
        text-shadow: 0 0 6px #00ff66;
        background: rgba(0,20,0,0.6);
        border: 2px solid #00ff66;
        box-shadow: inset 0 0 25px #00ff66;
        padding: 15px;
    }

    #input-line {
        display: flex;
        margin-top: 8px;
        align-items: center;
    }

    #prompt {
        margin-right: 5px;
        text-shadow: 0 0 6px #00ff66;
    }

    #cmd {
        background: transparent;
        border: none;
        border-bottom: 1px solid #00ff66;
        color: #00ff66;
        flex: 1;
        font-family: "Lucida Console", monospace;
        font-size: 16px;
        outline: none;
    }

    .caret {
        display: inline-block;
    }

    .caret::after {
        content: "█";
        animation: blink 0.7s steps(1) infinite;
    }
    @keyframes blink { 0%{opacity:1}50%{opacity:0}100%{opacity:1} }

    #json-tab pre {
        flex: 1;
        background: rgba(0,20,0,0.7);
        border: 2px solid #00ff66;
        padding: 10px;
        overflow-y: auto;
        white-space: pre-wrap;
        text-shadow: 0 0 6px #00ff66;
    }

    #download-json {
        margin-top: 8px;
        align-self: flex-start;
        background: rgba(0,20,0,0.8);
        border: 1px solid #00ff66;
        color: #00ff66;
        padding: 6px 12px;
        cursor: pointer;
        text-shadow: 0 0 6px #00ff66;
    }

    body::before {
        content: "";
        pointer-events: none;
        position: fixed;
        top:0; left:0; right:0; bottom:0;
        background: repeating-linear-gradient(
            rgba(0,255,50,0.03) 0px,
            rgba(0,255,50,0.03) 2px,
            transparent 2px,
            transparent 4px
        );
        z-index: 1;
        mix-blend-mode: screen;
    }
</style>
</head>
<body>

<canvas id="matrix"></canvas>

<div id="boot-screen"></div>

<div id="app">
    <div id="tabs">
        <button class="tab-btn active" data-tab="terminal">Terminal</button>
        <button class="tab-btn" data-tab="json">JSON Output</button>
    </div>
    <div id="tab-contents">
        <div id="terminal-tab" class="active">
            <div id="terminal">
                <pre>
   __  ___       _                               _   
  /  |/  /_  __ (_)____  ____ _________  ___  __(_)__
 / /|_/ / / / / / / __ \\/ __ `/ ___/ _ \\/ _ \\/ / / _ \\
/ /  / / /_/ / / / / / / /_/ / /  /  __/  __/ / /  __/
/_/  /_/\\__,_/_/_/_/ /_/\\__,_/_/   \\___/\\___/_/_/\\___/

Maigret OSINT CRT MATRIX CONSOLE
Type a command and press ENTER.
Example: maigret johndoe --json
------------------------------------------------------
                </pre>
            </div>
            <div id="input-line">
                <span id="prompt" class="caret">&gt;</span>
                <input id="cmd" autocomplete="off">
            </div>
        </div>
        <div id="json-tab">
            <pre id="json-output">No JSON available yet.</pre>
            <button id="download-json">Download JSON</button>
        </div>
    </div>
</div>

<script>
    // ----- Audio (typing beeps) -----
    let audioCtx = null;
    function initAudio() {
        if (!audioCtx) {
            audioCtx = new (window.AudioContext || window.webkitAudioContext)();
        }
    }
    function playClick() {
        if (!audioCtx) return;
        const osc = audioCtx.createOscillator();
        const gain = audioCtx.createGain();
        osc.frequency.value = 800 + Math.random() * 400;
        gain.gain.value = 0.05;
        osc.connect(gain);
        gain.connect(audioCtx.destination);
        osc.start();
        osc.stop(audioCtx.currentTime + 0.03);
    }

    document.addEventListener("click", initAudio, { once: true });
    document.addEventListener("keydown", initAudio, { once: true });

    // ----- Matrix rain background -----
    const canvas = document.getElementById("matrix");
    const ctx = canvas.getContext("2d");

    let width = canvas.width = window.innerWidth;
    let height = canvas.height = window.innerHeight;

    const chars = "アァカサタナハマヤャラワガザダバパイィキシチニヒミリヰギジヂビピウゥクスツヌフムユュルグズヅブプエェケセテネヘメレヱゲゼデベペオォコソトノホモヨョロヲゴゾドボポ0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ";
    const fontSize = 16;
    let columns = Math.floor(width / fontSize);
    let drops = [];

    function resetDrops() {
        columns = Math.floor(width / fontSize);
        drops = [];
        for (let i = 0; i < columns; i++) drops[i] = Math.random() * height;
    }
    resetDrops();

    window.addEventListener("resize", () => {
        width = canvas.width = window.innerWidth;
        height = canvas.height = window.innerHeight;
        resetDrops();
    });

    function drawMatrix() {
        ctx.fillStyle = "rgba(0,0,0,0.15)";
        ctx.fillRect(0, 0, width, height);
        ctx.fillStyle = "#00ff66";
        ctx.font = fontSize + "px monospace";
        for (let i = 0; i < drops.length; i++) {
            const text = chars.charAt(Math.floor(Math.random() * chars.length));
            ctx.fillText(text, i * fontSize, drops[i] * fontSize);
            if (drops[i] * fontSize > height && Math.random() > 0.95) {
                drops[i] = 0;
            }
            drops[i]++;
        }
        requestAnimationFrame(drawMatrix);
    }
    requestAnimationFrame(drawMatrix);

    // ----- Boot screen (BIOS style) -----
    const bootLines = [
        "PhoenixBIOS 4.0 Release 6.0",
        "Copyright (C) 1985-2025 Matrix Systems, Inc.",
        "",
        "CPU: Quantum-X 9000 @ 4.20 GHz",
        "Memory Test: 32768K OK",
        "Detecting Storage Devices...",
        "  - /dev/mtrx0: Maigret OSINT Core",
        "  - /dev/net0 : Render.com Virtual NIC",
        "",
        "Initializing Network Stack...",
        "  [OK] DHCP handshake",
        "  [OK] DNS resolve: api.maigret.local",
        "",
        "Loading OSINT Modules...",
        "  [OK] Target Profiler",
        "  [OK] Social Graph Resolver",
        "  [OK] Evidence Correlator",
        "",
        "Launching MAIGRET CRT MATRIX CONSOLE...",
        "",
        "Press ENTER to continue..."
    ];

    const bootEl = document.getElementById("boot-screen");
    const appEl = document.getElementById("app");

    let bootIndex = 0;
    let bootDone = false;

    function typeBootLine() {
        if (bootIndex >= bootLines.length) {
            bootDone = true;
            return;
        }
        const line = bootLines[bootIndex++];
        let charIdx = 0;
        const lineDiv = document.createElement("div");
        bootEl.appendChild(lineDiv);

        function typeChar() {
            if (charIdx <= line.length) {
                lineDiv.textContent = line.slice(0, charIdx);
                charIdx++;
                if (line[charIdx-1] && line[charIdx-1] !== " ") playClick();
                setTimeout(typeChar, 15 + Math.random() * 30);
            } else {
                bootEl.appendChild(document.createElement("br"));
                setTimeout(typeBootLine, 80 + Math.random() * 150);
            }
        }
        typeChar();
    }

    typeBootLine();

    document.addEventListener("keydown", (e) => {
        if (!bootDone) {
            if (e.key === "Enter") {
                bootDone = true;
                bootEl.style.display = "none";
                appEl.style.display = "flex";
                document.getElementById("cmd").focus();
                playClick();
            }
            e.preventDefault();
        }
    }, true);

    // ----- Tabs -----
    const tabButtons = document.querySelectorAll(".tab-btn");
    const terminalTab = document.getElementById("terminal-tab");
    const jsonTab = document.getElementById("json-tab");
    const jsonOutput = document.getElementById("json-output");
    const downloadBtn = document.getElementById("download-json");

    let lastJsonText = null;

    tabButtons.forEach(btn => {
        btn.addEventListener("click", () => {
            tabButtons.forEach(b => b.classList.remove("active"));
            btn.classList.add("active");
            const tab = btn.getAttribute("data-tab");
            if (tab === "terminal") {
                terminalTab.classList.add("active");
                jsonTab.classList.remove("active");
            } else {
                terminalTab.classList.remove("active");
                jsonTab.classList.add("active");
            }
        });
    });

    downloadBtn.addEventListener("click", () => {
        if (!lastJsonText) return;
        const blob = new Blob([lastJsonText], { type: "application/json" });
        const url = URL.createObjectURL(blob);
        const a = document.createElement("a");
        a.href = url;
        a.download = "maigret_output.json";
        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);
        URL.revokeObjectURL(url);
    });

    // ----- Terminal logic -----
    const term = document.getElementById("terminal");
    const cmdInput = document.getElementById("cmd");

    let history = [];
    let historyIndex = -1;
    let streaming = false;

    function append(text) {
        term.innerText += "\\n" + text;
        term.scrollTop = term.scrollHeight;
    }

    cmdInput.addEventListener("keydown", function(e) {
        if (!bootDone) return;

        if (e.key === "Enter") {
            const command = cmdInput.value.trim();
            if (!command) return;
            playClick();

            append("> " + command);
            history.push(command);
            historyIndex = history.length;
            cmdInput.value = "";

            if (!command.startsWith("maigret")) {
                append("ERROR: Only 'maigret' commands allowed.");
                return;
            }

            if (streaming) return;
            streaming = true;

            fetch("/run", {
                method: "POST",
                headers: {"Content-Type": "application/json"},
                body: JSON.stringify({command})
            })
            .then(r => r.json())
            .then(data => {
                const lines = data.lines || [];
                let idx = 0;
                lastJsonText = null;

                // try to detect JSON
                const joined = lines.join("\\n").trim();
                try {
                    if (joined.startsWith("{") || joined.startsWith("[")) {
                        const parsed = JSON.parse(joined);
                        lastJsonText = JSON.stringify(parsed, null, 2);
                        jsonOutput.textContent = lastJsonText;
                    } else {
                        jsonOutput.textContent = "No JSON detected in output.";
                    }
                } catch (err) {
                    jsonOutput.textContent = "No valid JSON detected in output.";
                }

                function streamNext() {
                    if (idx >= lines.length) {
                        streaming = false;
                        return;
                    }
                    append(lines[idx++]);
                    playClick();
                    setTimeout(streamNext, 40 + Math.random() * 80);
                }
                streamNext();
            })
            .catch(() => {
                append("ERROR: Command failed.");
                streaming = false;
            });

            e.preventDefault();
        } else if (e.key === "ArrowUp") {
            if (history.length > 0) {
                historyIndex = Math.max(0, historyIndex - 1);
                cmdInput.value = history[historyIndex] || "";
                setTimeout(() => cmdInput.setSelectionRange(cmdInput.value.length, cmdInput.value.length), 0);
            }
            e.preventDefault();
        } else if (e.key === "ArrowDown") {
            if (history.length > 0) {
                historyIndex = Math.min(history.length, historyIndex + 1);
                if (historyIndex === history.length) {
                    cmdInput.value = "";
                } else {
                    cmdInput.value = history[historyIndex] || "";
                }
                setTimeout(() => cmdInput.setSelectionRange(cmdInput.value.length, cmdInput.value.length), 0);
            }
            e.preventDefault();
        } else {
            // typing sound on normal keys
            if (e.key.length === 1) {
                playClick();
            }
        }
    });
</script>

</body>
</html>
"""

@app.route("/")
def page():
    return render_template_string(HTML)

@app.route("/run", methods=["POST"])
def run():
    data = request.get_json()
    cmd = data.get("command", "")

    if not cmd.strip().startswith("maigret"):
        return jsonify({"lines": ["ERROR: Only 'maigret' commands allowed."]})

    try:
        result = subprocess.check_output(
            cmd, shell=True, stderr=subprocess.STDOUT, text=True
        )
    except subprocess.CalledProcessError as e:
        result = e.output or "Execution error."

    lines = result.splitlines()
    if not lines:
        lines = [""]
    return jsonify({"lines": lines})

@app.route("/health")
def health():
    return "OK", 200

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=10000)
EOF

EXPOSE 10000

CMD ["python", "app.py"]
