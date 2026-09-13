# Joins the logstat modules into one file for mo test and mo run, because one file sees
# one module (TOOLCHAIN-BUGS.md 1). Give the files in dependency order, main.mo last:
#   awk -f join.awk parse.mo stats.mo report.mo main.mo
# Out: main.mo's header without its use lines, every module's declarations without the
# ones marked "# copy of", then every module's tests.
FNR == 1 { section = "head"; skip = 0; ismain = (FILENAME ~ /main\.mo$/) }
section == "head" {
  if (ismain && $0 !~ /^use /) header = header $0 "\n"
  if ($0 ~ /^intent /) section = "decls"
  next
}
/^(test|property) / { section = "tests" }
section == "tests" { tests = tests $0 "\n"; next }
skip == 1 { if ($0 ~ /^type /) { skip = 3; next } if ($0 ~ /^(struct|enum) /) { skip = 2; next } }
skip == 2 { if ($0 == "end") skip = 3; next }
skip == 3 { skip = 0; if ($0 == "") next }
/^# copy of / { skip = 1; next }
{ decls = decls $0 "\n" }
END { printf "%s%s\n%s", header, decls, tests }
