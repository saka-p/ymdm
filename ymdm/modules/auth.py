from __future__ import annotations
import subprocess


SUPPORTED_BROWSERS = ["firefox", "chrome", "chromium", "brave", "edge", "opera", "vivaldi"]

DESKTOP_TO_BROWSER = {
    "firefox": "firefox",
    "google-chrome": "chrome",
    "chromium": "chromium",
    "chromium-browser": "chromium",
    "brave-browser": "brave",
    "microsoft-edge": "edge",
    "opera": "opera",
    "vivaldi": "vivaldi",
}


def detect_default_browser() -> str | None:
    """Try to detect the default browser via xdg-settings."""
    try:
        result = subprocess.run(
            ["xdg-settings", "get", "default-web-browser"],
            capture_output=True, text=True, timeout=5
        )
        if result.returncode == 0:
            desktop = result.stdout.strip().lower().replace(".desktop", "")
            for key, browser in DESKTOP_TO_BROWSER.items():
                if key in desktop:
                    return browser
    except (FileNotFoundError, subprocess.TimeoutExpired):
        pass
    return None


def get_ydl_cookie_opts(browser: str) -> dict:
    """Return yt-dlp options for cookie extraction from the given browser."""
    return {"cookiesfrombrowser": (browser, None, None, None)}
