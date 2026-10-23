from __future__ import annotations

import base64
import ipaddress
import json
import logging
import mimetypes
import re
import socket
import subprocess
import sys
import time
import uuid
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from threading import Event, Lock, Thread
from typing import Any
from urllib.parse import parse_qs, urlparse

import ifaddr
import requests
from zeroconf import IPVersion, ServiceInfo, Zeroconf


HOST = "0.0.0.0"
PORT = 8080
BRIDGE_URL = "ws://localhost:9333"
REQUEST_TIMEOUT = 20
ASSET_TTL_SECONDS = 30 * 60
MAX_CACHED_VIDEO_BYTES = 35 * 1024 * 1024
BONJOUR_SERVICE_TYPE = "_rednoteocr._tcp.local."
BONJOUR_REFRESH_INTERVAL_SECONDS = 15

PROJECT_ROOT = Path(__file__).resolve().parent
VENV_PYTHON = PROJECT_ROOT / ".venv" / "bin" / "python"
CLI_PATH = PROJECT_ROOT / "xiaohongshu-skills" / "scripts" / "cli.py"

USER_AGENT = (
    "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) "
    "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 "
    "Mobile/15E148 Safari/604.1"
)

URL_PATTERN = re.compile(r"https?://[^\s]+", re.IGNORECASE)
EXPLORE_PATTERN = re.compile(
    r"/(?:explore|discovery/item)/(?P<feed_id>[A-Za-z0-9]+)",
    re.IGNORECASE,
)
TOKEN_PATTERN = re.compile(
    r"[?&]xsec_token=(?P<xsec_token>[^&#]+)",
    re.IGNORECASE,
)


logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s: %(message)s",
)
LOGGER = logging.getLogger("rednote-local-backend")
ASSET_CACHE: dict[str, dict[str, Any]] = {}
ASSET_CACHE_LOCK = Lock()


class LinkResolutionError(RuntimeError):
    pass


def extract_first_url(raw_input: str) -> str:
    match = URL_PATTERN.search(raw_input.strip())
    if not match:
        raise LinkResolutionError("The provided text does not contain a usable URL.")

    url = match.group(0).rstrip("。！？,;)")
    if url.startswith("http://"):
        url = "https://" + url[len("http://") :]

    return url


def resolve_share_link(raw_input: str) -> dict[str, Any]:
    entry_url = extract_first_url(raw_input)

    session = requests.Session()
    response = session.get(
        entry_url,
        headers={"User-Agent": USER_AGENT},
        allow_redirects=True,
        timeout=REQUEST_TIMEOUT,
    )
    response.raise_for_status()

    final_url = response.url
    html = response.text

    feed_id, xsec_token = extract_feed_identifiers(final_url, html)
    if not feed_id or not xsec_token:
        raise LinkResolutionError(
            "The share link resolved, but feed_id or xsec_token could not be extracted yet."
        )

    return {
        "entry_url": entry_url,
        "resolved_url": final_url,
        "feed_id": feed_id,
        "xsec_token": xsec_token,
        "html": html,
    }


def extract_feed_identifiers(url: str, html: str) -> tuple[str | None, str | None]:
    parsed = urlparse(url)
    feed_id = None
    xsec_token = None

    if explore_match := EXPLORE_PATTERN.search(parsed.path):
        feed_id = explore_match.group("feed_id")

    query = parse_qs(parsed.query)
    if "xsec_token" in query and query["xsec_token"]:
        xsec_token = query["xsec_token"][0]

    if not xsec_token:
        if token_match := TOKEN_PATTERN.search(html):
            xsec_token = token_match.group("xsec_token")

    if not feed_id:
        html_patterns = [
            r'"noteId"\s*:\s*"(?P<feed_id>[A-Za-z0-9]+)"',
            r'"note_id"\s*:\s*"(?P<feed_id>[A-Za-z0-9]+)"',
            r"/explore/(?P<feed_id>[A-Za-z0-9]+)\?",
        ]

        for pattern in html_patterns:
            match = re.search(pattern, html)
            if match:
                feed_id = match.group("feed_id")
                break

    return feed_id, xsec_token


