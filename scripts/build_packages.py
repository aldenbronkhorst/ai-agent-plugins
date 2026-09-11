#!/usr/bin/env python3
"""Build Git-installable packages from plugins/*; --check detects stale output."""

import argparse
import json
import os
from pathlib import Path
import sys

import yaml

ROOT = Path(__file__).resolve().parents[1]
IGNORED = {"__pycache__", ".DS_Store"}


def json_bytes(value):
    return (json.dumps(value, indent=2) + "\n").encode()


def files_below(directory):
    if not directory.exists():
        return {}
    files = {}
    for path in sorted(directory.rglob("*")):
        relative = path.relative_to(directory)
        if any(part in IGNORED for part in relative.parts) or path.suffix in {".pyc", ".pyo"}:
            continue
        if path.is_symlink():
            raise ValueError(f"Package files must not be symlinks: {path}")
        if path.is_file():
            files[relative] = path.read_bytes()
    return files


def skill_metadata(plugin):
    entries = []
    for path in sorted((plugin / "skills").glob("*/SKILL.md")):
        text = path.read_text(encoding="utf-8")
        lines = text.splitlines()
        if not lines or lines[0] != "---" or "---" not in lines[1:]:
            raise ValueError(f"Missing skill frontmatter: {path}")
        metadata = yaml.safe_load("\n".join(lines[1:lines.index("---", 1)]))
        if not isinstance(metadata, dict) or metadata.get("name") != path.parent.name or not isinstance(metadata.get("description"), str):
            raise ValueError(f"Invalid skill metadata: {path}")
        entries.append({"name": metadata["name"], "description": metadata["description"],
                        "frontmatter": metadata, "path": path.relative_to(plugin).as_posix()})
    return entries


def hermes_outputs(package, manifest, skills):
    """Native registration generated from the same canonical metadata and skills."""
    interface = manifest.get("extensions", {}).get("com.openai", {}).get("interface", {})
    native = {key: manifest[key] for key in ("name", "version", "description")}
    native["author"] = manifest.get("author", {}).get("name", "AI Agent Plugins")
    return {
        package / "plugin.yaml": yaml.safe_dump(native, sort_keys=False, allow_unicode=True).encode(),
        package / "hermes-skills.json": json_bytes({
            "name": manifest["name"], "version": manifest["version"],
            "display_name": interface.get("displayName", manifest["name"]), "skills": skills,
        }),
        package / "__init__.py": (ROOT / "packaging/hermes/__init__.py").read_bytes(),
    }


def build(check=False):
    # The existing catalog defines display order. Its paths/policies are retained.
    catalog = json.loads((ROOT / ".agents/plugins/marketplace.json").read_text())
    manifests = {p.parent.name: json.loads(p.read_text()) for p in (ROOT / "plugins").glob("*/plugin.json")}
    names = [entry["name"] for entry in catalog["plugins"]]
    if len(names) != len(set(names)) or set(names) != set(manifests):
        raise ValueError("Marketplace and portable plugin names must match exactly")
    outputs = {}
    modes = {}
    claude_entries = []
    bundle_skills = []
    for name in names:
        manifest = manifests[name]
        if manifest["name"] != name:
            raise ValueError(f"Plugin folder and manifest name differ: {name}")
        plugin = ROOT / "plugins" / name
        common = {key: manifest[key] for key in ("name", "version", "description", "author", "homepage", "repository") if key in manifest}
        interface = manifest.get("extensions", {}).get("com.openai", {}).get("interface", {})
        # Metadata compatibility only: every client uses the same skill/helper files.
        codex = {key: common[key] for key in ("name", "version", "description", "author") if key in common}
        codex.update(skills="./skills/", interface=interface)
        outputs[plugin / ".codex-plugin/plugin.json"] = json_bytes(codex)
        outputs[plugin / ".claude-plugin/plugin.json"] = json_bytes(common)
        indexed_skills = skill_metadata(plugin)
        outputs.update(hermes_outputs(plugin, manifest, indexed_skills))
        bundle_skills.extend(indexed_skills)
        claude_entries.append({"name": name, "source": f"./plugins/{name}", "description": manifest["description"]})
        skill_files = files_below(plugin / "skills")
        if Path(name, "SKILL.md") not in skill_files:
            raise ValueError(f"Missing primary skill for {name}")
        for relative, content in skill_files.items():
            output = ROOT / "skills" / relative
            if output in outputs:
                raise ValueError(f"Duplicate skill path: {relative}")
            outputs[output] = content
            modes[output] = (plugin / "skills" / relative).stat().st_mode & 0o777
    outputs[ROOT / ".claude-plugin/marketplace.json"] = json_bytes({
        "name": catalog["name"], "owner": {"name": "AI Agent Plugins"},
        "description": "Portable agent workflows with shared skills and helper scripts.",
        "plugins": claude_entries,
    })
    # Retain the existing optional bundle for users who already installed it.
    # Individual plugin links are the documented default for Hermes.
    outputs.update(hermes_outputs(ROOT, json.loads((ROOT / "plugin.json").read_text()), bundle_skills))
    expected_skills = {path.relative_to(ROOT / "skills") for path in outputs if path.is_relative_to(ROOT / "skills")}
    stale = set(files_below(ROOT / "skills")) - expected_skills
    changed = [path for path, content in outputs.items() if not path.exists() or path.read_bytes() != content]
    mode_changes = [path for path, mode in modes.items() if os.name != "nt" and path.exists() and (path.stat().st_mode & 0o111) != (mode & 0o111)]
    if check:
        if changed or stale or mode_changes:
            for path in sorted(set(changed + mode_changes)):
                print(f"Out of date: {path.relative_to(ROOT)}", file=sys.stderr)
            for relative in sorted(stale):
                print(f"Stale generated file: skills/{relative}", file=sys.stderr)
            print("Run python3 scripts/build_packages.py", file=sys.stderr)
            return 1
    else:
        for path in changed:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(outputs[path])
        for path, mode in modes.items():
            if os.name != "nt":
                path.chmod(mode)
        for relative in stale:
            (ROOT / "skills" / relative).unlink()
        for path in sorted((ROOT / "skills").rglob("*"), reverse=True):
            if path.is_dir() and not any(path.iterdir()):
                path.rmdir()
    print(f"{'Checked' if check else 'Built'} {len(names)} individual plugins and the root bundle; helpers included.")
    return 0


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    sys.exit(build(parser.parse_args().check))
