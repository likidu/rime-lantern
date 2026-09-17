import io
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "tools"))
import build_gloss as bg  # noqa: E402

BANK = "銀行 银行 [yin2 hang2] /bank/CL:家[jia1],個|个[ge4]/"
KAIFA = "開發 开发 [kai1 fa1] /to exploit (a resource); to open up (for development); to develop/"
GEIYU = "給予 给予 [ji3 yu3] /(literary) to give; to accord; to render/"
LE1 = "了 了 [le5] /(completed action marker)/(modal particle indicating change of state, situation now)/"
LE2 = "了 了 [liao3] /to finish/variant of 瞭|了[liao3]/"
DE = "的 的 [de5] /of; ~'s (possessive particle)/(used after an attribute when it modifies a noun)/"
DI = "的 的 [di1] /a taxi; a cab (abbr. for 的士[di1 shi4])/"
NUM = "110 110 [yao1 yao1 ling2] /the emergency number for law enforcement/"
VARIANT_ONLY = "瞭 了 [liao3] /variant of 了[liao3]/"
CJK_ONLY = "忘不了 忘不了 [wang4 bu5 liao3] /cannot forget 忘不了[wang4 bu5 liao3]/"


def test_parse_line_basic():
    trad, simp, pinyin, senses = bg.parse_line(BANK)
    assert (trad, simp, pinyin) == ("銀行", "银行", "yin2 hang2")
    assert senses == ["bank", "CL:家[jia1],個|个[ge4]"]


def test_parse_line_skips_comments_and_blank():
    assert bg.parse_line("# comment") is None
    assert bg.parse_line("#! date=2026-09-17") is None
    assert bg.parse_line("") is None


def test_classifier_sense_dropped():
    assert bg.glosses_for_entry(["bank", "CL:家[jia1],個|个[ge4]"]) == ["bank"]


def test_subsenses_split_and_parens_stripped():
    _, _, _, senses = bg.parse_line(KAIFA)
    assert bg.glosses_for_entry(senses) == ["to exploit", "to open up", "to develop"]


def test_leading_label_stripped_keeps_to():
    _, _, _, senses = bg.parse_line(GEIYU)
    assert bg.glosses_for_entry(senses) == ["to give", "to accord", "to render"]


def test_whole_parenthetical_used_as_fallback_only():
    _, _, _, senses = bg.parse_line(LE1)
    assert bg.glosses_for_entry(senses) == ["completed action marker"]
    _, _, _, senses = bg.parse_line(DE)
    assert bg.glosses_for_entry(senses) == ["of", "~'s"]


def test_variant_of_dropped():
    _, _, _, senses = bg.parse_line(LE2)
    assert bg.glosses_for_entry(senses) == ["to finish"]
    _, _, _, senses = bg.parse_line(VARIANT_ONLY)
    assert bg.glosses_for_entry(senses) == []


def test_sense_with_cjk_is_fallback():
    _, _, _, senses = bg.parse_line(CJK_ONLY)
    assert bg.glosses_for_entry(senses) == ["cannot forget"]


def test_build_merges_duplicate_headwords_in_order():
    table = bg.build([DE, DI, LE1, LE2, BANK, NUM, VARIANT_ONLY])
    assert "110" not in table
    assert table["的"] == ("的", ["of", "~'s", "a taxi"])
    assert table["了"] == ("了", ["completed action marker", "to finish"])
    assert table["银行"] == ("銀行", ["bank"])


def test_build_caps_senses():
    table = bg.build([KAIFA + ""])
    assert len(table["开发"][1]) == bg.MAX_SENSES


def test_write_tsv_format_and_header():
    table = bg.build([BANK, KAIFA])
    out = io.StringIO()
    bg.write_tsv(table, {"date": "2026-09-17T05:48:14Z", "entries": "2"}, out, "abc")
    text = out.getvalue()
    assert text.startswith("# rime-lantern gloss table")
    assert "release date 2026-09-17T05:48:14Z" in text
    assert "Source sha256: abc" in text
    rows = [l for l in text.splitlines() if not l.startswith("#")]
    assert rows == ["开发\t開發\tto exploit; to open up; to develop", "银行\t銀行\tbank"]


def test_duplicate_glosses_within_one_entry_collapse():
    senses = ["time (as in duration)", "time (as in clock time)", "Time"]
    assert bg.glosses_for_entry(senses) == ["time"]
