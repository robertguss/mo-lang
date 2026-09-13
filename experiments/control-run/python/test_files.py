from __future__ import annotations

import os
import tempfile
import unittest
from pathlib import Path

from files import list_logs, read_lines, require_inside
from records import ContractError


class FilesTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)
        self.dir = self.root / "logs"
        self.dir.mkdir()

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def write(self, name: str, text: str = "x\n") -> Path:
        path = self.dir / name
        path.write_text(text)
        return path

    def test_lists_only_log_files_in_name_order(self) -> None:
        for name in ("b.log", "a.log", "notes.txt", ".hidden.log", "c.log.bak", "10.log"):
            self.write(name)
        (self.dir / "sub.log").mkdir()
        (self.dir / "sub.log" / "inner.log").write_text("x\n")
        self.assertEqual([p.name for p in list_logs(self.dir)], ["10.log", "a.log", "b.log"])

    def test_skips_symlink_to_a_file_outside(self) -> None:
        outside = self.root / "secret.log"
        outside.write_text("secret\n")
        os.symlink(outside, self.dir / "evil.log")
        self.assertEqual(list_logs(self.dir), [])

    def test_empty_directory_has_no_logs(self) -> None:
        self.assertEqual(list_logs(self.dir), [])

    def test_reads_lines_as_bytes(self) -> None:
        path = self.write("a.log", "one\r\ntwo\nthree")
        self.assertEqual(list(read_lines(self.dir, path)), [b"one\r\n", b"two\n", b"three"])

    def test_rejects_path_outside_directory(self) -> None:
        outside = self.root / "secret.log"
        outside.write_text("secret\n")
        with self.assertRaises(ContractError):
            require_inside(self.dir, outside)
        with self.assertRaises(ContractError):
            require_inside(self.dir, self.dir / ".." / "secret.log")
        with self.assertRaises(ContractError):
            list(read_lines(self.dir, outside))

    def test_rejects_symlink_even_when_named_directly(self) -> None:
        target = self.write("real.log")
        link = self.dir / "link.log"
        os.symlink(target, link)
        with self.assertRaises(ContractError):
            list(read_lines(self.dir, link))


if __name__ == "__main__":
    unittest.main()
