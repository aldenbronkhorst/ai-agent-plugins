"""Package-level regression tests; the real Hermes lifecycle has its own runner."""

import importlib.util
import json
from pathlib import Path
import shutil
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
PACKAGES = sorted((ROOT / "plugins").iterdir())


def load_entrypoint(root):
    spec = importlib.util.spec_from_file_location("package_under_test", root / "__init__.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class Context:
    def __init__(self):
        self.skills = {}
        self.sections = {}

    def register_skill(self, name, path, description, frontmatter):
        assert isinstance(path, Path) and path.is_file()
        self.skills[name] = (path, description, frontmatter)

    def register_system_prompt_section(self, name, content, *, max_chars):
        assert len(content) <= max_chars <= 4000
        self.sections[name] = content


class PackageTests(unittest.TestCase):
    def test_standalone_packages_load_without_repository_or_sibling_plugins(self):
        total_context = 0
        for package in PACKAGES:
            with self.subTest(plugin=package.name), tempfile.TemporaryDirectory() as tmp:
                installed = Path(tmp) / package.name
                shutil.copytree(package, installed)
                ctx = Context()
                load_entrypoint(installed).register(ctx)
                self.assertEqual(set(ctx.skills), {package.name})
                path, description, metadata = ctx.skills[package.name]
                self.assertEqual(path.read_bytes(), (package / "skills" / package.name / "SKILL.md").read_bytes())
                self.assertEqual(description, metadata["description"])
                prompt = next(iter(ctx.sections.values()))
                self.assertIn(f"{package.name}:{package.name}", prompt)
                self.assertIn(description, prompt)
                self.assertIn("skill_view", prompt)
                self.assertIn(str(installed.resolve() / "skills"), prompt)
                total_context += len(prompt) + 150  # Hermes section framing
        self.assertLess(total_context, 8000)

    def test_optional_bundle_contains_all_workflows(self):
        ctx = Context()
        load_entrypoint(ROOT).register(ctx)
        self.assertEqual(set(ctx.skills), {p.name for p in PACKAGES})
        prompt = next(iter(ctx.sections.values()))
        self.assertIn(str(ROOT / "skills"), prompt)
        for package in PACKAGES:
            self.assertIn(f"ai-agent-plugins:{package.name}", prompt)

    def test_missing_skill_fails_instead_of_advertising_a_broken_plugin(self):
        with tempfile.TemporaryDirectory() as tmp:
            installed = Path(tmp) / "plugin"
            shutil.copytree(ROOT / "plugins/agent-core", installed)
            (installed / "skills/agent-core/SKILL.md").unlink()
            ctx = Context()
            with self.assertRaises(FileNotFoundError):
                load_entrypoint(installed).register(ctx)
            self.assertFalse(ctx.skills)
            self.assertFalse(ctx.sections)

    def test_skill_index_cannot_escape_its_package(self):
        with tempfile.TemporaryDirectory() as tmp:
            installed = Path(tmp) / "plugin"
            shutil.copytree(ROOT / "plugins/agent-core", installed)
            outside = Path(tmp) / "outside.md"
            outside.write_text("outside")
            index_path = installed / "hermes-skills.json"
            index = json.loads(index_path.read_text())
            index["skills"][0]["path"] = "../outside.md"
            index_path.write_text(json.dumps(index))
            ctx = Context()
            with self.assertRaises(ValueError):
                load_entrypoint(installed).register(ctx)
            self.assertFalse(ctx.skills)
            self.assertFalse(ctx.sections)


if __name__ == "__main__":
    unittest.main()
