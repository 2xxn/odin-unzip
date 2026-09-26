// Very barebone deserialization/decompression library for ZIP files
// Genuinely my first Odin library/piece of code ever.
// Rather straightforward to use, if you have trouble
// read https://en.wikipedia.org/wiki/ZIP_(file_format)
// no support for archives with passwords set.
package zip

import "core:compress/zlib"
import "core:bytes"
import "core:io"

MAGIC_LFH :: [4]byte{0x50,0x4B, 0x03, 0x04}
MAGIC_DD :: [4]byte{0x50,0x4B, 0x07, 0x08}
MAGIC_CDFH :: [4]byte{0x50,0x4B, 0x01, 0x02}
MAGIC_EOCD :: [4]byte{0x50,0x4B, 0x05, 0x06}

COMPRESSION_NONE :: 0
COMPRESSION_DEFLATE :: 8

ZipFile :: struct {
    data:    []byte,
    reader: ^bytes.Reader,
    entries: []CentralDirectoryFileHeader,
    names:  []string,
}

LocalFileHeader :: struct #packed {
    version_needed: u16,
    general_purpose_bit_flag: u16,
    compression: u16,

    file_last_modified_time: u16,
    file_last_modified_date: u16,

    using data_descriptor: DataDescriptor,

    file_name_length: u16,
    extra_field_length: u16,
}

LocalFileHeaderWithDynamic :: struct {
    using lfh: LocalFileHeader,

    file_name: string,
    extra_field: []u8
}

DataDescriptor :: struct #packed {
    crc32: u32,
    compressed_size: u32,
    uncompressed_size: u32,
}

CentralDirectoryFileHeader :: struct #packed {
    version_by: u16,

    using local_file_header: LocalFileHeader,

    file_comment_length: u16,

    disk_number: u16,
    internal_file_attributes: u16,
    external_file_attributes: u32,
    lfh_offset: u32,

    file_name: string,
    extra_field: []u8,
    file_comment: string,
}

EndOfCentralDirectory :: struct #packed {
    disk_number: u16,
    central_dir_disk: u16,
    central_dir_records_len_this_disk: u16,
    central_dir_records_len_total: u16,
    
    central_dir_size: u32,
    central_dir_start_offset: u32,

    comment_length: u16,
    comment: string
}

HeaderVariant :: union {
    LocalFileHeaderWithDynamic,
    LocalFileHeader,
    DataDescriptor,
    CentralDirectoryFileHeader,
    EndOfCentralDirectory,
}


@(private)
read_data_descriptor :: proc(reader: ^bytes.Reader) -> (header: DataDescriptor, err: io.Error) {
    n: int

    n, err = bytes.reader_read_ptr(reader, &header, 12)
    if err != nil || n != 12 do return

    return header, nil
}

@(private)
read_lfh :: proc(reader: ^bytes.Reader) -> (header: LocalFileHeader, err: io.Error) {
    n: int
    
    n, err = bytes.reader_read_ptr(reader, &header, 26)
    if err != nil || n != 26 do return

    return header, nil
}

@(private)
read_cdfh :: proc(reader: ^bytes.Reader) -> (header: CentralDirectoryFileHeader, err: io.Error) {
    n: int
    
    n, err = bytes.reader_read_ptr(reader, &header, 42)
    if err != nil || n != 42 do return

    return header, nil
}

@(private)
read_eocd :: proc(reader: ^bytes.Reader) -> (header: EndOfCentralDirectory, err: io.Error) {
    n: int

    n, err = bytes.reader_read_ptr(reader, &header, 18)
    if err != nil || n != 18 do return

    comment_data := make([]u8, header.comment_length)
    defer delete(comment_data) 

    n, err = bytes.reader_read(reader, comment_data)
    if err != nil || u16(n) != header.comment_length do return
    header.comment = string(comment_data)

    return header, nil
}

@(private)
read_header_dynamic :: proc(reader: ^bytes.Reader, fn_len: u16, ef_len: u16, fc_len: u16) -> (string, []u8, string, io.Error) {
    file_name_data := make([]u8, fn_len)

    n, err := bytes.reader_read(reader, file_name_data)
    if err != nil || u16(n) != fn_len {
        delete(file_name_data)
        return "", nil, "", err
    }
        
    file_name := string(file_name_data)

    extra_field := make([]u8, ef_len)
    n, err = bytes.reader_read(reader, extra_field)
    if err != nil || u16(n) != ef_len {
        delete(file_name_data)
        delete(extra_field)
        return "", nil, "", err
    }

    if fc_len > 0 {
        file_comment_data := make([]u8, fc_len)

        n, err = bytes.reader_read(reader, file_comment_data)
        if err != nil || u16(n) != fc_len {
            delete(file_name_data)
            delete(extra_field)
            delete(file_comment_data)
            return "", nil, "", err
        }
        file_comment := string(file_comment_data)

        return file_name, extra_field, file_comment, nil
    }


    return file_name, extra_field, "", nil
}

