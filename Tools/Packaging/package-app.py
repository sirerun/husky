#!/usr/bin/env python3
"""Wrap an existing local Husky .app with its app-switcher name and icon.

Usage: package-app.py SOURCE.app OUTPUT/Husky.app
This creates a development bundle; it does not sign or notarize a release.
"""
import pathlib
import plistlib
import shutil
import subprocess
import sys
import tempfile


def main():
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    source, destination = (pathlib.Path(arg).resolve() for arg in sys.argv[1:])
    if destination.exists() or destination.name != "Husky.app":
        raise SystemExit("Output must be a new path named Husky.app")
    if source in destination.parents:
        raise SystemExit("Output must be outside the source bundle")
    if (source / "Contents/_CodeSignature").exists():
        raise SystemExit("Source must be an unsigned development bundle")
    info_path = source / "Contents/Info.plist"
    with info_path.open("rb") as stream:
        info = plistlib.load(stream)
    if info.get("CFBundleExecutable") != "Husky":
        raise SystemExit("Source must contain the Husky executable")
    if not (source / "Contents/MacOS/Husky").is_file():
        raise SystemExit("Husky executable is missing")
    artwork = pathlib.Path(__file__).resolve().parents[2] / "App/Resources/Husky.png"
    # Generate every standard macOS icon representation from the approved artwork.
    with tempfile.TemporaryDirectory(prefix="husky-icon-") as scratch:
        iconset = pathlib.Path(scratch) / "Husky.iconset"
        iconset.mkdir()
        for size in (16, 32, 128, 256, 512):
            for scale in (1, 2):
                suffix = "@2x" if scale == 2 else ""
                pixels = str(size * scale)
                subprocess.run(["sips", "-z", pixels, pixels, str(artwork), "--out",
                                str(iconset / f"icon_{size}x{size}{suffix}.png")],
                               check=True, stdout=subprocess.DEVNULL)
        icon = pathlib.Path(scratch) / "Husky.icns"
        subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(icon)], check=True)
        shutil.copytree(source, destination, symlinks=True)
        resources = destination / "Contents/Resources"
        resources.mkdir(exist_ok=True)
        shutil.copy2(icon, resources / "Husky.icns")
    info.update(CFBundleName="Husky", CFBundleDisplayName="Husky", CFBundleIconFile="Husky.icns")
    with (destination / "Contents/Info.plist").open("wb") as stream:
        plistlib.dump(info, stream)
    print(destination)


if __name__ == "__main__":
    main()
