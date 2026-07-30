@echo off
rem Execution-policy-safe wrapper for generate-workspace-context.ps1.
rem Generates WORKSPACE.md and REPOSITORY_CONTEXT.md locally, matching the Copilot Cloud Agent setup.
rem Any arguments are forwarded to the PowerShell script.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0generate-workspace-context.ps1" %*