read_header :: proc(reader: ^bytes.Reader, free: bool = false) -> (HeaderVariant, io.Error) {
    value: [4]byte
    n, err := bytes.reader_read_ptr(reader, &value, 4)
    if err != nil || n != 4 do return nil, err

    switch value {
        case MAGIC_LFH: 
            lfh_dynamic: LocalFileHeaderWithDynamic = LocalFileHeaderWithDynamic{}
            lfh_dynamic.lfh, err = read_lfh(reader)
            if err != nil do return nil, err

            dummy: string
            lfh_dynamic.file_name, lfh_dynamic.extra_field, dummy, err = read_header_dynamic(reader, lfh_dynamic.file_name_length, lfh_dynamic.extra_field_length, 0)

            if free {
                delete(lfh_dynamic.extra_field)
                delete(lfh_dynamic.file_name)
            }

            return lfh_dynamic, nil
        case MAGIC_CDFH:
            header, err := read_cdfh(reader)
            if err != nil do return nil, err
            
            header.file_name, header.extra_field, header.file_comment, err = read_header_dynamic(reader, header.file_name_length, header.extra_field_length, header.file_comment_length)
            
            if free {
                delete(header.file_comment)
                delete(header.extra_field)
                delete(header.file_name)
            }

            return header, nil
        case MAGIC_DD:
            return read_data_descriptor(reader)
        case MAGIC_EOCD:
            return read_eocd(reader)
    }

    return nil, .Unsupported
}

// the only function that was written by AI, almost lost my mind
find_eocd_with_reader :: proc(reader: ^bytes.Reader) -> (offset: i64, ok: bool) {
    size := bytes.reader_size(reader)
    if size < 22 { return 0, false }
    
    // Start from the end, scan backwards within last 65557 bytes
    start := max(0, size - 65557)
    
    buf := make([]u8, 4)
    defer delete(buf)
    
    pos := size - 4 // start at last 4 bytes
    for pos >= start {
        _, err := bytes.reader_seek(reader, pos, .Start)
        if err != nil { return 0, false }
        
        n: int
        n, err = bytes.reader_read(reader, buf)
        if err != nil || n != 4 { return 0, false }
        
        if buf[0] == 0x50 && buf[1] == 0x4B && buf[2] == 0x05 && buf[3] == 0x06 {
            return pos, true
        }
        pos -= 1
    }
    return 0, false
}

parse :: proc(data: []byte) -> (file: ^ZipFile, err: io.Error) {
    reader := new(bytes.Reader)
    bytes.reader_init(reader, data)

    eocd_offset, found := find_eocd_with_reader(reader)
    if !found {
        free(reader)
        err = .Unsupported
        return
    }

    _, err = bytes.reader_seek(reader, eocd_offset, .Start)
    if err != nil {
        free(reader)
        return
    }

    header: HeaderVariant
    header, err = read_header(reader)
    if err != nil {
        free(reader)
        return
    }

    eocd := (header.(EndOfCentralDirectory))

    bytes.reader_seek(reader, i64(eocd.central_dir_start_offset), .Start)

    entries := make([]CentralDirectoryFileHeader, eocd.central_dir_records_len_total)
    names := make([]string, eocd.central_dir_records_len_total)    

    for i := 0; i < int(eocd.central_dir_records_len_this_disk); i += 1 {
        entry: HeaderVariant
        
        entry, err = read_header(reader)
        if err != nil {
            free(reader)
            delete(entries)
            delete(names)
            return
        }

        entries[i] = entry.(CentralDirectoryFileHeader)
        names[i] = entries[i].file_name
    }

    zfile := new(ZipFile)

    zfile.entries = entries
    zfile.data = data
    zfile.reader = reader
    zfile.names = names

    return zfile, nil
}

get_idx_of_entry :: proc(z: ^ZipFile, name: string) -> (idx: int, ok: bool) {
    for entry_name, i in z.names {
        if entry_name == name {
            return i, true
        }
    }
    return -1, false
}

// ZipFile functions

zip_close :: proc(z: ^ZipFile) {
    for entry in z.entries {
        delete(entry.extra_field)
        delete(entry.file_name)
        delete(entry.file_comment)
    }

    free(z.reader)
    delete(z.names)
    delete(z.entries)
    free(z)
}

zip_get_entries :: proc(z: ^ZipFile) -> []CentralDirectoryFileHeader {
    return z.entries
}

zip_entry_names :: proc(z: ^ZipFile) -> []string {
    return z.names
}

zip_contains :: proc(z: ^ZipFile, name: string) -> bool {
    for x in z.names {
        if x == name {
            return true
        }
    }
    return false
}

zip_read_file :: proc(z: ^ZipFile, name: string) -> ([]byte, io.Error) {
    if len(name)>0 && name[len(name)-1] == '/' {
        return nil, .Unsupported
    }

    id, ok := get_idx_of_entry(z, name)
    if !ok {
        return nil, .Empty
    }

    header := z.entries[id]

    _, err := bytes.reader_seek(z.reader, i64(header.lfh_offset), .Start)
    if err != nil do return nil, err

    _, err = read_header(z.reader, true) // skip lfh, we don't need it, we already have the cdfh
    if err != nil do return nil, err

    switch header.compression {
        case COMPRESSION_NONE:
            file_data := make([]u8, header.uncompressed_size)

            n, err := bytes.reader_read(z.reader, file_data)
            if err != nil || header.uncompressed_size != u32(n) {
                delete(file_data) // read failed
                return nil, err
            }

            return file_data, nil
        case COMPRESSION_DEFLATE:
            file_data_compressed := make([]u8, header.compressed_size)
            defer delete(file_data_compressed)

            n, err := bytes.reader_read(z.reader, file_data_compressed)
            if err != nil || header.compressed_size != u32(n) do return nil, err

            buffer := bytes.Buffer{}

            zliberr := zlib.inflate_from_byte_array(file_data_compressed, &buffer, true, int(header.uncompressed_size))
            if zliberr != nil {
                bytes.buffer_destroy(&buffer)
                return nil, .Unknown
            }

            return bytes.buffer_to_bytes(&buffer), nil
    }

    return nil, .Unsupported
}

// no saving to disk yet.