#!/usr/bin/env python3
"""Exercise the installed Hermes runtime in an isolated profile, without API calls.

Run with Hermes' Python: python scripts/test_hermes_integration.py --hermes-source PATH
Tests native Git installs, skill loading, prompt construction/rebuild, manual
shortcuts through the Desktop command backend, enable/disable, and updates.
"""

import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def git(repo, *args):
    return subprocess.run(["git", "-C", str(repo), *args], check=True, text=True,
                          capture_output=True).stdout.strip()


def run(source, scratch):
    profile = scratch / "profile"
    profile.mkdir()
    os.environ["HERMES_HOME"] = str(profile)
    os.environ["HERMES_ENABLE_PROJECT_PLUGINS"] = "false"
    os.chdir(scratch)
    sys.path.insert(0, str(source))

    from hermes_cli import plugins, plugins_cmd
    from tools.skills_tool import skill_view
    from agent.system_prompt import build_system_prompt, invalidate_system_prompt
    from agent.skill_bundles import save_bundle, build_bundle_invocation_message
    from run_agent import AIAgent

    upstream = scratch / "upstream"
    upstream.mkdir()
    shutil.copytree(ROOT / "plugins", upstream / "plugins",
                    ignore=shutil.ignore_patterns("__pycache__", "*.pyc", ".DS_Store"))
    names = sorted(p.name for p in (upstream / "plugins").iterdir())
    git(upstream, "init", "--initial-branch=main")
    git(upstream, "add", ".")
    git(upstream, "-c", "user.name=Plugin Tests", "-c", "user.email=tests@example.invalid",
        "commit", "-m", "Initial plugin fixture")

    for name in names:
        target, manifest, installed_name = plugins_cmd._install_plugin_core(
            f"{upstream.as_uri()}#plugins/{name}", force=False,
        )
        expected = json.loads((upstream / "plugins" / name / "plugin.json").read_text())
        assert installed_name == name and manifest["version"] == expected["version"]
        assert (target / "plugin.yaml").is_file()
        plugins_cmd._set_plugin_enabled(name, enable=True)

    manager = plugins.get_plugin_manager()
    manager.discover_and_load(force=True)
    assert all(manager._plugins[name].enabled for name in names), manager._plugins
    for name in names:
        loaded = json.loads(skill_view(f"{name}:{name}"))
        assert "error" not in loaded, loaded
        assert manager.find_plugin_skill(f"{name}:{name}").is_file()
    assert not any((profile / "skills").glob("*/SKILL.md")), "Plugin skills leaked into global skills"
    print(f"PASS: native Git install, enable, discover and skill_view for {len(names)} plugins")

    # Plugin skills are not scanned as /skill-name commands. Hermes' supported
    # bundles reference the installed namespaced skills without copying them.
    # Exercise the same completion and dispatch methods used by Desktop, rather
    # than merely asserting a skill can be loaded by the model.
    from tui_gateway import server
    for name in names:
        save_bundle(name, [f"{name}:{name}"], description=f"Use the {name} plugin")
        completion = server.handle_request({
            "id": f"complete-{name}", "method": "complete.slash",
            "params": {"text": f"/{name}"},
        })
        assert "error" not in completion, completion
        assert any(item["text"].strip().lstrip("/") == name
                   for item in completion["result"]["items"]), completion
        instruction = "Explain the workflow only; do not execute any helpers."
        dispatched = server.handle_request({
            "id": f"dispatch-{name}", "method": "command.dispatch",
            "params": {"name": name, "arg": instruction},
        })
        assert "error" not in dispatched, dispatched
        result = dispatched["result"]
        assert result["type"] == "send", result
        assert instruction in result["message"]
        assert f"{name}:{name}" in result["message"]
        skill_file = profile / "plugins" / name / "skills" / name / "SKILL.md"
        assert skill_file.read_text().strip() in result["message"]
        assert result["display"].startswith(f"/{name}"), result["display"]
    print("PASS: all eight manual shortcuts appear in Desktop completions and dispatch loaded skill prompts")

    agent = AIAgent(api_key="integration-test-placeholder", base_url="http://127.0.0.1:9/v1",
                    model="test/model", provider="openai", platform="cli", quiet_mode=True,
                    skip_context_files=True, skip_memory=True, session_id="plugin-integration-test")
    prompt = build_system_prompt(agent)
    for name in names:
        assert f"{name}:{name}" in prompt, f"Missing automatic discovery context: {name}"
        assert str((profile / "plugins" / name / "skills").resolve()) in prompt
    invalidate_system_prompt(agent)
    rebuilt = build_system_prompt(agent)
    for name in names:
        assert f"{name}:{name}" in rebuilt, f"Lost context after rebuild: {name}"
    print("PASS: all eight workflows advertised in real agent system prompt and after rebuild")

    plugins_cmd._set_plugin_enabled("proton-pass", enable=False)
    manager.discover_and_load(force=True)
    assert manager.find_plugin_skill("proton-pass:proton-pass") is None
    sections = manager.render_system_prompt_sections({})
    assert all("proton-pass:proton-pass" not in section.content for section in sections)
    assert manager.find_plugin_skill("odoo-19:odoo-19") is not None
    assert build_bundle_invocation_message("/proton-pass", "Explain only") is None
    assert build_bundle_invocation_message("/odoo-19", "Explain only") is not None
    plugins_cmd._set_plugin_enabled("proton-pass", enable=True)
    manager.discover_and_load(force=True)
    assert manager.find_plugin_skill("proton-pass:proton-pass") is not None
    assert build_bundle_invocation_message("/proton-pass", "Explain only") is not None
    print("PASS: disabled plugin cannot load through its shortcut; re-enabling restores it")

    skill = upstream / "plugins/agent-core/skills/agent-core/SKILL.md"
    marker = "Integration update marker"
    skill.write_text(skill.read_text() + f"\n{marker}\n")
    obsolete = profile / "plugins/agent-core/obsolete-test-file.txt"
    obsolete.write_text("must not survive a replacement update")
    git(upstream, "add", ".")
    git(upstream, "-c", "user.name=Plugin Tests", "-c", "user.email=tests@example.invalid",
        "commit", "-m", "Update plugin fixture")
    plugins_cmd._install_plugin_core(f"{upstream.as_uri()}#plugins/agent-core", force=True)
    manager.discover_and_load(force=True)
    assert marker in skill_view("agent-core:agent-core")
    assert marker in build_bundle_invocation_message("/agent-core", "Explain only")[0]
    assert not obsolete.exists()
    record = plugins_cmd._read_install_metadata()["agent-core"]
    assert record["revision"] == git(upstream, "rev-parse", "HEAD")
    assert record["source"].endswith("#plugins/agent-core") and not record["pinned"]
    print("PASS: native force-reinstall fetches upstream changes, removes stale files and records revision")
    manager.unload()
    assert not manager.render_system_prompt_sections({})
    assert all(manager.find_plugin_skill(f"{name}:{name}") is None for name in names)
    print("PASS: unload removes all plugin-owned discovery context and skills")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--hermes-source", required=True, type=Path)
    args = parser.parse_args()
    source = args.hermes_source.resolve(strict=True)
    with tempfile.TemporaryDirectory(prefix="ai-agent-plugins-hermes-") as tmp:
        run(source, Path(tmp))
