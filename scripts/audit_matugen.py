#!/usr/bin/env python3
"""Read-only wallpaper audit using the production Swift converter and installed wal.

Default: 15 randomly sampled wallpapers, all app schemes, both modes, contrast 0.
Exit 1 means measured readability/export failures; exit 2 means a setup failure.
Artifacts include the seed, sample, raw palettes, actual exports and an HTML preview.
This diagnostic does not exercise MatugenThemeService's publication/cache behavior.
"""
import argparse
import collections
import hashlib
import html
import json
import os
from pathlib import Path
import random
import re
import secrets
import shutil
import subprocess
import sys
import tempfile
import time

REPO = Path(__file__).resolve().parents[1]


def run(args, env=None, timeout=60, include_stderr=False):
    result = subprocess.run([str(a) for a in args], capture_output=True, text=True,
                            env=env, timeout=timeout)
    if result.returncode:
        raise RuntimeError(f'{args[0]} exited {result.returncode}: {result.stderr[-2000:]}')
    return result.stdout + (result.stderr if include_stderr else '')


def luminance(color):
    channels = [int(color[i:i + 2], 16) / 255 for i in (1, 3, 5)]
    linear = [v / 12.92 if v <= .04045 else ((v + .055) / 1.055) ** 2.4
              for v in channels]
    return sum(v * w for v, w in zip(linear, (.2126, .7152, .0722)))


def contrast(a, b):
    x, y = sorted((luminance(a), luminance(b)))
    return (y + .05) / (x + .05)


