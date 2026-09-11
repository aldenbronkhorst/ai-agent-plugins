"""Generated Hermes registration; edit packaging/hermes/__init__.py, then rebuild.

Workflow instructions and helpers stay in skills/. Registration only exposes
their metadata to Hermes and makes matching workflows discoverable in a session.
"""

import json
from pathlib import Path


def register(ctx):
    root = Path(__file__).resolve().parent
    metadata = json.loads((root / "hermes-skills.json").read_text(encoding="utf-8"))
    entries = []
    for skill in metadata["skills"]:
        path = (root / skill["path"]).resolve(strict=True)
        if not path.is_relative_to(root / "skills") or not path.is_file():
            raise ValueError(f"Invalid bundled skill path: {skill['path']}")
        entries.append((skill, path))

    # Keep descriptions in the system prompt, while loading full instructions on
    # demand. Hermes retains these bounded sections through context compression.
    # Do not copy skills into a global folder: disabling/removing the plugin must
    # remove its registrations, too.
    lines = [
        f"Installed workflow plugin: {metadata['display_name']}.",
        "For a matching request, load the named skill with skill_view before "
        "working.",
        f"Bundled skill directories: {root / 'skills'}/<skill-name>/. "
        "Resolve each skill's scripts and resources relative to that directory.",
    ]
    for skill, _path in entries:
        lines.append(f"{metadata['name']}:{skill['name']} — {skill['description']}")
    content = "\n".join(lines)
    if len(content) > 4000:
        raise ValueError("Plugin discovery context exceeds Hermes' 4000-character limit")
    for skill, path in entries:
        ctx.register_skill(skill["name"], path, skill["description"], skill["frontmatter"])
    ctx.register_system_prompt_section(
        f"ai-agent-plugins.{metadata['name']}", content, max_chars=4000,
    )
