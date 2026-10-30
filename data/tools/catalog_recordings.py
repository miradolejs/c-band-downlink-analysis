#!/usr/bin/env python3
"""Inventory RAW/JSON recordings using file sizes and JSON only; never open RAW data."""
import argparse
import csv
import json
import math
import os
import re
import sys
from collections import Counter
from datetime import datetime, timezone, date
from pathlib import Path

NAME = re.compile(r'^(\d+)_(\d{6})_(\d{6})$')
FIELDS = ['campaign', 'station', 'source_directory', 'measurement_id',
          'recording_start_local', 'start_iso', 'start_unix', 'start_utc',
          'utc_source', 'local_utc_offset_seconds', 'raw_path', 'json_path',
          'raw_size_bytes', 'json_size_bytes', 'samples_from_size',
          'samples_recorded', 'sample_rate_hz', 'duration_s', 'center_frequency_if_hz',
          'stored_format', 'write_error', 'temperature_c', 'humidity_percent',
          'env_valid', 'within_campaign', 'issues']


def number(value):
    if isinstance(value, bool) or not isinstance(value, (float, int)):
        return None
    return value if math.isfinite(value) else None


def filename_time(stem):
    m = NAME.fullmatch(stem)
    if not m:
        return '', None
    try:
        return m[1], datetime.strptime(m[3] + m[2], '%d%m%y%H%M%S')
    except ValueError:
        return m[1], None


def write_csv(path, fields, rows):
    temp = path.with_name(path.name + '.tmp')
    with temp.open('w', newline='', encoding='utf-8') as f:
        writer = csv.DictWriter(f, fieldnames=fields, extrasaction='ignore')
        writer.writeheader()
        writer.writerows(rows)
    temp.replace(path)


