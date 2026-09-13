"""Tests for logstat: every contract, every output section, the nevers, and properties."""

from __future__ import annotations

import io
import os
import random
import tempfile
import unittest
from pathlib import Path

import logstat
from logstat import (
    UINT32_MAX,
    Busy,
    ContractViolation,
    Malformed,
    Record,
    Slow,
    Summary,
    Tally,
    Timestamp,
    UsageError,
    format_count,
    mask_cards,
    parse_args,
    parse_line,
    parse_timestamp,
    render_json,
    render_text,
    summarize,
)

CARD = "4111111111111111"


def ts(text: str) -> Timestamp:
    parsed = parse_timestamp(text)
    assert parsed is not None, text
    return parsed


def record(
    at: str = "2026-09-12T10:00:00Z",
    method: str = "GET",
    path: str = "/",
    status: int = 200,
    ms: int = 1,
) -> Record:
    return Record(ts(at), method, path, status, ms)


def run_main(*argv: str) -> tuple[int, str, str]:
    out, err = io.BytesIO(), io.StringIO()
    code = logstat.main(list(argv), out, err)
    return code, out.getvalue().decode("utf-8"), err.getvalue()


class TempDir(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self._tmp.name)

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def write(self, name: str, *lines: str) -> None:
        (self.dir / name).write_text("".join(line + "\n" for line in lines), encoding="utf-8")


# ---------------------------------------------------------------- contracts: rejects


class RecordRejects(unittest.TestCase):
    def test_accepts_the_boundaries(self) -> None:
        record(status=100, ms=0)
        record(status=599, ms=UINT32_MAX)

    def test_rejects_status_below_100(self) -> None:
        with self.assertRaises(ContractViolation):
            record(status=99)

    def test_rejects_status_above_599(self) -> None:
        with self.assertRaises(ContractViolation):
            record(status=600)

    def test_rejects_negative_duration(self) -> None:
        with self.assertRaises(ContractViolation):
            record(ms=-1)

    def test_rejects_duration_over_uint32(self) -> None:
        with self.assertRaises(ContractViolation):
            record(ms=UINT32_MAX + 1)

    def test_rejects_a_method_that_is_not_letters(self) -> None:
        with self.assertRaises(ContractViolation):
            record(method="get")

    def test_rejects_a_path_without_a_slash(self) -> None:
        with self.assertRaises(ContractViolation):
            record(path="api")

    def test_rejects_a_path_holding_a_card_number(self) -> None:
        with self.assertRaises(ContractViolation):
            record(path=f"/pay/{CARD}")


class SummaryRejects(unittest.TestCase):
    def summary(self, **changes: object) -> Summary:
        fields: dict[str, object] = dict(
            requests=2, errors=1, successes=1, malformed=0, per_minute=0.0, slowest=(), busiest=()
        )
        fields.update(changes)
        return Summary(**fields)  # type: ignore[arg-type]

    def test_accepts_a_consistent_summary(self) -> None:
        self.summary()

    def test_rejects_errors_over_requests(self) -> None:
        with self.assertRaises(ContractViolation):
            self.summary(requests=1, errors=2, successes=-1)

    def test_rejects_requests_not_errors_plus_successes(self) -> None:
        with self.assertRaises(ContractViolation):
            self.summary(requests=3)

    def test_rejects_negative_malformed(self) -> None:
        with self.assertRaises(ContractViolation):
            self.summary(malformed=-1)

    def test_rejects_negative_per_minute(self) -> None:
        with self.assertRaises(ContractViolation):
            self.summary(per_minute=-1.0)

    def test_rejects_more_slowest_than_requests(self) -> None:
        slow = Slow(1, "GET", "/", ts("2026-09-12T10:00:00Z"))
        with self.assertRaises(ContractViolation):
            self.summary(slowest=(slow, slow, slow))

    def test_rejects_slowest_out_of_order(self) -> None:
        at = ts("2026-09-12T10:00:00Z")
        with self.assertRaises(ContractViolation):
            self.summary(slowest=(Slow(1, "GET", "/", at), Slow(2, "GET", "/", at)))

    def test_rejects_slowest_tie_out_of_timestamp_order(self) -> None:
        early, late = ts("2026-09-12T10:00:00Z"), ts("2026-09-12T10:00:01Z")
        with self.assertRaises(ContractViolation):
            self.summary(slowest=(Slow(5, "GET", "/", late), Slow(5, "GET", "/", early)))

    def test_rejects_busiest_out_of_order(self) -> None:
        with self.assertRaises(ContractViolation):
            self.summary(busiest=(Busy(1, "GET", "/a"), Busy(2, "GET", "/b")))

    def test_rejects_busiest_tie_out_of_path_order(self) -> None:
        with self.assertRaises(ContractViolation):
            self.summary(busiest=(Busy(1, "GET", "/b"), Busy(1, "GET", "/a")))


