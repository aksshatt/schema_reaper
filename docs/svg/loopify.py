"""Turns the README SVGs' play-once animations into loops.

GitHub loads every README image when the page opens and gives it no way to
see scroll position (no JS; an <img> SVG is an isolated document), so a
play-once animation has usually finished before the reader scrolls to it.
Looping with a long hold on the finished frame is the closest substitute:
wherever the reader lands, they see the finished picture or a replay.

Every animated element gets its *own* keyframes covering the whole cycle,
with its start delay baked into the percentages -- so all elements in an
image share one period and the reveal order stays intact on every loop
(a shared keyframe + animation-delay would drift the hide times apart).

An element's resting CSS is its finished frame, so reduced motion (or any
renderer without CSS animation) shows the complete picture.
"""
import hashlib
import re

# class -> animation spec. Times in seconds; `delay` is the default when the
# element carries no animation-delay of its own.
SPECS = {
    "pop":    dict(dur=.5, frm="opacity:0;transform:translateY(6px)", to="opacity:1;transform:none"),
    "l":      dict(dur=.35, frm="opacity:0;transform:translateY(4px)", to="opacity:1;transform:none"),
    "fade":   dict(dur=.8, frm="opacity:0", to="opacity:1"),
    "chip":   dict(dur=.6, frm="opacity:0", to="opacity:1"),
    "tag":    dict(dur=.4, frm="opacity:0", to="opacity:1"),
    "hl":     dict(dur=.9, frm="opacity:0", mids=[(.3, "opacity:.08")], to="opacity:0"),
    "hlDead": dict(dur=.9, frm="opacity:0", mids=[(.3, "opacity:.28")], to="opacity:.12"),
    "strike": dict(dur=.5, frm="stroke-dashoffset:200", to="stroke-dashoffset:0"),
    "grow":   dict(delay=.9, dur=2.2, frm="transform:scaleX(0)", to="transform:scaleX(1)",
                   timing="cubic-bezier(.4,0,.2,1)"),
}

STATIC = """
    .flow { stroke-dasharray: 6 6; animation: flow 1.2s linear infinite; }
    .pulse { animation: pulse 2.4s ease-in-out 1.2s infinite; transform-box: fill-box; transform-origin: center; }
    .grow { transform-box: fill-box; transform-origin: left center; }
    .strike { stroke-dasharray: 200; }
    .scan { opacity: 0; }
    @keyframes flow { to { stroke-dashoffset: -12; } }
    @keyframes pulse { 0%, 100% { opacity: 1; } 50% { opacity: .55; } }
    @keyframes blink { 50% { opacity: 0; } }"""

HIDE_AT, GONE_AT = 1.0, .45  # seconds before the cycle ends: start fading out / fully reset


def _pct(t, period):
    return f"{100 * t / period:.2f}%"


def keyframes(name, period, start, dur, frm, to, pre=None, mids=(), timing="ease-out"):
    pre = pre or frm
    end, hide, gone = start + dur, period - HIDE_AT, period - GONE_AT
    assert end < hide, f"{name}: appears at {end:.2f}s, after the hold should begin"
    frames = [("0%", f"{pre};animation-timing-function:step-end")]  # hold `pre` until start
    frames.append((_pct(start, period), f"{frm};animation-timing-function:{timing}"))
    frames += [(_pct(start + f * dur, period), props) for f, props in mids]
    frames += [(_pct(end, period), to), (_pct(hide, period), f"{to};animation-timing-function:ease-in"),
               (_pct(gone, period), pre), ("100%", pre)]
    body = " ".join(f"{p} {{ {v} }}" for p, v in frames)
    return f"    @keyframes {name} {{ {body} }}"


def loopify(svg, period, static_css="", extra_specs=None):
    specs = {**SPECS, **(extra_specs or {})}
    rules, counter = [], [0]
    # Unique per file: names only need to be unique within one <img> document,
    # but a page that inlines several of these SVGs would otherwise collide.
    prefix = "a" + hashlib.md5(svg.encode()).hexdigest()[:5]

    def tag(match):
        text = match.group(0)
        cls = re.search(r'class="([^"]*)"', text)
        if not cls:
            return text
        names = cls.group(1).split()
        animated = [n for n in names if n in specs]
        if not animated:
            return text
        spec = specs[animated[0]]
        delay = re.search(r'\s*style="animation-delay:([\d.]+)s"', text)
        start = float(delay.group(1)) if delay else spec.get("delay", 0.0)
        if delay:
            text = text.replace(delay.group(0), "")
        counter[0] += 1
        name = f"{prefix}{counter[0]}"
        kw = {k: spec[k] for k in ("pre", "mids", "timing") if k in spec}
        rules.append(keyframes(name, period, start, spec["dur"], spec["frm"], spec["to"], **kw))
        also = f", {spec['also']}" if "also" in spec else ""
        rules.append(f"    .{name} {{ animation: {name} {period}s linear infinite{also}; }}")
        return text.replace(cls.group(0), f'class="{" ".join(names + [name])}"')

    svg = re.sub(r"<[a-zA-Z][^>]*>", tag, svg)
    style = ("  <style>" + static_css + STATIC + "\n" + "\n".join(rules) +
             "\n    @media (prefers-reduced-motion: reduce) { * { animation: none !important; } }\n  </style>")
    svg, n = re.subn(r"  <style>.*?</style>", lambda _: style, svg, count=1, flags=re.S)
    assert n == 1, "expected exactly one <style> block"
    return svg
