# 🧠 Personal Home Server Stack — macOS

> A fully private, GPU-accelerated AI + media + storage server running on your Mac.
> Accessible from anywhere in the world via encrypted overlay networking. Zero cloud dependency.

---

## Overview

This guide sets up a unified home server on a Mac with three services accessible from a single browser window over an encrypted private network.

| Service | Role | Runtime |
|---|---|---|
| **Ollama** | Local LLM runtime with Apple Metal GPU acceleration | Native |
| **Qwen 3.5 (9B)** | The language model being served | Native via Ollama |
| **Open WebUI** | Unified portal: AI chat + sidebar links to all services | Native via uv |
| **Jellyfin** | Personal Netflix — streams movies from your external SSD | Docker |
| **Filebrowser** | Browser-based file manager for your external SSD | Docker |
| **Tailscale** | Encrypted WireGuard remote access from any device | Native |

---

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                              Mac                                 │
│                                                                  │
│  ┌─────────────────┐  HTTP   ┌──────────────────────────────┐    │
│  │  Ollama :11434  │ ◄──────► │  Open WebUI  :8080  (native)│    │
│  │  qwen3.5:9b     │         │  + Sidebar Links             │    │
│  │  Metal GPU      │         └──────────────────────────────┘    │
│  └─────────────────┘                       ▲                     │
│                                            │                     │
│  Samsung SSD (/Volumes/StorageServer)      │  Tailscale          │
│  ┌──────────────┐  ┌────────────────────┐  │  WireGuard          │
│  │   /Movies    │  │   /SharedFiles     │  │                     │
│  └──────┬───────┘  └────────┬───────────┘  │                     │
│  ┌──────▼───────┐  ┌────────▼───────────┐  │                     │
│  │  Jellyfin    │  │   Filebrowser      │  │                     │
│  │  :8096       │  │   :8082            │  │                     │
│  │  (Docker)    │  │   (Docker)         │  │                     │
│  └──────────────┘  └────────────────────┘  │                     │
└───────────────────────────────────────────┼──────────────────────┘
                                            │
                               ┌────────────▼───────────────┐
                               │    Any Tailscale Device    │
                               │   browser → 100.x.y.z:8080 │
                               │   AI  ·  Movies  ·  Files  │
                               └────────────────────────────┘
```

---

## Prerequisites

- Mac running **macOS 12 Ventura or later** (Apple Silicon M1–M4 strongly recommended)
- At least **16 GB RAM** (32 GB recommended for smooth 9B model inference)
- At least **10 GB free internal disk** for model weights
- A **Samsung SSD** (or any external drive) for media and file storage
- A free **Tailscale account**: [tailscale.com](https://tailscale.com)
- A free **Docker Hub account** (required by Docker Desktop): [hub.docker.com](https://hub.docker.com)

---

## Phase 1 — Homebrew

Homebrew is the macOS package manager used throughout this guide.

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

> **Apple Silicon only:** After installation, run the following and add it to your `~/.zshrc` to persist it across sessions:
> ```bash
> eval "$(/opt/homebrew/bin/brew shellenv)"
> ```

Verify:

```bash
brew --version
```

---

## Phase 2 — Ollama + GPU Configuration

Ollama is the runtime that downloads, manages, and serves LLMs with Apple Metal GPU acceleration.

### Install

```bash
brew install ollama
```

### Remove the GPU VRAM cap

By default, Ollama limits GPU memory usage conservatively. Setting `OLLAMA_MAX_VRAM=0` removes this cap so the model fully utilises your Mac's unified memory pool.

```bash
# For zsh (default on modern macOS)
echo 'export OLLAMA_MAX_VRAM=0' >> ~/.zshrc && source ~/.zshrc