def run_cli(*args: str) -> dict[str, Any]:
    if not VENV_PYTHON.exists():
        raise RuntimeError(f"Python virtual environment not found at {VENV_PYTHON}")

    if not CLI_PATH.exists():
        raise RuntimeError(f"xiaohongshu-skills CLI not found at {CLI_PATH}")

    command = [
        str(VENV_PYTHON),
        str(CLI_PATH),
        "--bridge-url",
        BRIDGE_URL,
        *args,
    ]

    completed = subprocess.run(
        command,
        cwd=PROJECT_ROOT,
        capture_output=True,
        text=True,
        encoding="utf-8",
    )

    stdout = completed.stdout.strip()
    stderr = completed.stderr.strip()

    if not stdout:
        raise RuntimeError(stderr or "The xiaohongshu-skills CLI did not return any JSON output.")

    try:
        payload = json.loads(stdout)
    except json.JSONDecodeError as error:
        raise RuntimeError(f"CLI returned non-JSON output: {stdout}") from error

    if completed.returncode == 1:
        raise RuntimeError(
            payload.get("hint")
            or payload.get("message")
            or "xiaohongshu-skills reports that the browser is not logged in."
        )

    if completed.returncode != 0:
        raise RuntimeError(
            payload.get("error")
            or payload.get("message")
            or stderr
            or f"xiaohongshu-skills exited with code {completed.returncode}."
        )

    return payload


def download_note_images(image_urls: list[str], referer_url: str) -> list[dict[str, str]]:
    session = requests.Session()
    downloaded_images: list[dict[str, str]] = []
    headers = {
        "User-Agent": USER_AGENT,
        "Referer": referer_url,
    }

    for image_url in image_urls[:8]:
        for candidate_url in candidate_image_urls(image_url):
            try:
                response = session.get(
                    candidate_url,
                    headers=headers,
                    timeout=REQUEST_TIMEOUT,
                )
                response.raise_for_status()

                content_type = response.headers.get("Content-Type", "").split(";")[0].strip()
                if not content_type.startswith("image/"):
                    guessed_type, _ = mimetypes.guess_type(candidate_url)
                    content_type = guessed_type or "image/jpeg"

                encoded = base64.b64encode(response.content).decode("utf-8")
                downloaded_images.append(
                    {
                        "url": candidate_url,
                        "data_url": f"data:{content_type};base64,{encoded}",
                    }
                )
                break
            except Exception as error:
                LOGGER.warning("Image download failed for %s: %s", candidate_url, error)

    return downloaded_images


def normalize_asset_url(url: str) -> str:
    normalized = (
        url.strip()
        .replace("\\/", "/")
        .replace("\\u002F", "/")
        .replace("&amp;", "&")
    )
    if normalized.startswith("//"):
        normalized = "https:" + normalized
    if normalized.startswith("http://"):
        normalized = "https://" + normalized[len("http://") :]
    return normalized


def candidate_image_urls(url: str) -> list[str]:
    normalized = normalize_asset_url(url)
    candidates: list[str] = []

    if "!" in normalized:
        candidates.append(normalized.split("!", 1)[0])

    candidates.append(normalized)

    deduplicated: list[str] = []
    seen: set[str] = set()

    for candidate in candidates:
        if candidate and candidate not in seen:
            deduplicated.append(candidate)
            seen.add(candidate)

    return deduplicated


def html_attributes(tag: str) -> dict[str, str]:
    regex = re.compile(
        r'([A-Za-z_:][-A-Za-z0-9_:.]*)\s*=\s*(?:"([^"]*)"|\'([^\']*)\'|([^\s>]+))'
    )
    attributes: dict[str, str] = {}

    for match in regex.finditer(tag):
        key = match.group(1).lower()
        value = match.group(2) or match.group(3) or match.group(4) or ""
        attributes[key] = value

    return attributes


def extract_video_urls(html: str) -> list[str]:
    candidates: list[str] = []

    meta_tags = re.findall(r"<meta\b[^>]*>", html, flags=re.IGNORECASE)
    allowed_meta_keys = {
        "og:video",
        "og:video:url",
        "og:video:secure_url",
        "twitter:player:stream",
    }

    for tag in meta_tags:
        attributes = html_attributes(tag)
        key = (attributes.get("property") or attributes.get("name") or "").lower()
        content = attributes.get("content", "")
        if key in allowed_meta_keys and content:
            candidates.append(content)

    raw_url_patterns = [
        r'https?://[^"\'\s<>]+(?:mp4|m3u8)(?:\?[^"\'\s<>]*)?',
        r'https?:\\\\/\\\\/[^"\'\s<>]+(?:mp4|m3u8)(?:\?[^"\'\s<>]*)?',
    ]

    for pattern in raw_url_patterns:
        candidates.extend(re.findall(pattern, html, flags=re.IGNORECASE))

    keyed_patterns = [
        r'"(?:masterUrl|playUrl|h264Url|h265Url|videoUrl|originVideoKey|url)"\s*:\s*"([^"]+?(?:mp4|m3u8)[^"]*)"',
        r"'(?:masterUrl|playUrl|h264Url|h265Url|videoUrl|originVideoKey|url)'\s*:\s*'([^']+?(?:mp4|m3u8)[^']*)'",
    ]

    for pattern in keyed_patterns:
        candidates.extend(re.findall(pattern, html, flags=re.IGNORECASE))

    deduplicated: list[str] = []
    seen: set[str] = set()

    for candidate in candidates:
        normalized = normalize_asset_url(candidate)
        if normalized and normalized not in seen:
            deduplicated.append(normalized)
            seen.add(normalized)

    return deduplicated


