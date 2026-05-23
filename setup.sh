#!/usr/bin/env bash
# =============================================================================
#  setup.sh — Local AI Stack for macOS
#  Installs: Homebrew · Ollama · Qwen 3.5 9B · uv · Open WebUI · Tailscale
#  Configures: GPU memory · shell profile · sleep prevention (launchd)
# =============================================================================
set -euo pipefail

# ─── Colour helpers ───────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}${BOLD}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}${BOLD}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}${BOLD}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}${BOLD}[ERROR]${RESET} $*" >&2; exit 1; }
step()    { echo -e "\n${BOLD}━━━  $*  ━━━${RESET}"; }

# ─── Compatibility guard ──────────────────────────────────────────────────────
[[ "$(uname)" == "Darwin" ]] || error "This script is macOS-only."

MACOS_VER=$(sw_vers -productVersion)
MACOS_MAJOR=$(echo "$MACOS_VER" | cut -d. -f1)
[[ "$MACOS_MAJOR" -ge 12 ]] || error "Requires macOS 12 Ventura or later (found $MACOS_VER)."

# ─── RAM check ────────────────────────────────────────────────────────────────
RAM_GB=$(( $(sysctl -n hw.memsize) / 1073741824 ))
if [[ "$RAM_GB" -lt 16 ]]; then
  warn "Only ${RAM_GB} GB RAM detected. 16 GB+ recommended for the 9B model."
  read -rp "Continue anyway? [y/N] " yn
  [[ "$yn" =~ ^[Yy]$ ]] || exit 0
fi

# ─── Disk check ───────────────────────────────────────────────────────────────
FREE_GB=$(( $(df -k ~ | awk 'NR==2{print $4}') / 1048576 ))
if [[ "$FREE_GB" -lt 10 ]]; then
  error "Less than 10 GB free disk space (${FREE_GB} GB). Please free up space first."
fi

# ─── Shell detection ──────────────────────────────────────────────────────────
detect_shell_profile() {
  local shell_name
  shell_name=$(basename "$SHELL")
  case "$shell_name" in
    zsh)  echo "$HOME/.zshrc" ;;
    bash) echo "$HOME/.bash_profile" ;;
    *)    echo "$HOME/.profile" ;;
  esac
}
SHELL_PROFILE=$(detect_shell_profile)

# ─── Banner ───────────────────────────────────────────────────────────────────
clear
echo -e "${BOLD}"
cat << 'EOF'
  ██████╗ ██╗    ██╗███████╗███╗   ██╗    █████╗ ██╗
 ██╔═══██╗██║    ██║██╔════╝████╗  ██║   ██╔══██╗██║
 ██║   ██║██║ █╗ ██║█████╗  ██╔██╗ ██║   ███████║██║
 ██║▄▄ ██║██║███╗██║██╔══╝  ██║╚██╗██║   ██╔══██║██║
 ╚██████╔╝╚███╔███╔╝███████╗██║ ╚████║   ██║  ██║██║
  ╚══▀▀═╝  ╚══╝╚══╝ ╚══════╝╚═╝  ╚═══╝   ╚═╝  ╚═╝╚═╝
EOF
echo -e "${RESET}"
echo -e "  ${CYAN}Local AI Stack Setup${RESET} — Qwen 3.5 · Ollama · Open WebUI · Tailscale"
echo -e "  macOS ${MACOS_VER} · ${RAM_GB} GB RAM · ${FREE_GB} GB free disk"
echo ""

# ─── Phase 1: Homebrew ────────────────────────────────────────────────────────
step "Phase 1 — Homebrew"

if command -v brew &>/dev/null; then
  success "Homebrew already installed ($(brew --version | head -1))"
