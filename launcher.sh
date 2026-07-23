#!/usr/bin/env bash
# a2ml-metadata-block
# id = "idaptik-ums-launcher"
# type = "launcher"
# version = "0.1.0"
# app-name = "idaptik-ums"
# app-display = "IDApTIK Universal Modding Studio"
# app-url = "http://localhost:4000"
# standards-compliance = ["hyperpolymath-launcher-v1"]
# modes = ["runtime", "integration", "meta"]
# platforms = ["linux", "windows", "macos"]
# lifecycle-phases-covered = ["LM-LA-INSTALL", "LM-LA-RUN"]
# lifecycle-phases-deferred = []
# end-metadata-block

set -euo pipefail

APP_NAME="idaptik-ums"
VERSION="0.1.0"
BUILD_SHA=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
PLATFORM=$(uname -s | tr '[:upper:]' '[:lower:]')

show_help() {
    echo "Usage: $0 [MODE]"
    echo "Modes:"
    echo "  --start     Run setup, doctor, gen, and launch the UMS (ums-ai-edit)."
    echo "  --stop      Kill the running UMS process."
    echo "  --status    Check if the UMS is running."
    echo "  --auto      Alias for --start."
    echo "  --integ     (Stub) Integrate with desktop."
    echo "  --disinteg  (Stub) Remove desktop integration."
    echo "  --version   Print version info."
    echo "  --help      Show this help."
}

MODE="${1:---auto}"

case "$MODE" in
    --start|--auto|--browser|--web)
        echo "[launcher] Preparing $APP_NAME for cleanest start..."
        ~/.local/bin/mise trust || true
        ~/.local/bin/mise exec -- just setup || just setup
        ~/.local/bin/mise exec -- just doctor || just doctor
        ~/.local/bin/mise exec -- just gen || just gen
        echo "[launcher] Launching UMS pipeline..."
        # Launching in foreground so you can interact with the modding studio!
        exec ~/.local/bin/mise exec -- cargo run -p ums-ai-edit || exec cargo run -p ums-ai-edit
        ;;
    --stop)
        echo "[launcher] Stopping $APP_NAME..."
        pkill -f "ums-ai-edit" || echo "Not running."
        ;;
    --status)
        if pgrep -f "ums-ai-edit" > /dev/null; then
            echo "Status: RUNNING"
            exit 0
        else
            echo "Status: STOPPED"
            exit 1
        fi
        ;;
    --integ|--disinteg)
        echo "[launcher] Mode $MODE is not fully implemented for this CLI pipeline yet."
        ;;
    --version)
        echo "$APP_NAME $VERSION ($BUILD_SHA) [$PLATFORM]"
        ;;
    --help)
        show_help
        ;;
    *)
        echo "Unknown mode: $MODE"
        show_help
        exit 1
        ;;
esac
