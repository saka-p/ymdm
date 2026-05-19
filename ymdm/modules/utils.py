from __future__ import annotations
from urllib.parse import urlparse, parse_qs, urlencode, urlunparse


def sanitize_youtube_url(url: str) -> str:
    """Clean up a YouTube Music URL.

    - Removes backslashes zsh may have added
    - Strips tracking params (si=, etc), keeping only list=
    """
    url = url.replace("\\", "")
    parsed = urlparse(url)
    params = parse_qs(parsed.query)
    clean_params = {k: v[0] for k, v in params.items() if k == "list"}
    clean_query = urlencode(clean_params)
    return urlunparse(parsed._replace(query=clean_query))
