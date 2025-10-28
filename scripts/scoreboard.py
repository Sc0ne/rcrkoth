#!/usr/bin/env python3
"""
Terminal scoreboard GUI for running periodic flag-check scripts.

Behavior:
- Runs listed scripts every INTERVAL seconds for ROUNDS rounds (default 30s, 20 rounds).
- Each script is run with a timeout. Stdout (trimmed) is treated as the flag string.
- The default flag "replace me with your flag" is ignored (treated UNCLAIMED).
- Displays countdown timer (10 minutes) and live scoreboard + host dashboard.
- Silent on script errors/timeouts (they don't print nor interrupt UI).
- Optional --map <json> file maps flag string -> display team name.

Usage:
  ./scoreboard.py [--map flags.json] [--interval 30] [--rounds 20]
"""

import curses
import subprocess
import shlex
import time
import argparse
import json
import os
from collections import defaultdict, deque
from datetime import datetime
from threading import Thread, Event, Lock

# CONFIG (modify as needed)
SCRIPTS = [
    "./debian.sh",
    "./ftp.sh",
    "./http.sh",
    "./ldap.sh",
    "./smb.sh",
    "./ubuntu.sh",
    "./win11.sh",
    "./winserv.sh",
]
DEFAULT_FLAG = "replace me with your flag"
SCRIPT_TIMEOUT = 15        # seconds for each script run
INTERVAL = 30              # how often to run checks (seconds)
ROUNDS = 20                # number of runs (20 * 30s = 600s = 10 minutes)

# Internal structures
last_flag = {s: "" for s in SCRIPTS}         # last raw flag string per script
flag_history = defaultdict(int)              # counts per flag (excluding default)
flag_lasttime = {}                           # most recent time seen per flag
flag_map = {}                                # optional mapping flag->team
host_flag_history = {s: deque(maxlen=2) for s in SCRIPTS}  # keep last 2 flags if required
lock = Lock()

# Control flags
stop_event = Event()

def run_script_get_flag(script_path):
    """Run script and return stdout stripped. On error/timeout returns ''."""
    try:
        if not os.path.exists(script_path):
            return ""
        res = subprocess.run([script_path], stdout=subprocess.PIPE,
                             stderr=subprocess.DEVNULL, timeout=SCRIPT_TIMEOUT, text=True)
        out = res.stdout.strip()
        if "\n" in out:
            out = "\n".join([line.rstrip() for line in out.splitlines() if line.strip() != ""])
            out = out.strip()
        return out
    except (subprocess.TimeoutExpired, FileNotFoundError, PermissionError):
        return ""
    except Exception:
        return ""

def worker_loop(interval, rounds, start_time, stdscr):
    """Thread: run checks every interval, rounds times, updating structures."""
    for round_no in range(1, rounds + 1):
        if stop_event.is_set():
            break
        round_start = time.time()
        threads = []
        results = {}

        def run_and_store(script):
            val = run_script_get_flag(script)
            with lock:
                results[script] = val

        for script in SCRIPTS:
            t = Thread(target=run_and_store, args=(script,))
            t.daemon = True
            t.start()
            threads.append(t)

        for t in threads:
            while t.is_alive():
                if stop_event.is_set():
                    break
                t.join(timeout=0.1)
            if stop_event.is_set():
                break

        with lock:
            for script, val in results.items():
                normalized = val.strip() if val else ""
                host_flag_history[script].appendleft((normalized, datetime.now()))
                last_flag[script] = normalized
                if normalized and normalized != DEFAULT_FLAG:
                    flag_history[normalized] += 1
                    flag_lasttime[normalized] = datetime.now()

        elapsed = time.time() - round_start
        sleep_for = interval - elapsed
        if sleep_for > 0:
            slept = 0.0
            while slept < sleep_for:
                if stop_event.is_set():
                    break
                time.sleep(min(0.5, sleep_for - slept))
                slept += 0.5
    stop_event.set()

