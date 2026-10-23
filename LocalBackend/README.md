# Run the optional Mac backend

The backend lets the iPhone app load Xiaohongshu posts through a Chrome session that is already logged in. It retrieves the post's text and media; the iPhone app still handles recipe extraction.

Three pieces run on your Mac: the XHS Bridge Chrome extension, its Python WebSocket bridge, and this project's HTTP adapter. The iPhone talks only to the adapter.

## First-time setup

You need macOS, Google Chrome, and Python 3.11 or later. Run these commands from the repository root. If `python3` points to an older version, use your Python 3.11+ executable for the virtual-environment command.

```bash
git submodule update --init --recursive
python3 --version
python3 -m venv LocalBackend/.venv
LocalBackend/.venv/bin/python -m pip install -r LocalBackend/requirements.txt
```

### Connect Chrome

1. Open `chrome://extensions/` in Chrome.
2. Turn on **Developer mode**.
3. Click **Load unpacked** and select `LocalBackend/xiaohongshu-skills/extension` inside your clone.
4. Confirm that **XHS Bridge** is enabled.
5. Open Xiaohongshu in Chrome and log in to your account.

Keep Chrome open while importing links. The extension and bridge use your browser's login session.

### Start the services

```bash
./LocalBackend/manage_services.sh start
./LocalBackend/manage_services.sh status
./LocalBackend/manage_services.sh login-status
```

The bridge uses port `9333`; the HTTP adapter uses port `8080`. To check the adapter directly:

```bash
curl http://localhost:8080/health
curl http://localhost:8080/login-status
```

### Connect the app

Enter the backend URL in the iPhone app's settings:

- **iPhone simulator on this Mac:** `http://localhost:8080`
- **Physical iPhone:** your Mac's reachable LAN address, for example `http://192.168.1.23:8080`

On a physical iPhone, `localhost` refers to the phone. Connect the phone and Mac to a network that allows them to reach each other, and allow local-network access if iOS asks. Automatic discovery is disabled, so update the saved URL when the Mac's address changes.

The adapter listens on all network interfaces and has no authentication or TLS. Keep it on a trusted local network; do not expose port `8080` to the internet.

## Daily use

```bash
./LocalBackend/manage_services.sh start
./LocalBackend/manage_services.sh status
./LocalBackend/manage_services.sh logs
./LocalBackend/manage_services.sh stop
```

These commands manage the manually started services. Chrome must remain open, the extension must remain enabled, and your Xiaohongshu session must still be logged in.

To test a link independently of the app, replace the example URL with a real share link:

```bash
curl -X POST http://localhost:8080/imports/link \
  -H 'Content-Type: application/json' \
  -d '{"input":"PASTE_A_XIAOHONGSHU_SHARE_LINK_HERE"}'
```

## Optional: start at login

After completing the setup above, you can install macOS launch agents:

```bash
./LocalBackend/install_launch_agents.sh
```

The installer copies the backend to `~/Library/Application Support/RednoteOCRBackend/LocalBackend`, creates a separate Python environment there, and starts the bridge and adapter when you log in. This avoids background-process access problems with projects stored inside `Documents`. Run the installer again after changing the backend code to update the deployed copy.

To remove login startup and unload those services:

```bash
./LocalBackend/uninstall_launch_agents.sh
```

Use the uninstall command to stop services managed by launchd; the ordinary `stop` command manages services started manually. `status` and `logs` can report the launchd copy as well.

## What happens during an import

The adapter extracts the first URL from the shared text, follows short-link redirects, and looks for the post ID and `xsec_token`. It calls the third-party `xiaohongshu-skills` CLI to retrieve the post, then returns a normalized response to the app.

Responses can include inline images and video URLs. Some videos are temporarily cached in memory and served through `/assets/{id}`; HLS streams and videos above the cache threshold use their source URL. The request and response contract is in [LOCAL_BACKEND.md](../LOCAL_BACKEND.md).

If a link does not expose the identifiers the adapter needs, or the browser cannot load the post, the import can fail. Check the service logs and browser login state first. The app may try the public webpage afterward, but that page may contain less information.
