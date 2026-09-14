import os
import tempfile
import unittest
from pathlib import Path

from logstat.contract import ContractError
from logstat.files import LogReadError, list_log_names, open_directory, read_lines
from logstat.options import UsageError


class FilesTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)
        self.logs = self.root / "logs"
        self.logs.mkdir()
        self.secret = self.root / "secret.log"
        self.secret.write_text("2026-09-12T10:00:00Z GET /secret 200 1\n")
        self.dir_fd = open_directory(str(self.logs))

    def tearDown(self) -> None:
        os.close(self.dir_fd)
        self._tmp.cleanup()

    def test_lists_log_files_in_name_order(self) -> None:
        for name in ("b.log", "a.log", "c.txt", ".hidden.log", "a.log.bak"):
            (self.logs / name).write_text("x\n")
        (self.logs / "sub.log").mkdir()
        self.assertEqual(list_log_names(self.dir_fd), ["a.log", "b.log"])

    def test_never_lists_a_symlink_leading_outside(self) -> None:
        (self.logs / "escape.log").symlink_to(self.secret)
        self.assertEqual(list_log_names(self.dir_fd), [])

    def test_never_reads_through_a_symlink(self) -> None:
        (self.logs / "escape.log").symlink_to(self.secret)
        with self.assertRaises(LogReadError):
            list(read_lines(self.dir_fd, "escape.log"))

    def test_rejects_a_name_that_is_not_plain(self) -> None:
        for name in ("../secret.log", "", "..", "a/b.log"):
            with self.assertRaisesRegex(ContractError, "requires the name is a plain name"):
                list(read_lines(self.dir_fd, name))

    def test_reads_lines_as_bytes(self) -> None:
        (self.logs / "a.log").write_bytes(b"one\ntwo\r\nthree")
        self.assertEqual(list(read_lines(self.dir_fd, "a.log")), [b"one\n", b"two\r\n", b"three"])

    def test_a_missing_directory_is_a_usage_error(self) -> None:
        with self.assertRaises(UsageError):
            open_directory(str(self.root / "missing"))
        with self.assertRaises(UsageError):
            open_directory(str(self.secret))


if __name__ == "__main__":
    unittest.main()
