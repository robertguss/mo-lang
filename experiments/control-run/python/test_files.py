import os
import tempfile
import unittest
from pathlib import Path

from files import OutsideDirectory, check_inside, list_log_files, read_lines, resolve_directory


class FilesTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name).resolve()
        self.root = self.base / "logs"
        self.root.mkdir()

    def write(self, path: Path, content: bytes = b"") -> Path:
        path.write_bytes(content)
        return path

    def test_lists_log_files_in_name_order(self) -> None:
        for name in ("b.log", "a.log", "c.log", "notes.txt", "a.log.bak", "Z.log"):
            self.write(self.root / name)
        self.assertEqual([p.name for p in list_log_files(self.root)], ["Z.log", "a.log", "b.log", "c.log"])

    def test_skips_directories_and_symlinks(self) -> None:
        (self.root / "dir.log").mkdir()
        outside = self.write(self.base / "secret.log", b"x\n")
        (self.root / "link.log").symlink_to(outside)
        self.write(self.root / "real.log")
        self.assertEqual([p.name for p in list_log_files(self.root)], ["real.log"])

    def test_skips_nested_files(self) -> None:
        (self.root / "sub").mkdir()
        self.write(self.root / "sub" / "deep.log")
        self.assertEqual(list_log_files(self.root), [])

    def test_reads_lines_as_bytes(self) -> None:
        path = self.write(self.root / "a.log", b"one\r\ntwo\nthree")
        self.assertEqual(list(read_lines(self.root, path)), [b"one\r\n", b"two\n", b"three"])

    def test_rejects_paths_outside_the_directory(self) -> None:
        outside = self.write(self.base / "secret.log", b"x\n")
        self.write(self.root / "a.log")
        (self.root / "sub").mkdir()
        nested = self.write(self.root / "sub" / "deep.log")
        for path in (outside, self.root / ".." / "secret.log", nested):
            with self.subTest(path), self.assertRaises(OutsideDirectory):
                check_inside(self.root, path)
            with self.subTest(path), self.assertRaises(OutsideDirectory):
                list(read_lines(self.root, path))

    def test_rejects_symlink_to_outside(self) -> None:
        outside = self.write(self.base / "secret.log", b"x\n")
        link = self.root / "link.log"
        link.symlink_to(outside)
        with self.assertRaises(OutsideDirectory):
            list(read_lines(self.root, link))

    def test_refuses_symlink_even_to_inside(self) -> None:
        target = self.write(self.root / "a.log", b"x\n")
        link = self.root / "b.log"
        link.symlink_to(target)
        with self.assertRaises(OSError):
            list(read_lines(self.root, link))

    def test_resolve_directory_rejects_missing_and_files(self) -> None:
        with self.assertRaises(OSError):
            resolve_directory(str(self.base / "missing"))
        with self.assertRaises(NotADirectoryError):
            resolve_directory(str(self.write(self.base / "file.log")))

    def test_resolve_directory_resolves(self) -> None:
        self.assertEqual(resolve_directory(os.path.join(str(self.root), "..", "logs")), self.root)


if __name__ == "__main__":
    unittest.main()
