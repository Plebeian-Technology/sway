# MupdfExtractor fixtures

`native.pdf` and `image_only.pdf` are small placeholders, not real PDFs. Every
spec that names them replaces `Sway::Subprocess.capture3`, so only the path has
to exist.

`text_layer.pdf` is a real one-page PDF with a real text layer. One example in
`spec/services/mupdf_extractor_spec.rb` runs mutool over it for real. Its text
is known because mutool built the file from the input below, so nothing about
the expected string is a guess. The words are obvious filler on purpose: no
fixture here may look like a bill, a hearing or a person.

## Regenerating text_layer.pdf

Write this content stream to `tmp/mupdf_text_layer_page.txt`:

```
%%MediaBox 0 0 612 792
%%Font F1 Times-Roman

BT /F1 16 Tf 72 720 Td (SWAY SYNTHETIC TEXT LAYER FIXTURE) Tj ET
BT /F1 12 Tf 72 690 Td (marker SWAY TEXT LAYER FIXTURE 5FLI9) Tj ET
BT /F1 12 Tf 72 660 Td (This page is generated for tests and holds no real content.) Tj ET
```

Then build the PDF with mutool 1.25.1, which ships in the rspec image:

```
dip compose run --rm --no-deps rspec mutool create \
  -o spec/fixtures/files/mupdf_extractor/text_layer.pdf \
  tmp/mupdf_text_layer_page.txt
```

Read back what extraction returns, and assert only on strings you see here.
mutool can reorder, re-space or drop characters, so what went in is not
automatically what comes out:

```
dip compose run --rm --no-deps rspec mutool draw -F txt \
  spec/fixtures/files/mupdf_extractor/text_layer.pdf
```

At the time of writing that prints 136 bytes on stdout. Two of them do not show
below: the page ends with a form feed and a newline, so counting what you can
see gives 134.

```
SWAY SYNTHETIC TEXT LAYER FIXTURE

marker SWAY TEXT LAYER FIXTURE 5FLI9

This page is generated for tests and holds no real content.
```

The length matters as much as the words. `MupdfExtractor::MIN_NATIVE_CHARS` is
50, so a shorter page would send the example down the OCR path instead.
