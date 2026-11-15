#!/bin/sh
# Voice workshop of Radio Survivor (E22): opens the workshop in your browser. Linux: ./atelier.sh
cd "$(dirname "$0")" || exit 1
for candidate in python3 python; do
    if command -v "$candidate" >/dev/null 2>&1 && "$candidate" -c 'import sys; sys.exit(sys.version_info < (3, 10))' 2>/dev/null; then
        exec "$candidate" radio_bridge.py --atelier "$@"
    fi
done
echo "Python 3.10 or newer is required to open the voice workshop."
echo "Install it from your distribution (for example: sudo apt install python3) or https://www.python.org/downloads/"
exit 1
