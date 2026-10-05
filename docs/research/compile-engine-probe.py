#!/usr/bin/env python3
"""Build a pinned Pikafish checkout for Apple targets and run the Mac probe.

This builds console probes, not an iOS application. It never runs iOS binaries.
It does not download sources or weights or change the source checkout.
"""

import argparse
import concurrent.futures
import json
import pathlib
import subprocess
import time


TARGETS = {
    "ios": ("iphoneos", "arm64-apple-ios17.0"),
    "sim": ("iphonesimulator", "arm64-apple-ios17.0-simulator"),
    "mac": ("macosx", "arm64-apple-macos14.0"),
}


def run(command):
    started = time.monotonic()
    result = subprocess.run(command, capture_output=True, text=True)
    return {
        "command": command,
        "exit_code": result.returncode,
        "elapsed_seconds": round(time.monotonic() - started, 3),
        "stdout": result.stdout,
        "stderr": result.stderr,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True, type=pathlib.Path,
                        help="Pikafish repository root, pinned to the desired release")
    parser.add_argument("--network", type=pathlib.Path,
                        help="Compatible NNUE file; enables the Mac runtime probe")
    parser.add_argument("--output", required=True, type=pathlib.Path)
    parser.add_argument("--target", choices=[*TARGETS, "all"], default="all")
    parser.add_argument("--jobs", type=int, default=4)
    args = parser.parse_args()
    source = args.source.resolve() / "src"
    if not (source / "engine.h").is_file():
        parser.error("--source must name a Pikafish checkout containing src/engine.h")
    if args.jobs < 1:
        parser.error("--jobs must be positive")
    network = args.network.resolve() if args.network else None
    if network and not network.is_file():
        parser.error("--network must name an existing file")
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    compiler = subprocess.check_output(["xcrun", "--find", "clang++"], text=True).strip()
    files = sorted(p for p in source.rglob("*.cpp")
                   if p.name != "main.cpp" and "universal" not in p.relative_to(source).parts)
    harness = pathlib.Path(__file__).with_name("inprocess-probe.cpp").resolve()
    commit = run(["git", "-C", str(args.source.resolve()), "rev-parse", "HEAD"])
    report = {"source_commit": commit["stdout"].strip(), "targets": {}}
    success = True

    for name in (TARGETS if args.target == "all" else [args.target]):
        sdk, triple = TARGETS[name]
        sdk_path = subprocess.check_output(
            ["xcrun", "--sdk", sdk, "--show-sdk-path"], text=True).strip()
        target_dir = output / name
        target_dir.mkdir(exist_ok=True)
        flags = ["-target", triple, "-isysroot", sdk_path, "-std=c++17", "-O1",
                 "-DNDEBUG", "-DIS_64BIT", "-DUSE_NEON", "-DUSE_POPCNT",
                 "-DZSTD_DISABLE_ASM", "-fno-exceptions", "-I", str(source)]

        def compile_one(path):
            relative = path.relative_to(source)
            obj = target_dir / (str(relative).replace("/", "__") + ".o")
            result = run([compiler, *flags, "-c", str(path), "-o", str(obj)])
            result.update(source=str(relative), object=str(obj))
            return result

        with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
            results = list(pool.map(compile_one, files))
        target_report = {"triple": triple, "compile": results}
        report["targets"][name] = target_report
        failed = [r for r in results if r["exit_code"]]
        print(f"{name}: {len(results) - len(failed)}/{len(results)} compiled", flush=True)
        if failed:
            success = False
            for failure in failed:
                print(failure["source"], failure["stderr"], flush=True)
            continue

        archive = target_dir / "libPikafish.a"
        # Replace only this probe's own output archive to avoid stale members.
        archive.unlink(missing_ok=True)
        archive_result = run(["xcrun", "ar", "rcs", str(archive),
                              *[r["object"] for r in results]])
        target_report["archive"] = archive_result
        if archive_result["exit_code"]:
            success = False
            continue
        target_report["archive_bytes"] = archive.stat().st_size
        executable = target_dir / "inprocess-probe"
        link = run([compiler, *flags, str(harness), str(archive), "-o", str(executable)])
        target_report["link"] = link
        print(f"{name}: link exit {link['exit_code']}", flush=True)
        if link["exit_code"]:
            success = False
            print(link["stderr"], flush=True)
            continue
        target_report["platform"] = run(["xcrun", "vtool", "-show-build", str(executable)])
        if name == "mac" and network:
            runtime = run(["/usr/bin/time", "-l", str(executable), str(network)])
            target_report["runtime"] = runtime
            print(runtime["stdout"], flush=True)
            print(runtime["stderr"], flush=True)
            success = success and runtime["exit_code"] == 0

    (output / "probe-results.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    return 0 if success else 1


if __name__ == "__main__":
    raise SystemExit(main())
