#!/usr/bin/env python3
# Live test driver: stand in for an MCP client and drive the real
# screenreader-mcp binary over stdio against a REAL, running NVDA bridge.
#
# This is the contributor's hands-on equivalent of the automated tiers. The Go
# unit/integration tests put a FAKE bridge behind the server, and the
# conformance tier puts the real Python bridge behind it but fakes NVDA at the
# bridge's own AdapterFactory. Only here is *everything* real -- the server
# binary, the wire, the add-on, and NVDA itself -- which is the one thing no
# automated tier can be (it needs a human at the keyboard to hear the speech).
# See CONTRIBUTING.md, "Running a live test against NVDA".
#
# Framing is MCP's stdio transport: newline-delimited JSON-RPC 2.0. The server
# logs to stderr, so stdout stays a clean JSON stream.
#
# Usage:
#   py -3.13 scripts/live_test.py <binary> smoke [announce-text]
#       Connect (live mode), prove tool gating, ANNOUNCE (you should hear it),
#       read the buffers, disconnect. No gestures are pressed.
#
#   py -3.13 scripts/live_test.py <binary> run [--mode live|silent]
#       Connect, then read one command per line from stdin and run it against
#       the open session, printing each result. Feed a scenario with a heredoc.
#       Commands:
#         announce <text...>         speak <text> to the human
#         press <gestureId> [...]    press reader gestures, in order
#         bookmark                   print get_next_speech_index
#         speech <sinceIndex>        get_speech since an index
#         lastspeech                 get_last_speech
#         braille <sinceIndex>       get_braille since an index
#         waitspeech <timeout> <t>   wait up to <timeout>s for speech containing <t>
#         waitfinish <timeout>       wait for speech to settle
#         status                     the connection status
#         sleep <seconds>            pause (give the human time to act)
#         echo <text...>             annotate the transcript
#         disconnect                 end the session (implicit at EOF too)

from __future__ import annotations

import json
import queue
import subprocess
import sys
import threading
import time

DEFAULT_ANNOUNCE = (
    "This is the agent speaking through NVDA. If you can hear this, announce works."
)


def main(argv: list[str]) -> int:
    if len(argv) < 3:
        print(__doc__)
        return 2
    binary, command = argv[1], argv[2]

    mode = "live"
    rest = argv[3:]
    if "--mode" in rest:
        i = rest.index("--mode")
        mode = rest[i + 1]
        rest = rest[:i] + rest[i + 2:]

    server = Server(binary)
    try:
        server.initialize()
        if command == "smoke":
            return scenario_smoke(server, rest[0] if rest else DEFAULT_ANNOUNCE)
        if command == "run":
            return scenario_run(server, mode)
        print(f"unknown command {command!r}")
        return 2
    finally:
        server.close()


# -- scenarios -----------------------------------------------------------------


def scenario_smoke(server: "Server", announce_text: str) -> int:
    names = server.tool_names()
    print(f"== tools before connect ({len(names)}): {', '.join(names)}")
    if "announce" in names:
        print("!! announce is advertised before connecting -- gating is broken")
        return 1

    print("== list_readers:")
    print(indent(server.tool("list_readers")))

    print("\n== connecting to nvda in LIVE mode ...")
    session = server.tool("connect_reader", {"reader": "nvda", "mode": "live"})
    print(indent(session))
    caps = session.get("capabilities", [])
    if "announce" not in caps:
        print(f"!! the bridge did not announce `announce` (got {caps})")
        return 1

    after = server.tool_names()
    print(f"== tools after connect ({len(after)}): {', '.join(after)}")
    if "announce" not in after:
        print("!! announce tool was not published after connect")
        return 1

    print(f'\n== ANNOUNCE -> you should HEAR: "{announce_text}"')
    print(f"   {server.tool('announce', {'text': announce_text})}")

    print(f"== get_next_speech_index: {server.tool('get_next_speech_index')}")
    print(f"== get_last_speech:       {server.tool('get_last_speech')}")

    print(f"\n== disconnecting: {server.tool('disconnect_reader')}")
    print("\n== SMOKE OK")
    return 0


def scenario_run(server: "Server", mode: str) -> int:
    session = server.tool("connect_reader", {"reader": "nvda", "mode": mode})
    print(f"== connected: {session.get('reader')} {session.get('readerVersion')} "
          f"over {session.get('endpoint')}, mode={session.get('mode')}, "
          f"synth={session.get('synth')}, caps={session.get('capabilities')}")

    for line in sys.stdin:
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        verb, _, arg = line.partition(" ")
        arg = arg.strip()
        try:
            handled = run_command(server, verb, arg)
        except Exception as exc:  # noqa: BLE001 -- a driver; surface everything
            print(f"   !! {verb}: {exc}")
            continue
        if handled == "stop":
            break

    print(f"== disconnecting: {server.tool('disconnect_reader')}")
    return 0