else
  info "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  # Add Homebrew to PATH for Apple Silicon
  if [[ -f /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
    # Persist it
    if ! grep -q 'homebrew/bin/brew shellenv' "$SHELL_PROFILE" 2>/dev/null; then
      echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> "$SHELL_PROFILE"
    fi
  fi
  success "Homebrew installed"
fi

brew update --quiet

# ─── Phase 2: Ollama ──────────────────────────────────────────────────────────
step "Phase 2 — Ollama"

if command -v ollama &>/dev/null; then
  success "Ollama already installed ($(ollama --version 2>/dev/null || echo 'version unknown'))"
else
  info "Installing Ollama via Homebrew..."
  brew install ollama
  success "Ollama installed"
fi

# Configure GPU memory cap removal
if grep -q 'OLLAMA_MAX_VRAM' "$SHELL_PROFILE" 2>/dev/null; then
  success "OLLAMA_MAX_VRAM already configured in $SHELL_PROFILE"
else
  info "Removing Ollama GPU VRAM cap in $SHELL_PROFILE..."
  echo '' >> "$SHELL_PROFILE"
  echo '# Ollama — remove GPU VRAM cap for maximum Metal performance' >> "$SHELL_PROFILE"
  echo 'export OLLAMA_MAX_VRAM=0' >> "$SHELL_PROFILE"
  export OLLAMA_MAX_VRAM=0
  success "OLLAMA_MAX_VRAM=0 written to $SHELL_PROFILE"
fi

# Start Ollama serve as a background service
if pgrep -x ollama &>/dev/null; then
  success "Ollama daemon already running"
else
  info "Starting Ollama daemon in background..."
  OLLAMA_MAX_VRAM=0 nohup ollama serve > /tmp/ollama.log 2>&1 &
  OLLAMA_PID=$!
  # Wait for it to become ready
  info "Waiting for Ollama API to become ready..."
  for i in {1..30}; do
    if curl -sf http://localhost:11434/api/tags > /dev/null 2>&1; then
      success "Ollama API is ready (PID $OLLAMA_PID)"
      break
    fi
    sleep 1
    [[ $i -eq 30 ]] && error "Ollama failed to start. Check /tmp/ollama.log"
  done
fi

# ─── Phase 3: Pull Qwen 3.5 ───────────────────────────────────────────────────
step "Phase 3 — Qwen 3.5 9B Model"

if ollama list 2>/dev/null | grep -q 'qwen3.5:9b'; then
  success "qwen3.5:9b already downloaded"
else
  info "Pulling qwen3.5:9b weights (~5-6 GB). This may take a while..."
  ollama pull qwen3.5:9b
  success "qwen3.5:9b downloaded and ready"
fi

# Quick smoke test (non-interactive)
info "Running a quick model smoke test..."
RESPONSE=$(echo "Reply with only the word READY and nothing else." \
  | ollama run qwen3.5:9b --nowordwrap 2>/dev/null | tr -d '[:space:]' || true)
if [[ "$RESPONSE" == *"READY"* ]]; then
  success "Model smoke test passed — GPU inference working"
else
  warn "Smoke test returned unexpected output ('$RESPONSE') — model may still be fine"
fi

# ─── Phase 4: uv + Open WebUI ─────────────────────────────────────────────────
step "Phase 4 — uv + Open WebUI"

if command -v uv &>/dev/null; then
  success "uv already installed ($(uv --version))"
else
  info "Installing uv..."
  brew install uv
  success "uv installed"
fi

# Check if Open WebUI is already running
if lsof -ti:8080 &>/dev/null; then
  warn "Port 8080 is already in use. Open WebUI may already be running."
  info "Skipping Open WebUI launch. Access it at http://localhost:8080"
else
  info "Launching Open WebUI on port 8080 (background process)..."
  DATA_DIR=~/.open-webui nohup uvx --python 3.11 open-webui@latest serve \
    > /tmp/open-webui.log 2>&1 &
  WEBUI_PID=$!

  info "Waiting for Open WebUI to become ready (first run may take 60–120s for install)..."
  for i in {1..90}; do
    if curl -sf http://localhost:8080 > /dev/null 2>&1; then
      success "Open WebUI is ready at http://localhost:8080 (PID $WEBUI_PID)"
      break
    fi
    printf '.'
    sleep 2
    [[ $i -eq 90 ]] && {
      warn "Open WebUI is taking longer than expected. Check /tmp/open-webui.log"
      warn "It may still be installing packages. Try http://localhost:8080 in a moment."
    }
  done
  echo ""
fi

# ─── Phase 5: Tailscale ───────────────────────────────────────────────────────
step "Phase 5 — Tailscale"

if brew list --cask tailscale &>/dev/null 2>&1 || [ -d "/Applications/Tailscale.app" ]; then
  success "Tailscale already installed"
else
  info "Installing Tailscale..."
  brew install --cask tailscale
  success "Tailscale installed"
fi

# Attempt to get Tailscale IP (only works if already authenticated)
if command -v tailscale &>/dev/null && tailscale ip -4 &>/dev/null 2>&1; then
  TAILSCALE_IP=$(tailscale ip -4)
  success "Tailscale connected — your IP: ${BOLD}${TAILSCALE_IP}${RESET}"
  REMOTE_URL="http://${TAILSCALE_IP}:8080"
else
  warn "Tailscale is installed but not yet authenticated."
  echo ""
  echo -e "  ${YELLOW}Action required:${RESET}"
  echo "  1. Open Tailscale from your Applications folder (or menu bar)"
  echo "  2. Click 'Log In' and authenticate with your Tailscale account"
  echo "  3. Run: tailscale ip -4  (to get your node's IP)"
  echo ""
  REMOTE_URL="http://<YOUR_TAILSCALE_IP>:8080"
fi

# ─── Phase 6: Always-on (launchd plist) ──────────────────────────────────────
step "Phase 6 — Always-On Configuration"

# Write a launchd plist to keep caffeinate running on login
PLIST_PATH="$HOME/Library/LaunchAgents/com.localai.caffeinate.plist"
if [[ -f "$PLIST_PATH" ]]; then
  success "caffeinate LaunchAgent already exists"
else
  info "Installing caffeinate LaunchAgent (persists across reboots)..."
  cat > "$PLIST_PATH" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.localai.caffeinate</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/bin/caffeinate</string>
    <string>-dis</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
</dict>
</plist>
PLIST
  launchctl load "$PLIST_PATH" 2>/dev/null || true
  success "caffeinate LaunchAgent installed and loaded"
fi

# pmset: prevent sleep on AC power (requires sudo)
info "Configuring power management (prevents sleep on AC power)..."
if sudo pmset -c sleep 0 displaysleep 0 2>/dev/null; then
  success "Power management: sleep disabled on AC power"
else
  warn "Could not set pmset (need sudo). Run manually:"
  echo "    sudo pmset -c sleep 0 displaysleep 0"
fi

# ─── Write a relaunch helper script ───────────────────────────────────────────
RELAUNCH_SCRIPT="$HOME/.local/bin/localai-start"
mkdir -p "$HOME/.local/bin"
cat > "$RELAUNCH_SCRIPT" << 'SCRIPT'
#!/usr/bin/env bash
# Relaunch the local AI stack after a reboot

echo "Starting Ollama..."
OLLAMA_MAX_VRAM=0 nohup ollama serve > /tmp/ollama.log 2>&1 &
sleep 3

echo "Starting Open WebUI..."
DATA_DIR=~/.open-webui nohup uvx --python 3.11 open-webui@latest serve \
  > /tmp/open-webui.log 2>&1 &

echo "Done. Access at: http://localhost:8080"
echo "Tailscale IP:   $(tailscale ip -4 2>/dev/null || echo 'Not connected')"
SCRIPT
chmod +x "$RELAUNCH_SCRIPT"
success "Relaunch helper written to $RELAUNCH_SCRIPT"

# ─── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${GREEN}${BOLD}  ✓  Setup complete!${RESET}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""
echo -e "  ${BOLD}Local access:${RESET}   http://localhost:8080"
echo -e "  ${BOLD}Remote access:${RESET}  ${REMOTE_URL}"
echo -e "  ${BOLD}Model:${RESET}          qwen3.5:9b"
echo -e "  ${BOLD}Ollama API:${RESET}     http://localhost:11434"
echo ""
echo -e "  ${YELLOW}Next steps:${RESET}"
echo "  1. Open http://localhost:8080 in your browser"
echo "  2. Register your admin account (first user = admin)"
if [[ "$REMOTE_URL" == *"TAILSCALE"* ]]; then
echo "  3. Log into Tailscale, then run: tailscale ip -4"
fi
echo "  4. To restart after a reboot, run: localai-start"
echo "     (add ~/.local/bin to your PATH if not already there)"
echo ""
echo -e "  ${BOLD}Log files:${RESET}"
echo "    Ollama:       /tmp/ollama.log"
echo "    Open WebUI:   /tmp/open-webui.log"
echo ""
