#!/usr/bin/env python3
"""Benchmark benilla against WoWGD on the same character and take matching screenshots.

Writes website/benchmark/results.json and website/benchmark/<spot>-<client>.jpg.
Run from anywhere: python3 tools/bench_compare.py [--runs 3] [--idle 60] [--skip-timing]
"""
import argparse
import json
import os
import re
import shutil
import statistics
import subprocess
import tempfile
import threading
import time
from datetime import datetime
from pathlib import Path

import psutil

WOW = Path("/mnt/SSD/Wow")
SITE = WOW / "WoWdot/website/benchmark"
WOWGD = WOW / "WoWdot/export/wowgd/linux/WoWGD.x86_64"
BENILLA = WOW / "benilla/target/debug/benilla"
DATA = WOW / "GameData/VanillaData/Data"
HOST, ACCOUNT, PASSWORD, CHARACTER = "192.168.1.251", "wowgd", "wowgd", "Mwarf"
SIZE = "1920x1080"
SPOTS = ["Goldshire", "Stormwind", "BootyBay", "Darnassus", "ThunderBluff", "Moonglade"]
# benilla probes run on wall clock from launch, so each spot gets a fixed slot.
FIRST_TELE_AT, SLOT = 30.0, 30.0
ANSI = re.compile(r"\x1b\[[0-9;]*m")

# Milestone patterns per client, matched against log lines.
MARKS = {
    "benilla": {
        "login": "net: parked at character select",
        "entered": "net: in world as",
        "loaded": "loading screen: cleared",
    },
    "wowgd": {
        "login": "bench \\d+ characters",
        "entered": "bench \\d+ world entered",
        "loaded": "bench \\d+ world ready",
    },
}


def benilla_home() -> str:
    # A fresh config copy per run keeps Mark's config untouched and starts from the default camera.
    home = Path(tempfile.mkdtemp(prefix="benilla-bench-"))
    shutil.copytree(WOW / "benilla/benilla-config", home / "benilla-config")
    for saved in (home / "benilla-config/camera").glob("*"):
        saved.unlink()
    return str(home / "benilla-config")


def launch(client: str, shots: str | None, journal: str | None) -> tuple[subprocess.Popen, float]:
    if client == "wowgd":
        # Godot block-buffers a piped stdout, which would hide the milestones until exit.
        args = [
            "stdbuf", "-oL", str(WOWGD), "--", f"--resolution={SIZE}", "--bench", f"--realm={HOST}",
            f"--account={ACCOUNT}", f"--password={PASSWORD}", f"--character={CHARACTER}",
        ]
        if shots:
            # benilla's default third-person camera: 15 yd back, pitched 0.45 rad down.
            args += [
                "--chat=" + ";".join(f".tele {s}" for s in SPOTS), f"--shot={shots}",
                "--camera=-25.8,15",
            ]
        env = os.environ.copy()
        cwd = WOWGD.parent
    else:
        args = [str(BENILLA)]
        env = os.environ | {
            "BENILLA_HOME": benilla_home(), "WOW_DATA": str(DATA), "WOW_WIN": SIZE,
            "WOW_DPI": "1", "WOW_NOVSYNC": "1", "WOW_NOSOUND": "1", "WOW_HOST": HOST,
            "WOW_USER": ACCOUNT, "WOW_PASS": PASSWORD, "WOW_CHAR": CHARACTER,
            "WOW_UNATTENDED": "1", "NO_COLOR": "1",
        }
        if journal:
            env["WOW_FPS_JOURNAL"] = journal
        if shots:
            n = len(SPOTS)
            env |= {
                "WOW_PROBE_LUA": 'SetBinding("F","TOGGLEUI")',
                "WOW_PROBE_KEY": f"F@{FIRST_TELE_AT - 5:.0f}",
                "WOW_PROBE_CHAT": ";".join(f".tele {s}" for s in SPOTS),
                "WOW_PROBE_CHAT_AT": f"{FIRST_TELE_AT:.0f}",
                "WOW_PROBE_CHAT_EVERY": f"{SLOT:.0f}",
                "WOW_LIVE_SHOT": f"{shots}/shot.png",
                "WOW_LIVE_SHOT_AT": f"{FIRST_TELE_AT + SLOT - 3:.0f}",
                "WOW_LIVE_SHOT_EVERY": f"{SLOT:.0f}",
                "WOW_LIVE_SHOT_COUNT": str(n),
                "WOW_PROBE_EXIT_AT": f"{FIRST_TELE_AT + SLOT * n + 5:.0f}",
            }
        cwd = BENILLA.parents[2]
    t0 = time.monotonic()
    proc = subprocess.Popen(
        args, env=env, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
        errors="replace",
    )
    return proc, t0


