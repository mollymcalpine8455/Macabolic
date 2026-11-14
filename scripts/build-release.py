#!/usr/bin/env python3
"""Build the standalone universal macOS ZIP used for GitHub Releases."""

import argparse
import plistlib
import re
import shutil
import struct
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "Macabolic"
PROJECT = ROOT / "Macabolic.xcodeproj" / "project.pbxproj"


def run(*args):
    subprocess.run(args, check=True)


def build(output):
    project = PROJECT.read_text()
    version = re.search(r"MARKETING_VERSION = ([\d.]+);", project)[1]
    build_number = re.search(r"CURRENT_PROJECT_VERSION = (\d+);", project)[1]
    deployment_target = re.search(r"MACOSX_DEPLOYMENT_TARGET = ([\d.]+);", project)[1]
    sources = [
        path for path in sorted(SOURCE.rglob("*.swift"))
        if f"{path.name} in Sources" in project
    ]

    with tempfile.TemporaryDirectory(prefix="macabolic-build-") as temp:
        work = Path(temp)
        copied_sources = []
        for path in sources:
            # Xcode's preview macro is unavailable in the Command Line Tools.
            body = re.sub(r"^#Preview \{\n.*?^\}\n", "", path.read_text(), flags=re.M | re.S)
            destination = work / path.name
            destination.write_text(body)
            copied_sources.append(destination)

        binaries = []
        for arch in ("x86_64", "arm64"):
            binary = work / f"Macabolic-{arch}"
            run("xcrun", "swiftc", "-swift-version", "5",
                "-target", f"{arch}-apple-macosx{deployment_target}",
                *copied_sources, "-o", binary)
            binaries.append(binary)

        app = work / "Macabolic yt-dlp.app"
        contents = app / "Contents"
        resources = contents / "Resources"
        resources.mkdir(parents=True)
        (contents / "MacOS").mkdir()
        executable = contents / "MacOS" / "Macabolic"
        run("xcrun", "lipo", "-create", *binaries, "-output", executable)

        info = plistlib.loads((SOURCE / "Info.plist").read_bytes())
        info.update(
            CFBundleName="Macabolic yt-dlp",
            CFBundleDisplayName="Macabolic yt-dlp",
            CFBundleIdentifier="org.macabolic.ytdlp.compatibility",
            CFBundleDevelopmentRegion="en",
            CFBundleExecutable="Macabolic",
            CFBundleShortVersionString=version,
            CFBundleVersion=build_number,
            LSMinimumSystemVersion=deployment_target,
            CFBundleLocalizations=["en", "tr", "ja"],
            CFBundleIconFile="AppIcon",
            LSApplicationCategoryType="public.app-category.utilities",
            NSHumanReadableCopyright="Macabolic contributors",
        )
        # Let the original app continue to handle its browser extension's URLs.
        info.pop("CFBundleURLTypes", None)
        info.pop("MacabolicReleaseRepository", None)
        (contents / "Info.plist").write_bytes(plistlib.dumps(info))

        iconset = SOURCE / "Resources" / "Assets.xcassets" / "AppIcon.appiconset"
        icon_types = {
            b"icp4": "16x16", b"icp5": "32x32",
            b"ic07": "128x128", b"ic08": "256x256", b"ic09": "512x512",
            b"ic10": "512x512@2x", b"ic11": "16x16@2x",
            b"ic12": "32x32@2x", b"ic13": "128x128@2x", b"ic14": "256x256@2x",
        }
        entries = []
        for kind, size in icon_types.items():
            png = (iconset / f"icon_{size}.png").read_bytes()
            entries.append(struct.pack(">4sI", kind, len(png) + 8) + png)
        payload = b"".join(entries)
        (resources / "AppIcon.icns").write_bytes(struct.pack(">4sI", b"icns", len(payload) + 8) + payload)

        shutil.copyfile(ROOT / "LICENSE", resources / "LICENSE")
        shutil.copyfile(SOURCE / "Credits.rtf", resources / "Credits.rtf")
        shutil.copytree(SOURCE / "Resources" / "ja.lproj", resources / "ja.lproj", copy_function=shutil.copyfile)
        run("codesign", "--force", "--sign", "-", "--entitlements", SOURCE / "Macabolic.entitlements", app)
        run("codesign", "--verify", "--strict", "--all-architectures", app)
        archive = work / "Macabolic.zip"
        run("ditto", "-c", "-k", "--norsrc", "--noextattr", "--keepParent", app, archive)
        run("unzip", "-tq", archive)
        output.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(archive, output)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path, help="Path for the generated ZIP")
    build(parser.parse_args().output.resolve())