def near_extreme(color):
    """Match ThemeColor.isNearExtreme without needing a color library."""
    value = luminance(color)
    return value <= .02 or value >= .98


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--count', type=int, default=15)
    parser.add_argument('--seed', type=int)
    parser.add_argument('--config', type=Path, default=Path.home() /
                        'Library/Application Support/PywalPick/config.json')
    parser.add_argument('--wallpapers', type=Path)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--replay', type=Path,
                        help='Replay the exact wallpaper paths and hashes from a prior manifest')
    args = parser.parse_args()
    if args.count < 1:
        parser.error('--count must be positive')
    config = json.loads(args.config.read_text())
    replay_manifest = json.loads(args.replay.read_text()) if args.replay else None
    folder = (args.wallpapers or Path((replay_manifest or {}).get('folder', config['wallpaperFolderPath']))).expanduser().resolve()
    matugen = Path(config['matugenBinaryPath']).expanduser()
    wal = Path(config['walBinaryPath']).expanduser()
    seed = args.seed if args.seed is not None else secrets.randbits(64)
    output = args.output or Path(tempfile.mkdtemp(prefix='matugen-quality-'))
    output = output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    if any(output.iterdir()):
        raise ValueError(f'Output directory must be empty: {output}')
    version_env = dict(os.environ, NO_FUN='1', XDG_CONFIG_HOME=str(output / 'xdg-config'),
                       XDG_CACHE_HOME=str(output / 'xdg-cache'), PYWAL_CACHE_DIR=str(output / 'version-cache'))
    types = (REPO / 'Sources/PywalPick/Types.swift').read_text()
    enum_source = types[types.index('public enum MatugenMode:'):
                        types.index('public enum NavigationDirection:')]
    schemes = re.findall(r'case \w+ = "(scheme-[^"]+)"', enum_source)
    extensions_source = types[types.index('public static let extensions:'):
                              types.index('public struct ImageFile:')]
    extensions = set(re.findall(r'"(\w+)"', extensions_source))
    # Matugen 4.1.0's image decoder rejects AVIF even though the picker can
    # display it. Keep the audit's sample runnable and report this exclusion;
    # a future Matugen version can remove it after an explicit compatibility check.
    matugen_unsupported_extensions = {'avif'}
    candidates = sorted({p.resolve() for p in folder.rglob('*')
                         if p.is_file() and p.suffix.lower().lstrip('.') in extensions
                         and p.suffix.lower().lstrip('.') not in matugen_unsupported_extensions
                         and not any(part.startswith('.') for part in p.relative_to(folder).parts)})
    if replay_manifest:
        entries = replay_manifest.get('wallpapers', [])
        if not entries:
            raise ValueError('Replay manifest contains no wallpapers')
        selected = []
        for entry in entries:
            path = Path(entry['path']).expanduser().resolve()
            if not path.is_file():
                raise ValueError(f'Replay wallpaper is missing: {path}')
            digest = hashlib.sha256(path.read_bytes()).hexdigest()
            if digest != entry.get('sha256') or path.stat().st_size != entry.get('size'):
                raise ValueError(f'Replay wallpaper changed: {path}')
            selected.append(path)
        seed = replay_manifest.get('seed', seed)
        args.count = len(selected)
    else:
        if len(candidates) < args.count:
            raise ValueError(f'Need {args.count} supported images; found {len(candidates)}')
        selected = random.Random(seed).sample(candidates, args.count)
    selected_entries = (replay_manifest or {}).get('wallpapers') or [
        dict(path=str(p), size=p.stat().st_size,
             sha256=hashlib.sha256(p.read_bytes()).hexdigest()) for p in selected
    ]
    metadata = dict(seed=seed, folder=str(folder), candidate_count=len(candidates),
                    count=args.count, schemes=schemes, modes=['dark', 'light'], contrast=0,
                    excluded_extensions=sorted(matugen_unsupported_extensions),
                    matugen_version=run([matugen, '--version'], version_env, include_stderr=True).strip(),
                    wal_version=run([wal, '-v'], version_env, include_stderr=True).strip(),
                    source_revision=run(['git', '-C', REPO, 'rev-parse', 'HEAD']).strip(),
                    converter_sha256=hashlib.sha256((REPO /
                        'Sources/PywalPick/MatugenThemeConverter.swift').read_bytes()).hexdigest(),
                    wallpapers=selected_entries)
    if replay_manifest:
        metadata['replay_of'] = str(args.replay.resolve())
    (output / 'manifest.json').write_text(json.dumps(metadata, indent=2))
    print(f'Seed {seed}; {len(selected)} of {len(candidates)} wallpapers; output {output}', flush=True)
    helper = output / 'main.swift'
    helper.write_text('import Foundation\n' + enum_source + '''
let args = CommandLine.arguments
let raw = try Data(contentsOf: URL(fileURLWithPath: args[2]))
let mode = MatugenMode(rawValue: args[3])!
let scheme = MatugenSchemeType(rawValue: args[4])!
if args[1] == "convert" {
    let result = try MatugenThemeConverter.makePywalScheme(
        from: raw, wallpaperPath: args[5], mode: mode, schemeType: scheme)
    try result.write(to: URL(fileURLWithPath: args[6]))
} else {
    let accent = try MatugenThemeConverter.materialAccent(from: raw, mode: mode)
    try MatugenThemeConverter.applyGeneratedThemeOverrides(
        at: URL(fileURLWithPath: args[5]), primary: accent.primary, onPrimary: accent.onPrimary)
}
''')
    executable = output / 'convert'
    run(['swiftc', '-module-cache-path', output / 'modules', helper,
         REPO / 'Sources/PywalPick/MatugenPaletteDocument.swift',
         REPO / 'Sources/PywalPick/ThemeColor.swift',
         REPO / 'Sources/PywalPick/MatugenToneSelector.swift',
         REPO / 'Sources/PywalPick/MatugenColorCandidate.swift',
         REPO / 'Sources/PywalPick/MatugenThemeConverter.swift', '-o', executable], timeout=180)
    matugen_config = output / 'config.toml'
    matugen_config.write_text('[config]\nversion_check = false\ncaching = false\n'
                             '[config.wallpaper]\ncommand = "/usr/bin/true"\nset = false\n[templates]\n')
    templates = output / 'xdg-config/wal/templates'
    templates.mkdir(parents=True, exist_ok=True)
    user_templates = Path(os.environ.get('XDG_CONFIG_HOME', str(Path.home() / '.config'))) / 'wal/templates'
    if user_templates.exists():
        shutil.copytree(user_templates, templates, dirs_exist_ok=True)
    rows = []
    start = time.monotonic()
    for index, wallpaper in enumerate(selected):
        for scheme in schemes:
            for mode in metadata['modes']:
                case = output / f'{index:02d}-{scheme}-{mode}'
                case.mkdir()
                row = dict(wallpaper=str(wallpaper), scheme=scheme, mode=mode,
                           artifact=case.name, failures=[])
                try:
                    env = dict(os.environ, NO_FUN='1', XDG_CONFIG_HOME=str(output / 'xdg-config'),
                               XDG_CACHE_HOME=str(output / 'xdg-cache'), PYWAL_CACHE_DIR=str(case))
                    raw = run([matugen, 'image', wallpaper, '--config', matugen_config,
                               '--json', 'hex', '--include-image-in-json', 'true',
                               '--base16-backend', 'wal', '--mode', mode, '--type', scheme,
                               '--contrast', '0.000', '--source-color-index', '0', '--quiet',
                               '--dry-run'], env)
                    raw_path = case / 'matugen-colors.json'
                    raw_path.write_text(raw)
                    converted = case / 'matugen-pywal-scheme.json'
                    run([executable, 'convert', raw_path, mode, scheme, wallpaper, converted])
                    run([wal, '--theme', converted, '--out-dir', case, '-n', '-q', '-e', '-s'], env)
                    run([executable, 'override', raw_path, mode, scheme, case])
                    expected = json.loads(converted.read_text())
                    exported = json.loads((case / 'colors.json').read_text())
                    colors, special = exported['colors'], exported['special']
                    if colors != expected['colors'] or special != expected['special']:
                        row['failures'].append('pywal changed converted colors')
                    if set(colors) != {f'color{i}' for i in range(16)}:
                        row['failures'].append('ANSI keys differ from color0...color15')
                    if not all(re.fullmatch(r'#[0-9a-fA-F]{6}', c)
                               for c in [*colors.values(), *special.values()]):
                        raise ValueError('Invalid hex in exported palette')
                    bg = special['background']
                    metrics = {'foreground': contrast(special['foreground'], bg),
                               'cursor': contrast(special['cursor'], bg)}
                    metrics.update({k: contrast(v, bg) for k, v in colors.items()})
                    metrics['near_extreme_ansi_slots'] = sum(
                        near_extreme(value) for value in colors.values()
                    )
                    metrics['duplicate_ansi_slot_groups'] = sum(
                        count > 1 for count in collections.Counter(colors.values()).values()
                    )
                    tilix = json.loads((case / 'colors-tilix.json').read_text())
                    metrics['tilix_selection'] = contrast(tilix['highlight-foreground-color'],
                                                           tilix['highlight-background-color'])
                    for key in ['foreground', 'color7', 'color8', 'color15',
                                *[f'color{i}' for i in [1, 2, 3, 4, 5, 6, 9, 10, 11, 12, 13, 14]],
                                'tilix_selection', 'cursor']:
                        threshold = 3 if key == 'cursor' else 4.5
                        if metrics[key] < threshold:
                            row['failures'].append(f'{key}: {metrics[key]:.3f} < {threshold}')
                    ghostty = case / 'colors-ghostty'
                    if ghostty.exists():
                        values = dict(re.findall(r'^([\w-]+)\s*=\s*(#[0-9a-fA-F]{6})\s*$',
                                                 ghostty.read_text(), re.M))
                        if all(k in values for k in ('selection-background', 'selection-foreground',
                                                    'background', 'foreground')):
                            row['ghostty_selection_invisible'] = (
                                values['selection-background'] == values['background'] and
                                values['selection-foreground'] == values['foreground'])
                            metrics['ghostty_selection'] = contrast(
                                values['selection-foreground'], values['selection-background'])
                            if row['ghostty_selection_invisible']:
                                row['failures'].append('Ghostty selection equals ordinary text')
                            elif metrics['ghostty_selection'] < 4.5:
                                row['failures'].append(
                                    f'Ghostty selection: {metrics["ghostty_selection"]:.3f} < 4.5')
                    row.update(metrics=metrics, colors=colors, special=special)
                except Exception as error:
                    row['failures'].append(f'pipeline error: {error}')
                rows.append(row)
        print(f'Completed {index + 1}/{len(selected)} wallpapers', flush=True)
        (output / 'partial-results.json').write_text(json.dumps(
            {'manifest': metadata, 'completed_wallpapers': index + 1, 'results': rows},
            indent=2
        ))
    summary = dict(cases=len(rows), failed_cases=sum(bool(r['failures']) for r in rows),
                   pipeline_errors=sum(any(f.startswith('pipeline error:') for f in r['failures']) for r in rows),
                   ghostty_invisible_selections=sum(r.get('ghostty_selection_invisible', False) for r in rows),
                   near_extreme_ansi_slots=sum(r.get('metrics', {}).get('near_extreme_ansi_slots', 0)
                                               for r in rows),
                   duplicate_ansi_slot_groups=sum(r.get('metrics', {}).get('duplicate_ansi_slot_groups', 0)
                                                  for r in rows),
                   failure_counts=dict(collections.Counter(f.split(':')[0] for r in rows for f in r['failures'])),
                   seconds=round(time.monotonic() - start, 2))
    (output / 'results.json').write_text(json.dumps(dict(manifest=metadata, summary=summary, results=rows), indent=2))
    cards = []
    for row in rows:
        title = html.escape(f"{Path(row['wallpaper']).name} / {row['scheme']} / {row['mode']}")
        if 'colors' not in row:
            cards.append(f'<article><h3>{title}</h3><pre>{html.escape(str(row["failures"]))}</pre></article>')
            continue
        special, colors = row['special'], row['colors']
        samples = ''.join(f'<div style="color:{colors[f"color{i}"]}">ANSI {i:02d}: The quick brown fox 0123456789 '
                          f'({row["metrics"][f"color{i}"]:.2f}:1)</div>' for i in range(16))
        cards.append(f'<article style="background:{special["background"]};color:{special["foreground"]}">'
                     f'<h3>{title}</h3><p>Default foreground; cursor <b style="background:{special["cursor"]}">▌</b>; '
                     f'near-extreme ANSI slots: {row["metrics"]["near_extreme_ansi_slots"]}; '
                     f'duplicate slot groups: {row["metrics"]["duplicate_ansi_slot_groups"]}</p>'
                     f'{samples}<details><summary>Findings</summary>{html.escape(str(row["failures"]))}</details></article>')
    (output / 'preview.html').write_text('<!doctype html><meta charset="utf-8"><title>Matugen audit</title>'
        '<style>body{font:14px monospace;background:#888;display:grid;grid-template-columns:repeat(2,1fr);gap:12px}'
        'article{padding:20px;overflow-wrap:anywhere}h3{font-size:15px}div{line-height:1.7}</style>' + ''.join(cards))
    print(json.dumps(summary, indent=2))
    return 1 if summary['failed_cases'] else 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except Exception as error:
        print(f'Audit setup failed: {error}', file=sys.stderr)
        sys.exit(2)
