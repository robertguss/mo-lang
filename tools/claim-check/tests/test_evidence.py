from __future__ import annotations

from pathlib import Path

from claim_check.evidence import Log, check, render
from claim_check.report import Claim, parse


def summary(value: str, exit_code: int | None = 0, words: str = "") -> Claim:
    claim = next(c for c in parse(f"- `{value}`").claims if c.kind == "summary")
    return Claim("c1", "summary", claim.value, words or value, "", exit_code, False, claim.counts)


SUITE = Log(
    "suite.log",
    "compile ok\nBuild Summary: 5/5 steps succeeded;\n  263/263 tests passed\n"
    "test success\nexit=0\n",
)


def test_a_summary_found_word_for_word_across_a_line_wrap(repo: Path) -> None:
    fact = check(
        summary("Build Summary: 5/5 steps succeeded; 263/263 tests passed"), [SUITE], "HEAD", repo
    )
    assert fact.status == "found"
    assert "263/263" in fact.excerpt
    assert fact.exit_record == "suite.log: exit=0"


def test_a_made_up_summary_is_not_found_and_never_judged(repo: Path) -> None:
    fact = check(
        summary("Build Summary: 5/5 steps succeeded; 264/264 tests passed"), [SUITE], "HEAD", repo
    )
    assert fact.status == "not_found"


def test_an_exit_code_the_log_contradicts(repo: Path) -> None:
    log = Log("suite.log", SUITE.text.replace("exit=0", "exit=1"))
    fact = check(
        summary("Build Summary: 5/5 steps succeeded; 263/263 tests passed"), [log], "HEAD", repo
    )
    assert fact.status == "contradicted"


def test_an_exit_file_beside_the_log_is_read_and_disagreeing_records_are_ambiguous(
    repo: Path,
) -> None:
    log = Log("d/darwin-full-suite.log", "Build Summary: 5/5 steps succeeded; 9/9 tests passed\n")
    agree = Log("d/darwin-exits.txt", "build-exit 0\nfull-exit 0\n")
    disagree = Log("d/darwin-exits.txt", "build-exit 0\nfull-exit 1\n")
    other_run = Log("d/linux-exits.txt", "full-exit 0\n")
    value = "Build Summary: 5/5 steps succeeded; 9/9 tests passed"
    assert check(summary(value), [log, agree], "HEAD", repo).status == "found"
    assert check(summary(value), [log, disagree], "HEAD", repo).status == "ambiguous"
    assert check(summary(value), [log, other_run], "HEAD", repo).status == "not_found"


def test_exit_codes_in_prose_and_before_the_summary_are_not_the_runs(repo: Path) -> None:
    log = Log(
        "fuzz.log",
        "---- mo run, exit 0\n2 inputs in 1 batches, seed 1: 0 crashes\n"
        "self-check: a planted panic: exit 134, counted as a crash\n",
    )
    fact = check(summary("2 inputs in 1 batches, seed 1: 0 crashes"), [log], "HEAD", repo)
    assert fact.status == "not_found"
    assert "no exit code" in fact.reason


def test_counts_are_codes(repo: Path) -> None:
    assert check(summary("0 passed, 0 failed, 0 skipped"), [], "HEAD", repo).status == "empty"
    assert check(summary("Ran 0 tests"), [], "HEAD", repo).status == "empty"
    failed = summary("Build Summary: 3/5 steps succeeded (1 failed); 1/2 tests passed (1 failed)")
    assert check(failed, [], "HEAD", repo).status == "contradicted"
    crashed = summary("10 inputs in 2 batches, seed 1: 1 crashes")
    assert check(crashed, [], "HEAD", repo).status == "contradicted"


def test_the_repeated_line_nearest_the_reports_subject_wins(repo: Path) -> None:
    log = Log(
        "verify.txt",
        "## step write-run: exit 0\n2 passed, 0 failed, 0 skipped\n"
        + "filler\n" * 20
        + "## step write-tests/boundaries: exit 0\n2 passed, 0 failed, 0 skipped\n",
    )
    claim = summary("2 passed, 0 failed, 0 skipped", 0, "`mo test boundaries.mo`: exit 0")
    fact = check(claim, [log], "HEAD", repo)
    assert "boundaries" in fact.excerpt
    assert fact.exit_record.endswith("## step write-tests/boundaries: exit 0")


def test_numbers_are_matched_at_the_claims_precision_and_unit(repo: Path) -> None:
    tsv = Log("n.tsv", "row\tper_call_us\nread\t28.77\nappend\t46.25\nlist\t4537.21\n")

    def number(v: str) -> str:
        return check(Claim("c", "number", v, v, ""), [tsv], "HEAD", repo).status

    assert number("28.8") == "found"
    assert number("46.3") == "found"  # half up
    assert number("46.2") == "found"  # half even: a report may round either way
    assert number("4.54") == "found"  # ms for µs
    assert number("31.0") == "not_found"


def test_commits_on_and_off_the_branch(repo: Path) -> None:
    def commit(sha: str) -> str:
        return check(Claim("c", "commit", sha, sha, ""), [], "HEAD", repo).status

    assert commit("4ad89c1a") == "found"
    assert commit("4ad89c1b") == "not_found"


def test_json_step_records_render_as_lines(tmp_path: Path) -> None:
    path = tmp_path / "verify.stdout.txt"
    path.write_text(
        '{"check": "a", "exit_code": 0, "stdout": "1 passed, 0 failed, 0 skipped\\n", '
        '"stderr": ""}\n'
    )
    assert render(path) == "## step a: exit 0\n1 passed, 0 failed, 0 skipped\n"


def test_a_number_is_found_on_the_row_its_label_names(repo: Path) -> None:
    tsv = Log(
        "n.tsv",
        "run\texe\truntime\trow\tbest_process_ms\tper_call_us\n"
        "2\tbefore\tmo run\tnone\t26.4\t0.00\n"
        "2\tbefore\tbinary\tread\t78.1\t26.35\n",
    )
    claim = Claim("c", "number", "26.4", "", "", label="`read` small file / binary before")
    fact = check(claim, [tsv], "HEAD", repo)
    assert fact.excerpt.splitlines()[-1].endswith("26.35")
    assert fact.excerpt.splitlines()[0].startswith("run\texe")  # the header, then one line
    assert len(fact.excerpt.splitlines()) == 2
    assert fact.reason == "26.35 in this line rounds to the claimed 26.4"
