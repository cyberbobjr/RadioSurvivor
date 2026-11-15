@echo off
rem Voice workshop of Radio Survivor (E22): opens the workshop in your browser. Windows: double-click this file.
setlocal
cd /d "%~dp0"
set "PYTHON="
py -3 -c "import sys; sys.exit(sys.version_info < (3, 10))" >nul 2>nul && set "PYTHON=py -3"
if not defined PYTHON python -c "import sys; sys.exit(sys.version_info < (3, 10))" >nul 2>nul && set "PYTHON=python"
if not defined PYTHON (
    echo Python 3.10 or newer is required to open the voice workshop.
    echo Install it from https://www.python.org/downloads/ ^(tick "Add python.exe to PATH"^), then try again.
    pause
    exit /b 1
)
%PYTHON% radio_bridge.py --atelier %*
if errorlevel 1 pause
