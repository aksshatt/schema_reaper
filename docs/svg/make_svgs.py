"""Builds the README's hero, terminal and pipeline SVGs into docs/assets/.
(The section diagrams come from make_diagrams.py; see docs/svg/README.md.)

Everything is self-contained: no external fonts, no scripts (GitHub serves
README images through camo and strips JS; CSS @keyframes and SMIL inside an
<img>-loaded SVG still animate). Each animation respects
prefers-reduced-motion and rests on a fully readable final frame; loopify
turns each one into a loop (see loopify.py for why).
"""
from html import escape
import os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from loopify import loopify  # noqa: E402

OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets")
os.makedirs(OUT, exist_ok=True)

MONO = "ui-monospace,SFMono-Regular,'SF Mono',Menlo,Consolas,'Liberation Mono',monospace"
SANS = "-apple-system,BlinkMacSystemFont,'Segoe UI','Noto Sans',Helvetica,Arial,sans-serif"


def write(name, svg):
    with open(os.path.join(OUT, name), "w") as f:
        f.write(svg.strip() + "\n")


# --------------------------------------------------------------------------
# 1. Animated terminal -- the real `schema_reaper scan` output, as printed by
#    docs/svg/sample_output.rb, coloured exactly as Reporters::Ansi does:
#    severity high=red medium=yellow low=cyan, table names bold magenta,
#    evidence dim, fixes green.
# --------------------------------------------------------------------------
C = {"red": "#ff7b72", "yellow": "#e3b341", "magenta": "#d2a8ff", "green": "#3fb950",
     "dim": "#8b949e", "fg": "#e6edf3", "prompt": "#79c0ff"}

S = lambda text, color="fg", bold=False: (text, color, bold)
LINES = [
    [],
    [S("  "), S("schema_reaper", bold=True), S("  "), S("3 findings across 2 tables", bold=True)],
    [S("  missing_fk_index 1 · always_null_column 1 · dead_table 1", "dim")],
    [S("  ~46.9 KB reclaimable", "dim")],
    [],
    [S("  "), S("users", "magenta", True)],
    [S("    "), S("█████", "yellow"), S("  90%  "), S("medium", "yellow", True), S("  "),
     S("missing_fk_index   ", bold=True), S("  team_id")],
    [S("           team_id has no covering index (declared foreign key constraint)", "dim")],
    [S("           → add_index :users, :team_id", "green")],
    [S("    "), S("████░", "red"), S("  85%  "), S("high  ", "red", True), S("  "),
     S("always_null_column ", bold=True), S("  api_key"), S("  46.9 KB", "dim")],
    [S("           pg_stats.null_frac = 1.0 across ~3000 row(s) · column carries no data", "dim")],
    [S("           → verify with `SELECT count(api_key) FROM users` then stage a removal", "green")],
    [],
    [S("  "), S("stale_exports", "magenta", True)],
    [S("    "), S("████░", "red"), S("  85%  "), S("high  ", "red", True), S("  "), S("dead_table", bold=True)],
    [S("           no model or query reference to `stale_exports` in scanned code · table holds ~0 row(s)", "dim")],
    [S("           → confirm no external consumer, then `drop_table :stale_exports`", "green")],
    [],
    [S("  "), S("high 2", "red", True), S("   "), S("medium 1", "yellow", True)],
    [S("  missing_fk_index 1 · always_null_column 1 · dead_table 1", "dim")],
]

CMD = "bundle exec schema_reaper scan"
FS = 13            # font size
CW = FS * 0.6      # monospace advance
LH = 19            # line height
PAD_X = 22
TOP = 44           # below the title bar
W = 880
H = TOP + 26 + LH * (len(LINES) + 1) + 14

typing_start, per_char = 0.5, 0.045
typing_end = typing_start + per_char * len(CMD)
out_start = typing_end + 0.45