def prune_asset_cache() -> None:
    now = time.time()
    with ASSET_CACHE_LOCK:
        expired_ids = [
            asset_id
            for asset_id, asset in ASSET_CACHE.items()
            if now - float(asset.get("created_at", now)) > ASSET_TTL_SECONDS
        ]
        for asset_id in expired_ids:
            ASSET_CACHE.pop(asset_id, None)


def cache_asset(content: bytes, content_type: str, filename: str) -> str:
    prune_asset_cache()
    asset_id = uuid.uuid4().hex
    with ASSET_CACHE_LOCK:
        ASSET_CACHE[asset_id] = {
            "content": content,
            "content_type": content_type,
            "filename": filename,
            "created_at": time.time(),
        }
    return asset_id


def cached_asset(asset_id: str) -> dict[str, Any] | None:
    prune_asset_cache()
    with ASSET_CACHE_LOCK:
        asset = ASSET_CACHE.get(asset_id)
        if asset is None:
            return None
        return dict(asset)


def infer_filename(url: str, content_type: str) -> str:
    parsed = urlparse(url)
    name = Path(parsed.path).name
    if name:
        return name

    extension = mimetypes.guess_extension(content_type) or ".bin"
    return f"asset{extension}"


def download_note_video(video_urls: list[str], referer_url: str) -> dict[str, str]:
    session = requests.Session()
    headers = {
        "User-Agent": USER_AGENT,
        "Referer": referer_url,
    }

    for candidate_url in video_urls[:3]:
        try:
            response = session.get(
                candidate_url,
                headers=headers,
                timeout=REQUEST_TIMEOUT,
                stream=True,
            )
            response.raise_for_status()

            content_type = response.headers.get("Content-Type", "").split(";")[0].strip().lower()

            if content_type in {"application/vnd.apple.mpegurl", "application/x-mpegurl"} or candidate_url.lower().endswith(".m3u8"):
                return {
                    "source_url": candidate_url,
                    "content_type": content_type or "application/vnd.apple.mpegurl",
                }

            content = response.content
            if not content:
                continue

            if len(content) > MAX_CACHED_VIDEO_BYTES:
                return {
                    "source_url": candidate_url,
                    "content_type": content_type or "video/mp4",
                }

            safe_content_type = content_type or "video/mp4"
            asset_id = cache_asset(
                content=content,
                content_type=safe_content_type,
                filename=infer_filename(candidate_url, safe_content_type),
            )

            return {
                "source_url": candidate_url,
                "asset_path": f"/assets/{asset_id}",
                "content_type": safe_content_type,
            }
        except Exception as error:
            LOGGER.warning("Video download failed for %s: %s", candidate_url, error)

    return {}


def normalize_detail_response(resolution: dict[str, Any], detail_payload: dict[str, Any]) -> dict[str, Any]:
    note = detail_payload.get("note", {})
    image_list = note.get("imageList", []) or []
    raw_image_urls = [
        normalize_asset_url(image.get("urlDefault"))
        for image in image_list
        if isinstance(image, dict) and image.get("urlDefault")
    ]

    title = str(note.get("title", "")).strip()
    desc = str(note.get("desc", "")).strip()
    note_type = str(note.get("type", "")).strip()
    video_urls = extract_video_urls(resolution.get("html", ""))
    is_video_note = bool(video_urls) or note_type.lower() == "video"
    image_urls = [] if is_video_note else raw_image_urls
    downloaded_images = download_note_images(image_urls, resolution["resolved_url"]) if image_urls else []
    downloaded_video = download_note_video(video_urls, resolution["resolved_url"]) if video_urls else {}
    video_url = downloaded_video.get("asset_path") or downloaded_video.get("source_url", "")
    media_kind = "video" if video_urls else ("images" if image_urls else "text")
    source_lines = [
        f"Source URL: {resolution['entry_url']}",
        f"Resolved URL: {resolution['resolved_url']}",
        f"Page Title: {title}" if title else "",
        desc,
    ]
    source_text = "\n".join(line for line in source_lines if line).strip()

    return {
        "source_url": resolution["entry_url"],
        "resolved_url": resolution["resolved_url"],
        "feed_id": resolution["feed_id"],
        "xsec_token": resolution["xsec_token"],
        "title": title,
        "description": "",
        "body_text": desc,
        "source_text": source_text,
        "media_kind": media_kind,
        "note_type": note_type,
        "image_urls": image_urls,
        "images": downloaded_images,
        "video_urls": video_urls,
        "video_url": video_url,
        "video_asset_path": downloaded_video.get("asset_path", ""),
        "video_content_type": downloaded_video.get("content_type", ""),
        "raw": detail_payload,
    }


