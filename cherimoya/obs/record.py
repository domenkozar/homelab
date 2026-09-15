"""Control a local OBS instance using its authenticated WebSocket API."""

import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import time

import websocket


class OBSNotReady(RuntimeError):
    pass


class OBSOutputUnavailable(RuntimeError):
    pass


def obs_running():
    return subprocess.run(
        ["pgrep", "-u", str(os.getuid()), "-x", r"obs|\.obs-wrapped"],
        stdout=subprocess.DEVNULL, check=False,
    ).returncode == 0


def close_obs():
    result = subprocess.run(
        ["pgrep", "-u", str(os.getuid()), "-x", r"obs|\.obs-wrapped"],
        capture_output=True, text=True, check=False,
    )
    pids = [int(pid) for pid in result.stdout.split()]
    if not pids:
        return
    if len(pids) != 1:
        raise RuntimeError("Recording saved; multiple OBS instances are open, so close the desired one manually.")
    pid = pids[0]
    # OBS 32 handles SIGTERM by saving settings and quitting the application;
    # SIGINT only closes the window, which can leave a tray instance running.
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    deadline = time.monotonic() + 20
    while time.monotonic() < deadline:
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            print("OBS closed.")
            return
        time.sleep(0.2)
    raise RuntimeError("Recording saved, but OBS has not closed yet. Check OBS for a dialog.")


def stop_recording(ws, active):
    if active:
        # Finalizing a long recording can take longer than a normal API request.
        ws.settimeout(60)
        print("Saved: " + request(ws, "StopRecord")["outputPath"])
    else:
        print("Already stopped.")
    # Keep OBS open if another output still needs it.
    for name in ("GetStreamStatus", "GetVirtualCamStatus", "GetReplayBufferStatus"):
        try:
            if request(ws, name)["outputActive"]:
                print("OBS remains open because another output is active.")
                return
        except OBSOutputUnavailable:
            continue
    close_obs()


def launch_obs():
    state = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state"))
    log_path = state / "obs-record-launch.log"
    log_path.parent.mkdir(parents=True, exist_ok=True)
    with log_path.open("a") as log:
        return subprocess.Popen(
            ["obs", "--collection", "Desktop and face", "--profile", "Desktop and face",
             "--scene", "Desktop", "--minimize-to-tray"],
            stdin=subprocess.DEVNULL, stdout=log, stderr=log, start_new_session=True,
        )


def connect_for_recording():
    deadline = time.monotonic() + 60
    process = None
    checked_process = False
    while True:
        ws = None
        try:
            ws = connect()
            request(ws, "GetRecordStatus")
            return ws
        except (ConnectionRefusedError, ConnectionResetError, TimeoutError,
                websocket.WebSocketTimeoutException, OBSNotReady):
            if ws is not None:
                ws.close()
            if not checked_process:
                if not obs_running():
                    print("Opening OBS…", flush=True)
                    process = launch_obs()
                checked_process = True
            if process is not None and process.poll() is not None:
                raise RuntimeError("OBS exited during startup; see ~/.local/state/obs-record-launch.log.")
            if time.monotonic() >= deadline:
                raise RuntimeError("OBS did not become ready within 60 seconds. Check its WebSocket settings.")
            time.sleep(0.5)
        except BaseException:
            if ws is not None:
                ws.close()
            raise


def notification_call(method, *arguments):
    result = subprocess.run(
        ["gdbus", "call", "--session", "--dest", "org.freedesktop.Notifications",
         "--object-path", "/org/freedesktop/Notifications",
         "--method", f"org.freedesktop.Notifications.{method}", *arguments],
        capture_output=True, text=True, timeout=2, check=True,
    )
    return result.stdout


def show_countdown(remaining, notification_id):
    reply = notification_call(
        "Notify", "record", str(notification_id), "media-record",
        f"Recording in {remaining}…", "Get ready · Ctrl-C in the terminal cancels",
        "[]", "{'transient': <true>, 'suppress-sound': <true>}", "0",
    )
    match = re.search(r"uint32 (\d+)", reply)
    if not match:
        raise RuntimeError("Could not read the countdown notification ID.")
    return int(match[1])


