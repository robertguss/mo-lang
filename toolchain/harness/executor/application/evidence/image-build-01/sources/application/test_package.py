"""Local packaging and archived-source checks, without executing Mo or Docker."""
import json
from pathlib import Path
import tarfile
import tempfile
import unittest
from unittest.mock import patch

import package
import fixtures


class Package(unittest.TestCase):
    def test_installed_distribution_must_match_verified_archive(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            installed = root / package.ZIG_ROOT
            (installed / 'lib').mkdir(parents=True)
            (installed / 'zig').write_bytes(b'executable')
            (installed / 'lib/std.zig').write_bytes(b'library')
            archive = root / 'archive.tar.xz'
            with tarfile.open(archive, 'w:xz') as target:
                target.add(installed, arcname=package.ZIG_ROOT)
            with patch.object(package, 'ZIG_SHA', package.sha(archive)):
                self.assertEqual(len(package.verify_distribution(archive, installed)), 2)
                (installed / 'lib/std.zig').write_bytes(b'mutated')
                with self.assertRaisesRegex(ValueError, 'differs'):
                    package.verify_distribution(archive, installed)
            with self.assertRaisesRegex(ValueError, 'archive hash'):
                package.verify_distribution(archive, installed)

    def test_package_inventory_rejects_links_and_empty(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with self.assertRaisesRegex(ValueError, 'empty'):
                package.inventory(root)
            (root / 'link').symlink_to('/tmp')
            with self.assertRaisesRegex(ValueError, 'nonregular'):
                package.inventory(root)

    def test_archived_application_source_and_matching_ids_fit_import_bounds(self):
        with tempfile.TemporaryDirectory() as directory:
            mapping, goldens, receipt = fixtures.load(Path(directory) / 'source')
            self.assertEqual(len(receipt['id_scope']), 5)
            for path in fixtures.PATHS:
                self.assertEqual(mapping[path], fixtures.archived(path))
            self.assertTrue(all(len(data) <= 65536 for data in mapping.values()))
            original = json.loads(fixtures.archived('.mo.ids'))
            selected = json.loads(mapping['.mo.ids'])
            self.assertTrue(all(row in original['files'] for row in selected['files']))
            self.assertTrue(all(goldens.values()))


if __name__ == '__main__':
    unittest.main(verbosity=2)
