# README illustrations

Source for every SVG in [`docs/assets/`](../assets). The SVGs are generated
files — edit these scripts, not the SVGs.

| file | builds |
|---|---|
| `make_svgs.py` | `hero.svg`, `terminal.svg`, `pipeline-{light,dark}.svg` |
| `make_diagrams.py` | `debt-*`, `automation-*`, `safety-*`, `ci-*` (light and dark) |
| `loopify.py` | turns an animation into a loop; used for `hero`, `terminal`, `pipeline-*` and `debt-*` only |
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
it. `loopify.py` makes an animation loop with a long hold on the finished
frame, for diagrams that are glanced at rather than read line by line
(`hero`, `terminal`, `pipeline-*`, `debt-*`).

`automation-*`, `safety-*` and `ci-*` carry label text meant to be read, so
`make_diagrams.py` builds those with `svg_static` instead of `svg`: the reveal
plays once and holds the finished frame forever, rather than fading in/out on
a loop and pulling attention away from the text mid-read. Every element's
resting style is that finished frame either way, so reduced motion (or a
renderer without CSS animation) always shows the complete picture. Keep fonts
to system stacks — an `<img>` SVG can't load web fonts.
