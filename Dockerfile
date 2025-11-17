FROM python:3.11-slim

ENV PIP_NO_CACHE_DIR=1 \
    PYTHONUNBUFFERED=1 \
    FLASK_RUN_PORT=10000

RUN apt-get update && apt-get install -y --no-install-recommends \
    git ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# FIX: Maigret 0.5.0 requires Flask ≥ 3.1.1
RUN printf "Flask==3.1.1\nmaigret==0.5.0\n" > requirements.txt \
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
    background: black;
    font-family: "Lucida Console", monospace;
    color: #00ff66;
    overflow: hidden; /* prevent page scroll */
}

canvas#matrix {
    position: fixed; 
    top:0; left:0;
    width:100%; 
    height:100%;
    z-index: 0;
}

#boot-screen {
    position: fixed;
    top:0; left:0; right:0; bottom:0;
    padding: 30px;
    color:#00ff66;
    white-space: pre-wrap;
    font-size:14px;
    overflow-y:auto;
    z-index: 3;
}

#app {
    display:none;
    position: relative;
    z-index: 2;
    height:100%;
    padding:20px;
    box-sizing:border-box;
    display:flex;
    flex-direction:column;
    overflow:hidden;
}

#tabs { display:flex; gap:10px; margin-bottom:10px; }

.tab-btn {
    padding:8px 14px;
    background:rgba(0,20,0,0.8);
    border:1px solid #00ff66;
    cursor:pointer;
}
.tab-btn.active {
    background:#003300;
    box-shadow:0 0 15px #00ff66;
}

#terminal-tab, #json-tab {
    flex:1; display:none; flex-direction:column;
}
#terminal-tab.active, #json-tab.active { display:flex; }

#terminal {
    flex:1;
    background:rgba(0,20,0,0.6);
    border:2px solid #00ff66;
    padding:15px;
    overflow-y: scroll !important;  /* ★ FIX: terminal scrolls */
    max-height: calc(100vh - 180px); /* ★ FIX: fits screen */
    white-space:pre-wrap;
}

#input-line { display:flex; margin-top:8px; }
#cmd {
    flex:1;
    background:transparent;
    border:none;
    border-bottom:1px solid #00ff66;
    color:#00ff66;
    outline:none;
}
.caret::after {
    content:"█";
    animation: blink 0.7s steps(1) infinite;
}
@keyframes blink {
    0%{opacity:1;}50%{opacity:0;}100%{opacity:1;}
}

#json-tab pre {
    flex:1;
    background:rgba(0,20,0,0.7);
    border:2px solid #00ff66;
    overflow-y:auto;
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

    <div id="terminal-tab" class="active">
        <div id="terminal">