def draw_ui(stdscr, start_time, total_seconds):
    curses.use_default_colors()
    stdscr.nodelay(True)
    while not stop_event.is_set():
        stdscr.erase()
        h, w = stdscr.getmaxyx()

        # Header and countdown
        now = datetime.now()
        elapsed = (now - start_time).total_seconds()
        remaining = max(0, int(total_seconds - elapsed))
        mins = remaining // 60
        secs = remaining % 60
        timer_str = f"Time remaining: {mins:02d}:{secs:02d}"
        stdscr.addstr(0, 2, timer_str, curses.A_BOLD)

        # Round info
        round_est = min(ROUNDS, int(elapsed // INTERVAL) + 1)
        progress_str = f"Round: {round_est}/{ROUNDS}"
        stdscr.addstr(0, w//2 - len(progress_str)//2, progress_str)

        # Scoreboard area
        left_x = 2
        top_y = 2
        stdscr.addstr(top_y, left_x, "SCOREBOARD", curses.A_UNDERLINE | curses.A_BOLD)
        with lock:
            items = []
            for flag, count in flag_history.items():
                display = flag_map.get(flag, flag)
                items.append((count, display, flag))
            items.sort(reverse=True, key=lambda x: (x[0], x[1]))

        y = top_y + 2
        if not items:
            stdscr.addstr(y, left_x, "(no flags captured yet)")
            y += 1
        else:
            for cnt, display, flag in items:
                s = f"{display} ({cnt})"
                if len(s) > w//2 - 6:
                    s = s[:w//2 - 9] + "..."
                stdscr.addstr(y, left_x, s)
                y += 1

        # Host/dashboard area
        right_x = w//2 + 2
        stdscr.addstr(top_y, right_x, "HOST DASHBOARD", curses.A_UNDERLINE | curses.A_BOLD)
        y = top_y + 2
        with lock:
           for script in SCRIPTS:
                name = os.path.basename(script)
                last = last_flag.get(script, None)
                if last is None:
                   owner = "OFFLINE"          # no data at all
                elif last == "" or last == DEFAULT_FLAG:
                   owner = "UNCLAIMED"
                label = f"{name}: {owner}"
                maxlen = w - right_x - 4
                if len(label) > maxlen:
                    label = label[:maxlen-3] + "..."
                stdscr.addstr(y, right_x, label)
                y += 1
                raw_label = f"  {last}" if last else ""
                if len(raw_label) > maxlen:
                    raw_label = raw_label[:maxlen-3] + "..."
                stdscr.addstr(y, right_x, raw_label, curses.A_DIM)
                y += 1

        # Footer
        footer = "Press 'q' to quit early. Script runs every {}s for {} rounds.".format(INTERVAL, ROUNDS)
        stdscr.addstr(h-2, 2, footer, curses.A_REVERSE)

        stdscr.refresh()

        try:
            ch = stdscr.getch()
            if ch == ord('q') or ch == ord('Q'):
                stop_event.set()
                break
        except Exception:
            pass

        time.sleep(0.25)

def main():
    global INTERVAL, ROUNDS, SCRIPT_TIMEOUT, flag_map

    parser = argparse.ArgumentParser(description="Terminal scoreboard GUI for flag checks")
    parser.add_argument("--map", help="JSON file mapping flag->team name", default=None)
    parser.add_argument("--interval", type=int, help="Interval between checks in seconds", default=INTERVAL)
    parser.add_argument("--rounds", type=int, help="Number of rounds to perform", default=ROUNDS)
    parser.add_argument("--timeout", type=int, help="Per-script timeout seconds", default=SCRIPT_TIMEOUT)
    args = parser.parse_args()

    INTERVAL = args.interval
    ROUNDS = args.rounds
    SCRIPT_TIMEOUT = args.timeout

    if args.map:
        try:
            with open(args.map, "r") as f:
                flag_map = json.load(f)
        except Exception as e:
            print(f"Warning: failed to load map file: {e}")

    total_seconds = INTERVAL * ROUNDS
    start_time = datetime.now()

    worker = Thread(target=worker_loop, args=(INTERVAL, ROUNDS, start_time, None), daemon=True)
    worker.start()

    try:
        curses.wrapper(lambda scr: draw_ui(scr, start_time, total_seconds))
    except KeyboardInterrupt:
        stop_event.set()

    stop_event.set()
    worker.join(timeout=2)

if __name__ == "__main__":
    main()

