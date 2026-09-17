# rime-lantern

An English gloss on the highlighted Chinese candidate in [Rime](https://rime.im).
Type pinyin as usual; with the switch on, the highlighted candidate shows a
short dictionary meaning, and the gloss follows the highlight as you move it:

```
1. 银行  bank   2. 🏦   3. 引航   4. 引吭        ← after typing yinhang
1. 银行         2. 🏦   3. 引航  to pilot        ← after pressing Down twice
1. 给予  jǐ yǔ · to give                         ← Rime-Ice's correction hint is kept
```

`mode: all` glosses every candidate instead, which suits a vertical
candidate list.

It is a `lua_filter` plus a gloss table built from
[CC-CEDICT](https://cc-cedict.org). Word-level, offline, no network, no
sentence translation. Built and tested against
[雾凇拼音 (Rime-Ice)](https://github.com/iDvel/rime-ice); usable with any schema.

## Requirements

- librime with the Lua plugin (librime-lua ≥ 1.10, the `*module` syntax).
  Fcitx5-rime and ibus-rime on Linux, Squirrel on macOS, Weasel on Windows all
  ship it.
- Lua 5.3 or newer, or LuaJIT.

## Install

**plum** (any frontend) installs the filter and the table:

```sh
rime-install likidu/rime-lantern
```

**Arch Linux**: the `rime-lantern` AUR package installs them under
`/usr/share/rime-data/`.

**Manual**: copy `lua/lantern.lua` to `<rime user dir>/lua/` and the
`lantern/` directory to `<rime user dir>/lantern/`.

Then wire it into your schema (next section) and redeploy.

## Enable in Rime-Ice

Add this to `rime_ice.custom.yaml` in your Rime user directory (the file is
in `examples/`). If you already have a `patch:` block, put these keys inside
it:

```yaml
patch:
  switches/+:
    - name: english_gloss
      states: [ 译关, 译开 ]
      abbrev: [ 关, 译 ]
  engine/filters/+:
    - lua_filter@*lantern
  key_binder/bindings/+:
    - { when: always, toggle: english_gloss, accept: Control+Shift+E }
  lantern:
    data: lantern/cedict-en.tsv
    mode: highlighted
    senses: 1
    max_chars: 24
    separator: " · "
    option: english_gloss
```

Fresh setup with **no** `rime_ice.custom.yaml` yet? plum can write it:

```sh
rime-install likidu/rime-lantern:rime_ice
```

Do not run that on an existing file: when a `patch:` block is already there,
librime resolves the `/+` keys during the merge and the result *replaces*
Rime-Ice's switches and filters instead of appending to them. Editing by hand
is always safe.

To remember the switch across restarts when toggled from the F4 menu, list
`english_gloss` in `switcher/save_options` in `default.custom.yaml`
(`examples/default.custom.yaml` has Rime-Ice's defaults plus it). Spell the
list out in full: an append there breaks in the same way as soon as the patch
block has other switcher keys or an `__include`.

The switch starts **off**. Toggle with `Control+Shift+E` or from the schema
menu (F4). Change `accept:` to rebind.

## Other schemas

Same snippet in `<schema>.custom.yaml`. Put `lua_filter@*lantern` after any
simplifier or traditionalizer so it sees the final text; appending with
`engine/filters/+` does that. Nothing in the filter depends on Rime-Ice.

## Configuration (`lantern:`)

| key         | default                 | meaning                                              |
|-------------|-------------------------|------------------------------------------------------|
| `data`      | `lantern/cedict-en.tsv` | gloss table, relative to the user dir then shared dir |
| `mode`      | `highlighted`           | `highlighted`: only the highlighted candidate, following Up/Down and paging; `all`: every candidate |
| `senses`    | `1`                     | how many senses to show, joined by `; `              |
| `max_chars` | `24`                    | truncate longer glosses with `…`; `0` disables. With `mode: highlighted` only one gloss is on screen, so `40` reads well |
| `separator` | `" · "`                 | placed between an existing comment and the gloss     |
| `option`    | `english_gloss`         | the switch that turns the gloss on                   |
| `ellipsis`  | `…`                     | truncation marker                                    |

## Behaviour

- `mode: highlighted` hooks Rime's context updates: on every key, including
  Up/Down and paging, it puts the gloss on the highlighted candidate and
  removes it from the others. `mode: all` is a plain filter that glosses
  every candidate once.
- Only candidates made entirely of CJK ideographs are looked up. English
  words, emoji, numbers, and sentence candidates stay as they are.
- An existing comment (a pinyin or correction hint) is kept; the gloss is
  appended after `separator`.
- Traditional and simplified forms are both indexed, so the gloss works with
  Rime-Ice's 简/繁 switch either way.
- The table loads lazily on the first candidate with the switch on: about
  200 ms and 22 MB on a 2026 laptop, once per process. With the switch off
  nothing is loaded.

## The gloss table

`lantern/cedict-en.tsv` is generated from CC-CEDICT by `tools/build_gloss.py`:
one row per simplified headword (`simplified<TAB>traditional<TAB>sense1; sense2;
sense3`), sub-senses split, parenthetical notes, pinyin, classifiers and
cross-references removed, duplicate headwords merged in dictionary order.
The source release date and checksum are in the file header. About 114k
rows, 5.7 MB.

To rebuild from a newer CC-CEDICT:

```sh
tools/fetch_cedict.sh
python3 tools/build_gloss.py .scratch/cedict/cedict.txt lantern/cedict-en.tsv \
  --sha256 "$(cut -d' ' -f1 .scratch/cedict/cedict.txt.sha256)"
```

## Development

```sh
python -m pytest tests/python          # build script
busted tests/lua                       # filter logic
luajit tests/lua/luajit_smoke.lua      # no-utf8 code paths
cc -O -o tests/harness/rime_probe tests/harness/rime_probe.c -lrime
tests/integration.sh                   # deploys Rime-Ice + lantern, probes candidates
```

`tests/harness/rime_probe` drives librime headlessly and prints
`candidate<TAB>comment`, handy for checking any Rime config.

## Roadmap

- Commit the English instead of the Chinese (modifier + candidate number),
  as a `lua_processor`.
- LevelDB-backed table for zero load time.
- Optional user overlay table layered over the CEDICT one.

## License

Code: MIT. Gloss table: CC BY-SA 4.0, derived from CC-CEDICT (see
`lantern/LICENSE`). Rime-lantern is not affiliated with MDBG or Rime-Ice.