<pre>
   __  ___       _                               _
  /  |/  /_  __ (_)____  ____ _________  ___  __(_)__
 / /|_/ / / / / / / __ \\/ __ `/ ___/ _ \\/ _ \\/ / / _ \\
/ /  / / /_/ / / / / / / /_/ / /  /  __/  __/ / /  __/
/_/  /_/\\__,_/_/_/_/ /_/\\__,_/_/   \\___/\\___/_/_/\\___/

Maigret OSINT CRT MATRIX CONSOLE
Type commands like:
maigret testuser --json
---------------------------------------------
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

<script>
// MATRIX BACKGROUND
const canvas = document.getElementById("matrix");
const ctx = canvas.getContext("2d");
function resize(){ canvas.width=innerWidth; canvas.height=innerHeight; }
resize(); window.onresize=resize;

const chars="アァカサタパ0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ";
let drops = Array(Math.floor(innerWidth/16)).fill(0);
function matrixDraw(){
    ctx.fillStyle="rgba(0,0,0,0.15)";
    ctx.fillRect(0,0,canvas.width,canvas.height);
    ctx.fillStyle="#00ff66"; ctx.font="16px monospace";
    drops.forEach((y,i)=>{
        ctx.fillText(chars[Math.floor(Math.random()*chars.length)], i*16, y*16);
        drops[i] = (y*16 > canvas.height && Math.random()>0.95) ? 0 : y+1;
    });
    requestAnimationFrame(matrixDraw);
}
matrixDraw();

// AUTO-CONTINUE BOOT
const bootLines = [
"PhoenixBIOS 4.0 Release 6.0",
"© 1985-2025 Matrix Systems, Inc.",
"",
"CPU: Quantum-X 9000",
"Memory Test: 32768K OK",
"[OK] Loading modules...",
"[OK] Initializing OSINT engine...",
"",
"Launching MAIGRET TERMINAL...",
""
];

const boot = document.getElementById("boot-screen");
const appDiv = document.getElementById("app");
let i=0;

function typeLine(){
    if(i >= bootLines.length){
        setTimeout(()=>{
            boot.style.display="none";
            appDiv.style.display="flex";
            document.getElementById("cmd").focus();
        },500);
        return;
    }
    const line = bootLines[i++];
    const div = document.createElement("div");
    boot.appendChild(div);
    let j=0;
    function typeChar(){
        div.textContent = line.slice(0,j++);
        if(j <= line.length) setTimeout(typeChar, 18+Math.random()*25);
        else {
            boot.appendChild(document.createElement("br"));
            setTimeout(typeLine, 60+Math.random()*100);
        }
    }
    typeChar();
}
typeLine();

// TABS
const tabs=document.querySelectorAll(".tab-btn");
const termTab=document.getElementById("terminal-tab");
const jsonTab=document.getElementById("json-tab");
tabs.forEach(btn=>{
    btn.onclick=()=>{
        tabs.forEach(b=>b.classList.remove("active"));
        btn.classList.add("active");
        if(btn.dataset.tab==="terminal"){
            termTab.classList.add("active");
            jsonTab.classList.remove("active");
        } else {
            jsonTab.classList.add("active");
            termTab.classList.remove("active");
        }
    };
});

// TERMINAL
let hist=[], histIndex=-1;
const term=document.getElementById("terminal");
const cmd=document.getElementById("cmd");

cmd.onkeydown = (e)=>{
    if(e.key==="Enter"){
        let c = cmd.value.trim();
        if(!c) return;
        term.innerText += "\\n> "+c;
        cmd.value="";
        hist.push(c);
        histIndex = hist.length;
        if(!c.startsWith("maigret")){
            term.innerText+="\\nERROR: Only 'maigret' allowed.";
            return;
        }
        fetch("/run",{
            method:"POST",
            headers:{"Content-Type":"application/json"},
            body:JSON.stringify({command:c})
        })
        .then(r=>r.json())
        .then(d=>{
            d.lines.forEach(line=> term.innerText+="\\n"+line);
            term.scrollTop = term.scrollHeight;
        });
        e.preventDefault();
    }
    if(e.key==="ArrowUp"){
        histIndex=Math.max(0,histIndex-1);
        cmd.value = hist[histIndex] || "";
    }
    if(e.key==="ArrowDown"){
        histIndex=Math.min(hist.length,histIndex+1);
        cmd.value = histIndex===hist.length ? "" : hist[histIndex];
    }
};
</script>
</body>
</html>
"""

@app.route("/")
def index():
    return render_template_string(HTML)

@app.route("/run", methods=["POST"])
def run_cmd():
    cmd = request.json.get("command","")
    if not cmd.startswith("maigret"):
        return jsonify({"lines":["ERROR: Only 'maigret' commands allowed."]})
    try:
        out = subprocess.check_output(cmd, shell=True, stderr=subprocess.STDOUT, text=True)
    except subprocess.CalledProcessError as e:
        out = e.output or "Execution error."
    return jsonify({"lines": out.splitlines()})

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=10000)
EOF

EXPOSE 10000
CMD ["python", "app.py"]
