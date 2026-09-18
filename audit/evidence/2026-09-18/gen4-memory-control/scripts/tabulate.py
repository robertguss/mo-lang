#!/usr/bin/env python3
"""The tables of RESULTS.md from the run logs: python3 tabulate.py <logs dir>."""
import re, sys, statistics as st
L = sys.argv[1].rstrip('/') + '/'
def parse(f):
    t = open(f).read()
    g = lambda p: float(re.search(p, t).group(1))
    return dict(load=g(r'load average: ([\d.]+)'), rc=g(r'rss at 30000 jobs ([\d.]+)'),
                p1=g(r'1 worker: \d+ in [\d.]+s = (\d+)/s'), p32=g(r'32 workers: \d+ in [\d.]+s = (\d+)/s'),
                rp=g(r'rss after pairs ([\d.]+)'), rt=g(r'restart with a \d+ MB log: ([\d.]+)s'),
                date=re.search(r'# date: (.*)', t).group(1)[11:19])
V = ['gen3', 'gen4', 'cheap', 'none']
print("| variant | contracts | trial | time (UTC) | load 1-min | RSS after creates (MiB) | RSS after pairs (MiB) | pairs/s, 32 workers | pairs/s, 1 worker | restart (s) |")
print("|---|---|---|---|---|---|---|---|---|---|")
for v in V:
    for c in ['on', 'off']:
        for tr in [1, 2]:
            d = parse(f'{L}{v}-contracts-{c}-trial{tr}.log')
            print(f"| {v} | {c} | {tr} | {d['date']} | {d['load']:.2f} | {d['rc']:.1f} | {d['rp']:.1f} | {d['p32']:.0f} | {d['p1']:.0f} | {d['rt']:.2f} |")
print()
print("| variant | contracts | RSS after creates, trials 1-5 (MiB) | RSS after pairs, trials 1-5 (MiB) | median after pairs | low-state runs (after creates < 90 MiB) | pairs/s at 32, trials 1-5 | median pairs/s | median restart (s) |")
print("|---|---|---|---|---|---|---|---|---|")
for v in V:
    for c in ['on', 'off']:
        ds = [parse(f'{L}{v}-contracts-{c}-trial{tr}.log') for tr in range(1, 6)]
        j = lambda k: ", ".join(f"{d[k]:.0f}" for d in ds)
        low = sum(d['rc'] < 90 for d in ds)
        print(f"| {v} | {c} | {j('rc')} | {j('rp')} | {st.median(d['rp'] for d in ds):.0f} | {low}/5 | {j('p32')} | {st.median(d['p32'] for d in ds):.0f} | {st.median(d['rt'] for d in ds):.2f} |")
print()
print("Set A (restart invalid), trials 1-2:")
print("| variant | contracts | RSS after creates (MiB) | RSS after pairs (MiB) | pairs/s at 32 |")
print("|---|---|---|---|---|")
for v in V:
    for c in ['on', 'off']:
        ds = [parse(f'{L}setA-restart-invalid/{v}-contracts-{c}-trial{tr}.log') for tr in (1, 2)]
        f = lambda k, fmt: ', '.join(fmt.format(d[k]) for d in ds)
        print(f"| {v} | {c} | {f('rc', '{:.1f}')} | {f('rp', '{:.1f}')} | {f('p32', '{:.0f}')} |")
