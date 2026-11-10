#!/usr/bin/env python3
"""Package a certificate-bound local app as a DMG and ZIP; does not notarize it."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tempfile

import signing

ROOT = Path(__file__).resolve().parents[1]


def run(args, **kwargs):
    return subprocess.run(args, check=True, text=True, **kwargs)


def digest(path):
    with path.open("rb") as stream:
        checksum = hashlib.sha256()
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            checksum.update(chunk)
    return checksum.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, default=ROOT / "dist/Keylian.app")
    parser.add_argument("--output", type=Path, help="Defaults to dist/releases/v<version>")
    args = parser.parse_args()
    app = args.app.resolve()
    signing.verify(app)
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    if info.get("CFBundleIdentifier") != signing.BUNDLE_ID:
        raise RuntimeError("Unexpected application bundle identifier")
    version = info["CFBundleShortVersionString"]
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise RuntimeError("Expected a three-component release version")
    output = args.output.resolve() if args.output else ROOT / "dist/releases" / f"v{version}"
    architectures = sorted(run(["lipo", "-archs", str(app / "Contents/MacOS/Keylian")], capture_output=True).stdout.split())
    if architectures == ["arm64", "x86_64"]:
        platform = "universal"
    elif architectures in [["arm64"], ["x86_64"]]:
        platform = architectures[0]
    else:
        raise RuntimeError(f"Unsupported architectures: {architectures}")
    stem = f"Keylian-{version}-macOS-{platform}"
    names = [stem + ".dmg", stem + ".zip", "BUILD_INFO.json", "SHA256SUMS.txt"]
    output.mkdir(parents=True, exist_ok=True)
    if any((output / name).exists() for name in names):
        raise RuntimeError("Release output already exists; choose a new --output directory")
    commit = run(["git", "rev-parse", "HEAD"], cwd=ROOT, capture_output=True).stdout.strip()
    if run(["git", "status", "--porcelain", "--untracked-files=no"], cwd=ROOT, capture_output=True).stdout.strip():
        raise RuntimeError("Commit tracked changes before packaging a release")
    with tempfile.TemporaryDirectory(prefix="keylian-package-") as temporary:
        work = Path(temporary)
        payload = work / stem
        payload.mkdir()
        staged_app = payload / "Keylian.app"
        run(["ditto", str(app), str(staged_app)])
        # Preserve the pinned signing identity after adding the license to the app.
        shutil.copy2(ROOT / "LICENSE", staged_app / "Contents/Resources/LICENSE")
        signing.sign(staged_app)
        shutil.copy2(ROOT / "LICENSE", payload / "LICENSE.txt")
        shutil.copy2(ROOT / "docs/INSTALL.md", payload / "安装说明.txt")
        run(["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(payload), str(work / names[1])])
        run(["hdiutil", "create", "-volname", f"Keylian {version}", "-srcfolder", str(payload), "-format", "UDZO", "-fs", "HFS+", str(work / names[0])])
        run(["hdiutil", "verify", str(work / names[0])])
        metadata = {
            "app": "Keylian",
            "version": version,
            "build": info["CFBundleVersion"],
            "minimum_macos": info["LSMinimumSystemVersion"],
            "architectures": architectures,
            "packaging_commit": commit,
            "code_signature_verified": True,
            "notarized": False,
            "license": "MIT",
            "executable_sha256": digest(staged_app / "Contents/MacOS/Keylian"),
            "assets": {name: {"bytes": (work / name).stat().st_size, "sha256": digest(work / name)} for name in names[:2]},
        }
        (work / names[2]).write_text(json.dumps(metadata, indent=2) + "\n")
        (work / names[3]).write_text("".join(f"{digest(work / name)}  {name}\n" for name in names[:3]))
        for name in names:
            shutil.copy2(work / name, output / name)
    print(json.dumps({"output": str(output), "assets": names, "architectures": architectures}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
