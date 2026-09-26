package main

import "core:fmt"
import "core:os"
import zip "../"

main :: proc() {
	if len(os.args) < 2 {
		fmt.println("usage: odin run demo -- <archive.zip>")
		return
	}
	path := os.args[1]

	data, err := os.read_entire_file_from_path(path, context.allocator)
	if err != nil {
		fmt.println("could not read", path, ":", err)
		return
	}
	defer delete(data)

	zf: ^zip.ZipFile
	zf, err = zip.parse(data)
	if err != nil {
		fmt.println("could not parse", path, ":", err)
		return
	}
	defer zip.zip_close(zf)

	fmt.println("entries:")
	for name in zip.zip_entry_names(zf) {
		fmt.println("  -", name)
	}

	for name in zip.zip_entry_names(zf) {
		if len(name) > 0 && name[len(name) - 1] == '/' {
			continue
		}

		content: []byte
		content, err = zip.zip_read_file(zf, name)
		if err != nil {
			fmt.println("could not read", name, ":", err)
			continue
		}
		fmt.printf("%s (%d bytes)\n", name, len(content))
		delete(content)
	}
}
