@echo off
setlocal EnableExtensions
title 0x INJECT AI - V - OpenCode depth engine

set "KIT_ROOT=%~dp0"
if "%KIT_ROOT:~-1%"=="\" set "KIT_ROOT=%KIT_ROOT:~0,-1%"

if not exist "%KIT_ROOT%\lib\menu.ps1" (
    echo.
    echo  ERROR: Run this from the extracted forge folder ^(lib\ missing^).
    echo.
    pause
    exit /b 1
)

if not exist "%KIT_ROOT%\forge\persona\AGENTS.md" (
    echo.
    echo  ERROR: forge\persona\AGENTS.md missing ^(V operating instruction^).
    echo.
    pause
    exit /b 1
)

chcp 65001 >nul 2>&1
mode con: cols=112 lines=42 >nul 2>&1

rem --- CLI switches: Setup.bat [install|repair|status|revert|inject|lint|stats|sessions|selftest] [plain] [fa|en] ---
set "PSARGS="
:parse
if "%~1"=="" goto run
if /i "%~1"=="install" (
    set "PSARGS=%PSARGS% -Action install"
    shift
    goto parse
)
if /i "%~1"=="repair" (
    set "PSARGS=%PSARGS% -Action repair"
    shift
    goto parse
)
if /i "%~1"=="status" (
    set "PSARGS=%PSARGS% -Action status"
    shift
    goto parse
)
if /i "%~1"=="revert" (
    set "PSARGS=%PSARGS% -Action revert"
    shift
    goto parse
)
if /i "%~1"=="inject" (
    set "PSARGS=%PSARGS% -Action inject"
    shift
    goto parse
)
if /i "%~1"=="lint" (
    set "PSARGS=%PSARGS% -Action lint"
    shift
    goto parse
)
if /i "%~1"=="stats" (
    set "PSARGS=%PSARGS% -Action stats"
    shift
    goto parse
)
if /i "%~1"=="sessions" (
    set "PSARGS=%PSARGS% -Action sessions"
    shift
    goto parse
)
if /i "%~1"=="selftest" (
    set "PSARGS=%PSARGS% -Action selftest"
    shift
    goto parse
)
if /i "%~1"=="unit" (
    set "PSARGS=%PSARGS% -Action unit"
    shift
    goto parse
)
if /i "%~1"=="plain" (
    set "PSARGS=%PSARGS% -Plain"
    shift
    goto parse
)
if /i "%~1"=="fa" (
    set "PSARGS=%PSARGS% -Lang fa"
    shift
    goto parse
)
if /i "%~1"=="en" (
    set "PSARGS=%PSARGS% -Lang en"
    shift
    goto parse
)
shift
goto parse

:run
powershell -NoProfile -ExecutionPolicy Bypass -File "%KIT_ROOT%\lib\menu.ps1" -KitRoot "%KIT_ROOT%" %PSARGS%
endlocal
exit /b 0