class OtherRejects(unittest.TestCase):
    def test_tally_rejects_top_0(self) -> None:
        with self.assertRaises(ContractViolation):
            Tally(0)

    def test_tally_rejects_top_101(self) -> None:
        with self.assertRaises(ContractViolation):
            Tally(101)

    def test_format_count_rejects_negative(self) -> None:
        with self.assertRaises(ContractViolation):
            format_count(-1)

    def test_read_lines_rejects_a_name_with_a_slash(self) -> None:
        with self.assertRaises(ContractViolation):
            next(logstat.read_lines(0, "../secret.log"))


# ---------------------------------------------------------------- parsing


class ParseTimestamp(unittest.TestCase):
    def test_accepts_z_offsets_and_fractions(self) -> None:
        self.assertEqual(ts("2026-09-12T10:00:00Z").micros, ts("2026-09-12T12:00:00+02:00").micros)
        self.assertEqual(ts("2026-09-12T10:00:00.5Z").micros - ts("2026-09-12T10:00:00Z").micros, 500_000)

    def test_rejects_other_shapes(self) -> None:
        for text in [
            "2026-09-12T10:00:00",  # no zone
            "2026-09-12 10:00:00Z",
            "2026-09-12t10:00:00z",
            "2026-09-12T10:00Z",
            "2026-02-30T10:00:00Z",
            "2026-09-12T24:00:00Z",
            "2026-09-12T10:00:60Z",
            "2026-09-12T10:00:00+24:00",
            "2026-09-12T10:00:00+05:60",
            "2026-09-12T10:00:00.1234567Z",
            "0001-01-01T00:00:00+01:00",  # before datetime.min in UTC
            "２０２６-09-12T10:00:00Z",  # fullwidth digits
        ]:
            with self.subTest(text=text):
                self.assertIsNone(parse_timestamp(text))


class ParseLine(unittest.TestCase):
    def test_yields_a_record(self) -> None:
        parsed = parse_line("2026-09-12T10:00:02Z POST /api/orders 500 340")
        self.assertEqual(parsed, record("2026-09-12T10:00:02Z", "POST", "/api/orders", 500, 340))

    def test_malformed_lines(self) -> None:
        for line in [
            "",
            "this line is not a log line",
            "2026-09-12T10:00:02Z POST /api/orders 500",
            "2026-09-12T10:00:02Z POST /api/orders 500 340 extra",
            "2026-09-12T10:00:02Z  POST /api/orders 500 340",
            "2026-09-12T10:00:02Z\tPOST /api/orders 500 340",
            "2026-09-12T10:00:02Z post /api/orders 500 340",
            "2026-09-12T10:00:02Z POST api/orders 500 340",
            "2026-09-12T10:00:02Z POST /api/\x1b[31m 500 340",
            "2026-09-12T10:00:02Z POST /api/orders 99 340",
            "2026-09-12T10:00:02Z POST /api/orders 600 340",
            "2026-09-12T10:00:02Z POST /api/orders 500 -1",
            "2026-09-12T10:00:02Z POST /api/orders 500 +1",
            "2026-09-12T10:00:02Z POST /api/orders 500 1_000",
            "2026-09-12T10:00:02Z POST /api/orders 500 4294967296",
            "2026-09-12T10:00:02Z POST /api/orders 500 ١٢",
            "2026-09-12T10:00:02Z POST /api/orders 500 " + "9" * 5000,
            "2026-09-12T10:00:02Z POST /api/orders 500 abc",
        ]:
            with self.subTest(line=line[:80]):
                self.assertIsInstance(parse_line(line), Malformed)

    def test_duration_uint32_max_is_accepted(self) -> None:
        parsed = parse_line(f"2026-09-12T10:00:02Z GET / 200 {UINT32_MAX}")
        self.assertIsInstance(parsed, Record)

    def test_masks_card_numbers_in_the_path(self) -> None:
        parsed = parse_line(f"2026-09-12T10:00:02Z POST /pay/{CARD}/ok 201 5")
        assert isinstance(parsed, Record)
        self.assertEqual(parsed.path, "/pay/" + "*" * 16 + "/ok")

    def test_decode_line(self) -> None:
        self.assertEqual(logstat.decode_line(b"a b\r\n"), "a b")
        self.assertEqual(logstat.decode_line(b"a b"), "a b")
        self.assertIsNone(logstat.decode_line(b"\xff\xfe\n"))


