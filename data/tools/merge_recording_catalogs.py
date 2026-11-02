#!/usr/bin/env python3
"""Merge per-disk catalog snapshots without accessing any original archive disk."""
import argparse
import copy
import json
import sys
from pathlib import Path, PurePosixPath
from catalog_recordings import FIELDS, write_inventory


def merge(inputs, output):
    output = Path(output).resolve()
    paths = [(Path(p) / 'catalog_snapshot.json' if Path(p).is_dir() else Path(p)).resolve()
             for p in inputs]
    if not paths:
        raise ValueError('At least one input snapshot is required.')
    if len(set(paths)) != len(paths):
        raise ValueError('The same input snapshot was specified more than once.')
    if any(p.parent == output for p in paths):
        raise ValueError('Output must differ from input snapshot directories.')
    snapshots = []
    for p in paths:
        obj = json.loads(p.read_text(encoding='utf-8-sig'))
        if not isinstance(obj, dict) or obj.get('snapshot_schema_version') != 1:
            raise ValueError('Unsupported snapshot format: ' + str(p))
        if not all(k in obj for k in ('config', 'rows', 'issues', 'sources')):
            raise ValueError('Incomplete snapshot: ' + str(p))
        snapshots.append(obj)
    config = snapshots[0]['config']
    if not config.get('campaigns') or not config.get('sources'):
        raise ValueError('Empty source/campaign configuration.')
    if any(x['config'] != config for x in snapshots[1:]):
        raise ValueError('Input snapshots use different archive configurations. Rescan using one configuration.')
    configured = {s['directory']: s for s in config['sources']}
    if len(configured) != len(config['sources']):
        raise ValueError('Duplicate source directory in configuration.')
    retained, issues, source_obs = {}, {}, {name: [] for name in configured}
    duplicate_count = 0
    for snapshot in snapshots:
        current_sources = {s['source_directory']: s for s in snapshot['sources']}
        if set(current_sources) != set(configured):
            raise ValueError('Snapshot source list differs from configuration.')
        for name, s in current_sources.items():
            if (s['station'], s['campaign']) != (configured[name]['station'], configured[name]['campaign']):
                raise ValueError('Snapshot source assignment differs from configuration.')
            source_obs[name].append(s)
        for original in snapshot['rows']:
            row = copy.deepcopy(original)
            if set(row) != set(FIELDS):
                raise ValueError('Catalog field mismatch; use snapshots produced by the same tool version.')
            name = row['source_directory']
            if name not in configured or (row['station'], row['campaign']) != (configured[name]['station'], configured[name]['campaign']):
                raise ValueError('Invalid station/source assignment in catalog row.')
            row['issues'] = ';'.join(x for x in row['issues'].split(';') if x != 'duplicate_recording_key')
            identity = None
            for label in ('raw', 'json'):
                path = row[label + '_path']
                if not path:
                    continue
                rel = PurePosixPath(path)
                if rel.is_absolute() or '..' in rel.parts or not rel.is_relative_to(PurePosixPath(name)):
                    raise ValueError('Unsafe or unexpected archive-relative path in snapshot.')
                key = rel.with_suffix('').as_posix()
                if identity is not None and key != identity:
                    raise ValueError('RAW and JSON paths do not identify one recording.')
                identity = key
            if identity is None:
                raise ValueError('Catalog entry has neither RAW nor JSON path.')
            if identity in retained:
                if retained[identity] != row:
                    raise ValueError('Conflicting observations of the same archive path: ' + identity +
                                     '. Resolve the discrepancy or replace the older disk snapshot; nothing was merged.')
                duplicate_count += 1
            else:
                retained[identity] = row
        for i in snapshot['issues']:
            if i['code'] in ('missing_source_directory', 'duplicate_recording_key'):
                continue
            key = (i['path'], i['code'], i['detail'])
            issues[key] = i
    sources = []
    for name, source in configured.items():
        observations = source_obs[name]
        available = any(s['available'] for s in observations)
        sources.append(dict(source_directory=name, campaign=source['campaign'], station=source['station'],
                            available=available, scan_errors=sum(s['scan_errors'] for s in observations)))
        if not available:
            i = dict(path=name, code='missing_source_directory', detail='Absent from all input disk snapshots.')
            issues[(i['path'], i['code'], i['detail'])] = i
    return write_inventory(list(retained.values()), list(issues.values()), sources,
                           config['campaigns'], config, output,
                           merged_inputs=len(paths), duplicate_entries_removed=duplicate_count)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--inputs', nargs='+', required=True, type=Path,
                   help='Per-disk directories or catalog_snapshot.json paths.')
    p.add_argument('--output', required=True, type=Path)
    args = p.parse_args()
    try:
        report = merge(args.inputs, args.output)
        print('Input snapshots:', report['merged_input_snapshots'])
        print('Identical catalog entries removed:', report['duplicate_entries_removed'])
        if not report['all_configured_sources_available'] or any(s['scan_errors'] for s in report['sources']):
            print('WARNING: merged inventory still has missing sources or scan errors.', file=sys.stderr)
            return 2
        return 0
    except (OSError, ValueError, KeyError, TypeError) as e:
        print('ERROR:', e, file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
