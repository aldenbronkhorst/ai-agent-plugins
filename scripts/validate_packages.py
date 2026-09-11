#!/usr/bin/env python3
"""Validate portable manifests, generated package contents, and icon paths."""

import json
from pathlib import Path
import sys
from urllib.request import urlopen

from jsonschema import Draft202012Validator
import yaml

from build_packages import ROOT, build

SCHEMA_URL = "https://agent-plugins.org/schemas/1.0.0/plugin.schema.json"


def main():
    if build(check=True):
        return 1
    with urlopen(SCHEMA_URL, timeout=30) as response:
        validator = Draft202012Validator(json.load(response))
    for manifest_path in [ROOT / "plugin.json", *sorted((ROOT / "plugins").glob("*/plugin.json"))]:
        manifest = json.loads(manifest_path.read_text())
        validator.validate(manifest)
        package = manifest_path.parent
        native = yaml.safe_load((package / "plugin.yaml").read_text())
        index = json.loads((package / "hermes-skills.json").read_text())
        for key in ("name", "version"):
            if not native[key] == index[key] == manifest[key]:
                raise ValueError(f"Hermes {key} differs for {manifest['name']}")
        for skill in index["skills"]:
            path = (package / skill["path"]).resolve(strict=True)
            if not path.is_relative_to((package / "skills").resolve()) or path.name != "SKILL.md":
                raise ValueError(f"Invalid indexed skill: {skill['path']}")
        interface = manifest.get("extensions", {}).get("com.openai", {}).get("interface", {})
        for field in ("composerIcon", "logo"):
            if field in interface:
                icon = (package / interface[field]).resolve(strict=True)
                if not icon.is_file() or not icon.is_relative_to(package.resolve()):
                    raise ValueError(f"Invalid {field} for {manifest['name']}")
        print(f"Validated portable and native packaging: {manifest['name']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