def close_countdown(notification_id):
    if notification_id:
        notification_call("CloseNotification", str(notification_id))


def connect():
    root = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
    path = root / "obs-studio/plugin_config/obs-websocket/config.json"
    config = json.loads(path.read_text())
    if not config.get("server_enabled"):
        raise RuntimeError("Enable WebSocket server in OBS → Tools → WebSocket Server Settings.")
    ws = websocket.create_connection(
        f"ws://127.0.0.1:{config.get('server_port', 4455)}",
        timeout=5,
        http_no_proxy=["127.0.0.1"],
    )
    try:
        hello = json.loads(ws.recv())
        if hello["op"] != 0:
            raise RuntimeError("Unexpected OBS handshake.")
        identify = {"rpcVersion": 1, "eventSubscriptions": 0}
        auth = hello["d"].get("authentication")
        if auth:
            def digest(value):
                return base64.b64encode(hashlib.sha256(value.encode()).digest()).decode()
            secret = digest(config["server_password"] + auth["salt"])
            identify["authentication"] = digest(secret + auth["challenge"])
        ws.send(json.dumps({"op": 1, "d": identify}))
        if json.loads(ws.recv())["op"] != 2:
            raise RuntimeError("OBS authentication failed.")
        return ws
    except BaseException:
        ws.close()
        raise


def request(ws, name):
    ws.send(json.dumps({"op": 6, "d": {"requestType": name, "requestId": name}}))
    response = json.loads(ws.recv())
    if response["op"] != 7 or response["d"]["requestId"] != name:
        raise RuntimeError("Unexpected OBS response.")
    data = response["d"]
    if not data["requestStatus"]["result"]:
        if data["requestStatus"].get("code") == 604 and name in (
            "GetVirtualCamStatus", "GetReplayBufferStatus"
        ):
            raise OBSOutputUnavailable(data["requestStatus"].get("comment", "Output unavailable"))
        if data["requestStatus"].get("code") == 207:
            raise OBSNotReady("OBS is still starting.")
        raise RuntimeError(data["requestStatus"].get("comment", "OBS request failed."))
    return data.get("responseData", {})


def main():
    parser = argparse.ArgumentParser(prog="record", description="Open OBS if needed, then start recording.")
    parser.add_argument("--delay", type=int, default=None, metavar="SECONDS",
                        help="Countdown duration (default: 5; use 0 to start immediately)")
    actions = parser.add_mutually_exclusive_group()
    actions.add_argument("--stop", action="store_true", help="Save recording and close OBS")
    actions.add_argument("--status", action="store_true", help="Show recording status")
    args = parser.parse_args()
    if args.delay is not None and (args.delay < 0 or args.stop or args.status):
        parser.error("--delay must be nonnegative and is only valid when starting")
    delay = 5 if args.delay is None else args.delay

    if (args.stop or args.status) and not obs_running():
        print("Stopped (OBS is closed).")
        return
    ws = connect() if args.stop or args.status else connect_for_recording()
    try:
        status = request(ws, "GetRecordStatus")
        active = status["outputActive"]
        if args.status:
            print("Paused" if status.get("outputPaused") else "Recording" if active else "Stopped")
        elif args.stop:
            stop_recording(ws, active)
        elif active:
            print("Already recording.")
        else:
            notification_id = 0
            try:
                for remaining in range(delay, 0, -1):
                    print(f"Recording in {remaining}s… (Ctrl-C to cancel)", flush=True)
                    notification_id = show_countdown(remaining, notification_id)
                    time.sleep(1)
            finally:
                close_countdown(notification_id)
            request(ws, "StartRecord")
            print("Recording started. Run `record --stop` to finish.")
    finally:
        ws.close()


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\nCancelled.", file=sys.stderr)
        sys.exit(130)
    except (OSError, ValueError, KeyError, RuntimeError, subprocess.SubprocessError,
            websocket.WebSocketException) as error:
        print(f"record: {error}\nMake sure OBS is open and its WebSocket server is enabled.", file=sys.stderr)
        sys.exit(1)
