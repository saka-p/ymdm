from __future__ import annotations
from .config import Config, PlaylistEntry
from .state import get_connection, is_downloaded, mark_downloaded

def sync_playlist(playlist: PlaylistEntry, config: Config):
    import yt_dlp
    conn = get_connection()
    output_dir = config.general.music_dir / playlist.name
    output_dir.mkdir(parents=True, exist_ok=True)

    ydl_opts = {
        "format": "bestaudio/best",
        "postprocessors": [{
            "key": "FFmpegExtractAudio",
            "preferredcodec": config.general.format,
            "preferredquality": config.general.audio_quality,
        }],
        "outtmpl": str(output_dir / "%(title)s.%(ext)s"),
        "writethumbnail": config.metadata.embed_thumbnail,
        "quiet": True,
        "no_warnings": True,
    }

    with yt_dlp.YoutubeDL(ydl_opts) as ydl:
        info = ydl.extract_info(playlist.url, download=False)
        entries = info.get("entries", [])
        for entry in entries:
            video_id = entry.get("id")
            if not video_id:
                continue
            if config.general.sync_mode == "new_only" and is_downloaded(conn, video_id):
                continue
            ydl.download([f"https://music.youtube.com/watch?v={video_id}"])
            file_path = str(output_dir / f"{entry.get('title', video_id)}.{config.general.format}")
            mark_downloaded(
                conn,
                video_id=video_id,
                title=entry.get("title", ""),
                artist=entry.get("artist") or entry.get("uploader"),
                album=entry.get("album") or playlist.name,
                playlist=playlist.name,
                file_path=file_path,
            )
