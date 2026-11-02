#!/usr/bin/env python3
"""Copy selected I/Q sample ranges from a city/village pair, without resampling."""
import argparse
import hashlib
import json
import math
import os
import re
import sys
import tempfile
from datetime import datetime, timezone
from decimal import Decimal, InvalidOperation, ROUND_HALF_UP
from pathlib import Path

NAME = re.compile(r'^(\d+)_(\d{6})_(\d{6})$')


def numeric(value, name, positive=False):
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
        raise ValueError(name + ' must be a finite number.')
    if positive and value <= 0:
        raise ValueError(name + ' must be positive.')
    return value


def inspect_source(raw):
    raw = Path(raw).resolve()
    jp = raw.with_suffix('.json')
    if not raw.is_file() or not jp.is_file():
        raise ValueError('Both RAW and matching JSON must exist: ' + str(raw))
    m = NAME.fullmatch(raw.stem)
    if not m:
        raise ValueError('RAW filename must use N_HHMMSS_DDMMYY.')
    nominal = datetime.strptime(m[3] + m[2], '%d%m%y%H%M%S')
    if jp.stat().st_size > 4 * 1024 * 1024:
        raise ValueError('JSON exceeds the 4 MiB metadata size limit.')
    original_json = jp.read_bytes()
    meta = json.loads(original_json.decode('utf-8-sig'))
    if not isinstance(meta, dict) or meta.get('format') != 'int16':
        raise ValueError('Only documented interleaved int16 I/Q is supported.')
    fs = numeric(meta.get('sample_rate'), 'sample_rate', positive=True)
    fc = numeric(meta.get('center_freq'), 'center_freq', positive=True)
    n = numeric(meta.get('samples_recorded'), 'samples_recorded')
    size = raw.stat().st_size
    if n < 0 or n != int(n) or size % 4 or size != 4 * n:
        raise ValueError('RAW size and metadata sample count are inconsistent: ' + raw.name)
    if meta.get('write_error') is not False:
        raise ValueError('Source metadata must explicitly report write_error=false.')
    return dict(raw=raw, json=jp, json_bytes=original_json, meta=meta, fs=fs, fc=fc,
                samples=size//4, nominal=nominal, before=raw.stat())


def sample_index(seconds, fs):
    return int((Decimal(str(seconds)) * Decimal(str(fs))).to_integral_value(rounding=ROUND_HALF_UP))


def extract(city_raw, village_raw, offset, duration, output):
    try:
        offset, duration = Decimal(str(offset)), Decimal(str(duration))
    except InvalidOperation:
        raise ValueError('Offset and duration must be decimal numbers.')
    if not offset.is_finite() or not duration.is_finite() or offset < 0 or duration <= 0:
        raise ValueError('Offset must be nonnegative and duration must be positive.')
    sources = {'city': inspect_source(city_raw), 'village': inspect_source(village_raw)}
    c, v = sources.values()
    if c['raw'].samefile(v['raw']):
        raise ValueError('City and village inputs must be different files.')
    if c['nominal'] != v['nominal']:
        raise ValueError('The two RAW filenames must identify the same nominal recording time.')
    if c['fs'] != v['fs'] or c['fc'] != v['fc']:
        raise ValueError('Station sample rates and center frequencies must match.')
    start = sample_index(offset, c['fs'])
    count = sample_index(duration, c['fs'])
    if count < 1:
        raise ValueError('Requested duration rounds to zero samples.')
    if any(start + count > s['samples'] for s in sources.values()):
        raise ValueError('Requested interval exceeds the available samples in at least one source.')
    # Guard against pairing repeated local times from different UTC occurrences.
    epochs = [s['meta'].get('start_unix') for s in sources.values()]
    delta = None
    if all(isinstance(x, (int, float)) and not isinstance(x, bool) and math.isfinite(x) for x in epochs):
        delta = epochs[0] - epochs[1]
        if abs(delta) > 2:
            raise ValueError('Software start timestamps differ by more than 2 s; check the source pair.')
    output = Path(output).resolve()
    for s in sources.values():
        if output == s['raw'].parent or s['raw'].parent in output.parents:
            raise ValueError('Output must not be inside a source recording directory.')
    expected = [output / 'pair_manifest.json', output / 'checksums.sha256']
    for station, s in sources.items():
        expected += [output / station / (s['raw'].stem + suffix)
                     for suffix in ('_excerpt.raw', '_excerpt.json', '_source.json')]
    if any(p.exists() for p in expected):
        raise ValueError('Output files already exist. Choose a new output directory; no files were overwritten.')
    output.mkdir(parents=True, exist_ok=True)
    manifest = dict(schema_version=1, created_utc=datetime.now(timezone.utc).isoformat(),
        nominal_recording_start_local=c['nominal'].isoformat(),
        source_software_start_difference_city_minus_village_s=delta,
        sample_rate_hz=c['fs'], center_frequency_if_hz=c['fc'],
        requested_start_offset_s=str(offset), requested_duration_s=str(duration),
        start_sample_zero_based=start, sample_count=count,
        actual_start_offset_s=start/c['fs'], actual_duration_s=count/c['fs'],
        rounding='Nearest complex sample; decimal half-up.',
        synchronization='Same nominal recording time and sample offset only; no PPS or cross-correlation alignment.',
        timestamp_limitation='Source start timestamps are software references, not verified first-sample hardware timestamps.',
        stations={})
    with tempfile.TemporaryDirectory(prefix='.iq_excerpt_', dir=output) as temp:
        stage = Path(temp)
        hashes = []
        for station, s in sources.items():
            dest = stage / station
            dest.mkdir()
            stem = s['raw'].stem
            rp = dest / (stem + '_excerpt.raw')
            h = hashlib.sha256()
            with s['raw'].open('rb') as src, rp.open('xb') as dst:
                src.seek(4 * start)
                remaining = 4 * count
                while remaining:
                    chunk = src.read(min(1024 * 1024, remaining))
                    if not chunk:
                        raise ValueError('Unexpected EOF while reading ' + s['raw'].name)
                    dst.write(chunk)
                    h.update(chunk)
                    remaining -= len(chunk)
            after = s['raw'].stat()
            if (after.st_size, after.st_mtime_ns) != (s['before'].st_size, s['before'].st_mtime_ns):
                raise ValueError('Source changed while extracting: ' + s['raw'].name)
            preserved = dest / (stem + '_source.json')
            preserved.write_bytes(s['json_bytes'])
            derived = dict(schema_name='iq_excerpt_metadata', schema_version=1,
                is_excerpt=True, format='int16', byte_order='little-endian', component_order='I,Q',
                bytes_per_complex_sample=4, sample_rate=s['fs'], center_freq=s['fc'],
                gain=s['meta'].get('gain'), samples_recorded=count,
                source_raw_filename=s['raw'].name, source_json_filename=s['json'].name,
                source_metadata_file=preserved.name, source_raw_size_bytes=s['before'].st_size,
                source_start_iso=s['meta'].get('start_iso'), source_start_unix=s['meta'].get('start_unix'),
                source_env_valid=s['meta'].get('env_valid'),
                temperature_c=s['meta'].get('temperature_c'), humidity_percent=s['meta'].get('humidity_percent'),
                environmental_note='Copied source-recording values; not a separate measurement during the excerpt.',
                requested_start_offset_s=str(offset), requested_duration_s=str(duration),
                start_sample_zero_based=start, actual_start_offset_s=start/s['fs'],
                actual_duration_s=count/s['fs'],
                raw_sha256=h.hexdigest(),
                timestamp_note='No verified absolute timestamp is assigned to the excerpt first sample. Source timestamps remain in source_* fields.')
            dp = dest / (stem + '_excerpt.json')
            dp.write_text(json.dumps(derived, indent=2, ensure_ascii=False, allow_nan=False)+'\n', encoding='utf-8')
            for p in (rp, dp, preserved):
                # Only small output files, never full source RAW recordings, are hashed.
                digest = h.hexdigest() if p == rp else hashlib.sha256(p.read_bytes()).hexdigest()
                hashes.append((p.relative_to(stage).as_posix(), digest))
            manifest['stations'][station] = dict(source_raw_filename=s['raw'].name,
                excerpt_raw=rp.relative_to(stage).as_posix(), excerpt_metadata=dp.relative_to(stage).as_posix(),
                source_metadata=preserved.relative_to(stage).as_posix(), raw_size_bytes=4*count,
                raw_sha256=h.hexdigest())
        mp = stage/'pair_manifest.json'
        mp.write_text(json.dumps(manifest, indent=2, ensure_ascii=False, allow_nan=False)+'\n', encoding='utf-8')
        hashes.append(('pair_manifest.json', hashlib.sha256(mp.read_bytes()).hexdigest()))
        (stage/'checksums.sha256').write_text(''.join(f'{digest}  {path}\n' for path,digest in sorted(hashes)), encoding='ascii')
        # Refuse all pre-existing targets before publishing staged output files.
        targets = [p for p in stage.rglob('*') if p.is_file()]
        if any((output/p.relative_to(stage)).exists() for p in targets):
            raise ValueError('A target appeared during extraction; no staged file was published.')
        for p in targets:
            target = output/p.relative_to(stage)
            target.parent.mkdir(parents=True, exist_ok=True)
            os.replace(p, target)
    print('Wrote two excerpts:', count, 'complex samples each;', 4*count, 'bytes each.')
    print('Actual interval:', start/c['fs'], 'to', (start+count)/c['fs'], 's from each source start.')
    print('No additional inter-station synchronization was applied.')
    print('Output:', output)
    return manifest


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--city-raw', required=True, type=Path)
    p.add_argument('--village-raw', required=True, type=Path)
    p.add_argument('--offset', default='10', help='Seconds from source start (default: 10).')
    p.add_argument('--duration', default='1', help='Seconds to copy (default: 1).')
    p.add_argument('--output', required=True, type=Path)
    args = p.parse_args()
    try:
        extract(args.city_raw, args.village_raw, args.offset, args.duration, args.output)
        return 0
    except (OSError, ValueError, TypeError) as e:
        print('ERROR:', e, file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
