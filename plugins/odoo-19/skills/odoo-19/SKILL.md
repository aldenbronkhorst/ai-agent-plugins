---
name: odoo-19
description: Use, develop, review, test, and deploy Odoo 19 systems and customizations. Use for normal Odoo operations, models, views, security, reports, migrations, integrations, and record changes.
---

# Odoo 19

- Target Odoo 19.
- Prefer the Odoo API for normal application work, including reading or changing records and running supported business operations. Do not default to browser automation.
- When the user asks for a total, KPI, summary, statement, or other figure, first use an existing Odoo report, dashboard, computed field, or business method that already produces it. Preserve its filters and business context and treat the Odoo result as the source of truth; aggregate raw records only when no suitable built-in result exists or the user asks for an independent audit, reconciliation, or custom calculation.
- For Odoo 19 external API calls, default to JSON-2: send `POST /json/2/<model>/<method>` with the API key as an `Authorization: bearer ...` header and a JSON body. Add `X-Odoo-Database` only when the deployment requires an explicit database.
- For direct JSON-2 calls, prefer the bundled `scripts/odoo_json2.py` client over rebuilding HTTP and authentication code when it fits the request. It accepts any Odoo model, method, and JSON-object body and returns Odoo's response unchanged; it is a transport helper, not a restricted operation layer. Use `scripts/credential-contract.json` with a compatible credential provider when credentials must be discovered and injected; for routine use, pass that file directly to the provider runner without opening or inspecting it first because the runner validates it. The client also works independently with `ODOO_URL`, `ODOO_API_KEY`, and optional `ODOO_DATABASE` supplied securely by any method. If the helper is unsuitable or fails, use the documented JSON-2 request structure directly or choose another appropriate access method rather than treating the helper as a gate.
- Resolve bundled paths relative to this skill directory and run `scripts/odoo_json2.py <MODEL> <METHOD> --body '<JSON_OBJECT>'` with a verified Python 3.9+ executable. On Windows, do not assume `py -3` exists: prefer a compatible runtime already supplied by the host or workspace, otherwise verify `py -3`, `python3`, or `python`; a Microsoft Store execution alias is not a usable runtime. Install Python only when no compatible runtime is already available. Use `--body-file <PATH>` or `--body-file -` for a file or standard input. The syntax is complete, so do not run a help command first.
- For a simple access or user-identity check when the URL and API key are available, make one minimal read-only JSON-2 call to `res.users/context_get`, return its result, and stop. Do not try `/web/session/authenticate`, legacy RPC, or broader Odoo validation first; use those only when the task specifically requires them.
- For server-side technical work such as modules, services, logs, configuration, or command-line diagnostics, use SSH when access is available.
- Use the browser only when the task specifically requires the Odoo interface or the required operation is unavailable through the API or SSH.
- Inspect the current repository and module conventions before changing code.
- Make the smallest appropriate change.
- Test the affected module and workflow on staging.
- Deploy to production only after explicit user approval.
- Before changing records, confirm the correct database and company, then verify the result.
