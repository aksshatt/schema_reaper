# README illustrations

Source for every SVG in [`docs/assets/`](../assets). The SVGs are generated
files — edit these scripts, not the SVGs.

| file | builds |
|---|---|
| `make_svgs.py` | `hero.svg`, `terminal.svg`, `pipeline-{light,dark}.svg` |
| `make_diagrams.py` | `debt-*`, `automation-*`, `safety-*`, `ci-*` (light and dark) |
| `loopify.py` | shared by both: turns each animation into a loop |
| `sample_output.rb` | prints the real scan report that `terminal.svg` replays |

## Rebuilding

```sh
python3 docs/svg/make_svgs.py      # Python 3.9+, standard library only
python3 docs/svg/make_diagrams.py
```

Both write to `docs/assets/` (pass another directory as the first argument to
write elsewhere). Rebuilding unchanged scripts produces identical files.

## Keeping the terminal honest

`terminal.svg` must show what `schema_reaper scan` really prints. When the
table reporter or an analyzer's wording changes:

```sh
bundle exec ruby -Ilib docs/svg/sample_output.rb
```

It runs the real `Runner` and `Reporters::Table` against a fixture schema and a
two-model app — no database needed. Copy the output into `LINES` in
`make_svgs.py` (keeping the colour of each segment), then rebuild.

## Constraints

GitHub shows README images as `<img>`, which strips scripts and can't see page
scroll, so a play-once animation has usually finished before anyone scrolls to
it. `loopify.py` makes each animation loop with a long hold on the finished
frame. Every element's resting style is that finished frame, so reduced motion
(or a renderer without CSS animation) still shows the complete picture. Keep
fonts to system stacks — an `<img>` SVG can't load web fonts.
