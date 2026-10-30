"""Disable only 5.2b4's obsolete native-share hook registration.

Crash: YTLite + 0x2cfb4 calls the removed shareEntityEndpoint selector.
The initializer at 0x2cf14 installs the two native-share hooks. Returning
before either registration preserves YouTube's original share handlers.
Refuse all binaries except the exact inspected, cyan-injected arm64 build.
iLoader must re-sign the resulting IPA before installation.
"""
import hashlib
import os
from pathlib import Path
import struct
import sys
import tempfile
import zipfile

ipa = Path(sys.argv[1])
expected = "5691b31ce17a039cdc8b917b56792641409e989a01e0dff74e3c180ddf33e14d"
member = "Payload/YouTube.app/Frameworks/YTLite.dylib"
with zipfile.ZipFile(ipa) as source:
    binary = bytearray(source.read(member))
    assert hashlib.sha256(binary).hexdigest() == expected, "Unexpected YTLite binary; refusing patch"
    assert struct.unpack_from("<II", binary) == (0xfeedfacf, 0x100000c)
    # Confirm file offsets equal VM addresses within the executable segment.
    offset = 32
    mapped = False
    for _ in range(struct.unpack_from("<I", binary, 16)[0]):
        command, size = struct.unpack_from("<II", binary, offset)
        if command == 0x19:
            vmaddr, vmsize, fileoff, filesize = struct.unpack_from("<QQQQ", binary, offset + 24)
            if vmaddr <= 0x2cf14 < vmaddr + filesize:
                assert fileoff + 0x2cf14 - vmaddr == 0x2cf14
                mapped = True
        offset += size
    assert mapped
    assert binary[0x2cf14:0x2cf24].hex() == "fd7bbfa9fd030091c04a009000b81f91"
    binary[0x2cf14:0x2cf18] = bytes.fromhex("c0035fd6")  # arm64 ret
    with tempfile.NamedTemporaryFile(dir=ipa.parent, suffix=".ipa", delete=False) as tmp:
        destination = Path(tmp.name)
    try:
        with zipfile.ZipFile(destination, "w", compression=zipfile.ZIP_DEFLATED) as target:
            for info in source.infolist():
                target.writestr(info, binary if info.filename == member else source.read(info.filename))
        with zipfile.ZipFile(destination) as check:
            assert check.testzip() is None
        os.replace(destination, ipa)
    finally:
        destination.unlink(missing_ok=True)
print("Disabled obsolete native-share initializer; original YouTube sharing retained.")