class MaskCards(unittest.TestCase):
    def test_masks_16_or_more_digits_only(self) -> None:
        self.assertEqual(mask_cards("/a/" + "1" * 15), "/a/" + "1" * 15)
        self.assertEqual(mask_cards("/a/" + "1" * 16), "/a/" + "*" * 16)
        self.assertEqual(mask_cards("/" + "2" * 19 + "/x"), "/" + "*" * 19 + "/x")


# ---------------------------------------------------------------- output sections

SMALL = [
    record("2026-09-12T10:00:01Z", "GET", "/api/users", 200, 12),
    record("2026-09-12T10:00:02Z", "POST", "/api/orders", 500, 340),
    record("2026-09-12T10:00:31Z", "GET", "/api/users", 200, 340),
    record("2026-09-12T10:00:31Z", "GET", "/health", 200, 1_500),
]


class Sections(unittest.TestCase):
    def setUp(self) -> None:
        self.summary = summarize(SMALL, top=3, malformed=1_234)
        self.lines = render_text(self.summary).split("\n")

    def test_head_section(self) -> None:
        self.assertEqual(
            self.lines[:5],
            ["requests       4", "errors         1  (25.0%)", "malformed  1_234", "per minute   8.0", ""],
        )

    def test_slowest_section(self) -> None:
        self.assertEqual(
            self.lines[5:10],
            [
                "slowest",
                "  1_500 ms  GET /health       2026-09-12T10:00:31Z",
                "    340 ms  POST /api/orders   2026-09-12T10:00:02Z",
                "    340 ms  GET /api/users     2026-09-12T10:00:31Z",
                "",
            ],
        )

    def test_busiest_section(self) -> None:
        self.assertEqual(
            self.lines[10:],
            ["busiest", "  2  GET /api/users", "  1  POST /api/orders", "  1  GET /health", ""],
        )

    def test_json(self) -> None:
        self.assertEqual(
            render_json(self.summary),
            '{"requests": 4, "errors": 1, "error_rate": 0.25, "malformed": 1234, "per_minute": 8.0, '
            '"slowest": [{"ms": 1500, "method": "GET", "path": "/health", "at": "2026-09-12T10:00:31Z"}, '
            '{"ms": 340, "method": "POST", "path": "/api/orders", "at": "2026-09-12T10:00:02Z"}, '
            '{"ms": 340, "method": "GET", "path": "/api/users", "at": "2026-09-12T10:00:31Z"}], '
            '"busiest": [{"count": 2, "method": "GET", "path": "/api/users"}, '
            '{"count": 1, "method": "POST", "path": "/api/orders"}, '
            '{"count": 1, "method": "GET", "path": "/health"}]}\n',
        )

    def test_empty_summary_renders(self) -> None:
        empty = summarize([])
        self.assertEqual(
            render_text(empty),
            "requests       0\nerrors         0  (0.0%)\nmalformed      0\nper minute   0.0\n\nslowest\n\nbusiest\n",
        )
        self.assertIn('"error_rate": 0.0', render_json(empty))

    def test_error_rate_rounds_to_three_places(self) -> None:
        records = [record(status=500)] * 37 + [record()] * (1204 - 37)
        summary = summarize(records)
        self.assertIn('"error_rate": 0.031', render_json(summary))
        self.assertIn("errors        37  (3.1%)", render_text(summary))
        self.assertIn("requests   1_204", render_text(summary))


