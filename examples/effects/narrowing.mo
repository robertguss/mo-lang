module Effects.Narrowing
expose ReportError, report

intent "Hand a helper only the slice of the file system it needs: one folder, read-only."

enum ReportError
  Missing(path: String)
  Timeout
end

fn read_report(reports: Fs, name: String) : Result(String, ReportError)
  text = try reports.read(name, within: 100.ms)
  Ok(text)
end

fn report(fs: Fs, name: String) : Result(String, ReportError)
  reports = fs.scoped("/var/app/reports").read_only
  read_report(reports, name)
end

test "a report that is not in the folder is Missing"
  assert report(Fs.fixture(), "q3.txt") is Error(Missing(_))
end

verified: types, contracts, tests (1), property (0 seeds), sim (not run)
          proven: not run
