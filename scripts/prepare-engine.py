#!/usr/bin/env python3
"""Prepare pinned engine sources and a verified, bundled offline network."""
import argparse
import hashlib
from pathlib import Path
import shutil
import subprocess
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
COMMIT = '4c17cee11f888ae1d48a9494f2e2239f019f0a1f'
SHA256 = '7d13d73569a9b571ba0eb20cf1596247bc2a42738967e61afef6482b231e900e'
URL = 'https://github.com/official-pikafish/Pikafish/releases/download/Pikafish-2026-09-06/Pikafish.2026-09-06.7z'

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--network', type=Path, help='Use a previously downloaded compatible pikafish.nnue')
    args = parser.parse_args()
    subprocess.run(['git', 'submodule', 'update', '--init', '--recursive'], cwd=ROOT, check=True)
    upstream = ROOT / 'Vendor/Pikafish'
    commit = subprocess.check_output(['git', '-C', str(upstream), 'rev-parse', 'HEAD'], text=True).strip()
    if commit != COMMIT:
        raise SystemExit('Pikafish submodule does not match the pinned release.')
    destination = ROOT / 'build/engine'
    shutil.copytree(upstream / 'src', destination, dirs_exist_ok=True)
    header = destination / 'position.h'
    original = header.read_text()
    needle = '    u16   chased(Color c);'
    if needle not in original:
        raise SystemExit('Position extension requires review for this engine version.')
    header.write_text(original.replace('#include <utility>', '#include <utility>\n#include <vector>').replace(
        needle, needle + '\n    std::vector<Move> safe_captures(Color color);'))
    shared = destination / 'shm.h'
    original = shared.read_text()
    start = original.index('#if (defined(__linux__)')
    end = original.index('    #define USE_UNIX_SHM', start)
    # App builds use the existing local allocator, without Unix sockets/shared-memory services.
    original = original[:start] + '#if 0  // Xiangqi app: use local memory on Apple platforms.\n' + original[end:]
    shared.write_text(original)

    resource = ROOT / 'Resources/pikafish.nnue'
    resource.parent.mkdir(exist_ok=True)
    if args.network:
        shutil.copyfile(args.network, resource)
    elif not resource.exists():
        extractor = shutil.which('7z') or shutil.which('7zz')
        if not extractor:
            raise SystemExit('Install 7-Zip (brew install sevenzip) or pass --network /path/to/pikafish.nnue.')
        archive = ROOT / 'build/Pikafish.2026-09-06.7z'
        if not archive.exists():
            print('Downloading the pinned official release...', flush=True)
            urllib.request.urlretrieve(URL, archive)
        extract = ROOT / 'build/network-download'
        subprocess.run([extractor, 'x', str(archive), '-y', '-r', 'pikafish.nnue', f'-o{extract}'], check=True)
        candidates = list(extract.rglob('pikafish.nnue'))
        if not candidates:
            raise SystemExit('The release did not contain pikafish.nnue.')
        shutil.copyfile(candidates[0], resource)
    if hashlib.sha256(resource.read_bytes()).hexdigest() != SHA256:
        raise SystemExit('NNUE checksum mismatch; expected the Pikafish-2026-09-06 network.')
    for name in ['Copying.txt', 'AUTHORS']:
        shutil.copyfile(upstream / name, ROOT / 'Resources' / ('Pikafish-' + name))
    print('Prepared pinned engine, local-memory adaptation, and verified offline NNUE.')

if __name__ == '__main__':
    main()