class Ordering(unittest.TestCase):
    def test_busiest_ties_by_path_then_method(self) -> None:
        records = [record(path="/b"), record(path="/a", method="PUT"), record(path="/a", method="DELETE")]
        busiest = summarize(records).busiest
        self.assertEqual([(b.method, b.path) for b in busiest], [("DELETE", "/a"), ("PUT", "/a"), ("GET", "/b")])

    def test_slowest_ties_by_instant_not_text(self) -> None:
        later = record("2026-09-12T10:00:00Z", path="/later", ms=9)
        earlier = record("2026-09-12T10:30:00+01:00", path="/earlier", ms=9)
        slowest = summarize([later, earlier]).slowest
        self.assertEqual([s.path for s in slowest], ["/earlier", "/later"])

    def test_slowest_keeps_only_top_and_is_deterministic(self) -> None:
        records = [record(ms=ms, path=f"/{i}") for i, ms in enumerate([5, 9, 1, 9, 7, 3])]
        expected = ["/1", "/3", "/4"]
        for seed in range(20):
            shuffled = records[:]
            random.Random(seed).shuffle(shuffled)
            got = [s.path for s in summarize(shuffled, top=3).slowest]
            self.assertEqual(got[2], "/4")
            self.assertEqual(sorted(got[:2]), expected[:2])
        in_order = [s.path for s in summarize(records, top=3).slowest]
        self.assertEqual(in_order, expected)


class PerMinute(unittest.TestCase):
    def test_single_request_is_zero(self) -> None:
        self.assertEqual(summarize([record()]).per_minute, 0.0)

    def test_same_timestamp_is_zero(self) -> None:
        self.assertEqual(summarize([record(), record()]).per_minute, 0.0)

    def test_span_uses_earliest_and_latest_not_file_order(self) -> None:
        records = [record("2026-09-12T10:01:00Z"), record("2026-09-12T10:00:00Z"), record("2026-09-12T10:00:30Z")]
        self.assertEqual(summarize(records).per_minute, 3.0)


class Since(unittest.TestCase):
    def test_ignores_lines_before_since_keeps_equal(self) -> None:
        tally = Tally(5, ts("2026-09-12T10:00:01Z"))
        for at in ["2026-09-12T10:00:00Z", "2026-09-12T10:00:01Z", "2026-09-12T10:00:02Z"]:
            tally.add(record(at))
        tally.add_raw(b"garbage\n")
        summary = tally.summary()
        self.assertEqual((summary.requests, summary.malformed), (2, 1))


# ---------------------------------------------------------------- command line


class Args(unittest.TestCase):
    def test_defaults_and_all_options(self) -> None:
        self.assertEqual(parse_args(["logs"]), logstat.Options("logs"))
        options = parse_args(["--json", "--top", "100", "logs", "--since", "2026-09-12T10:00:00Z"])
        self.assertEqual((options.directory, options.top, options.as_json), ("logs", 100, True))
        self.assertEqual(options.since, ts("2026-09-12T10:00:00Z"))

    def test_usage_errors(self) -> None:
        for argv in [
            [],
            ["a", "b"],
            ["logs", "--top", "0"],
            ["logs", "--top", "101"],
            ["logs", "--top", "-1"],
            ["logs", "--top", "five"],
            ["logs", "--top", "1_0"],
            ["logs", "--top"],
            ["logs", "--top", "5", "--top", "6"],
            ["logs", "--json", "--json"],
            ["logs", "--since", "yesterday"],
            ["logs", "--since"],
            ["logs", "--verbose"],
        ]:
            with self.subTest(argv=argv), self.assertRaises(UsageError):
                parse_args(argv)

    def test_usage_error_exits_2_with_one_line(self) -> None:
        code, out, err = run_main("logs", "--top", "0")
        self.assertEqual((code, out), (2, ""))
        self.assertEqual(err.count("\n"), 1)
        self.assertTrue(err.startswith("logstat: --top"))


# ---------------------------------------------------------------- files and the nevers


