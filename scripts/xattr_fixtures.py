"""Cross-platform fixture attributes; production filesystem code is read-only."""
import ctypes
import os
import sys
from lib.wine_filesystem import read_attribute


def set_attribute(path, name, data):
    if sys.platform != 'darwin':
        return os.setxattr(path, name, data, follow_symlinks=False)
    library = ctypes.CDLL('/usr/lib/libSystem.B.dylib', use_errno=True)
    writer = library.setxattr
    writer.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_void_p, ctypes.c_size_t, ctypes.c_uint32, ctypes.c_int]
    if writer(os.fsencode(path), os.fsencode(name), data, len(data), 0, 1):
        code = ctypes.get_errno()
        raise OSError(code, os.strerror(code), str(path))
