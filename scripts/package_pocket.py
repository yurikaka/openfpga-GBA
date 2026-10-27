#!/usr/bin/env python3
"""Package an already-built core as an SD-root installation ZIP (no release)."""
import hashlib
import json
from pathlib import Path
import subprocess
import zipfile


ROOT = Path(__file__).resolve().parent.parent


def main():
    package = ROOT / "pkg"
    core_dir = package / "Cores/mincer_ray.GBA"
    for path in sorted(package.rglob("*.json")):
        json.loads(path.read_text())
    core = json.loads((core_dir / "core.json").read_text())["core"]
    for entry in core["cores"]:
        bitstream = core_dir / entry["filename"]
        if not bitstream.is_file() or bitstream.stat().st_size == 0:
            raise SystemExit(f"Missing or empty bitstream: {bitstream}")
    for directory in ("Cores", "Platforms", "Assets"):
        if not (package / directory).is_dir():
            raise SystemExit(f"Missing package directory: {directory}")

    revision = subprocess.check_output(
        ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True
    ).strip()
    branch = subprocess.check_output(
        ["git", "rev-parse", "--abbrev-ref", "HEAD"], cwd=ROOT, text=True
    ).strip()
    output_dir = ROOT / "build_output/packages"
    output_dir.mkdir(parents=True, exist_ok=True)
    output = output_dir / f"mincer_ray.GBA-cartridge-support-{revision[:7]}.zip"
    info = {
        "commit": revision,
        "branch": branch,
        "core_version": core["metadata"]["version"],
        "framework_required": core["framework"]["version_required"],
        "bitstream_sha256": hashlib.sha256(
            (core_dir / core["cores"][0]["filename"]).read_bytes()
        ).hexdigest(),
    }
    with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED) as archive:
        # Include Assets even if it only contains a .gitkeep in the source.
        for path in sorted(package.rglob("*")):
            relative = path.relative_to(package).as_posix()
            if path.is_dir():
                archive.writestr(relative + "/", b"")
            elif path.name not in (".gitkeep", ".DS_Store"):
                archive.write(path, relative)
        archive.writestr("build-info.json", json.dumps(info, indent=2) + "\n")
    with zipfile.ZipFile(output) as archive:
        if archive.testzip() is not None:
            raise SystemExit("ZIP CRC verification failed")
        for name in ("Cores/mincer_ray.GBA/bitstream.rbf_r", "Platforms/gba.json",
                     "Assets/gba/common/"):
            if name not in archive.namelist():
                raise SystemExit(f"Missing ZIP entry: {name}")
    digest = hashlib.sha256(output.read_bytes()).hexdigest()
    output.with_suffix(".zip.sha256").write_text(f"{digest}  {output.name}\n")
    print(f"Packaged {output} ({output.stat().st_size} bytes)")
    print(json.dumps(info, indent=2))


if __name__ == "__main__":
    main()
