"""Refuses a Windows archive whose binaries need a DLL nobody ships with them.

Windows records an import by a bare name, so a binary cannot name the machine that built it the way
a macOS one can. What it can do is import a library installed on the build image and nowhere else.
The tool then refuses to start on a user's machine, with no error anybody can act on. MSVC's own C
runtime is the one that bites. ucrtbase and the api-ms-win-crt forwarders are part of Windows.
msvcp140 and vcruntime140 arrive with the Visual C++ redistributable, which Windows Update never
installs.

Reads the import table directly rather than calling a toolchain program, because no Windows runner
image carries objdump and the table is a handful of structs. That also means this runs on a
development machine with nothing installed.

Usage: windows-imports.py <staging directory>
"""

import glob
import os
import struct
import sys

# What Windows itself provides. Everything else has to be in the archive beside the binary that
# wants it, which is the first place Windows looks.
SYSTEM_PREFIXES = (
    "api-ms-win-", "kernel32", "user32", "advapi32", "shell32", "ole32", "oleaut32", "gdi32",
    "ws2_32", "ucrtbase", "ntdll", "bcrypt", "crypt32", "shlwapi", "version", "msvcrt",
)

# The PE header's optional part is longer for 64-bit images, and the data directories follow it.
PE32_PLUS = 0x20b
OPTIONAL_HEADER_SIZE = {PE32_PLUS: 112}
DEFAULT_OPTIONAL_HEADER_SIZE = 96
IMPORT_DIRECTORY = 8
SECTION_HEADER_SIZE = 40
IMPORT_DESCRIPTOR_SIZE = 20


def imported(path):
    """The DLL names a binary imports, or nothing at all when it imports none."""
    image = open(path, "rb").read()
    header = struct.unpack_from("<I", image, 0x3c)[0]
    if image[header:header + 4] != b"PE\0\0":
        return []
    sections, = struct.unpack_from("<H", image, header + 6)
    optional_size, = struct.unpack_from("<H", image, header + 20)
    magic, = struct.unpack_from("<H", image, header + 24)
    directories = header + 24 + OPTIONAL_HEADER_SIZE.get(magic, DEFAULT_OPTIONAL_HEADER_SIZE)
    table, = struct.unpack_from("<I", image, directories + IMPORT_DIRECTORY)
    if table == 0:
        return []

    # A header address is where the loader would map the bytes, not where they sit in the file. The
    # section table is what converts between the two.
    layout, at = [], header + 24 + optional_size
    for _ in range(sections):
        address, size, position = struct.unpack_from("<III", image, at + 12)
        layout.append((address, size, position))
        at += SECTION_HEADER_SIZE

    def position_of(address):
        for start, size, position in layout:
            if start <= address < start + size:
                return position + (address - start)
        return None

    names, at = [], position_of(table)
    while True:
        descriptor = image[at:at + IMPORT_DESCRIPTOR_SIZE]
        if len(descriptor) < IMPORT_DESCRIPTOR_SIZE or descriptor == b"\0" * IMPORT_DESCRIPTOR_SIZE:
            return names
        name = position_of(struct.unpack_from("<I", descriptor, 12)[0])
        names.append(image[name:image.index(b"\0", name)].decode())
        at += IMPORT_DESCRIPTOR_SIZE


def main(stage):
    binaries = os.path.join(stage, "bin")
    shipped = {name.lower() for name in os.listdir(binaries)}
    missing = False
    for path in sorted(glob.glob(os.path.join(binaries, "*.exe")) + glob.glob(os.path.join(binaries, "*.dll"))):
        for dependency in imported(path):
            name = dependency.lower()
            if name.startswith(SYSTEM_PREFIXES) or name in shipped:
                continue
            print(f"{os.path.basename(path)} needs {dependency}, which is not in the archive")
            missing = True
    if missing:
        return 1
    print("every import is either Windows' own or inside the archive")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1]))
