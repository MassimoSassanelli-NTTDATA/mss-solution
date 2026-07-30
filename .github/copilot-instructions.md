# Copilot Instructions

Repository-wide guidance for GitHub Copilot and other AI agents working in this
repository. These instructions are **generic and reusable**: they apply to every
issue and pull request and are not tied to any single task. Read them before
planning or implementing any change.

## Project Context

This repository contains the complete solution **Mobile Scan Simplified**.

Mobile Scan Simplified is a mobile application for SAP S/4HANA Public Cloud that streamlines warehouse operations using smartphones or handheld scanners. It is designed for organizations that want to manage their warehouse processes efficiently through mobile devices.

With the app, warehouse employees can:

- Record goods receipts
- Post goods issues
- Perform stock transfers
- Execute picking operations
- Conduct inventory counts
- Check stock levels and handling units in real time

By providing a user-friendly mobile interface and real-time integration with SAP S/4HANA Public Cloud, Mobile Scan Simplified helps increase productivity, improve data accuracy, and optimize warehouse processes.

## Skill Usage

- When a request clearly falls within the scope of an existing skill, read that skill first.
- Use the skill as a router to narrow the search space and identify the most relevant implementation files.
- After reading the skill, verify the guidance against the actual code by reading only the few most relevant files.
- Do not rely on the skill alone when code generation or code changes are requested; the actual implementation remains the source of truth.
- Prefer a direct code-first entry only when no suitable skill exists or when the request targets a specific file, symbol, error, or local runtime behavior.

## Agent Context

For implementation rules, repository roles, and cross-repository guidance,
see [AGENTS.md](../AGENTS.md).