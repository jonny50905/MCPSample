@echo off
rem Lint wrapper: runs ps-doc-lint.ps1 with the execution policy bypassed.
rem Works from any directory, in cmd or PowerShell. Usage:
rem   scripts\ps-doc-lint.cmd <domain>
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ps-doc-lint.ps1" -Domain %*
