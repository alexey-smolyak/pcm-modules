import os
import sys
import time
import json
import subprocess
from datetime import datetime

try:
    import pyautogui
except ImportError:
    pyautogui = None

BASE = r"C:\Users\admin\Documents"

MAIN = os.path.join(BASE, "main.py")

DATA = os.path.join(BASE, "students.json")

SHOTS = os.path.join(BASE, "screenshots")

SESSION_SECONDS = 45 * 60

SCREENSHOT_INTERVAL = 60

def load():

    try:

        with open(DATA, "r", encoding="utf-8") as f:
            return json.load(f)

    except Exception:

        return []


def save(data):

    records = load()

    records.append(data)

    with open(DATA, "w", encoding="utf-8") as f:

        json.dump(
            records,
            f,
            ensure_ascii=False,
            indent=2
        )


def screenshot():

    if pyautogui is None:
        return

    try:

        os.makedirs(
            SHOTS,
            exist_ok=True
        )

        name = datetime.now().strftime(
            "screen_%Y-%m-%d_%H-%M-%S.png"
        )

        path = os.path.join(
            SHOTS,
            name
        )

        pyautogui.screenshot().save(path)

    except Exception as e:

        print(
            "Screenshot error:",
            e
        )


def run_timer():

    screenshot()

    started = time.time()

    next_screenshot = started + SCREENSHOT_INTERVAL

    while True:

        now = time.time()

        elapsed = now - started

        if elapsed >= SESSION_SECONDS:
            break

        if now >= next_screenshot:

            screenshot()

            next_screenshot += SCREENSHOT_INTERVAL

        time.sleep(1)

    save({
        "event": "session_ended",
        "timestamp": datetime.now().isoformat(
            timespec="seconds"
        )
    })

    try:

        subprocess.Popen(
            [
                sys.executable,
                MAIN
            ],
            creationflags=subprocess.CREATE_NO_WINDOW
        )

    except Exception as e:

        save({
            "event": "restart_error",
            "error": str(e),
            "timestamp": datetime.now().isoformat(
                timespec="seconds"
            )
        })


if __name__ == "__main__":

    run_timer()