rows = []
# prompt + typed command, revealed char-by-char by a stepped CSS clip-path
prompt_y = TOP + 26
cmd_x = PAD_X + CW * 2
widths = ";".join(f"{CW * i:.1f}" for i in range(len(CMD) + 1))
key_times = ";".join(f"{i / len(CMD):.4f}" for i in range(len(CMD) + 1))
rows.append(f'''
  <text x="{PAD_X}" y="{prompt_y}" class="t"><tspan fill="{C['green']}" font-weight="700">$</tspan></text>
  <text x="{cmd_x:.1f}" y="{prompt_y}" class="t cmd" fill="{C['fg']}">{escape(CMD)}</text>
  <rect class="cursor" x="{cmd_x + CW * len(CMD):.1f}" y="{prompt_y - 12}" width="{CW:.1f}" height="15" fill="{C['fg']}"/>''')

for i, segs in enumerate(LINES):
    if not segs:
        continue
    y = prompt_y + LH * (i + 1)
    delay = out_start + i * 0.09
    BOLD = ' font-weight="700"'
    spans = "".join(
        f'<tspan fill="{C[c]}"{BOLD if b else ""}>{escape(t)}</tspan>' for t, c, b in segs
    )
    rows.append(f'  <text x="{PAD_X}" y="{y}" class="t l" xml:space="preserve" '
                f'style="animation-delay:{delay:.2f}s">{spans}</text>')

TERMINAL_SPECS = {
    "cmd": dict(delay=typing_start, dur=typing_end - typing_start, frm="clip-path:inset(0 100% 0 0)",
                to="clip-path:inset(0 0 0 0)", timing=f"steps({len(CMD)}, end)"),
    "cursor": dict(delay=typing_start, dur=typing_end - typing_start,
                   frm=f"transform:translateX(-{CW * len(CMD):.1f}px)", to="transform:translateX(0)",
                   timing=f"steps({len(CMD)}, end)", also="blink 1s step-end infinite"),
}
write("terminal.svg", loopify(f'''
<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}" role="img"
     aria-labelledby="title desc">
  <title id="title">schema_reaper scan -- example terminal output</title>
  <desc id="desc">Running bundle exec schema_reaper scan prints 3 findings across 2 tables: a missing
  foreign-key index on users.team_id, an always-null users.api_key column reclaiming 46.9 KB, and an
  unreferenced empty stale_exports table, each with a confidence bar, severity and a suggested fix.</desc>
  <style>
    .t {{ font-family: {MONO}; font-size: {FS}px; white-space: pre; }}
    .l {{ opacity: 0; animation: in .35s ease-out forwards; }}
    .cmd {{ clip-path: inset(0 100% 0 0); animation: type {typing_end - typing_start:.2f}s steps({len(CMD)}, end) {typing_start}s forwards; }}
    .cursor {{ animation: move {typing_end - typing_start:.2f}s steps({len(CMD)}, end) {typing_start}s forwards, blink 1s step-end infinite; }}
    @keyframes type {{ to {{ clip-path: inset(0 0 0 0); }} }}
    @keyframes move {{ to {{ transform: translateX({CW * len(CMD):.1f}px); }} }}
    @keyframes in {{ from {{ opacity: 0; transform: translateY(4px); }} to {{ opacity: 1; transform: none; }} }}
    @keyframes blink {{ 50% {{ opacity: 0; }} }}
    @media (prefers-reduced-motion: reduce) {{ .l {{ animation: none; opacity: 1; }} .cmd {{ animation: none; clip-path: none; }} .cursor {{ animation: none; transform: translateX({CW * len(CMD):.1f}px); }} }}
  </style>
  <rect width="{W}" height="{H}" rx="12" fill="#0d1117"/>
  <rect x=".5" y=".5" width="{W - 1}" height="{H - 1}" rx="11.5" fill="none" stroke="#30363d"/>
  <path d="M12 .5h{W - 24}a11.5 11.5 0 0 1 11.5 11.5v20H.5V12A11.5 11.5 0 0 1 12 .5z" fill="#161b22"/>
  <line x1="0" y1="32" x2="{W}" y2="32" stroke="#30363d"/>
  <circle cx="20" cy="16" r="6" fill="#ff5f57"/><circle cx="40" cy="16" r="6" fill="#febc2e"/>
  <circle cx="60" cy="16" r="6" fill="#28c840"/>
  <text x="{W / 2}" y="20" text-anchor="middle" font-family="{SANS}" font-size="12" fill="#8b949e">~/my_app — schema_reaper scan</text>
{chr(10).join(rows)}
</svg>''', 14, static_css=f"\n    .t {{ font-family: {MONO}; font-size: {FS}px; white-space: pre; }}",
    extra_specs=TERMINAL_SPECS))


