"""Windows DPAPI CurrentUser, ciphertext only on disk. Never log contents."""
import ctypes
import json
import os
from ctypes import wintypes
from pathlib import Path

class Blob(ctypes.Structure):
    _fields_ = [('size', wintypes.DWORD), ('data', ctypes.POINTER(ctypes.c_byte))]

def crypt(data, decrypt=False):
    if os.name != 'nt':
        raise RuntimeError('DPAPI requer Windows')
    buf = ctypes.create_string_buffer(data)
    src = Blob(len(data), ctypes.cast(buf, ctypes.POINTER(ctypes.c_byte)))
    out = Blob()
    fn = ctypes.windll.crypt32.CryptUnprotectData if decrypt else ctypes.windll.crypt32.CryptProtectData
    if not fn(ctypes.byref(src), None, None, None, None, 1, ctypes.byref(out)):
        raise ctypes.WinError()
    try:
        return ctypes.string_at(out.data, out.size)
    finally:
        ctypes.windll.kernel32.LocalFree(out.data)

def write(path, value):
    path = Path(path)
    temp = path.with_suffix('.tmp')
    temp.write_bytes(crypt(json.dumps(value).encode()))
    os.replace(temp, path)

def read(path):
    return json.loads(crypt(Path(path).read_bytes(), True))
