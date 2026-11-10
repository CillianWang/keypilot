#!/usr/bin/env python3
"""Exercise rename migration and rollback using disposable files, without touching installed apps."""
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import install
import signing


class RenameMigrationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="keylian-migration-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.target = self.root / "Keylian.app"
        self.legacy = self.root / "KeyPilot.app"
        self.staging = self.root / "Keylian.staging.app"
        self.backup = self.root / "backup"
        self.backup.mkdir()
        self.make_app(self.staging, "new")

    def make_app(self, app, content):
        app.mkdir()
        (app / "payload").write_text(content)

    def assert_content(self, app, content):
        self.assertEqual((app / "payload").read_text(), content)

    def test_legacy_install_is_archived_and_new_name_installed(self):
        self.make_app(self.legacy, "legacy")
        moved = install.replace_apps(self.staging, self.target, [self.legacy], self.backup,
                                     lambda app: self.assert_content(app, "new"))
        self.assert_content(self.target, "new")
        self.assertFalse(self.legacy.exists())
        self.assert_content(Path(moved[str(self.legacy)]), "legacy")

    def test_both_existing_names_are_preserved_in_backup(self):
        self.make_app(self.target, "previous-new-name")
        self.make_app(self.legacy, "legacy")
        moved = install.replace_apps(self.staging, self.target, [self.target, self.legacy], self.backup,
                                     lambda app: self.assert_content(app, "new"))
        self.assert_content(Path(moved[str(self.target)]), "previous-new-name")
        self.assert_content(Path(moved[str(self.legacy)]), "legacy")

    def test_failed_signature_verification_restores_both_old_apps(self):
        self.make_app(self.target, "previous-new-name")
        self.make_app(self.legacy, "legacy")
        def reject(_):
            raise RuntimeError("invalid staged signature")
        with self.assertRaisesRegex(RuntimeError, "invalid staged signature"):
            install.replace_apps(self.staging, self.target, [self.target, self.legacy], self.backup, reject)
        self.assert_content(self.target, "previous-new-name")
        self.assert_content(self.legacy, "legacy")

    def test_failed_publish_restores_legacy_and_keeps_staging(self):
        self.make_app(self.legacy, "legacy")
        rename = Path.rename
        staging = self.staging
        def fail_publish(source, destination):
            if source == staging:
                raise OSError("cannot publish")
            return rename(source, destination)
        with patch.object(Path, "rename", fail_publish):
            with self.assertRaisesRegex(OSError, "cannot publish"):
                install.replace_apps(self.staging, self.target, [self.legacy], self.backup, lambda _: None)
        self.assertFalse(self.target.exists())
        self.assert_content(self.legacy, "legacy")
        self.assert_content(self.staging, "new")

    def test_first_install_verification_failure_leaves_no_bad_app(self):
        def reject(_):
            raise RuntimeError("invalid staged signature")
        with self.assertRaises(RuntimeError):
            install.replace_apps(self.staging, self.target, [], self.backup, reject)
        self.assertFalse(self.target.exists())

    def test_signing_checks_legacy_identity_even_if_new_app_matches(self):
        self.make_app(self.target, "previous-new-name")
        self.make_app(self.legacy, "legacy")
        config = self.root / "signing.json"
        config.write_text(json.dumps({"bundle_id": signing.BUNDLE_ID, "identity": "expected"}))
        with patch.multiple(signing, INSTALL=self.target, LEGACY_INSTALL=self.legacy, CONFIG=config), \
             patch.object(signing, "identities", return_value={"expected": "test identity"}), \
             patch.object(signing, "installed_identity", side_effect=lambda app: "expected" if app == self.target else "foreign"):
            with self.assertRaisesRegex(RuntimeError, "KeyPilot.app"):
                signing.load()


if __name__ == "__main__":
    unittest.main()