# --------------------------------------------------------------------------
# 2. Hero banner -- dark card with its own background, so one file works in
#    both GitHub themes. A scan line sweeps a mini "users" table; the rows the
#    gem would flag light up red and get struck through.
# --------------------------------------------------------------------------
HW, HH = 1200, 340
cols = [("id", "bigint", False), ("email", "varchar", False), ("team_id", "bigint", False),
        ("api_key", "varchar", True), ("legacy_score", "integer", True), ("created_at", "timestamp", False)]
tx, ty, tw, rh = 800, 66, 320, 32
table_rows = []
for i, (name, typ, dead) in enumerate(cols):
    y = ty + 56 + i * rh
    cls = ' class="dead"' if dead else ""
    delay = 1.1 + i * 0.35
    extra = ""
    if dead:
        x2 = tx + 14 + len(name) * 9.2 + 6
        extra = (f'<line class="strike" x1="{tx + 14}" y1="{y - 5}" x2="{x2:.0f}" y2="{y - 5}" stroke="#ff7b72" '
                 f'stroke-width="2" style="animation-delay:{delay + .25:.2f}s"/>'
                 f'<text class="tag" x="{tx + tw - 110}" y="{y}" font-family="{MONO}" font-size="12" fill="#ff7b72" '
                 f'font-weight="700" text-anchor="end" style="animation-delay:{delay + .35:.2f}s">dead</text>')
    table_rows.append(f"""
    <g{cls}>
      <rect class="{'hlDead' if dead else 'hl'}" x="{tx + 1}" y="{y - 21}" width="{tw - 2}" height="{rh}" fill="#ff7b72" opacity="{.12 if dead else 0}"
            style="animation-delay:{delay:.2f}s"/>
      <text x="{tx + 18}" y="{y}" font-family="{MONO}" font-size="15" fill="#e6edf3">{name}</text>
      <text x="{tx + tw - 18}" y="{y}" font-family="{MONO}" font-size="13" fill="#8b949e" text-anchor="end">{typ}</text>
      {extra}
    </g>""")
    if i < len(cols) - 1:
        table_rows.append(f'<line x1="{tx}" y1="{y + 11}" x2="{tx + tw}" y2="{y + 11}" stroke="#30363d"/>')
table_h = 56 + len(cols) * rh - 12

chips = ["7 analyzers", "staged migrations", "CI baseline gate", "scheduled scans + alerts"]
chip_svg, cx = [], 64
for i, label in enumerate(chips):
    w = len(label) * 8.2 + 28
    chip_svg.append(f'''<g class="chip" style="animation-delay:{.6 + i * .15:.2f}s">
      <rect x="{cx}" y="252" width="{w:.0f}" height="32" rx="16" fill="#ffffff" fill-opacity=".06" stroke="#ffffff" stroke-opacity=".18"/>
      <text x="{cx + w / 2:.0f}" y="273" text-anchor="middle" font-family="{SANS}" font-size="14" fill="#f0c9c6">{label}</text></g>''')
    cx += w + 12

