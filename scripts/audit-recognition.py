#!/usr/bin/env python3
"""Manually compare known screenshots with the official API. Never persist the API key."""
import concurrent.futures
import getpass
import json
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / 'build/recognition-audit'
ENDPOINT = 'https://api.deepseek.com/chat/completions'


class OfficialHostOnly(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        target = urllib.parse.urlsplit(newurl)
        if target.scheme != 'https' or target.hostname != 'api.deepseek.com':
            raise urllib.error.HTTPError(newurl, code, 'Unexpected redirect', headers, fp)
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def run(fixture, key):
    name = fixture['test']
    start = time.monotonic()
    print(f'Starting {name}', flush=True)
    request = urllib.request.Request(ENDPOINT, data=(ROOT / f'{name}-request.json').read_bytes(), method='POST',
                                   headers={'Content-Type': 'application/json', 'Authorization': 'Bearer ' + key})
    try:
        with urllib.request.build_opener(OfficialHostOnly()).open(request, timeout=float(fixture['timeout'])) as response:
            payload = json.load(response)
        choice = payload.get('choices', [{}])[0]
        content = choice.get('message', {}).get('content') or ''
        (ROOT / f'{name}-content.json').write_text(content.replace(key, '[redacted]'))
        result = {'test': name, 'http_status': 200, 'model': payload.get('model'), 'finish_reason': choice.get('finish_reason'),
                  'usage': payload.get('usage'), 'elapsed_seconds': round(time.monotonic() - start, 2)}
    except urllib.error.HTTPError as error:
        result = {'test': name, 'http_status': error.code, 'elapsed_seconds': round(time.monotonic() - start, 2)}
    except Exception as error:
        result = {'test': name, 'error': type(error).__name__, 'elapsed_seconds': round(time.monotonic() - start, 2)}
    print(json.dumps(result, ensure_ascii=False), flush=True)
    return result


def main():
    fixtures = json.loads((ROOT / 'manifest.json').read_text())
    if len(sys.argv) > 1:
        fixtures = [fixture for fixture in fixtures if fixture['thinking'] == sys.argv[1]]
    if not fixtures:
        raise SystemExit('No fixtures for this thinking setting.')
    key = getpass.getpass('DeepSeek test key (not stored): ').strip()
    if not key:
        raise SystemExit('Missing key')
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(lambda fixture: run(fixture, key), fixtures))
    key = None
    (ROOT / 'wire-results.json').write_text(json.dumps(results, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