def scan(archive_root, config, output):
    root = Path(archive_root).resolve()
    output = Path(output).resolve()
    if not root.is_dir():
        raise ValueError('Archive root is not a directory.')
    campaigns = config['campaigns']
    ranges = {k: (date.fromisoformat(v['start_date']), date.fromisoformat(v['end_date']))
              for k, v in campaigns.items()}
    if any(a > b for a, b in ranges.values()):
        raise ValueError('Campaign start must not follow campaign end.')
    rows, issues, sources, seen_dirs = [], [], [], set()

    def issue(path, code, detail=''):
        issues.append({'path': path, 'code': code, 'detail': detail.replace(str(root), '<archive-root>')})

    for source in config['sources']:
        directory = Path(source['directory'])
        if directory.is_absolute() or '..' in directory.parts:
            raise ValueError('Source directories must be relative to the archive root.')
        folder = (root / directory).resolve()
        if folder == root or root not in folder.parents:
            raise ValueError('Source must be a subdirectory of the archive root.')
        if folder in seen_dirs or any(p in folder.parents or folder in p.parents for p in seen_dirs):
            raise ValueError('Configured source directories must not overlap.')
        seen_dirs.add(folder)
        if output == folder or folder in output.parents:
            raise ValueError('Output directory must not be inside a scanned source.')
        campaign, station = source['campaign'], source['station']
        if campaign not in campaigns or station not in ('city', 'village'):
            raise ValueError('Unknown campaign or station in configuration.')
        source_name = directory.as_posix()
        status = {'source_directory': source_name, 'campaign': campaign, 'station': station,
                  'available': folder.is_dir(), 'raw_files': 0, 'json_files': 0,
                  'raw_bytes': 0, 'json_bytes': 0, 'scan_errors': 0}
        sources.append(status)
        if not folder.is_dir():
            issue(source_name, 'missing_source_directory')
            continue
        # Directory enumeration and stat calls do not read RAW contents.
        def walk_error(error):
            status['scan_errors'] += 1
            issue(source_name, 'directory_scan_error', str(error))
        for dirname, subdirs, names in os.walk(folder, onerror=walk_error, followlinks=False):
            subdirs.sort()
            grouped = {}
            for name in sorted(names):
                p = Path(dirname) / name
                ext = p.suffix.lower()
                if ext not in ('.raw', '.json'):
                    continue
                if p.is_symlink():
                    issue(p.relative_to(root).as_posix(), 'symlink_not_scanned')
                    status['scan_errors'] += 1
                    continue
                entry = grouped.setdefault(p.stem, {})
                if ext in entry:
                    raise ValueError('Multiple extensions differing only in case: ' + str(p))
                entry[ext] = p
            for stem, pair in sorted(grouped.items()):
                row = dict.fromkeys(FIELDS, '')
                row.update(campaign=campaign, station=station, source_directory=source_name)
                flags, details = [], {}
                raw, jp = pair.get('.raw'), pair.get('.json')
                for ext, label in (('.raw', 'raw'), ('.json', 'json')):
                    p = pair.get(ext)
                    if p is None:
                        flags.append('missing_' + label)
                        continue
                    row[label + '_path'] = p.relative_to(root).as_posix()
                    try:
                        size = p.stat().st_size
                    except OSError as e:
                        flags.append(label + '_stat_error')
                        details[label + '_stat_error'] = str(e)
                        status['scan_errors'] += 1
                        continue
                    row[label + '_size_bytes'] = size
                    status[label + '_files'] += 1
                    status[label + '_bytes'] += size
                mid, nominal = filename_time(stem)
                row['measurement_id'] = mid
                if nominal is None:
                    flags.append('invalid_filename')
                    row['within_campaign'] = ''
                else:
                    row['recording_start_local'] = nominal.isoformat()
                    a, b = ranges[campaign]
                    row['within_campaign'] = a <= nominal.date() <= b
                    if not row['within_campaign']:
                        flags.append('outside_campaign')
                    if Path(dirname).name != nominal.strftime('%d%m%y'):
                        flags.append('daily_directory_mismatch')
                meta = {}
                if jp is not None:
                    try:
                        # Only small metadata files are opened.
                        if jp.stat().st_size > 4 * 1024 * 1024:
                            raise ValueError('JSON exceeds the 4 MiB metadata size limit.')
                        with jp.open(encoding='utf-8-sig') as f:
                            meta = json.load(f)
                        if not isinstance(meta, dict):
                            raise ValueError('JSON root must be an object.')
                    except (OSError, ValueError, UnicodeError) as e:
                        meta = {}
                        flags.append('invalid_json')
                        details['invalid_json'] = str(e)
                for k in ('start_iso', 'write_error', 'temperature_c', 'humidity_percent', 'env_valid'):
                    row[k] = meta.get(k) if meta.get(k) is not None else ''
                fs, ns = number(meta.get('sample_rate')), number(meta.get('samples_recorded'))
                row['sample_rate_hz'] = fs if fs is not None else ''
                row['samples_recorded'] = ns if ns is not None else ''
                row['center_frequency_if_hz'] = number(meta.get('center_freq')) or ''
                row['stored_format'] = meta.get('format', '')
                if meta:
                    if fs is None or fs <= 0:
                        flags.append('invalid_sample_rate')
                    if ns is None or ns < 0 or ns != int(ns):
                        flags.append('invalid_sample_count')
                    if meta.get('format') != 'int16':
                        flags.append('unsupported_format')
                    if meta.get('write_error') is True:
                        flags.append('reported_write_error')
                    for k in ('write_error', 'env_valid'):
                        if not isinstance(meta.get(k), bool):
                            flags.append('missing_or_invalid_' + k)
                size = row['raw_size_bytes']
                if size != '':
                    if size == 0:
                        flags.append('empty_raw')
                    if size % 4:
                        flags.append('raw_size_not_multiple_of_4')
                    else:
                        # Fixed four bytes/sample is the documented archive convention.
                        row['samples_from_size'] = size // 4
                        if fs is not None and fs > 0 and meta.get('format') == 'int16':
                            row['duration_s'] = (size // 4) / fs
                    if ns is not None and ns >= 0 and size != 4 * ns:
                        flags.append('sample_count_size_mismatch')
                # UTC is derived only from explicit JSON timestamps, never a guessed local offset.
                epoch = number(meta.get('start_unix'))
                iso = meta.get('start_iso')
                local = None
                if isinstance(iso, str):
                    try:
                        local = datetime.fromisoformat(iso.replace('Z', '+00:00'))
                    except ValueError:
                        flags.append('invalid_start_iso')
                elif meta:
                    flags.append('missing_start_iso')
                utc = None
                if epoch is not None:
                    row['start_unix'] = epoch
                    try:
                        utc = datetime.fromtimestamp(epoch, timezone.utc)
                        row['utc_source'] = 'start_unix'
                    except (ValueError, OSError, OverflowError):
                        flags.append('invalid_start_unix')
                if utc is None and local is not None and local.tzinfo is not None:
                    utc = local.astimezone(timezone.utc)
                    row['utc_source'] = 'offset_aware_start_iso'
                if utc is not None:
                    row['start_utc'] = utc.isoformat().replace('+00:00', 'Z')
                    if local is not None:
                        if local.tzinfo is not None:
                            if abs((local.astimezone(timezone.utc) - utc).total_seconds()) > 1:
                                flags.append('timestamp_inconsistency')
                            row['local_utc_offset_seconds'] = local.utcoffset().total_seconds()
                        else:
                            offset = (local - utc.replace(tzinfo=None)).total_seconds()
                            near = min((3600, 7200), key=lambda x: abs(offset-x))
                            if abs(offset-near) <= 1:
                                row['local_utc_offset_seconds'] = near
                            else:
                                flags.append('unexpected_local_utc_offset')
                elif meta:
                    flags.append('absolute_time_unavailable')
                if local is not None and nominal is not None:
                    if abs((local.replace(tzinfo=None) - nominal).total_seconds()) > 2:
                        flags.append('filename_json_time_difference_gt_2s')
                row['issues'] = ';'.join(sorted(set(flags)))
                rows.append(row)
                for code in sorted(set(flags)):
                    issue(row['raw_path'] or row['json_path'], code, details.get(code, ''))
    return write_inventory(rows, issues, sources, campaigns, config, output)


def write_inventory(rows, issues, sources, campaigns, config, output,
                    merged_inputs=0, duplicate_entries_removed=0):
    output = Path(output).resolve()
    # Recompute volumes from retained catalog rows, not sums of input summaries.
    for source in sources:
        selected = [r for r in rows if r['source_directory'] == source['source_directory']]
        for label in ('raw', 'json'):
            source[label + '_files'] = sum(r[label + '_size_bytes'] != '' for r in selected)
            source[label + '_bytes'] = sum(r[label + '_size_bytes'] for r in selected
                                          if r[label + '_size_bytes'] != '')
    issues = [i for i in issues if i['code'] != 'duplicate_recording_key']
    for row in rows:
        row['issues'] = ';'.join(x for x in row['issues'].split(';') if x != 'duplicate_recording_key')
    # Repeated identifiers are retained, not silently deduplicated or summed as unique data.
    keys = Counter((r['campaign'], r['station'], r['measurement_id'], r['recording_start_local'])
                   for r in rows if r['recording_start_local'])
    for row in rows:
        if row['recording_start_local'] and keys[(row['campaign'], row['station'], row['measurement_id'], row['recording_start_local'])] > 1:
            row['issues'] = ';'.join(filter(None, [row['issues'], 'duplicate_recording_key']))
            issues.append(dict(path=row['raw_path'] or row['json_path'], code='duplicate_recording_key', detail=''))
    rows.sort(key=lambda r: (r['campaign'], r['station'], r['recording_start_local'], r['raw_path'], r['json_path']))
    output.mkdir(parents=True, exist_ok=True)
    for campaign in campaigns:
        write_csv(output / ('recordings_' + campaign + '.csv'), FIELDS,
                  [r for r in rows if r['campaign'] == campaign and r['within_campaign'] is True])
    outside = [r for r in rows if r['within_campaign'] is not True]
    write_csv(output / 'recordings_outside_campaign_or_invalid_date.csv', FIELDS, outside)
    write_csv(output / 'catalog_issues.csv', ['path', 'code', 'detail'], issues)
    summary = []
    for campaign in campaigns:
        for station in ('city', 'village'):
            selected = [r for r in rows if r['campaign'] == campaign and r['station'] == station]
            ss = [s for s in sources if s['campaign'] == campaign and s['station'] == station]
            raw_bytes = sum(s['raw_bytes'] for s in ss)
            json_bytes = sum(s['json_bytes'] for s in ss)
            summary.append(dict(campaign=campaign, station=station,
                configured_sources=len(ss), available_sources=sum(s['available'] for s in ss),
                scan_errors=sum(s['scan_errors'] for s in ss),
                raw_files=sum(s['raw_files'] for s in ss), json_files=sum(s['json_files'] for s in ss),
                raw_bytes=raw_bytes, json_bytes=json_bytes, total_bytes=raw_bytes+json_bytes,
                total_TB=(raw_bytes+json_bytes)/1e12, total_TiB=(raw_bytes+json_bytes)/2**40,
                paired_entries=sum(bool(r['raw_path'] and r['json_path']) for r in selected),
                in_campaign_entries=sum(r['within_campaign'] is True for r in selected),
                outside_or_invalid_date_entries=sum(r['within_campaign'] is not True for r in selected),
                entries_with_issues=sum(bool(r['issues']) for r in selected)))
    write_csv(output / 'archive_summary.csv', list(summary[0]), summary)
    report = dict(schema_version=1, generated_utc=datetime.now(timezone.utc).isoformat(),
                  raw_payloads_read=False, raw_checksums_computed=False,
                  scope='Logical file sizes by archive-relative path; no RAW content-based deduplication.',
                  all_configured_sources_available=all(s['available'] for s in sources),
                  campaigns=campaigns, sources=sources, summary=summary,
                  issue_counts=dict(Counter(i['code'] for i in issues)),
                  outside_or_invalid_date_entries=len(outside))
    report['merged_input_snapshots'] = merged_inputs
    report['duplicate_entries_removed'] = duplicate_entries_removed
    snapshot = dict(snapshot_schema_version=1, config=config, rows=rows, issues=issues, sources=sources)
    (output / 'catalog_snapshot.json').write_text(json.dumps(snapshot, indent=2, ensure_ascii=False, allow_nan=False)+'\n', encoding='utf-8')
    (output / 'archive_summary.json').write_text(json.dumps(report, indent=2, ensure_ascii=False, allow_nan=False)+'\n', encoding='utf-8')
    print('RAW files:', sum(s['raw_files'] for s in sources))
    print('JSON files:', sum(s['json_files'] for s in sources))
    print('Total bytes:', sum(s['raw_bytes'] + s['json_bytes'] for s in sources))
    print('Entries with issues:', sum(bool(r['issues']) for r in rows))
    print('Configured sources available:', sum(s['available'] for s in sources), '/', len(sources))
    print('Catalogs written to:', output)
    return report


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--archive-root', required=True, type=Path)
    p.add_argument('--output', required=True, type=Path)
    p.add_argument('--allow-partial', action='store_true', help='Allow missing configured directories for a per-disk scan; scan errors still return status 2.')
    p.add_argument('--config', type=Path, default=Path(__file__).with_name('archive_layout.json'))
    args = p.parse_args()
    try:
        config = json.loads(args.config.read_text(encoding='utf-8-sig'))
        if config.get('schema_version') != 1 or not config.get('campaigns') or not config.get('sources'):
            raise ValueError('Unsupported or empty archive configuration.')
        report = scan(args.archive_root, config, args.output)
        if (not report['all_configured_sources_available'] and not args.allow_partial) or any(s['scan_errors'] for s in report['sources']):
            print('WARNING: incomplete scan; inspect archive_summary.json and catalog_issues.csv.', file=sys.stderr)
            return 2
        if not report['all_configured_sources_available']:
            print('Partial disk scan saved. Missing configured sources must be supplied by other scans.')
        return 0
    except (OSError, ValueError, KeyError, TypeError) as e:
        print('ERROR:', e, file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
