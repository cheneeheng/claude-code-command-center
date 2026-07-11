"""frontmatter: lenient flat-key reader edge cases."""

from __future__ import annotations

from roundtable.frontmatter import parse


def test_no_frontmatter():
    assert parse("# just a body\n") == ({}, "# just a body\n")


def test_basic_keys_and_body():
    meta, body = parse("---\ntitle: My Plan\nstatus: ready\n---\n# body\n")
    assert meta == {"title": "My Plan", "status": "ready"}
    assert body == "# body\n"


def test_crlf_normalized():
    meta, _ = parse("---\r\ntitle: X\r\n---\r\nbody")
    assert meta == {"title": "X"}


def test_bare_cr_normalized():
    meta, _ = parse("---\rtitle: Y\r---\rbody")
    assert meta == {"title": "Y"}


def test_unterminated_fence_returns_original():
    text = "---\ntitle: X\nno closing fence"
    assert parse(text) == ({}, text)


def test_exactly_three_dashes_only():
    assert parse("---") == ({}, "---")


def test_skips_blank_comment_and_colonless_lines():
    meta, _ = parse("---\n\n# comment\nnot a kv line\ntitle: T\n---\n")
    assert meta == {"title": "T"}


def test_quoted_values_stripped():
    meta, _ = parse("---\na: \"quoted\"\nb: 'single'\n---\n")
    assert meta == {"a": "quoted", "b": "single"}


def test_empty_key_ignored():
    meta, _ = parse("---\n: novalue\ntitle: T\n---\n")
    assert meta == {"title": "T"}
