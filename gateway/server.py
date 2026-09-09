#!/usr/bin/env python3
"""Cross-agent MCP gateway."""
from __future__ import annotations
import os, shutil, subprocess, time
from pathlib import Path
from dotenv import load_dotenv
from fastmcp import FastMCP
from starlette.requests import Request
from starlette.responses import PlainTextResponse

load_dotenv()
WORKSPACE = Path(os.environ.get("WORKSPACE", "/opt/cross-agent/workspace")).expanduser()
TIMEOUT = int(os.environ.get("DISPATCH_TIMEOUT", "600"))
MAX_DEPTH = int(os.environ.get("MAX_DEPTH", "1"))
GATEWAY_HOST = os.environ.get("GATEWAY_HOST", "127.0.0.1")
GATEWAY_PORT = int(os.environ.get("GATEWAY_PORT", "8787"))
SUBAGENT_GUARD = (
    "You are a SUBAGENT invoked by another coding agent. "
    "Complete the assigned task yourself. Do not call dispatch_claude, "
    "dispatch_codex, dispatch_grok, dispatch_gpt_work, or any cross-agent "
    "MCP/connector. Do not spawn another vendor's CLI. Return a concise "
    "report: what you did, key findings, files changed, and open risks."
)
mcp = FastMCP("cross-agent-gateway")

def _which(name: str):
    return shutil.which(name)

def _status():
    WORKSPACE.mkdir(parents=True, exist_ok=True)
    return {
        "workspace": str(WORKSPACE),
        "host": os.uname().nodename if hasattr(os, "uname") else "unknown",
        "timeout_sec": TIMEOUT,
        "max_depth": MAX_DEPTH,
        "binaries": {"claude": _which("claude"), "codex": _which("codex"), "grok": _which("grok")},
    }

def _run(argv, cwd: Path, timeout: int):
    started = time.time()
    try:
        proc = subprocess.run(argv, cwd=str(cwd), capture_output=True, text=True, timeout=timeout, env={**os.environ, "TERM": "dumb", "NO_COLOR": "1"})
    except subprocess.TimeoutExpired as exc:
        return {"ok": False, "exit_code": None, "timed_out": True, "duration_sec": round(time.time()-started, 2), "stdout": (exc.stdout or "")[-12000:], "stderr": ((exc.stderr or "") + f"\nTIMEOUT after {timeout}s")[-8000:], "command": argv}
    except FileNotFoundError as exc:
        return {"ok": False, "exit_code": 127, "timed_out": False, "duration_sec": round(time.time()-started, 2), "stdout": "", "stderr": str(exc), "command": argv}
    return {"ok": proc.returncode == 0, "exit_code": proc.returncode, "timed_out": False, "duration_sec": round(time.time()-started, 2), "stdout": (proc.stdout or "")[-16000:], "stderr": (proc.stderr or "")[-6000:], "command": argv}

def _workspace(path):
    base = WORKSPACE.resolve()
    target = Path(path).expanduser() if path else base
    target = (base / target).resolve() if not target.is_absolute() else target.resolve()
    target.mkdir(parents=True, exist_ok=True)
    try:
        target.relative_to(base)
    except ValueError as exc:
        raise ValueError(f"cwd must stay inside {base}") from exc
    return target

def _compose_prompt(task: str, context):
    parts = [SUBAGENT_GUARD, "", "TASK:", task.strip()]
    if context and context.strip():
        parts.extend(["", "CONTEXT:", context.strip()])
    return "\n".join(parts)

def _check_depth(depth: int):
    if depth < 0 or depth > MAX_DEPTH:
        raise ValueError(f"depth {depth} outside 0..{MAX_DEPTH}")

@mcp.custom_route("/healthz", methods=["GET"])
async def healthz(_request: Request) -> PlainTextResponse:
    return PlainTextResponse("ok")

@mcp.tool()
def list_targets() -> dict:
    """Which headless CLIs are installed on this host."""
    return _status()

@mcp.tool()
def dispatch_claude(task: str, cwd: str | None = None, model: str | None = None, write: bool = False, depth: int = 0, context: str | None = None) -> dict:
    """Run Claude Code as a one-shot subagent."""
    _check_depth(depth)
    binary = _which("claude")
    if not binary:
        return {"ok": False, "error": "claude CLI not on PATH"}
    argv = [binary, "-p", _compose_prompt(task, context), "--output-format", "text"]
    model = model or os.environ.get("CLAUDE_MODEL")
    if model:
        argv.extend(["--model", model])
    argv.extend(["--permission-mode", "acceptEdits", "--allowedTools", "Bash,Read,Edit,Write,Glob,Grep"] if write else ["--allowedTools", "Read,Glob,Grep"])
    result = _run(argv, _workspace(cwd), TIMEOUT)
    result["target"] = "claude"
    return result

@mcp.tool()
def dispatch_codex(task: str, cwd: str | None = None, model: str | None = None, write: bool = False, depth: int = 0, context: str | None = None) -> dict:
    """Run Codex CLI (ChatGPT Work engine) as a one-shot subagent."""
    _check_depth(depth)
    binary = _which("codex")
    if not binary:
        return {"ok": False, "error": "codex CLI not on PATH"}
    argv = [binary, "exec", "--ephemeral"]
    model = model or os.environ.get("CODEX_MODEL")
    if model:
        argv.extend(["-m", model])
    argv.append("--full-auto" if write else None)
    if not write:
        argv.extend(["--sandbox", "read-only"])
    argv = [x for x in argv if x is not None]
    argv.append(_compose_prompt(task, context))
    result = _run(argv, _workspace(cwd), TIMEOUT)
    result["target"] = "codex"
    return result

@mcp.tool()
def dispatch_gpt_work(task: str, cwd: str | None = None, model: str | None = None, write: bool = False, depth: int = 0, context: str | None = None) -> dict:
    """Alias of dispatch_codex."""
    return dispatch_codex(task=task, cwd=cwd, model=model, write=write, depth=depth, context=context)

@mcp.tool()
def dispatch_grok(task: str, cwd: str | None = None, model: str | None = None, write: bool = False, depth: int = 0, context: str | None = None) -> dict:
    """Run Grok Build CLI as a one-shot subagent."""
    _check_depth(depth)
    binary = _which("grok")
    if not binary:
        return {"ok": False, "error": "grok CLI not on PATH"}
    argv = [binary, "--no-auto-update", "--no-alt-screen", "-p", _compose_prompt(task, context), "--output-format", "plain"]
    model = model or os.environ.get("GROK_MODEL")
    if model:
        argv.extend(["-m", model])
    if write:
        argv.append("--always-approve")
    result = _run(argv, _workspace(cwd), TIMEOUT)
    result["target"] = "grok"
    return result

if __name__ == "__main__":
    WORKSPACE.mkdir(parents=True, exist_ok=True)
    mcp.run(transport="http", host=GATEWAY_HOST, port=GATEWAY_PORT, path="/mcp")
