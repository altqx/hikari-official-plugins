import json
import os
import shutil
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import release  # noqa: E402
from registry import minisign  # noqa: E402
from registry.testkey import TEST_KEY  # noqa: E402

FIXTURES = Path(__file__).resolve().parent / "plugins"


class ReleaseTools(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp)
        self.plugins = self.tmp / "plugins"
        shutil.copytree(FIXTURES, self.plugins)
        patch = mock.patch.object(release, "PLUGINS", self.plugins)
        patch.start()
        self.addCleanup(patch.stop)
        if not os.environ.get("HIKARI_PLUGIN_SCHEMA"):
            self.skipTest("HIKARI_PLUGIN_SCHEMA is not set")

    def sample(self) -> Path:
        return self.plugins / "sample"

    def edit_manifest(self, **fields):
        path = self.sample() / "hikari-plugin.json"
        manifest = json.loads(path.read_text())
        manifest.update(fields)
        path.write_text(json.dumps(manifest))

    def test_the_package_leaves_out_tests_and_the_changelog(self):
        target = release.build(self.sample(), self.tmp / "dist")
        self.assertEqual(target.name, "hikarisub.sample-1.2.0.hikariplugin")
        names = sorted(zipfile.ZipFile(target).namelist())
        self.assertEqual(names, ["README.md", "hikari-plugin.json", "lua/sample.lua", "main.lua"])

    def test_two_builds_are_byte_for_byte_the_same(self):
        first = release.build(self.sample(), self.tmp / "a").read_bytes()
        second = release.build(self.sample(), self.tmp / "b").read_bytes()
        self.assertEqual(first, second)

    def test_an_id_outside_the_handle_is_refused(self):
        self.edit_manifest(id="alice.sample")
        with self.assertRaisesRegex(release.ReleaseError, "not under the hikarisub handle"):
            release.build(self.sample(), self.tmp / "dist")

    def test_the_folder_is_named_after_the_id(self):
        self.edit_manifest(id="hikarisub.other")
        with self.assertRaisesRegex(release.ReleaseError, "must be named other"):
            release.build(self.sample(), self.tmp / "dist")

    def test_another_public_key_is_refused(self):
        self.edit_manifest(publicKey="RW" + "A" * 54)
        with self.assertRaisesRegex(release.ReleaseError, "keys/hikarisub.pub"):
            release.build(self.sample(), self.tmp / "dist")

    def test_a_manifest_the_app_schema_refuses_is_refused(self):
        self.edit_manifest(api="one")
        with self.assertRaisesRegex(release.ReleaseError, "manifest: api"):
            release.build(self.sample(), self.tmp / "dist")

    def test_a_plugin_without_tests_is_refused(self):
        shutil.rmtree(self.sample() / "tests")
        with self.assertRaisesRegex(release.ReleaseError, "no tests/run.lua"):
            release.build(self.sample(), self.tmp / "dist")

    def test_a_signed_package_verifies_and_a_changed_one_does_not(self):
        target = release.build(self.sample(), self.tmp / "dist")
        release.sign(target, TEST_KEY)
        release.verify(target, TEST_KEY.public)
        target.write_bytes(target.read_bytes() + b"\0")
        with self.assertRaisesRegex(release.ReleaseError, "bad signature"):
            release.verify(target, TEST_KEY.public)

    def test_a_signature_by_another_key_does_not_verify_with_the_hikarisub_key(self):
        target = release.build(self.sample(), self.tmp / "dist")
        release.sign(target, TEST_KEY)
        with self.assertRaisesRegex(release.ReleaseError, "untrusted key"):
            release.verify(target, minisign.parse_public_key(release.PUBLIC_KEY.read_text()))

    def test_signing_refuses_a_key_that_is_not_the_hikarisub_key(self):
        env = {"HIKARISUB_MINISIGN_KEY": minisign.secret_key_file(TEST_KEY), "HIKARISUB_MINISIGN_PASSWORD": ""}
        with mock.patch.dict(os.environ, env):
            with self.assertRaisesRegex(release.ReleaseError, "does not match keys/hikarisub.pub"):
                release.secret_from_env()

    def test_signing_without_a_key_says_so(self):
        with mock.patch.dict(os.environ, {"HIKARISUB_MINISIGN_KEY": ""}):
            with self.assertRaisesRegex(release.ReleaseError, "HIKARISUB_MINISIGN_KEY is empty"):
                release.secret_from_env()

    def test_a_tag_names_the_plugin_and_its_version(self):
        folder, version = release.folder_for_tag("hikarisub.sample-v1.2.0")
        self.assertEqual((folder, version), (self.sample(), "1.2.0"))

    def test_a_tag_whose_version_is_not_the_manifests_is_refused(self):
        with self.assertRaisesRegex(release.ReleaseError, "the manifest says hikarisub.sample 1.2.0"):
            release.folder_for_tag("hikarisub.sample-v1.3.0")

    def test_a_tag_of_another_form_is_refused(self):
        for tag in ("v1.2.0", "hikarisub.sample-1.2.0", "alice.sample-v1.2.0", "hikarisub.missing-v1.0.0"):
            with self.subTest(tag=tag), self.assertRaises(release.ReleaseError):
                release.folder_for_tag(tag)

    def test_a_dispatch_names_only_a_folder_directly_in_plugins(self):
        nested = self.plugins / "sample" / "inner"
        shutil.copytree(self.sample(), nested, ignore=shutil.ignore_patterns("inner"))
        for name in ("../tools/tests/plugins/sample", "sample/inner", "..", "Sample", "/sample"):
            with self.subTest(name=name), self.assertRaisesRegex(release.ReleaseError, "by its folder in plugins/"):
                release.plugin_folder(name)
        self.assertEqual(release.plugin_folder("sample"), self.sample())

    def test_a_tag_names_only_a_folder_directly_in_plugins(self):
        for tag in ("hikarisub...-v1.2.0", "hikarisub.sample.inner-v1.2.0"):
            with self.subTest(tag=tag), self.assertRaises(release.ReleaseError):
                release.folder_for_tag(tag)

    def test_release_notes_are_the_versions_changelog_section(self):
        self.assertEqual(release.release_notes(self.sample(), "1.2.0"), "- Says hello.\n")
        with self.assertRaisesRegex(release.ReleaseError, "no '## 2.0.0' section"):
            release.release_notes(self.sample(), "2.0.0")

    def test_the_plugins_own_tests_run(self):
        release.run_tests(self.sample(), os.environ.get("LUAJIT", "luajit"))
        (self.sample() / "tests" / "run.lua").write_text("error('red')\n")
        with self.assertRaisesRegex(release.ReleaseError, "tests failed"):
            release.run_tests(self.sample(), os.environ.get("LUAJIT", "luajit"))


if __name__ == "__main__":
    unittest.main()
