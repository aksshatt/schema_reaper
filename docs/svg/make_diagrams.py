"""Builds the README's section diagrams (debt, automation, safety, ci) into
docs/assets/ -- same palette and animation language as pipeline-{light,dark}.svg. One file per GitHub theme, used via <picture>.
Pure CSS animation, prefers-reduced-motion respected, readable final frame.
"""
from html import escape
import os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from loopify import loopify  # noqa: E402

OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets")
MONO = "ui-monospace,SFMono-Regular,'SF Mono',Menlo,Consolas,'Liberation Mono',monospace"
SANS = "-apple-system,BlinkMacSystemFont,'Segoe UI','Noto Sans',Helvetica,Arial,sans-serif"

THEMES = {
    "dark": dict(card="#161b22", border="#30363d", text="#e6edf3", sub="#8b949e", accent="#ff7b72",
                 core="#2a1113", flow="#ff7b72", ok="#3fb950", okbg="#12261a", bad="#ff7b72", badbg="#2a1113",
                 blue="#79c0ff", bluebg="#0f2233", amber="#e3b341", amberbg="#2b2210", track="#30363d"),
    "light": dict(card="#f6f8fa", border="#d0d7de", text="#1f2328", sub="#59636e", accent="#cc342d",
                  core="#fff1f0", flow="#cc342d", ok="#1a7f37", okbg="#dafbe1", bad="#cf222e", badbg="#ffebe9",
                  blue="#0969da", bluebg="#ddf4ff", amber="#9a6700", amberbg="#fff8c5", track="#d0d7de"),
}

STYLE = """
  <style>
    .pop { opacity: 0; animation: pop .5s ease-out forwards; }
    .flow { stroke-dasharray: 6 6; animation: flow 1.2s linear infinite; }
    .pulse { animation: pulse 2.4s ease-in-out 1.2s infinite; transform-box: fill-box; transform-origin: center; }
    .grow { transform: scaleX(0); transform-box: fill-box; transform-origin: left center;
            animation: grow 2.2s cubic-bezier(.4,0,.2,1) .9s forwards; }
    @keyframes pop { from { opacity: 0; transform: translateY(6px); } to { opacity: 1; transform: none; } }
    @keyframes flow { to { stroke-dashoffset: -12; } }
    @keyframes pulse { 0%, 100% { opacity: 1; } 50% { opacity: .55; } }
    @keyframes grow { to { transform: scaleX(1); } }
    @media (prefers-reduced-motion: reduce) {
      .pop { animation: none; opacity: 1; } .flow, .pulse { animation: none; }
      .grow { animation: none; transform: none; }
    }
  </style>"""


def svg(name, w, h, title, desc, body):
    """Looped: reveals, then holds -- fades out and back in every cycle. Use
    for diagrams that are glanced at, not read line by line."""
    with open(os.path.join(OUT, name), "w") as f:
        f.write(loopify(f'''<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}" role="img"
     aria-labelledby="title desc">
  <title id="title">{escape(title)}</title>
  <desc id="desc">{escape(desc)}</desc>{STYLE}
{body}
</svg>
''', 12))


def svg_static(name, w, h, title, desc, body):
    """Plays the reveal once, then holds the finished frame forever -- no
    repeat fade-out. Use for diagrams carrying label text meant to be read:
    a looped fade makes labels vanish mid-read whenever the cycle turns over."""
    with open(os.path.join(OUT, name), "w") as f:
        f.write(f'''<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}" role="img"
     aria-labelledby="title desc">
  <title id="title">{escape(title)}</title>
  <desc id="desc">{escape(desc)}</desc>{STYLE}
{body}
</svg>
''')


def box(t, x, y, w, h, title, sub=None, delay=0.0, fill=None, stroke=None, mono_title=False, dash=False, cls="pop"):
    font = MONO if mono_title else SANS
    size = 13.5 if mono_title else 15
    d = ' stroke-dasharray="5 4"' if dash else ""
    ty = y + (h / 2 + 5 if sub is None else h / 2 - 4)
    out = [f'<g class="{cls}" style="animation-delay:{delay:.2f}s">',
           f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="12" fill="{fill or t["card"]}" stroke="{stroke or t["border"]}"{d}/>',
           f'<text x="{x + 16}" y="{ty:.0f}" font-family="{font}" font-size="{size}" font-weight="600" fill="{t["text"]}">{escape(title)}</text>']
    if sub:
        out.append(f'<text x="{x + 16}" y="{ty + 20:.0f}" font-family="{SANS}" font-size="12.5" fill="{t["sub"]}">{escape(sub)}</text>')
    out.append("</g>")
    return "".join(out)


def curve(t, x1, y1, x2, y2, color=None):
    mx = (x1 + x2) / 2
    return (f'<path class="flow" d="M{x1} {y1} C {mx} {y1}, {mx} {y2}, {x2} {y2}" fill="none" '
            f'stroke="{color or t["flow"]}" stroke-width="2" stroke-opacity=".75"/>')


