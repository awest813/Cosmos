"""Fixture excerpt — Bethesda protonfix exe swap pattern (reference parsing tests)."""

from protonfixes import util


def get_redirect_name(game_id: str) -> util.ReplaceType:
    mapping = {
        "22380": ("FalloutNV.exe", "nvse_loader.exe"),
        "377160": ("Fallout4Launcher.exe", "f4se_loader.exe"),
    }.get(game_id, ("", ""))
    return util.ReplaceType(*mapping)


def main_with_id(game_id: str) -> None:
    util.protontricks("vcrun2019")
    # Tuple form used in Bethesda protonfixes
    _ = ("FalloutNV.exe", "nvse_loader.exe")
