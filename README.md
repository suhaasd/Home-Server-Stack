# 🧠 Local AI Stack on macOS — Qwen 3.5 + Ollama + Open WebUI + Tailscale

> Run a private, GPU-accelerated large language model on your Mac — accessible from anywhere in the world via an encrypted overlay network, with zero cloud dependency.

---

## Overview

This guide walks you through setting up a fully local, private AI stack on a Mac (Apple Silicon or Intel) that includes:

| Component | Role |
|---|---|
| **Ollama** | Local LLM runtime with Metal GPU acceleration |
| **Qwen 3.5 (9B)** | The language model being served |
| **Open WebUI** | ChatGPT-style browser interface for the model |
| **Tailscale** | Encrypted WireGuard-based remote access |
| **caffeinate** | Prevents sleep so your Mac stays as an always-on server |

Your data never leaves your machine. No API keys. No subscriptions.

---

## Prerequisites

- A Mac running **macOS 12 Ventura or later** (Apple Silicon M1/M2/M3/M4 recommended for GPU acceleration)
- At least **16 GB RAM** (32 GB recommended for the 9B model)
- At least **10 GB free disk space** for model weights
- A **Tailscale account** (free tier is sufficient): [tailscale.com](https://tailscale.com)
- Basic familiarity with the macOS Terminal

---

## Phase 1 — Install Ollama

Ollama is the runtime that downloads, manages, and serves local LLMs using Apple Metal GPU acceleration.

1. Download and install Ollama from the official site:

   ```bash
   # Option A: Download the macOS app directly
   # Visit: https://ollama.com/download/mac

   # Option B: Install via Homebrew
   brew install ollama
   ```

2. If you used the `.dmg` installer, open the app from your **Applications** folder and follow the setup prompts. The Ollama icon will appear in your macOS menu bar.

3. Verify the installation by confirming the daemon is running:

   ```bash
   ollama --version
   ```

---

## Phase 2 — Configure GPU Memory

By default, Ollama caps GPU VRAM usage conservatively. For large models like Qwen 3.5 9B, override this to maximize Apple Metal performance.

1. Open a Terminal and set the environment variable in your shell profile:

   ```bash
   # For zsh (default on modern macOS)
   echo 'export OLLAMA_MAX_VRAM=0' >> ~/.zshrc
   source ~/.zshrc

   # For bash
   echo 'export OLLAMA_MAX_VRAM=0' >> ~/.bash_profile
   source ~/.bash_profile
   ```

   Setting `OLLAMA_MAX_VRAM=0` removes the cap and lets Ollama use all available unified memory.

2. **Restart Ollama** to apply the environment change:
   - Click the Ollama icon in the macOS **menu bar**
   - Select **Quit Ollama**
   - Relaunch it from `/Applications/Ollama.app`

---

## Phase 3 — Pull and Run Qwen 3.5

Qwen 3.5 is Alibaba's open-weight multimodal model. The 9B variant is an excellent balance between capability and hardware requirements.

1. Pull and run the model (this will download ~5–6 GB of weights on first run):

   ```bash
   ollama run qwen3.5:9b
   ```

2. Once the interactive prompt appears, test it:

   ```
   >>> Hello! Can you describe what you are?
   ```

3. When satisfied, exit the interactive session:

   ```
   >>> /bye
   ```

   The model will remain loaded in memory and ready for the WebUI to call.

> **Tip:** To list all models you have downloaded locally, run `ollama list`.

---

## Phase 4 — Deploy Open WebUI

Open WebUI provides a polished, ChatGPT-style browser interface that connects to your local Ollama backend. We use `uv` — Astral's blazing-fast Python environment manager — to install it in an isolated environment without polluting your system Python.

### Step 4.1 — Install Homebrew (if not already installed)

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

### Step 4.2 — Install uv

```bash
brew install uv
```

### Step 4.3 — Launch Open WebUI

```bash
DATA_DIR=~/.open-webui uvx --python 3.11 open-webui@latest serve
```

This single command:
- Creates an isolated Python 3.11 virtual environment
- Installs the latest `open-webui` package into it
- Stores all application data (chat history, settings, user accounts) under `~/.open-webui`
- Starts the web server on port `8080`

### Step 4.4 — Create your admin account

1. Open your browser and navigate to: [http://localhost:8080](http://localhost:8080)
2. Click **Sign Up** and register a user
3. **The first registered user automatically becomes the administrator**

> **Note:** Open WebUI will auto-detect your locally running Ollama instance and list `qwen3.5:9b` as an available model.

---

## Phase 5 — Set Up Tailscale

Tailscale creates a secure, encrypted WireGuard mesh network between your devices. This lets you access your Mac's Open WebUI from your phone, laptop, or any other device — even across different networks — without exposing any ports to the public internet.

### Step 5.1 — Install Tailscale

```bash
brew install --cask tailscale
```

### Step 5.2 — Connect to your tailnet

1. Open **Tailscale** from your Applications folder
2. Click **Log In** from the menu bar icon
3. Authenticate with your Tailscale account in the browser that opens
4. Your Mac is now a node in your private tailnet

### Step 5.3 — Get your Mac's Tailscale IP

```bash
tailscale ip -4
```

Save this IP address (format: `100.x.y.z`). This is your stable private address across all tailnet devices.

---

## Phase 6 — Keep the Mac Always-On

If you're using a MacBook as a server, you need to prevent it from sleeping when the lid is closed or when idle.

### Step 6.1 — Disable lid-close sleep

1. Go to **System Settings → Battery**
2. Click **Options** (bottom right)
3. Enable: **"Prevent automatic sleeping on power adapter when the display is off"**
4. Keep the Mac **plugged into power**

### Step 6.2 — Block process suspension with caffeinate

In a dedicated terminal window, run:

```bash
caffeinate -dis
```

| Flag | Effect |
|---|---|
| `-d` | Prevents display sleep |
| `-i` | Prevents system idle sleep |
| `-s` | Prevents sleep while on AC power |

**Keep this terminal window open.** Closing it will end the caffeinate process and the Mac may sleep.

> **Tip:** For a persistent solution, consider adding Ollama and Open WebUI as Login Items or using a `launchd` plist so they restart automatically on reboot.

---

## Remote Access

From any device authenticated on your Tailscale account — iPhone, iPad, Windows PC, Linux machine — anywhere in the world:

1. Open a browser
2. Navigate to:

   ```
   http://<YOUR_MAC_TAILSCALE_IP>:8080
   ```

   Example: `http://100.101.102.103:8080`

3. Log in with the admin credentials you created in Phase 4

You now have full access to Qwen 3.5 9B — including multimodal image uploads — from any of your devices, routed over an encrypted WireGuard tunnel.

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                        Your Mac                             │
│                                                             │
│   ┌─────────────┐    HTTP     ┌──────────────────────────┐  │
│   │   Ollama    │ ◄─────────► │     Open WebUI           │  │
│   │  :11434     │             │     (uvx, port 8080)     │  │
│   │  qwen3.5:9b │             └──────────────────────────┘  │
│   │  Metal GPU  │                          ▲                │
│   └─────────────┘                          │                │
│                                  Tailscale WireGuard        │
└──────────────────────────────────────────┼─────────────────┘
                                           │
                              ┌────────────▼────────────┐
                              │   Any Tailscale Device   │
                              │  iPhone / iPad / Laptop  │
                              │  browser → 100.x.y.z:8080│
                              └──────────────────────────┘
```

---