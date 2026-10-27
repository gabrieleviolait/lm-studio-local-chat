@echo off
chcp 65001 >nul
title Local Chat for LM Studio
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Start-LocalChat.ps1"
