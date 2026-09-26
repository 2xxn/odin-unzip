# odin-unzip

A small, simple library for decompression of ZIP archives in [Odin](https://odin-lang.org).

```odin
import zip "../odin-unzip"

data, err := os.read_entire_file_from_path("archive.zip", context.allocator)
if err != nil { return }
defer delete(data)

zf, err := zip.parse(data)
if err != nil { return }
defer zip.zip_close(zf)

for name in zip.zip_entry_names(zf) {
    fmt.println(name)
}

content, err := zip.zip_read_file(zf, "some/file.txt")
if err != nil { return }
defer delete(content)

fmt.println(string(content))
```

## What it does

- Reads the end-of-central-directory record and the central directory
- Lists entry names, and checks whether an entry exists
- Extracts entries stored (method 0) or deflated (method 8)
- Handles data descriptors, and archives whose sizes live only in the central directory

## What it doesn't do

- **Creating or writing archives.** This is a reader only.
- **Password-protected entries.** Not detected; they fail with a
  compression-method error rather than a clear "encrypted" one.
- **ZIP64.** Sizes and offsets are 32-bit. Archives needing the ZIP64 extended
  information field will report wrong sizes or fail. Plenty of modern tools
  emit ZIP64 metadata, so this is a real limitation.
- **Streaming.** Every entry is read into memory in full.
- **Multi-disk (spanned) archives.**
- **CRC-32 verification.** Extracted data is not checksummed.

## Caveats

`parse` allocates using the total entry count from the end-of-central-directory
record but iterates using the count for the current disk. An archive where those
disagree will write out of bounds. Single-disk archives are unaffected.

Errors while reading an entry's variable-length fields (name, extra, comment)
are discarded rather than returned, so a truncated entry can parse
"successfully" with empty fields.

Use this on archives you trust, or whose structure you have validated yourself.
The out-of-bounds write is reachable with a deliberately malformed file.

## Install

Copy `zip.odin` into your project — it's a single file with no dependencies
beyond the Odin core library. Or reference it as a shared collection:

```sh
odin build your_app -collection:shared=path/to/odin-unzip/..
```

## Demo

```sh
odin run demo -- path/to/archive.zip
```

It prints the entry list, then extracts every file entry with its size.

## License

MIT. See [LICENSE](LICENSE).