for theme, t in THEMES.items():
    # ---------------------------------------------------------------- debt
    groups = [
        ("Dead weight", "nothing references it any more", t["accent"], t["core"],
         ["dead_column", "dead_table"]),
        ("Index trouble", "costs writes, or missing where needed", t["blue"], t["bluebg"],
         ["unused_index", "duplicate_index", "missing_fk_index"]),
        ("Degenerate data", "the data itself says it's dead", t["amber"], t["amberbg"],
         ["always_null_column", "single_value_column"]),
    ]
    parts, W, cw, gap = [], 1000, 312, 24
    for i, (title, sub, color, bg, names) in enumerate(groups):
        x = 8 + i * (cw + gap)
        rows = "".join(
            f'<text x="{x + 20}" y="{104 + j * 26}" font-family="{MONO}" font-size="14" fill="{t["text"]}">'
            f'<tspan fill="{color}">▸</tspan> {n}</text>' for j, n in enumerate(names))
        parts.append(f'''<g class="pop" style="animation-delay:{i * .15:.2f}s">
      <rect x="{x}" y="8" width="{cw}" height="176" rx="14" fill="{t['card']}" stroke="{t['border']}"/>
      <path d="M{x} 22a14 14 0 0 1 14-14h{cw - 28}a14 14 0 0 1 14 14v2H{x}z" fill="{color}"/>
      <text x="{x + 20}" y="56" font-family="{SANS}" font-size="17" font-weight="700" fill="{t['text']}">{title}</text>
      <text x="{x + 20}" y="76" font-family="{SANS}" font-size="12.5" fill="{t['sub']}">{escape(sub)}</text>
      {rows}</g>''')
    svg(f"debt-{theme}.svg", W, 192, "What schema_reaper finds",
        "Three kinds of schema debt. Dead weight: dead_column, dead_table. Index trouble: unused_index, "
        "duplicate_index, missing_fk_index. Degenerate data: always_null_column, single_value_column.",
        "\n".join(parts))

    # ------------------------------------------------------ automation flow
    W, H = 1000, 330
    src = [("whenever / cron", "runs rake schema_reaper:alert", 20),
           ("sidekiq-cron", "enqueues the job directly", 125),
           ("Manual trigger", "POST /internal/schema_scan", 230)]
    job = (340, 110, 220, 100)
    notif = (620, 125, 140, 70)
    outs = [("Webhook", "Slack-compatible JSON", 60), ("Email", "via your ApplicationMailer", 190)]
    parts = []
    for _, _, y in src:
        parts.append(curve(t, 250, y + 35, job[0], job[1] + job[3] / 2))
    parts.append(curve(t, job[0] + job[2], job[1] + job[3] / 2, notif[0], notif[1] + notif[3] / 2))
    for _, _, y in outs:
        parts.append(curve(t, notif[0] + notif[2], notif[1] + notif[3] / 2, 800, y + 35))
    for i, (title, sub, y) in enumerate(src):
        parts.append(box(t, 20, y, 230, 70, title, sub, delay=i * .12, dash=(i == 2)))
    parts.append(f'''<g class="pop" style="animation-delay:.45s">
      <rect class="pulse" x="{job[0]}" y="{job[1]}" width="{job[2]}" height="{job[3]}" rx="14" fill="{t['core']}" stroke="{t['accent']}" stroke-width="1.5"/>
      <text x="{job[0] + 18}" y="{job[1] + 36}" font-family="{MONO}" font-size="14" font-weight="700" fill="{t['text']}">SchemaReaper::ScanJob</text>
      <text x="{job[0] + 18}" y="{job[1] + 60}" font-family="{SANS}" font-size="12.5" fill="{t['sub']}">scans the live DB + your code</text>
      <text x="{job[0] + 18}" y="{job[1] + 80}" font-family="{SANS}" font-size="12.5" fill="{t['sub']}">one job for every path</text></g>''')
    parts.append(box(t, *notif, "Notifier", "both channels fire", delay=.6))
    for i, (title, sub, y) in enumerate(outs):
        parts.append(box(t, 800, y, 180, 70, title, sub, delay=.75 + i * .12))
    parts.append(f'<text class="pop" style="animation-delay:.9s" x="20" y="322" font-family="{SANS}" font-size="12" '
                 f'fill="{t["sub"]}">default schedule: quarterly  ·  manual trigger: bearer token, 5-minute cooldown  ·  '
                 f'delivery failures are logged, never raised</text>')
    svg_static(f"automation-{theme}.svg", W, H, "How production automation runs",
        "whenever or cron runs rake schema_reaper:alert, sidekiq-cron enqueues the job directly, and the "
        "token-protected manual trigger POST /internal/schema_scan enqueues it on demand. All three run "
        "SchemaReaper::ScanJob, which scans the live database and your code; the Notifier then sends the "
        "report to a Slack-compatible webhook and by email through your ApplicationMailer.",
        "\n".join(parts))

    # ------------------------------------------------------- safety timeline
    W, H = 1000, 210
    y0 = 92
    parts = [f'<line x1="60" y1="{y0}" x2="940" y2="{y0}" stroke="{t["track"]}" stroke-width="4" stroke-linecap="round"/>',
             f'<line class="grow" x1="60" y1="{y0}" x2="940" y2="{y0}" stroke="{t["ok"]}" stroke-width="4" stroke-linecap="round"/>']
    steps = [
        (60, "generate-migration", "writes the pair", t["blue"], t["bluebg"]),
        (340, "1 · ignore", "self.ignored_columns += %w[col]", t["ok"], t["okbg"]),
        (610, "soak in production", "until nothing reads it", t["amber"], t["amberbg"]),
        (940, "2 · drop", "remove_column — irreversible", t["bad"], t["badbg"]),
    ]
    for i, (x, title, sub, color, bg) in enumerate(steps):
        anchor = "start" if i == 0 else "end" if i == len(steps) - 1 else "middle"
        parts.append(f'''<g class="pop" style="animation-delay:{.2 + i * .45:.2f}s">
      <circle cx="{x}" cy="{y0}" r="15" fill="{bg}" stroke="{color}" stroke-width="3"/>
      <circle cx="{x}" cy="{y0}" r="5" fill="{color}"/>
      <text x="{x}" y="{y0 - 32}" text-anchor="{anchor}" font-family="{SANS}" font-size="16" font-weight="700" fill="{t['text']}">{escape(title)}</text>
      <text x="{x}" y="{y0 + 42}" text-anchor="{anchor}" font-family="{MONO}" font-size="12.5" fill="{t['sub']}">{escape(sub)}</text></g>''')
    parts.append(f'''<g class="pop" style="animation-delay:1.3s">
      <rect x="250" y="{y0 + 68}" width="180" height="28" rx="14" fill="{t['okbg']}"/>
      <text x="340" y="{y0 + 87}" text-anchor="middle" font-family="{SANS}" font-size="13" font-weight="600" fill="{t['ok']}">nothing dropped yet</text></g>''')
    parts.append(f'''<g class="pop" style="animation-delay:2.1s">
      <rect x="760" y="{y0 + 68}" width="180" height="28" rx="14" fill="{t['badbg']}"/>
      <text x="850" y="{y0 + 87}" text-anchor="middle" font-family="{SANS}" font-size="13" font-weight="600" fill="{t['bad']}">only after the soak</text></g>''')
    svg_static(f"safety-{theme}.svg", W, H, "The staged removal path",
        "generate-migration writes two migrations. Step 1 adds the column to ignored_columns and is deployed; "
        "nothing is dropped. Once it has soaked in production and nothing reads the column, step 2 runs "
        "remove_column, which is irreversible.",
        "\n".join(parts))

    # --------------------------------------------------------------- CI gate
    W, H = 1000, 200
    parts = [curve(t, 200, 100, 250, 100), curve(t, 530, 100, 590, 100),
             curve(t, 790, 100, 830, 45, t["ok"]), curve(t, 790, 100, 830, 155, t["bad"])]
    parts.append(box(t, 20, 65, 180, 70, "Pull request", "adds or changes code", delay=0))
    parts.append(box(t, 250, 65, 280, 70, "schema_reaper scan --ci", "--format sarif > reaper.sarif",
                     delay=.2, mono_title=True))
    parts.append(f'''<g class="pop" style="animation-delay:.4s">
      <rect class="pulse" x="590" y="60" width="200" height="80" rx="14" fill="{t['core']}" stroke="{t['accent']}" stroke-width="1.5"/>
      <text x="606" y="93" font-family="{SANS}" font-size="15" font-weight="700" fill="{t['text']}">compare with</text>
      <text x="606" y="116" font-family="{MONO}" font-size="13" fill="{t['text']}">baseline.json</text></g>''')
    parts.append(box(t, 830, 12, 160, 66, "✓ passes", "only known findings", delay=.65, fill=t["okbg"], stroke=t["ok"]))
    parts.append(box(t, 830, 122, 160, 66, "✗ exit 1", "new dead weight", delay=.8, fill=t["badbg"], stroke=t["bad"]))
    svg_static(f"ci-{theme}.svg", W, H, "The CI baseline gate",
        "On each pull request, schema_reaper scan --ci compares the findings with the committed "
        "baseline.json. It passes when every finding is already in the baseline and exits 1 when the change "
        "adds new dead weight.",
        "\n".join(parts))

print("wrote", sorted(f for f in os.listdir(OUT) if f.split("-")[0] in {"debt", "automation", "safety", "ci"}))