def local_ipv4_addresses() -> list[str]:
    direct_addresses: list[str] = []
    discovered_addresses: list[str] = []

    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
            probe.connect(("8.8.8.8", 80))
            direct_addresses.append(probe.getsockname()[0])
    except OSError:
        pass

    try:
        for adapter in ifaddr.get_adapters():
            for ip_config in adapter.ips:
                candidate = ip_config.ip
                if isinstance(candidate, tuple):
                    continue
                discovered_addresses.append(str(candidate))
    except Exception as error:
        LOGGER.warning("Unable to enumerate adapter IP addresses via ifaddr: %s", error)

    try:
        _, _, resolved_addresses = socket.gethostbyname_ex(socket.gethostname())
        discovered_addresses.extend(resolved_addresses)
    except OSError:
        pass

    ordered_candidates = [*direct_addresses, *discovered_addresses]
    preferred_addresses: list[str] = []
    link_local_addresses: list[str] = []
    seen: set[str] = set()

    for candidate in ordered_candidates:
        normalized = candidate.strip()
        if not normalized or normalized in seen:
            continue

        try:
            ip_address = ipaddress.ip_address(normalized)
        except ValueError:
            continue

        if ip_address.version != 4:
            continue

        if ip_address.is_loopback or ip_address.is_multicast or ip_address.is_unspecified:
            continue

        seen.add(normalized)
        if ip_address.is_link_local:
            link_local_addresses.append(normalized)
        else:
            preferred_addresses.append(normalized)

    return preferred_addresses or link_local_addresses


class BonjourAdvertiser:
    def __init__(self, *, port: int) -> None:
        self.port = port
        self.service_name = f"RednoteOCR Backend ({socket.gethostname()}).{BONJOUR_SERVICE_TYPE}"
        self.server_name = f"{socket.gethostname()}.local."
        self._lock = Lock()
        self._stop_event = Event()
        self._thread: Thread | None = None
        self._zeroconf: Zeroconf | None = None
        self._service_info: ServiceInfo | None = None
        self._published_addresses: tuple[str, ...] = ()

    def start(self) -> None:
        self._refresh(force=True)
        self._thread = Thread(
            target=self._watch_loop,
            name="rednote-bonjour-advertiser",
            daemon=True,
        )
        self._thread.start()

    def stop(self) -> None:
        self._stop_event.set()
        if self._thread is not None:
            self._thread.join(timeout=2)

        with self._lock:
            self._unpublish_locked(close_zeroconf=True)

    def _watch_loop(self) -> None:
        while not self._stop_event.wait(BONJOUR_REFRESH_INTERVAL_SECONDS):
            try:
                self._refresh(force=False)
            except Exception:
                LOGGER.exception("Failed while refreshing Bonjour advertisement.")

    def _refresh(self, *, force: bool) -> None:
        ip_addresses = tuple(local_ipv4_addresses())

        with self._lock:
            if not force and ip_addresses == self._published_addresses:
                return

            if not ip_addresses:
                if self._published_addresses:
                    LOGGER.info(
                        "No usable IPv4 addresses were found. Unpublishing Bonjour service until the network comes back."
                    )
                self._unpublish_locked(close_zeroconf=True)
                self._published_addresses = ()
                return

            if self._zeroconf is None:
                self._zeroconf = Zeroconf(ip_version=IPVersion.V4Only)

            service_info = ServiceInfo(
                BONJOUR_SERVICE_TYPE,
                self.service_name,
                addresses=[socket.inet_aton(address) for address in ip_addresses],
                port=self.port,
                properties={
                    b"path": b"/",
                    b"scheme": b"http",
                },
                server=self.server_name,
            )

            if self._service_info is not None:
                try:
                    self._zeroconf.unregister_service(self._service_info)
                except Exception:
                    LOGGER.exception("Failed to unregister the previous Bonjour advertisement before republishing.")

            self._zeroconf.register_service(service_info)
            self._service_info = service_info

            if force or not self._published_addresses:
                LOGGER.info(
                    "Published Bonjour service %s for local discovery on %s",
                    self.service_name,
                    ", ".join(ip_addresses),
                )
            else:
                LOGGER.info(
                    "Detected local IP change. Republished Bonjour service on %s",
                    ", ".join(ip_addresses),
                )

            self._published_addresses = ip_addresses

    def _unpublish_locked(self, *, close_zeroconf: bool) -> None:
        if self._zeroconf is not None and self._service_info is not None:
            try:
                self._zeroconf.unregister_service(self._service_info)
            except Exception:
                LOGGER.exception("Failed to unregister Bonjour service cleanly.")

        self._service_info = None

        if close_zeroconf and self._zeroconf is not None:
            self._zeroconf.close()
            self._zeroconf = None


