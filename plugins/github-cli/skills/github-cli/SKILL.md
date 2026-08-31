---
name: github-cli
description: Use GitHub through the official GitHub CLI, Git, and SSH or HTTPS for authentication, repositories, pull requests, issues, Actions, releases, organizations, secrets, and API requests. Use for terminal-first GitHub work without a connector plugin.
---

# GitHub CLI

- Use the official `gh` CLI for GitHub services and ordinary Git for local repository and version-control operations. Do not use a GitHub connector, MCP server, or browser automation unless the user requests it or the terminal interfaces cannot perform the task faithfully.

## Authentication

- Check `gh auth status` before starting a new login. If `gh` is unavailable, install the current official CLI through the system's trusted package manager, then continue.
- If the intended account is not authenticated, use `gh auth login --hostname <host> --web --git-protocol https`. GitHub CLI displays a one-time code and opens GitHub's device-verification page; the user may complete it in that browser or on another device. Let the user sign in and approve access, then verify the authenticated identity with `gh auth status` or `gh api user`.
- Treat this native OAuth login and `gh`'s operating-system credential storage as the normal credential path. Do not search a password manager for a GitHub password or personal access token before trying it, and never use `--insecure-storage`, print a token, call token-showing flags, or ask the user to paste a token when the device flow is suitable.
- Use HTTPS and `gh auth setup-git` as the portable default, especially for multiple accounts. Reuse an existing valid SSH setup when the user or environment already prefers it, but do not create, upload, replace, or delete SSH or signing keys merely to complete ordinary setup.
- Treat multiple accounts and GitHub hosts as normal. Inspect known accounts with `gh auth status` and select the intended one with `gh auth switch --hostname <host> --user <login>`. Before a mutation, verify the active account, host, and repository rather than assuming the last-used account is correct.
- Use `gh auth refresh --scopes <scopes>` only when the requested operation lacks a required scope. Use a password manager or another approved secure credential source only for headless automation that genuinely requires `GH_TOKEN` or `GH_ENTERPRISE_TOKEN`, and keep those values out of files, command output, logs, and source control.

## Operations

- Use Git for clone, fetch, branch, status, diff, commit, merge, rebase, and push. Use `gh` for GitHub-hosted state such as pull requests, issues, reviews, Actions, releases, repository settings, and API access. These are complementary tools, not a fixed operation allowlist.
- Prefer structured output such as `--json` and `--jq`. Use `gh api --paginate` when a complete paginated result is required.
- Infer the repository from a verified working tree when unambiguous; otherwise specify it explicitly with `--repo <host/owner/repo>`. Inspect current state before changing it and verify the remote result afterward.
- A request to create, edit, push, merge, comment, release, or change settings authorizes that scoped operation. Do not infer authorization for unrelated repositories, broader organization changes, destructive cleanup, or publication beyond the requested target.
