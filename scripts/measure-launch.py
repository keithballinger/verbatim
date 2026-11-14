#!/usr/bin/env python3
"""Measure process creation to a loaded, editable note after folder authorization.

Each newly launched process is terminated immediately after the readiness marker.
Do not interact with the app during this benchmark. This is not a cold-cache test.
"""
import argparse
import selectors
import subprocess
import time
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--runs", type=int, default=5)
args = parser.parse_args()
if not 1 <= args.runs <= 20:
    parser.error("--runs must be between 1 and 20")
if subprocess.run(["pgrep", "-x", "Verbatim"], capture_output=True).returncode == 0:
    parser.error("Close Verbatim before measuring launch.")

binary = Path(__file__).resolve().parent.parent / ".build/Build/Products/Release/Verbatim.app/Contents/MacOS/Verbatim"
for n in range(args.runs):
    start = time.perf_counter()
    process = subprocess.Popen([str(binary), "--measure-launch"], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, bufsize=0)
    selector = selectors.DefaultSelector()
    selector.register(process.stderr, selectors.EVENT_READ)
    try:
        deadline = start + 10
        while time.perf_counter() < deadline:
            if selector.select(timeout=0.1):
                line = process.stderr.readline()
                if not line:
                    raise SystemExit("Verbatim exited without a readiness marker.")
                if b"VERBATIM_EDITOR_READY" in line:
                    print(f"Launch {n + 1}: {(time.perf_counter() - start) * 1000:.1f} ms", flush=True)
                    break
        else:
            raise SystemExit("No editor became ready. Run the app normally and authorize a notes folder first.")
    finally:
        selector.close()
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
        process.stderr.close()
