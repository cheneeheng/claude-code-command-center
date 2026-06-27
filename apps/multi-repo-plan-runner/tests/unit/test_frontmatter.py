"""Unit tests for the read-only frontmatter reader."""

from docket import frontmatter


def test_no_frontmatter_returns_empty_meta():
    meta, body = frontmatter.parse("# just a heading\ntext")
    assert meta == {}
    assert body == "# just a heading\ntext"


def test_parses_flat_keys_and_strips_quotes():
    text = '---\ntitle: "Alpha"\nstatus: ready\n---\n# body\n'
    meta, body = frontmatter.parse(text)
    assert meta == {"title": "Alpha", "status": "ready"}
    assert body == "# body\n"


def test_crlf_and_missing_trailing_newline():
    text = "---\r\ntitle: Win\r\n---\r\nbody"
    meta, body = frontmatter.parse(text)
    assert meta["title"] == "Win"
    assert body == "body"


def test_skips_comments_blank_and_colonless_lines():
    text = "---\n# a comment\n\nnocolon\ntitle: Kept\n---\nb"
    meta, _ = frontmatter.parse(text)
    assert meta == {"title": "Kept"}


def test_empty_key_is_ignored():
    meta, _ = frontmatter.parse("---\n: orphan\ntitle: T\n---\nb")
    assert meta == {"title": "T"}


def test_bare_dashes_only_is_unterminated():
    # normalized == "---": enters the block but finds no closing fence.
    meta, body = frontmatter.parse("---")
    assert meta == {}
    assert body == "---"


def test_unterminated_fence_returns_original():
    text = "---\ntitle: T\nno closing fence\n"
    meta, body = frontmatter.parse(text)
    assert meta == {}
    assert body == text