def run_command(server: "Server", verb: str, arg: str):
    if verb == "announce":
        print(f"-> announce {arg!r}: {server.tool('announce', {'text': arg})}")
    elif verb == "press":
        ids = arg.split()
        print(f"-> press {ids}: {server.tool('press_gesture', {'gestures': ids})}")
    elif verb == "bookmark":
        print(f"-> bookmark: {server.tool('get_next_speech_index')}")
    elif verb == "speech":
        print(f"-> speech since {arg}: {server.tool('get_speech', {'since_index': int(arg)})}")
    elif verb == "lastspeech":
        print(f"-> lastspeech: {server.tool('get_last_speech')}")
    elif verb == "braille":
        print(f"-> braille since {arg}: {server.tool('get_braille', {'since_index': int(arg)})}")
    elif verb == "waitspeech":
        timeout, _, text = arg.partition(" ")
        result = server.tool("wait_for_speech", {"text": text.strip(), "timeout": float(timeout)})
        print(f"-> waitspeech {text.strip()!r} ({timeout}s): {result}")
    elif verb == "waitfinish":
        print(f"-> waitfinish ({arg}s): {server.tool('wait_for_speech_to_finish', {'timeout': float(arg)})}")
    elif verb == "status":
        print(f"-> status: {server.tool('status')}")
    elif verb == "sleep":
        time.sleep(float(arg))
        print(f"-> slept {arg}s")
    elif verb == "echo":
        print(f"-- {arg}")
    elif verb == "disconnect":
        return "stop"
    else:
        print(f"   ?? unknown command {verb!r}")
    return None


# -- the MCP-over-stdio client -------------------------------------------------


class Server:
    """The screenreader-mcp binary, spoken to as an MCP client would."""

    def __init__(self, binary: str) -> None:
        self._proc = subprocess.Popen(
            [binary], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, bufsize=0,
        )
        self._lines: "queue.Queue[bytes]" = queue.Queue()
        self._err: list[bytes] = []
        threading.Thread(target=_pump, args=(self._proc.stdout, self._lines), daemon=True).start()
        threading.Thread(target=_drain, args=(self._proc.stderr, self._err), daemon=True).start()
        self._id = 0

    def initialize(self) -> None:
        info = self._call("initialize", {
            "protocolVersion": "2025-06-18",
            "capabilities": {},
            "clientInfo": {"name": "live_test", "version": "0"},
        }).get("serverInfo", {})
        print(f"== initialized: {info.get('name')} {info.get('version')}")
        self._notify("notifications/initialized")

    def tool_names(self) -> list[str]:
        return sorted(t["name"] for t in self._call("tools/list")["tools"])

    def tool(self, name: str, arguments: dict | None = None) -> dict:
        result = self._call("tools/call", {"name": name, "arguments": arguments or {}})
        if result.get("isError"):
            text = "".join(c.get("text", "") for c in result.get("content", []))
            raise RuntimeError(text or "tool failed")
        if "structuredContent" in result:
            return result["structuredContent"]
        for block in result.get("content", []):
            if block.get("type") == "text":
                try:
                    return json.loads(block["text"])
                except json.JSONDecodeError:
                    return {"text": block["text"]}
        return result

    def close(self) -> None:
        try:
            self._proc.stdin.close()
        except Exception:
            pass
        self._proc.terminate()

    def _call(self, method: str, params: dict | None = None, timeout: float = 30.0) -> dict:
        self._id += 1
        my_id = self._id
        msg = {"jsonrpc": "2.0", "id": my_id, "method": method}
        if params is not None:
            msg["params"] = params
        self._send(msg)
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            try:
                raw = self._lines.get(timeout=max(0.01, deadline - time.monotonic()))
            except queue.Empty:
                break
            reply = json.loads(raw)
            if reply.get("id") != my_id:
                continue  # a notification or a later id -- keep reading
            if "error" in reply:
                raise RuntimeError(f"{method} -> {reply['error']}")
            return reply.get("result", {})
        stderr = b"".join(self._err).decode("utf-8", "replace").strip()
        hint = f"\n---- server stderr ----\n{stderr}" if stderr else ""
        raise TimeoutError(f"no response to {method} within {timeout}s{hint}")

    def _notify(self, method: str, params: dict | None = None) -> None:
        msg = {"jsonrpc": "2.0", "method": method}
        if params is not None:
            msg["params"] = params
        self._send(msg)

    def _send(self, msg: dict) -> None:
        self._proc.stdin.write((json.dumps(msg) + "\n").encode("utf-8"))
        self._proc.stdin.flush()


def _pump(stream, out: "queue.Queue[bytes]") -> None:
    for line in stream:
        line = line.strip()
        if line:
            out.put(line)


def _drain(stream, buf: list[bytes]) -> None:
    for line in stream:
        buf.append(line)


def indent(obj) -> str:
    return json.dumps(obj, indent=2, ensure_ascii=False)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