HERO_SPECS = {
    "scan": dict(delay=1.0, dur=2.4, pre="opacity:0;transform:translateY(0)", frm="opacity:1;transform:translateY(0)",
                 mids=[(.9, f"opacity:1;transform:translateY({table_h * .9:.0f}px)")],
                 to=f"opacity:0;transform:translateY({table_h}px)", timing="linear"),
}
write("hero.svg", loopify(f'''
<svg xmlns="http://www.w3.org/2000/svg" width="{HW}" height="{HH}" viewBox="0 0 {HW} {HH}" role="img"
     aria-labelledby="title desc">
  <title id="title">schema_reaper</title>
  <desc id="desc">schema_reaper: find and safely remove dead columns, tables and indexes in Rails and
  PostgreSQL apps. Illustration: a users table being scanned, with api_key and legacy_score flagged dead.</desc>
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#2a0906"/><stop offset=".55" stop-color="#120708"/><stop offset="1" stop-color="#0d1117"/>
    </linearGradient>
    <linearGradient id="brand" x1="0" x2="1">
      <stop offset="0" stop-color="#ffb3ad"/><stop offset=".5" stop-color="#ff5a4f"/><stop offset="1" stop-color="#cc342d"/>
    </linearGradient>
    <linearGradient id="sweep" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#ff7b72" stop-opacity="0"/><stop offset=".85" stop-color="#ff7b72" stop-opacity=".35"/>
      <stop offset="1" stop-color="#ff7b72" stop-opacity=".9"/>
    </linearGradient>
    <pattern id="grid" width="32" height="32" patternUnits="userSpaceOnUse">
      <path d="M32 0H0v32" fill="none" stroke="#ffffff" stroke-opacity=".035"/>
    </pattern>
    <clipPath id="card"><rect x="{tx}" y="{ty}" width="{tw}" height="{table_h}" rx="10"/></clipPath>
  </defs>
  <style>
    .fade {{ opacity: 0; animation: fade .8s ease-out forwards; }}
    .chip {{ opacity: 0; animation: fade .6s ease-out forwards; }}
    .hl {{ animation: hl .9s ease-out forwards; }}
    .dead .hl {{ animation: hlDead .9s ease-out forwards; }}
    .strike {{ stroke-dasharray: 200; stroke-dashoffset: 200; animation: strike .5s ease-out forwards; }}
    .tag {{ opacity: 0; animation: fade .4s ease-out forwards; }}
    .scan {{ animation: scan 2.4s cubic-bezier(.4,0,.2,1) 1s 1 forwards; opacity: 0; }}
    @keyframes fade {{ to {{ opacity: 1; }} }}
    @keyframes hl {{ 0% {{ opacity: 0; }} 30% {{ opacity: .08; }} 100% {{ opacity: 0; }} }}
    @keyframes hlDead {{ 0% {{ opacity: 0; }} 30% {{ opacity: .28; }} 100% {{ opacity: .12; }} }}
    @keyframes strike {{ to {{ stroke-dashoffset: 0; }} }}
    @keyframes scan {{ 0% {{ opacity: 1; transform: translateY(0); }} 90% {{ opacity: 1; }} 100% {{ opacity: 0; transform: translateY({table_h}px); }} }}
    @media (prefers-reduced-motion: reduce) {{
      .fade, .chip, .tag {{ animation: none; opacity: 1; }}
      .strike {{ animation: none; stroke-dashoffset: 0; }}
      .hl, .scan {{ animation: none; }} .dead .hl {{ animation: none; opacity: .12; }}
    }}
  </style>
  <rect width="{HW}" height="{HH}" rx="18" fill="url(#bg)"/>
  <rect width="{HW}" height="{HH}" rx="18" fill="url(#grid)"/>
  <rect x=".5" y=".5" width="{HW - 1}" height="{HH - 1}" rx="17.5" fill="none" stroke="#ffffff" stroke-opacity=".08"/>

  <g class="fade">
    <text x="64" y="92" font-family="{SANS}" font-size="15" font-weight="600" letter-spacing="3" fill="#ff7b72">RUBY GEM · RAILS + POSTGRESQL</text>
    <text x="60" y="160" font-family="{MONO}" font-size="64" font-weight="800" fill="url(#brand)">schema_reaper</text>
    <text x="64" y="202" font-family="{SANS}" font-size="21" fill="#e6edf3">Find — and safely remove — the dead columns, tables</text>
    <text x="64" y="230" font-family="{SANS}" font-size="21" fill="#e6edf3">and indexes your Rails app no longer uses.</text>
  </g>
  {"".join(chip_svg)}

  <g class="fade" style="animation-delay:.3s">
    <rect x="{tx}" y="{ty}" width="{tw}" height="{table_h}" rx="10" fill="#0d1117" fill-opacity=".85" stroke="#30363d"/>
    <text x="{tx + 18}" y="{ty + 22}" font-family="{MONO}" font-size="13" font-weight="700" fill="#d2a8ff">users</text>
    <text x="{tx + tw - 18}" y="{ty + 22}" font-family="{MONO}" font-size="12" fill="#8b949e" text-anchor="end">~3,000 rows</text>
    <line x1="{tx}" y1="{ty + 32}" x2="{tx + tw}" y2="{ty + 32}" stroke="#30363d"/>
    <g clip-path="url(#card)">{"".join(table_rows)}
      <rect class="scan" x="{tx}" y="{ty - 28}" width="{tw}" height="30" fill="url(#sweep)"/>
    </g>
  </g>
</svg>''', 12, extra_specs=HERO_SPECS))