# For bash
echo 'export OLLAMA_MAX_VRAM=0' >> ~/.bash_profile && source ~/.bash_profile
```

### Restart Ollama to apply the change

- Click the Ollama icon in your **menu bar** → **Quit Ollama**
- Relaunch from `/Applications/Ollama.app`

Verify the API is reachable:

```bash
curl http://localhost:11434/api/tags
```

---

## Phase 3 — Qwen 3.5 9B Model

Pull the model weights (~5–6 GB download, one-time):

```bash
ollama pull qwen3.5:9b
```

Run a quick test:

```bash
ollama run qwen3.5:9b
# Type a message, then exit with /bye
```

> **Tip:** `ollama list` shows all locally cached models. Once loaded, the model stays resident in memory — Open WebUI queries it directly over `localhost:11434`.

---

## Phase 4 — Open WebUI

Open WebUI is the browser frontend for the entire stack. It provides:
- A ChatGPT-style chat interface connected to your local Ollama backend
- A unified sidebar portal with links to Jellyfin and Filebrowser

We use `uv` (Astral's Python manager) to run it in an isolated environment.

### Install uv

```bash
brew install uv
```

### Launch Open WebUI

```bash
DATA_DIR=~/.open-webui uvx --python 3.11 open-webui@latest serve
```

This creates an isolated Python 3.11 environment, installs Open WebUI, and starts the server on port `8080`. All data — chat history, user accounts, settings — is stored in `~/.open-webui`.

### Create your admin account

1. Navigate to [http://localhost:8080](http://localhost:8080)
2. Click **Sign Up** and register
3. **The first registered user is automatically the administrator**

---

## Phase 5 — Prep the Samsung SSD

1. Plug the Samsung SSD into your Mac's USB-C port
2. Open **Disk Utility** → select the drive → click **Erase**
   - Apple devices only → choose **APFS**
   - Needs Windows compatibility → choose **exFAT**
   - Set the name to: `StorageServer`
3. Open **Finder**, navigate to the drive, and create two folders:

```
/Volumes/StorageServer/
├── Movies/        ← drop .mkv / .mp4 files here
└── SharedFiles/   ← files you want to access or share remotely
```

---

## Phase 6 — Docker Desktop

Docker runs Jellyfin and Filebrowser as lightweight containers. Since the AI stack runs natively, Docker here adds no performance penalty to inference.

1. Download **Docker Desktop for Mac (Apple Silicon)** from [docker.com/products/docker-desktop](https://www.docker.com/products/docker-desktop/)
2. Install and open the app
3. Sign in with your Docker Hub account
4. Wait for the whale icon in the menu bar to stop animating — Docker is ready

---

## Phase 7 — Jellyfin + Filebrowser

### Create the project directory

```bash
mkdir ~/server-stack && cd ~/server-stack
```

### Launch the containers

```bash
docker compose up -d
```

### Verify both are running

```bash
docker ps
```

Both `jellyfin` and `filebrowser` should show status `Up`.

### First-time setup

| Service | Local URL | Default credentials |
|---|---|---|
| Jellyfin | [http://localhost:8096](http://localhost:8096) | Created during setup wizard |
| Filebrowser | [http://localhost:8082](http://localhost:8082) | `admin` / `admin` — **change immediately** |

In Jellyfin's setup wizard, add a media library and point it to `/media` (which maps to your SSD's `Movies/` folder).

---

## Phase 8 — Tailscale

Tailscale creates an encrypted WireGuard mesh network between your devices. This lets you reach the entire stack from your phone or laptop anywhere in the world — without opening any firewall ports or configuring a router.

### Install

```bash
brew install --cask tailscale
```

### Authenticate

1. Open **Tailscale** from Applications (or the menu bar)
2. Click **Log In** and complete the browser OAuth flow
3. Your Mac is now a node in your private tailnet

### Get your Mac's stable Tailscale IP

```bash
tailscale ip -4
# Example: 100.11.22.33
```

Save this IP — it is your permanent address within your tailnet and does not change.

---

## Phase 9 — Unify in Open WebUI

Pin Jellyfin and Filebrowser as sidebar links so the entire stack is reachable from a single browser window.

1. Open [http://localhost:8080](http://localhost:8080)
2. Go to **Admin Panel → Settings → Interface**
3. Find the **Custom Navigation Links** section
4. Add the following two entries (replace `100.11.22.33` with your actual Tailscale IP):

| Label | URL |
|---|---|
| 🎬 Movie Streamer | `http://100.11.22.33:8096` |
| 📁 Cloud Storage | `http://100.11.22.33:8082` |

5. Save settings

Anyone authenticated on your tailnet who opens `http://100.11.22.33:8080` now has all three services accessible from the sidebar.

---

## Phase 10 — Always-On Configuration

To use the Mac as a persistent home server, you need to prevent it from sleeping when idle or when the lid is closed.

### System Settings

1. Go to **System Settings → Battery → Options**
2. Enable: **"Prevent automatic sleeping on power adapter when the display is off"**
3. Keep the Mac **plugged into power**

### Disable sleep via Terminal

```bash
sudo pmset -c sleep 0 displaysleep 0
```

### Install caffeinate as a persistent background service

Rather than keeping a terminal window open, install it as a `launchd` agent that survives reboots:

```bash
cat > ~/Library/LaunchAgents/com.localai.caffeinate.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.localai.caffeinate</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/bin/caffeinate</string>
    <string>-dis</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
</dict>
</plist>
EOF

launchctl load ~/Library/LaunchAgents/com.localai.caffeinate.plist
```

| caffeinate flag | Effect |
|---|---|
| `-d` | Prevents display sleep |
| `-i` | Prevents idle sleep |
| `-s` | Prevents sleep while on AC power |

### After a reboot

```bash
# Ollama
open /Applications/Ollama.app

# Open WebUI
DATA_DIR=~/.open-webui uvx --python 3.11 open-webui@latest serve &

# Docker containers restart automatically (restart: unless-stopped in the Compose file)
```

---

## Remote Access

From any device authenticated on your Tailscale account:

| Service | Remote URL |
|---|---|
| **Open WebUI (AI + Portal)** | `http://100.x.y.z:8080` |
| **Jellyfin (Movies)** | `http://100.x.y.z:8096` |
| **Filebrowser (Files)** | `http://100.x.y.z:8082` |

**Typical flow from a remote device:**
1. Open `http://<TAILSCALE_IP>:8080` in any browser
2. Log in with your admin credentials
3. Use the sidebar to switch between AI chat (`qwen3.5:9b`), movie streaming (Jellyfin), and file management (Filebrowser) — all routed over an encrypted WireGuard tunnel

---

## Port Reference

| Port | Service | Access |
|---|---|---|
| `8080` | Open WebUI — AI interface and unified portal | LAN + Tailscale |
| `11434` | Ollama API | Internal (localhost only) |
| `8096` | Jellyfin — movie streaming | LAN + Tailscale |
| `8082` | Filebrowser — file management | LAN + Tailscale |

---
