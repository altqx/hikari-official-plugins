"""python tools/release.py <command>; see README.md. Needs the hikari-plugins registry on PYTHONPATH."""

import argparse
import json
import os
import re
import subprocess
import sys
import zipfile
from pathlib import Path

import jsonschema
from registry import minisign, package

ROOT = Path(__file__).resolve().parent.parent
PLUGINS = ROOT / "plugins"
HANDLE = "hikarisub."
PUBLIC_KEY = ROOT / "keys" / "hikarisub.pub"
LEFT_OUT = ("tests/", "CHANGELOG.md")
ZIP_TIME = (1980, 1, 1, 0, 0, 0)
APP_SCHEMA_URL = "https://raw.githubusercontent.com/altqx/hikari/main/docs/schemas/hikari-plugin.schema.json"


class ReleaseError(Exception):
    pass


def manifest_of(folder: Path) -> dict:
    return json.loads((folder / package.MANIFEST).read_text(encoding="utf-8"))


def plugin_folders() -> list[Path]:
    return sorted(p for p in PLUGINS.iterdir() if (p / package.MANIFEST).is_file()) if PLUGINS.is_dir() else []


def validate_against_app(manifest: dict) -> None:
    path = os.environ.get("HIKARI_PLUGIN_SCHEMA")
    if not path:
        raise ReleaseError(f"HIKARI_PLUGIN_SCHEMA is not set: download {APP_SCHEMA_URL}")
    schema = json.loads(Path(path).read_text(encoding="utf-8"))
    validator = jsonschema.Draft202012Validator(schema, format_checker=jsonschema.FormatChecker())
    errors = sorted(validator.iter_errors(manifest), key=lambda e: list(e.path))
    if errors:
        where = "/".join(str(p) for p in errors[0].path) or "(root)"
        raise ReleaseError(f"manifest: {where}: {errors[0].message}")


def check_layout(folder: Path) -> dict:
    manifest = manifest_of(folder)
    validate_against_app(manifest)
    pid = manifest["id"]
    if not pid.startswith(HANDLE):
        raise ReleaseError(f"{folder.name}: the id {pid} is not under the hikarisub handle")
    if folder.name != pid.removeprefix(HANDLE):
        raise ReleaseError(f"{folder.name}: the folder must be named {pid.removeprefix(HANDLE)}, after the id")
    if manifest.get("publicKey") != minisign_line(PUBLIC_KEY):
        raise ReleaseError(f"{folder.name}: publicKey must be the key in keys/hikarisub.pub")
    if not (folder / "tests" / "run.lua").is_file():
        raise ReleaseError(f"{folder.name}: no tests/run.lua")
    return manifest


def minisign_line(path: Path) -> str:
    return path.read_text().splitlines()[1].strip()


def packaged_files(folder: Path) -> list[str]:
    names = []
    for path in sorted(folder.rglob("*")):
        rel = path.relative_to(folder).as_posix()
        if path.is_file() and not any(part.startswith(".") for part in rel.split("/")) \
                and not rel.startswith(LEFT_OUT[0]) and rel != LEFT_OUT[1]:
            names.append(rel)
    return names


def build(folder: Path, out: Path) -> Path:
    manifest = check_layout(folder)
    out.mkdir(parents=True, exist_ok=True)
    target = out / f"{manifest['id']}-{manifest['version']}.hikariplugin"
    with zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED) as z:
        for name in packaged_files(folder):
            info = zipfile.ZipInfo(name, ZIP_TIME)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            z.writestr(info, (folder / name).read_bytes())
    package.open_package(target.read_bytes(), manifest["api"])
    return target


def run_tests(folder: Path, luajit: str) -> None:
    result = subprocess.run([luajit, "tests/run.lua"], cwd=folder)
    if result.returncode != 0:
        raise ReleaseError(f"{folder.name}: tests failed")


def secret_from_env() -> minisign.SecretKey:
    text = os.environ.get("HIKARISUB_MINISIGN_KEY")
    if not text:
        raise ReleaseError("No signing key: HIKARISUB_MINISIGN_KEY is empty")
    secret = minisign.parse_secret_key(text, os.environ.get("HIKARISUB_MINISIGN_PASSWORD") or None)
    if secret.public != minisign.parse_public_key(PUBLIC_KEY.read_text()):
        raise ReleaseError("The signing key does not match keys/hikarisub.pub")
    return secret


