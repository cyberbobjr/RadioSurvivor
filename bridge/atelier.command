#!/bin/sh
# Voice workshop of Radio Survivor (E22): opens the workshop in your browser. macOS: double-click this file.
cd "$(dirname "$0")" || exit 1
for candidate in python3 python; do
    if command -v "$candidate" >/dev/null 2>&1 && "$candidate" -c 'import sys; sys.exit(sys.version_info < (3, 10))' 2>/dev/null; then
        exec "$candidate" radio_bridge.py --atelier "$@"
    fi
done
echo "Python 3.10 or newer is required to open the voice workshop."
echo "Install it from https://www.python.org/downloads/ then double-click this file again."
printf "Press Enter to close this window. "
read -r _
exit 1
