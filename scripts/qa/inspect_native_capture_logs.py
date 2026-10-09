#!/usr/bin/env python3
"""Read only allowlisted capture diagnostics from the authorized QA Mac mini.

Never emit raw unified-log messages. Unknown/interpolated data stays in memory.
This reports diagnostics, not successful pixel delivery or UI acceptance.
"""
import argparse
import json
import re
import subprocess
import sys


EVENTS = {
    "start monitoring screen changes": "monitor_requested",
    "HandleAutoFrameBufferUpdateMessage2  flag %d": "screen_selection_flag",
    "SSAgent_MonitorScreenChanges_rpc result %d": "monitor_rpc_result",
    "stop screen capture": "capture_stop",
    "screen capture is not active": "capture_inactive",
}
NUMBERS = {
    "screen_selection_flag": re.compile(r"HandleAutoFrameBufferUpdateMessage2\s+flag\s+([01])(?:\s|$)"),
    "monitor_rpc_result": re.compile(r"SSAgent_MonitorScreenChanges_rpc result\s+(-?\d+)(?:\s|$)"),
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--minutes", type=int, choices=range(1, 31), default=5)
    args = parser.parse_args()
    predicate = 'process == "screensharingd" OR process == "ScreensharingAgent"'
    # Host/account are the explicitly authorized QA target, never user-supplied
    # shell fragments or a password. Require existing trusted SSH identity.
    command = ["ssh", "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=yes",
               "-o", "ConnectTimeout=15", "chenxu@100.64.0.3",
               f"/usr/bin/log show --last {args.minutes}m --style json --info --debug "
               f"--predicate '{predicate}'"]
    try:
        result = subprocess.run(command, capture_output=True, timeout=40)
        if result.returncode:
            raise ValueError("remote query failed")
        if len(result.stdout) > 8 * 1024 * 1024:
            raise ValueError("query exceeds inspection limit")
        rows = json.loads(result.stdout)
        if not isinstance(rows, list):
            raise ValueError("unexpected log container")
        count = 0
        for row in rows:
            if not isinstance(row, dict):
                continue
            event = EVENTS.get(row.get("formatString"))
            timestamp = row.get("timestamp", "")
            if event is None or not isinstance(timestamp, str) or not re.fullmatch(
                    r"\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}(?:\.\d+)?[+-]\d{4}", timestamp):
                continue
            record = {"timestamp": timestamp, "event": event}
            pattern = NUMBERS.get(event)
            message = row.get("eventMessage", "")
            match = pattern.search(message) if pattern and isinstance(message, str) else None
            if match:
                record["value"] = int(match.group(1))
            print(json.dumps(record))
            count += 1
        print(json.dumps({"matched_events": count, "minutes": args.minutes}))
        return 0
    except (subprocess.TimeoutExpired, ValueError, OSError):
        # Remote stderr/JSON parse errors can contain private values.
        print("Capture diagnostic query unavailable; raw output withheld.", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
