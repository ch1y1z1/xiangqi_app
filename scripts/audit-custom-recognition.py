#!/usr/bin/env python3
"""Run app-generated image requests manually. Read the key without saving it."""
import argparse
import concurrent.futures
import getpass
import json
import re
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def redact(text, key):
    if key:
        text = text.replace(key, '[redacted]')
    return re.sub(r'sk-[A-Za-z0-9_-]+', '[redacted]', text)


def run(item, key):
    folder, fixture = item
    name = fixture['test']
    result = {'test': name, 'api': fixture['api'], 'thinking': fixture['thinking'], 'model_requested': fixture['model']}
    start = time.monotonic()
    print(f"Starting {fixture['api']} / {name}", flush=True)
    headers = {'Content-Type': 'application/json'}
    if key:
        headers['Authorization'] = 'Bearer ' + key
    request = urllib.request.Request(fixture['endpoint'], data=(folder / f'{name}-request.json').read_bytes(),
                                     method='POST', headers=headers)
    try:
        with urllib.request.build_opener(NoRedirect()).open(request, timeout=float(fixture['timeout'])) as response:
            result['http_status'] = response.status
            result['content_type'] = response.headers.get('Content-Type', '')
            payload = json.load(response)
        result['model_returned'] = payload.get('model')
        result['usage'] = payload.get('usage')
        if fixture['api'] == 'chatCompletions':
            choice = payload.get('choices', [{}])[0]
            result['finish_reason'] = choice.get('finish_reason')
            if choice.get('finish_reason') == 'length':
                raise ValueError('Incomplete completion')
            content = choice.get('message', {}).get('content') or ''
        else:
            result['response_status'] = payload.get('status')
            if payload.get('status') not in (None, 'completed'):
                raise ValueError('Response not completed')
            content = ''.join(part.get('text', '') for output in payload.get('output', [])
                              if output.get('type') == 'message' and output.get('role') == 'assistant'
                              for part in output.get('content', []) if part.get('type') == 'output_text')
        if not content:
            raise ValueError('Missing final text')
        (folder / f'{name}-content.json').write_text(redact(content, key))
        result['has_final_text'] = True
    except urllib.error.HTTPError as error:
        result['http_status'] = error.code
        try:
            body = json.loads(error.read(8192))
            message = body.get('error', {}).get('message')
            if isinstance(message, str):
                result['error_message'] = redact(message, key)[:500]
        except Exception:
            pass
    except Exception as error:
        result['error'] = type(error).__name__
        if isinstance(error, ValueError) and not isinstance(error, json.JSONDecodeError):
            result['error_message'] = redact(str(error), key)[:500]
    result['elapsed_seconds'] = round(time.monotonic() - start, 2)
    print(redact(json.dumps(result, ensure_ascii=False), key), flush=True)
    return folder, result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('endpoint', help='Authorized base URL; requests must stay on this origin')
    parser.add_argument('folders', nargs='+', type=Path, help='Folders prepared with --prepare-recognition-audit')
    parser.add_argument('--thinking', help='Only run the selected thinking level')
    args = parser.parse_args()
    origin = urllib.parse.urlsplit(args.endpoint)
    if origin.scheme not in ('http', 'https') or not origin.hostname or origin.username or origin.password:
        raise SystemExit('Invalid authorized endpoint')
    items = []
    for folder in args.folders:
        for fixture in json.loads((folder / 'manifest.json').read_text()):
            if args.thinking and fixture['thinking'] != args.thinking:
                continue
            target = urllib.parse.urlsplit(fixture['endpoint'])
            if (target.scheme, target.netloc) != (origin.scheme, origin.netloc):
                raise SystemExit('Fixture origin differs from the authorized endpoint')
            # Never let an old content file count as a successful new request.
            (folder / f"{fixture['test']}-content.json").unlink(missing_ok=True)
            items.append((folder, fixture))
    if not items:
        raise SystemExit('No matching fixtures')
    key = getpass.getpass('Custom API test key (not stored; empty for keyless service): ').strip()
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(lambda item: run(item, key), items))
    for folder in args.folders:
        report = [result for parent, result in results if parent == folder]
        (folder / 'wire-results.json').write_text(redact(json.dumps(report, ensure_ascii=False, indent=2), key))
    key = None


if __name__ == '__main__':
    main()