class RequestHandler(BaseHTTPRequestHandler):
    server_version = "RednoteLocalBackend/0.1"

    def do_GET(self) -> None:
        parsed_path = urlparse(self.path).path

        if parsed_path == "/health":
            self.respond_json(
                HTTPStatus.OK,
                {
                    "ok": True,
                    "bridge_url": BRIDGE_URL,
                    "cli_path": str(CLI_PATH),
                    "python": str(VENV_PYTHON),
                },
            )
            return

        if parsed_path == "/login-status":
            try:
                payload = run_cli("check-login")
                self.respond_json(HTTPStatus.OK, payload)
            except Exception as error:
                self.respond_json(
                    HTTPStatus.BAD_GATEWAY,
                    {"error": str(error)},
            )
            return

        if parsed_path.startswith("/assets/"):
            asset_id = parsed_path.removeprefix("/assets/").strip()
            asset = cached_asset(asset_id)
            if asset is None:
                self.respond_json(HTTPStatus.NOT_FOUND, {"error": "Asset not found."})
                return

            self.respond_bytes(
                HTTPStatus.OK,
                asset["content"],
                content_type=asset["content_type"],
                filename=asset["filename"],
            )
            return

        self.respond_json(HTTPStatus.NOT_FOUND, {"error": "Not found."})

    def do_POST(self) -> None:
        parsed_path = urlparse(self.path).path
        if parsed_path != "/imports/link":
            self.respond_json(HTTPStatus.NOT_FOUND, {"error": "Not found."})
            return

        try:
            body = self.read_json_body()
            raw_input = str(body.get("input", "")).strip()
            if not raw_input:
                self.respond_json(
                    HTTPStatus.BAD_REQUEST,
                    {"error": "Request JSON must include a non-empty `input` field."},
                )
                return

            resolution = resolve_share_link(raw_input)
            detail_payload = run_cli(
                "get-feed-detail",
                "--feed-id",
                resolution["feed_id"],
                "--xsec-token",
                resolution["xsec_token"],
            )
            response_payload = normalize_detail_response(resolution, detail_payload)
            self.respond_json(HTTPStatus.OK, response_payload)
        except requests.HTTPError as error:
            self.respond_json(
                HTTPStatus.BAD_GATEWAY,
                {"error": f"Failed to open the share link: {error}"},
            )
        except LinkResolutionError as error:
            self.respond_json(HTTPStatus.BAD_GATEWAY, {"error": str(error)})
        except Exception as error:
            LOGGER.exception("Link import failed")
            self.respond_json(HTTPStatus.BAD_GATEWAY, {"error": str(error)})

    def read_json_body(self) -> dict[str, Any]:
        content_length = int(self.headers.get("Content-Length", "0"))
        raw_body = self.rfile.read(content_length) if content_length > 0 else b""

        if not raw_body:
            return {}

        return json.loads(raw_body.decode("utf-8"))

    def respond_json(self, status: HTTPStatus, payload: dict[str, Any]) -> None:
        data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def respond_bytes(
        self,
        status: HTTPStatus,
        payload: bytes,
        *,
        content_type: str,
        filename: str
    ) -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(payload)))
        self.send_header("Cache-Control", "private, max-age=300")
        self.send_header("Content-Disposition", f'inline; filename="{filename}"')
        self.end_headers()
        self.wfile.write(payload)

    def log_message(self, format: str, *args: Any) -> None:
        LOGGER.info("%s - %s", self.address_string(), format % args)


def main() -> None:
    server = ThreadingHTTPServer((HOST, PORT), RequestHandler)
    LOGGER.info("Local adapter listening at http://%s:%d", HOST, PORT)
    LOGGER.info("Bridge server should be available at %s", BRIDGE_URL)
    LOGGER.info("Bonjour auto-discovery is disabled. Clients should connect to the saved backend URL directly.")

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        LOGGER.info("Stopping local adapter server...")
    finally:
        server.server_close()


if __name__ == "__main__":
    if sys.stdout and hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")

    main()
