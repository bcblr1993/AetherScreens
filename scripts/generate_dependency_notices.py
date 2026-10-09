#!/usr/bin/env python3
"""Collect the locked Swift packages' license and notice texts for distribution."""
import argparse
import json
import subprocess
from pathlib import Path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    pins = json.loads((root / 'Package.resolved').read_text())['pins']
    checkouts = {p.name.casefold(): p for p in (root / '.build/checkouts').iterdir() if p.is_dir()}
    sections = ['AetherScreens third-party dependencies\n'
                'Versions and revisions are from Package.resolved.\n']
    for pin in sorted(pins, key=lambda p: p['identity']):
        identity = pin['identity']
        checkout = checkouts.get(identity.casefold())
        if checkout is None:
            raise SystemExit(f'Missing resolved checkout: {identity}; resolve packages first.')
        revision = subprocess.run(['git', '-C', str(checkout), 'rev-parse', 'HEAD'],
                                  check=True, capture_output=True, text=True).stdout.strip()
        if revision != pin['state']['revision']:
            raise SystemExit(f'Checkout does not match Package.resolved: {identity}')
        documents = [checkout / name for name in ('LICENSE', 'LICENSE.txt', 'LICENSE.md', 'NOTICE', 'NOTICE.txt')
                     if (checkout / name).is_file()]
        if not any(p.name.startswith('LICENSE') for p in documents):
            raise SystemExit(f'Missing dependency license: {identity}')
        for folder in ('license', 'licenses'):
            directory = checkout / folder
            if directory.is_dir():
                documents.extend(sorted(p for p in directory.rglob('*') if p.is_file()))
        state = pin['state']
        sections.append(f"\n{'=' * 72}\n{identity} {state.get('version', state['revision'])}\n"
                        f"Source: {pin['location']}\nRevision: {state['revision']}\n")
        for document in documents:
            sections.append(f'\n--- {document.relative_to(checkout)} ---\n{document.read_text()}\n')
    text = ''.join(sections)
    destination = root / 'assets/licenses/ThirdPartyNotices.txt'
    if args.check:
        if not destination.is_file() or destination.read_text() != text:
            raise SystemExit('Dependency notices are missing or stale; regenerate them.')
    else:
        destination.write_text(text)
    print(f"{'Verified' if args.check else 'Generated'} notices for {len(pins)} locked dependencies.")


if __name__ == '__main__':
    main()