# --------------------------------------------------------------------------
# 3. "How it works" pipeline, one file per GitHub theme (<picture>).
# --------------------------------------------------------------------------
THEMES = {
    "dark": dict(card="#161b22", border="#30363d", text="#e6edf3", sub="#8b949e", accent="#ff7b72",
                 core="#2a1113", coreBorder="#ff7b72", flow="#ff7b72", chip="#21262d"),
    "light": dict(card="#f6f8fa", border="#d0d7de", text="#1f2328", sub="#59636e", accent="#cc342d",
                  core="#fff1f0", coreBorder="#cc342d", flow="#cc342d", chip="#ffffff"),
}
PW, PH = 1000, 380
inputs = [("Live PostgreSQL", "schema · pg_stats · index scans"),
          ("Your codebase", "Prism AST · views · SQL strings"),
          ("Runtime signal", "optional · sampled column reads")]
outputs = [("Reports", "terminal · markdown · json · sarif"),
           ("CI baseline gate", "fail only on new dead weight"),
           ("Scheduled report", "Slack-style webhook + email"),
           ("Staged migrations", "ignore first, drop later")]

for theme, t in THEMES.items():
    parts = []
    bx, bw, bh = 20, 250, 70
    in_ys = [48 + i * 104 for i in range(3)]
    for i, ((title, sub), y) in enumerate(zip(inputs, in_ys)):
        dash = ' stroke-dasharray="5 4"' if i == 2 else ""
        parts.append(f'''<g class="pop" style="animation-delay:{i * .12:.2f}s">
      <rect x="{bx}" y="{y}" width="{bw}" height="{bh}" rx="12" fill="{t['card']}" stroke="{t['border']}"{dash}/>
      <text x="{bx + 20}" y="{y + 30}" font-family="{SANS}" font-size="16" font-weight="600" fill="{t['text']}">{title}</text>
      <text x="{bx + 20}" y="{y + 52}" font-family="{SANS}" font-size="13" fill="{t['sub']}">{escape(sub)}</text></g>''')
    cx0, cy0, cw, ch = 375, 60, 250, 260
    for y in in_ys:
        parts.append(f'<path class="flow" d="M{bx + bw} {y + bh / 2} C {bx + bw + 55} {y + bh / 2}, {cx0 - 55} {cy0 + ch / 2}, {cx0} {cy0 + ch / 2}" '
                     f'fill="none" stroke="{t["flow"]}" stroke-width="2" stroke-opacity=".7"/>')
    ox, ow, oh = 730, 250, 64
    out_ys = [34 + i * 82 for i in range(4)]
    for y in out_ys:
        parts.append(f'<path class="flow" d="M{cx0 + cw} {cy0 + ch / 2} C {cx0 + cw + 55} {cy0 + ch / 2}, {ox - 55} {y + oh / 2}, {ox} {y + oh / 2}" '
                     f'fill="none" stroke="{t["flow"]}" stroke-width="2" stroke-opacity=".7"/>')
    analyzers = ["dead_column", "dead_table", "unused_index", "duplicate_index",
                 "missing_fk_index", "always_null_column", "single_value_column"]
    alist = "".join(
        f'<text x="{cx0 + 24}" y="{cy0 + 78 + i * 22}" font-family="{MONO}" font-size="13" fill="{t["text"]}">'
        f'<tspan fill="{t["accent"]}">▸</tspan> {a}</text>' for i, a in enumerate(analyzers))
    parts.append(f'''<g class="pop" style="animation-delay:.4s">
      <rect x="{cx0}" y="{cy0}" width="{cw}" height="{ch}" rx="16" fill="{t['core']}" stroke="{t['coreBorder']}" stroke-width="1.5"/>
      <text x="{cx0 + 24}" y="{cy0 + 34}" font-family="{SANS}" font-size="17" font-weight="700" fill="{t['text']}">7 analyzers</text>
      <text x="{cx0 + 24}" y="{cy0 + 54}" font-family="{SANS}" font-size="12.5" fill="{t['sub']}">confidence · severity · reclaim</text>
      {alist}</g>''')
    for i, ((title, sub), y) in enumerate(zip(outputs, out_ys)):
        parts.append(f'''<g class="pop" style="animation-delay:{.7 + i * .12:.2f}s">
      <rect x="{ox}" y="{y}" width="{ow}" height="{oh}" rx="12" fill="{t['card']}" stroke="{t['border']}"/>
      <text x="{ox + 18}" y="{y + 27}" font-family="{SANS}" font-size="14.5" font-weight="600" fill="{t['text']}">{escape(title)}</text>
      <text x="{ox + 18}" y="{y + 47}" font-family="{SANS}" font-size="12.5" fill="{t['sub']}">{escape(sub)}</text></g>''')

    write(f"pipeline-{theme}.svg", loopify(f'''
<svg xmlns="http://www.w3.org/2000/svg" width="{PW}" height="{PH}" viewBox="0 0 {PW} {PH}" role="img"
     aria-labelledby="title desc">
  <title id="title">How schema_reaper works</title>
  <desc id="desc">Three inputs -- the live PostgreSQL schema and statistics, a static scan of your
  codebase, and an optional runtime signal -- feed seven analyzers, which score each finding and
  produce reports in four formats, a CI baseline gate, scheduled webhook and email reports, and
  staged removal migrations.</desc>
  <style>
    .pop {{ opacity: 0; animation: pop .5s ease-out forwards; }}
    .flow {{ stroke-dasharray: 6 6; animation: flow 1.2s linear infinite; }}
    @keyframes pop {{ from {{ opacity: 0; transform: translateY(6px); }} to {{ opacity: 1; transform: none; }} }}
    @keyframes flow {{ to {{ stroke-dashoffset: -12; }} }}
    @media (prefers-reduced-motion: reduce) {{ .pop {{ animation: none; opacity: 1; }} .flow {{ animation: none; }} }}
  </style>
  {chr(10).join(parts)}
</svg>''', 12))

print("wrote", sorted(os.listdir(OUT)))
