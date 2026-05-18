from __future__ import annotations
from pathlib import Path

def embed_metadata(file_path: Path, title: str, artist: str | None,
                   album: str | None, track_number: int | None,
                   thumbnail_path: Path | None):
    from mutagen.id3 import ID3, TIT2, TPE1, TALB, TRCK, APIC
    from mutagen.id3 import ID3NoHeaderError
    try:
        tags = ID3(file_path)
    except ID3NoHeaderError:
        tags = ID3()
    tags["TIT2"] = TIT2(encoding=3, text=title)
    if artist:
        tags["TPE1"] = TPE1(encoding=3, text=artist)
    if album:
        tags["TALB"] = TALB(encoding=3, text=album)
    if track_number:
        tags["TRCK"] = TRCK(encoding=3, text=str(track_number))
    if thumbnail_path and thumbnail_path.exists():
        with open(thumbnail_path, "rb") as img:
            tags["APIC"] = APIC(encoding=3, mime="image/jpeg", type=3, desc="Cover", data=img.read())
    tags.save(file_path)
