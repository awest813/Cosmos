#!/usr/bin/env bash
# Path conversions read the selected prefix; never create or repair its drives.
COSMOS_WINE_FILESYSTEM_HELPER="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/wine_filesystem.py"
wine_fs_host_path() { python3 "${COSMOS_WINE_FILESYSTEM_HELPER}" host "$1" "$2"; }
wine_fs_windows_path() { python3 "${COSMOS_WINE_FILESYSTEM_HELPER}" windows "$1" "$2"; }
wine_fs_inspect() { python3 "${COSMOS_WINE_FILESYSTEM_HELPER}" inspect "$1"; }