class Files(TempDir):
    def test_reads_only_log_files_directly_inside_in_name_order(self) -> None:
        self.write("b.log", "2026-09-12T10:00:02Z GET /b 200 5")
        self.write("a.log", "2026-09-12T10:00:02Z GET /a 200 5")
        self.write("notes.txt", "2026-09-12T10:00:02Z GET /txt 200 5")
        self.write(".hidden.log", "2026-09-12T10:00:02Z GET /hidden 200 5")
        (self.dir / "sub.log").mkdir()
        (self.dir / "sub.log" / "c.log").write_text("2026-09-12T10:00:02Z GET /sub 200 5\n")
        code, out, _ = run_main(str(self.dir), "--json")
        self.assertEqual(code, 0)
        self.assertIn('"requests": 2', out)
        self.assertIn('"slowest": [{"ms": 5, "method": "GET", "path": "/a"', out)

    def test_never_follows_a_symlink_outside(self) -> None:
        with tempfile.TemporaryDirectory() as outside:
            secret = Path(outside) / "secret.log"
            secret.write_text("2026-09-12T10:00:02Z GET /secret 200 5\n")
            os.symlink(secret, self.dir / "link.log")
            self.write("real.log", "2026-09-12T10:00:02Z GET /real 200 5")
            code, out, _ = run_main(str(self.dir))
        self.assertEqual(code, 0)
        self.assertNotIn("/secret", out)
        self.assertIn("/real", out)

    def test_no_log_file_exits_1(self) -> None:
        self.write("notes.txt", "hello")
        code, out, err = run_main(str(self.dir))
        self.assertEqual((code, out), (1, ""))
        self.assertIn("no .log file", err)

    def test_missing_directory_is_a_usage_error(self) -> None:
        code, _, err = run_main(str(self.dir / "nope"))
        self.assertEqual(code, 2)
        self.assertEqual(err.count("\n"), 1)

    def test_bad_bytes_and_crlf_do_not_crash(self) -> None:
        (self.dir / "x.log").write_bytes(
            b"2026-09-12T10:00:02Z GET /a 200 5\r\n\xff\xfe garbage\n\n2026-09-12T10:00:03Z GET /a 500 6"
        )
        code, out, _ = run_main(str(self.dir), "--json")
        self.assertEqual(code, 0)
        self.assertTrue(out.startswith('{"requests": 2, "errors": 1, "error_rate": 0.5, "malformed": 2,'))

    def test_card_number_never_reaches_stdout(self) -> None:
        self.write("a.log", f"2026-09-12T10:00:02Z GET /cards/{CARD} 200 5", f"2026-09-12T10:00:03Z GET /x{CARD}9 200 5")
        for flags in [(), ("--json",)]:
            code, out, _ = run_main(str(self.dir), *flags)
            self.assertEqual(code, 0)
            self.assertNotRegex(out, "[0-9]{16}")
            self.assertIn("*" * 16, out)


# ---------------------------------------------------------------- properties


def random_record(rng: random.Random) -> Record:
    moment = f"2026-09-{rng.randint(1, 30):02d}T{rng.randint(0, 23):02d}:{rng.randint(0, 59):02d}:00Z"
    return record(
        moment,
        rng.choice(["GET", "POST", "PUT", "DELETE"]),
        rng.choice(["/", "/a", "/b", "/a/b"]),
        rng.randint(100, 599),
        rng.choice([0, 1, rng.randint(0, 5000), UINT32_MAX]),
    )


class Properties(unittest.TestCase):
    def test_errors_never_exceed_requests(self) -> None:
        rng = random.Random(2026)
        for _ in range(300):
            records = [random_record(rng) for _ in range(rng.randint(0, 60))]
            summary = summarize(records, top=rng.randint(1, 100))
            self.assertLessEqual(summary.errors, summary.requests)
            self.assertEqual(summary.requests, summary.errors + summary.successes)
            self.assertEqual(summary.requests, len(records))
            self.assertEqual(summary.errors, sum(1 for r in records if 500 <= r.status <= 599))

    def test_any_bytes_are_counted_never_raised(self) -> None:
        rng = random.Random(7)
        alphabet = b"0123456789 :-TZ./GETPOST\t\r\xff\xc3"
        valid = b"2026-09-12T10:00:02Z GET /a 200 5"
        for _ in range(300):
            tally = Tally(5)
            lines = []
            for _ in range(rng.randint(0, 20)):
                if rng.random() < 0.3:
                    lines.append(valid)
                else:
                    lines.append(bytes(rng.choice(alphabet) for _ in range(rng.randint(0, 40))))
            for line in lines:
                tally.add_raw(line)
            summary = tally.summary()
            self.assertEqual(summary.requests + summary.malformed, len(lines))
            self.assertLessEqual(summary.errors, summary.requests)


if __name__ == "__main__":
    unittest.main()