def sign(target: Path, secret: minisign.SecretKey) -> Path:
    signature = minisign.sign(target.read_bytes(), secret, f"file:{target.name}")
    out = target.with_name(target.name + ".minisig")
    out.write_text(signature)
    return out


def verify(target: Path, public: minisign.PublicKey) -> None:
    signature = target.with_name(target.name + ".minisig").read_text()
    try:
        minisign.verify(target.read_bytes(), signature, [public])
    except minisign.MinisignError as e:
        raise ReleaseError(f"{target.name}: {e}") from e


def folder_for_tag(tag: str) -> tuple[Path, str]:
    match = re.fullmatch(r"(hikarisub\.[a-z0-9.-]+)-v(\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.+-]+)?)", tag)
    if not match:
        raise ReleaseError(f"{tag}: a release tag is <id>-v<version>, e.g. hikarisub.macro-chains-v1.0.0")
    pid, version = match.groups()
    try:
        folder = plugin_folder(pid.removeprefix(HANDLE))
    except ReleaseError as e:
        raise ReleaseError(f"{tag}: {e}") from e
    manifest = manifest_of(folder)
    if manifest["id"] != pid or manifest["version"] != version:
        raise ReleaseError(f"{tag}: the manifest says {manifest['id']} {manifest['version']}")
    return folder, version


def release_notes(folder: Path, version: str) -> str:
    changelog = folder / "CHANGELOG.md"
    text = changelog.read_text(encoding="utf-8") if changelog.is_file() else ""
    match = re.search(rf"^## {re.escape(version)}\s*$\n(.*?)(?=^## |\Z)", text, re.M | re.S)
    if not match or not match.group(1).strip():
        raise ReleaseError(f"{folder.name}: CHANGELOG.md has no '## {version}' section")
    return match.group(1).strip() + "\n"


def plugin_folder(name: str) -> Path:
    folder = PLUGINS / name
    if not re.fullmatch(r"[a-z0-9][a-z0-9-]*", name) or folder.resolve().parent != PLUGINS.resolve():
        raise ReleaseError(f"{name}: a plugin is named by its folder in plugins/, such as macro-chains")
    if not (folder / package.MANIFEST).is_file():
        raise ReleaseError(f"no plugin {name} in plugins/")
    return folder


def cmd_check(args) -> None:
    folders = [plugin_folder(args.plugin)] if args.plugin else plugin_folders()
    for folder in folders:
        target = build(folder, Path(args.out))
        run_tests(folder, args.luajit)
        print(f"{folder.name}: {target.name} passes")
    print(f"{len(folders)} plugins checked.")


def cmd_package(args) -> None:
    folder = folder_for_tag(args.tag)[0] if args.tag else plugin_folder(args.plugin)
    target = build(folder, Path(args.out))
    sign(target, secret_from_env())
    verify(target, minisign.parse_public_key(PUBLIC_KEY.read_text()))
    print(target)
    if path := os.environ.get("GITHUB_OUTPUT"):
        with open(path, "a") as f:
            f.write(f"package={target}\nfolder={folder}\n")


def cmd_folder(args) -> None:
    print(folder_for_tag(args.tag)[0].name)


def cmd_notes(args) -> None:
    folder, version = folder_for_tag(args.tag)
    sys.stdout.write(release_notes(folder, version))


def main() -> int:
    parser = argparse.ArgumentParser(prog="release")
    sub = parser.add_subparsers(required=True)
    p = sub.add_parser("check", help="package every plugin (or one), check it as the registry does, run its tests")
    p.add_argument("plugin", nargs="?")
    p.add_argument("--out", default="dist")
    p.add_argument("--luajit", default="luajit")
    p.set_defaults(func=cmd_check)
    p = sub.add_parser("package", help="package, sign with HIKARISUB_MINISIGN_KEY and verify one plugin")
    who = p.add_mutually_exclusive_group(required=True)
    who.add_argument("--tag")
    who.add_argument("--plugin")
    p.add_argument("--out", default="dist")
    p.set_defaults(func=cmd_package)
    p = sub.add_parser("folder", help="print the plugins/ folder a release tag names")
    p.add_argument("tag")
    p.set_defaults(func=cmd_folder)
    p = sub.add_parser("notes", help="print the CHANGELOG.md section for a release tag")
    p.add_argument("tag")
    p.set_defaults(func=cmd_notes)
    args = parser.parse_args()
    try:
        args.func(args)
    except (ReleaseError, package.PackageError, minisign.MinisignError) as e:
        print(f"Refused: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