def run(client: str, idle: float, shots: str | None = None, timeout: float = 400) -> dict:
    journal = tempfile.mktemp(suffix=".csv") if client == "benilla" and not shots else None
    proc, t0 = launch(client, shots, journal)
    lines: list[tuple[float, str]] = []

    def read() -> None:
        for line in proc.stdout:
            lines.append((time.monotonic() - t0, ANSI.sub("", line.rstrip())))

    reader = threading.Thread(target=read, daemon=True)
    reader.start()
    ps = psutil.Process(proc.pid)
    ps.cpu_percent()
    samples: list[tuple[float, float, float]] = []
    loaded_at = None
    while proc.poll() is None:
        time.sleep(0.5)
        try:
            samples.append((time.monotonic() - t0, ps.cpu_percent(), ps.memory_info().rss / 2**20))
        except psutil.NoSuchProcess:
            break
        if loaded_at is None:
            loaded_at = mark_time(client, lines, "loaded")
        now = time.monotonic() - t0
        if not shots and loaded_at is not None and now > loaded_at + idle:
            break
        if now > timeout:
            print(f"{client}: timed out")
            break
    if proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(10)
        except subprocess.TimeoutExpired:
            proc.kill()
    reader.join(5)
    result = {name: mark_time(client, lines, name) for name in MARKS[client]}
    result["log"] = [f"{t:8.2f} {line}" for t, line in lines]
    if not shots and result["loaded"] is not None:
        # Skip the first seconds after load, where both clients are still streaming.
        idle_samples = [s for s in samples if s[0] > result["loaded"] + 10]
        result["idle_cpu"] = statistics.mean(s[1] for s in idle_samples)
        result["idle_rss"] = statistics.mean(s[2] for s in idle_samples)
        result["peak_rss"] = max(s[2] for s in samples)
        result["fps"] = idle_fps(client, lines, journal, result["loaded"] + 10)
    result["samples"] = samples
    result["teleports"] = teleport_times(client, lines)
    return result


def mark_time(client: str, lines: list[tuple[float, str]], name: str) -> float | None:
    for t, line in list(lines):
        if re.search(MARKS[client][name], line):
            if client == "wowgd":
                # Godot's own clock starts with the process, so it is immune to pipe latency.
                return int(re.search(r"bench (\d+)", line)[1]) / 1000
            return t
    return None


def idle_fps(client: str, lines: list[tuple[float, str]], journal: str | None, after: float) -> float | None:
    if client == "wowgd":
        values = [
            int(m[2]) for _, line in lines
            if (m := re.search(r"bench (\d+) fps (\d+)", line)) and int(m[1]) / 1000 > after
        ]
        return statistics.mean(values) if values else None
    if not journal or not os.path.exists(journal):
        return None
    rows = [r.split(",") for r in Path(journal).read_text().splitlines() if r and not r.startswith("#")]
    header, body = rows[0], rows[1:]
    t, mean_ms = header.index("t"), header.index("mean_ms")
    values = [1000 / float(r[mean_ms]) for r in body if float(r[t]) > after and float(r[mean_ms]) > 0]
    return statistics.mean(values) if values else None


def teleport_times(client: str, lines: list[tuple[float, str]]) -> list[float]:
    if client == "wowgd":
        return [int(m[1]) / 1000 for _, line in lines if (m := re.search(r"bench (\d+) teleport", line))]
    return [t for t, line in lines if "loading screen: cleared" in line][1:]


def median(values: list) -> float | None:
    values = [v for v in values if v is not None]
    return round(statistics.median(values), 2) if values else None


def to_jpg(src: Path, dst: Path) -> None:
    subprocess.run(["magick", str(src), "-quality", "88", str(dst)], check=True)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--runs", type=int, default=3)
    parser.add_argument("--idle", type=float, default=60)
    parser.add_argument("--skip-timing", action="store_true")
    options = parser.parse_args()
    SITE.mkdir(parents=True, exist_ok=True)
    results_path = SITE / "results.json"
    results = json.loads(results_path.read_text()) if results_path.exists() else {}
    raw = Path(tempfile.mkdtemp(prefix="bench-raw-"))
    print(f"raw logs in {raw}")

    if not options.skip_timing:
        runs: dict[str, list[dict]] = {"benilla": [], "wowgd": []}
        for i in range(options.runs):
            for client in ("benilla", "wowgd"):
                print(f"timing run {i + 1} {client}")
                r = run(client, options.idle)
                (raw / f"{client}-{i}.log").write_text("\n".join(r.pop("log")))
                (raw / f"{client}-{i}.samples.json").write_text(json.dumps(r.pop("samples")))
                print({k: v for k, v in r.items() if k != "teleports"})
                runs[client].append(r)
                # Lets the server drop the previous session before the next login.
                time.sleep(15)
        results["timing"] = {
            client: {
                key: median([r.get(key) for r in rs])
                for key in ("login", "entered", "loaded", "idle_cpu", "idle_rss", "peak_rss", "fps")
            }
            | {"world_load": median([r["loaded"] - r["entered"] for r in rs if r["loaded"] and r["entered"]])}
            for client, rs in runs.items()
        }
        results["runs"] = options.runs
        results["idle_seconds"] = options.idle

    results["spots"] = SPOTS
    results["teleports"] = {}
    for client in ("benilla", "wowgd"):
        print(f"scenic run {client}")
        shots = raw / f"shots-{client}"
        shots.mkdir()
        r = run(client, 0, shots=str(shots))
        (raw / f"{client}-scenic.log").write_text("\n".join(r["log"]))
        results["teleports"][client] = r["teleports"]
        files = sorted(shots.glob("*.png"), key=lambda p: int(re.search(r"(\d+)\.png$", p.name)[1]))
        print(f"{client}: {len(files)} shots")
        for spot, png in zip(SPOTS, files):
            to_jpg(png, SITE / f"{spot.lower()}-{client}.jpg")
        time.sleep(15)

    results["date"] = datetime.now().strftime("%Y-%m-%d")
    results_path.write_text(json.dumps(results, indent=2))
    print(json.dumps(results.get("timing"), indent=2))


if __name__ == "__main__":
    main()
