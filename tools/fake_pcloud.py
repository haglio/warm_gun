"""A stand-in for the pCloud HTTP API, serving a local folder over plain HTTP.

    python tools/fake_pcloud.py --root "/path/to/pCloud Drive" --scratch /tmp/warm-gun-scratch

Warm Gun talks to pCloud through a handful of JSON methods (see WarmGunKit's
``PCloudAPI``). This serves the same methods with the same response shapes off
a local directory, so the whole app can be driven end-to-end in the Simulator
with no credentials — and, just as important, with no writes to the real
library: ``renamefile`` only records the move in ``<scratch>/moves.json`` and
hides the file from later listings, and ``uploadfile`` lands in ``<scratch>``.
Any pCloud path that does not exist under ``--root`` is looked up under
``--scratch`` instead, which is how the sync folder (``/WarmGun``) works.

Methods: userinfo (any credentials log in), listfolder (recursive), getfilelink,
renamefile, createfolderifnotexists, uploadfile, plus ``/dl/<fileid>`` for the
bytes a file link points at. Durations come from ffprobe when it is on PATH,
cached in ``<scratch>/probe_cache.json`` so a second listing is instant.

Point the app at it with API host ``http://localhost:8765`` (the scheme marks
it as a local origin) and the same library path you would give pCloud.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

VIDEO_SUFFIXES = {".mp4", ".mkv", ".mov", ".avi", ".webm", ".m4v"}


def fnv64(text: str) -> int:
    h = 0xCBF29CE484222325
    for b in text.encode("utf-8"):
        h ^= b
        h = (h * 0x100000001B3) & 0xFFFFFFFFFFFFFFFF
    return h >> 1  # keep it inside a signed 64-bit int for Swift's Int64


class Store:
    def __init__(self, root: Path, scratch: Path, probe: bool) -> None:
        self.root = root
        self.scratch = scratch
        self.scratch.mkdir(parents=True, exist_ok=True)
        self.ffprobe = shutil.which("ffprobe") if probe else None
        self.cache_file = scratch / "probe_cache.json"
        self.probe_cache: dict[str, dict] = json.loads(self.cache_file.read_text()) if self.cache_file.exists() else {}
        self.moves_file = scratch / "moves.json"
        self.moved: dict[str, str] = json.loads(self.moves_file.read_text()) if self.moves_file.exists() else {}
        self.files_by_id: dict[int, Path] = {}

    def resolve(self, pcloud_path: str) -> Path | None:
        rel = pcloud_path.strip("/")
        for base in (self.root, self.scratch):
            candidate = base / rel if rel else base
            if candidate.exists():
                return candidate
        return None

    def pcloud_path(self, local: Path) -> str:
        for base in (self.root, self.scratch):
            try:
                return "/" + str(local.relative_to(base)).replace(os.sep, "/")
            except ValueError:
                continue
        return "/" + local.name

    def probe(self, path: Path) -> dict:
        key = str(path)
        stat = path.stat()
        cached = self.probe_cache.get(key)
        if cached and cached.get("size") == stat.st_size and cached.get("mtime") == int(stat.st_mtime):
            return cached
        info: dict = {"size": stat.st_size, "mtime": int(stat.st_mtime)}
        if self.ffprobe and path.suffix.lower() in VIDEO_SUFFIXES:
            try:
                out = subprocess.run(
                    [self.ffprobe, "-v", "error", "-select_streams", "v:0", "-show_entries",
                     "stream=codec_name,width,height:format=duration", "-of", "json", str(path)],
                    capture_output=True, text=True, timeout=30, check=False).stdout
                data = json.loads(out or "{}")
                stream = (data.get("streams") or [{}])[0]
                info.update({
                    "duration": data.get("format", {}).get("duration"),
                    "videocodec": stream.get("codec_name"),
                    "width": stream.get("width"),
                    "height": stream.get("height"),
                })
            except (subprocess.SubprocessError, ValueError):
                pass
        self.probe_cache[key] = info
        return info

    def save_caches(self) -> None:
        self.cache_file.write_text(json.dumps(self.probe_cache))
        self.moves_file.write_text(json.dumps(self.moved))

    def entry(self, path: Path, recursive: bool) -> dict | None:
        pc = self.pcloud_path(path)
        if pc in self.moved:
            return None
        if path.is_dir():
            folder = {
                "name": path.name or "/", "isfolder": True, "folderid": fnv64(pc),
                "modified": int(path.stat().st_mtime), "path": pc,
            }
            if recursive:
                children = []
                for child in sorted(path.iterdir()):
                    if child.name.startswith("."):
                        continue
                    e = self.entry(child, recursive)
                    if e is not None:
                        children.append(e)
                folder["contents"] = children
            return folder
        info = self.probe(path)
        fileid = fnv64(pc)
        self.files_by_id[fileid] = path
        entry = {
            "name": path.name, "isfolder": False, "fileid": fileid, "size": info["size"],
            "modified": info["mtime"], "contenttype": "video/mp4" if path.suffix.lower() in VIDEO_SUFFIXES else "application/octet-stream",
        }
        if info.get("duration"):
            entry["duration"] = str(info["duration"])  # pCloud sends it as a string
        for key in ("videocodec", "width", "height"):
            if info.get(key) is not None:
                entry[key] = info[key]
        return entry


class Handler(BaseHTTPRequestHandler):
    store: Store
    port: int

    def log_message(self, fmt, *args):  # quieter than the default, one line per call
        sys.stderr.write("%s %s\n" % (self.command, self.path.split("?")[0]))

    def reply(self, payload: dict, status: int = 200) -> None:
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:
        url = urlparse(self.path)
        q = {k: v[0] for k, v in parse_qs(url.query).items()}
        method = url.path.strip("/")
        if url.path.startswith("/dl/"):
            return self.serve_file(int(url.path[4:]))
        if method == "userinfo":
            # Like the real API: a token is minted only when getauth=1 is asked
            # for; the bare token check gets the account alone.
            body = {"result": 0, "email": "dev@example.com", "userid": 1}
            if q.get("getauth") == "1":
                body["auth"] = "dev-token"
            return self.reply(body)
        if method == "getapiserver":
            return self.reply({"result": 0, "api": ["localhost:%d" % self.port]})
        if method == "listfolder":
            target = self.store.resolve(q.get("path", "/"))
            if target is None or not target.is_dir():
                return self.reply({"result": 2005, "error": "Directory does not exist."})
            entry = self.store.entry(target, q.get("recursive") == "1")
            self.store.save_caches()
            return self.reply({"result": 0, "metadata": entry})
        if method == "getfilelink":
            fileid = int(q.get("fileid", "0"))
            if fileid not in self.store.files_by_id:
                return self.reply({"result": 2009, "error": "File not found."})
            return self.reply({"result": 0, "hosts": ["localhost:%d" % self.port], "path": "/dl/%d" % fileid,
                               "expires": int(time.time()) + 3600})
        if method == "renamefile":
            source = q.get("path")
            if source is None and "fileid" in q:
                local = self.store.files_by_id.get(int(q["fileid"]))
                source = self.store.pcloud_path(local) if local else None
            if source is None or self.store.resolve(source) is None:
                return self.reply({"result": 2009, "error": "File not found."})
            self.store.moved[source] = q.get("topath", "")
            self.store.save_caches()
            sys.stderr.write("renamefile recorded (nothing moved on disk): %s -> %s\n" % (source, q.get("topath")))
            return self.reply({"result": 0, "metadata": {"name": Path(q.get("topath", "")).name}})
        if method == "createfolderifnotexists":
            rel = q.get("path", "/").strip("/")
            if self.store.resolve(q.get("path", "/")) is None:
                (self.store.scratch / rel).mkdir(parents=True, exist_ok=True)
            return self.reply({"result": 0, "created": True})
        return self.reply({"result": 1000, "error": "Unknown method %s" % method})

    def do_POST(self) -> None:
        url = urlparse(self.path)
        q = {k: v[0] for k, v in parse_qs(url.query).items()}
        if url.path.strip("/") != "uploadfile":
            return self.reply({"result": 1000, "error": "Unknown method"})
        length = int(self.headers.get("Content-Length", "0"))
        raw = self.rfile.read(length)
        # One multipart part: the bytes between the first blank line and the closing boundary.
        boundary = self.headers.get("Content-Type", "").split("boundary=")[-1].encode()
        head, _, rest = raw.partition(b"\r\n\r\n")
        payload = rest.rsplit(b"\r\n--" + boundary, 1)[0]
        folder = self.store.scratch / q.get("path", "/").strip("/")
        folder.mkdir(parents=True, exist_ok=True)
        (folder / q.get("filename", "upload.bin")).write_bytes(payload)
        return self.reply({"result": 0, "fileids": [1], "metadata": [{"name": q.get("filename")}]})

    def serve_file(self, fileid: int) -> None:
        path = self.store.files_by_id.get(fileid)
        if path is None or not path.is_file():
            return self.reply({"result": 2009, "error": "File not found."}, status=404)
        size = path.stat().st_size
        self.send_response(200)
        self.send_header("Content-Type", "video/mp4")
        self.send_header("Content-Length", str(size))
        self.end_headers()
        with path.open("rb") as f:
            shutil.copyfileobj(f, self.wfile, length=1 << 20)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--root", required=True, help="local folder standing in for the pCloud root")
    parser.add_argument("--scratch", required=True, help="where uploads, moves and the probe cache go")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--no-probe", action="store_true", help="skip ffprobe; listings carry no durations")
    args = parser.parse_args()
    Handler.store = Store(Path(args.root).expanduser(), Path(args.scratch).expanduser(), probe=not args.no_probe)
    Handler.port = args.port
    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    sys.stderr.write("fake pCloud on http://localhost:%d  root=%s  scratch=%s\n" % (args.port, args.root, args.scratch))
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
