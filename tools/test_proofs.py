"""Build the test proofs page (HTML + JPEG thumbnails) from the automatic test runs.

    python RadioSurvivor/tools/test_proofs.py OUT_DIR [--server REPORT ...]

Reads tools/autoclient/runs/*/ (autoclient-result.txt, autoclient.txt, the RST report *-solo.txt / *-client.txt,
captures *.png) and optional dedicated-server RST reports; writes OUT_DIR/index.html and OUT_DIR/img/*.jpg.
Only test results and screenshots are read: no .env, no bridge log.
"""
import html
import re
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
RUNS = ROOT / 'tools' / 'autoclient' / 'runs'
LINE = re.compile(r'^(PASS|FAIL|ERROR|SKIP|EMPTY)\s+(\S+) :: (.*?) \((\d+) ms\)\s*(.*)$')
RESULT = re.compile(r'RST-RESULT ok=(\w+) total=(\d+) pass=(\d+) fail=(\d+) error=(\d+) skip=(\d+)')


def parse_report(path):
    tests = []
    if path is None or not path.exists():
        return tests
    for raw in path.read_text(encoding='utf-8', errors='replace').splitlines():
        m = LINE.match(raw)
        if m:
            tests.append({'status': m.group(1), 'suite': m.group(2), 'name': m.group(3),
                          'ms': int(m.group(4)), 'why': m.group(5)})
    return tests


def run_info(d):
    res = (d / 'autoclient-result.txt')
    m = RESULT.search(res.read_text(encoding='utf-8', errors='replace')) if res.exists() else None
    cfg = (d / 'autoclient.txt').read_text(encoding='utf-8', errors='replace') if (d / 'autoclient.txt').exists() else ''
    what = ''
    for key in ('campaign', 'suite'):
        mm = re.search(r'^' + key + r'=(.+)$', cfg, re.M)
        if mm:
            what = key + ' ' + mm.group(1).strip()
            break
    report = next(iter(sorted(d.glob('*-solo.txt')) + sorted(d.glob('*-client.txt'))), None)
    bridge = (d / 'bridge.log').exists()
    return {'id': d.name, 'what': what or '?', 'bridge': bridge, 'tests': parse_report(report),
            'totals': m.groups() if m else None, 'pngs': sorted(d.glob('*.png')), 'report': report}


def thumb(src, out_dir, name, width=1100):
    out = out_dir / 'img' / name
    out.parent.mkdir(parents=True, exist_ok=True)
    im = Image.open(src).convert('RGB')
    if im.width > width:
        im = im.resize((width, round(im.height * width / im.width)))
    im.save(out, 'JPEG', quality=78, optimize=True)
    return 'img/' + name


def esc(s):
    return html.escape(str(s))


def status_chip(ok, total):
    if total is None:
        return '<span class="chip warn">sans résultat</span>'
    return '<span class="chip ' + ('good' if ok else 'bad') + '">' + ('vert' if ok else 'échecs') + '</span>'


def tests_table(tests):
    rows = []
    for t in tests:
        rows.append('<tr class="s-' + t['status'].lower() + '"><td><span class="st">' + esc(t['status'])
                    + '</span></td><td class="mono">' + esc(t['suite']) + '</td><td>' + esc(t['name'])
                    + ('<div class="why">' + esc(t['why']) + '</div>' if t['why'] else '')
                    + '</td><td class="num">' + f"{t['ms'] / 1000:.1f} s" + '</td></tr>')
    return ('<div class="tablewrap"><table><thead><tr><th>État</th><th>Suite</th><th>Test</th><th>Durée</th></tr>'
            '</thead><tbody>' + ''.join(rows) + '</tbody></table></div>')


def main():
    out = Path(sys.argv[1])
    servers = []
    args = sys.argv[2:]
    while args:
        if args[0] == '--server' and len(args) > 1:
            servers.append(Path(args[1]))
            args = args[2:]
        else:
            args = args[1:]
    out.mkdir(parents=True, exist_ok=True)
    runs = [run_info(d) for d in sorted(RUNS.iterdir()) if d.is_dir()]
    runs = [r for r in runs if r['totals'] or r['tests']]
    gallery_run = next((r for r in reversed(runs) if len(r['pngs']) > 5), None)

    summary_rows, sections = [], []
    for r in reversed(runs):
        t = r['totals']
        ok = t is not None and t[0] == 'true'
        total = t[1] if t else '–'
        counts = (f'{t[2]} / {t[1]}' if t else '–')
        fails = (int(t[3]) + int(t[4])) if t else 0
        stamp = r['id'][:8] + ' ' + r['id'][9:11] + ':' + r['id'][11:13]
        summary_rows.append('<tr><td class="mono">' + esc(stamp) + '</td><td>' + esc(r['what'])
                            + (' <span class="tag">pont</span>' if r['bridge'] else '') + '</td><td class="num">'
                            + counts + '</td><td class="num">' + (str(fails) if t else '–') + '</td><td>'
                            + status_chip(ok, total if t else None) + '</td><td><a href="#' + esc(r['id'])
                            + '">détail</a></td></tr>')
        final = next((p for p in r['pngs'] if p.name.startswith('autoclient-')), None)
        img = ''
        if final is not None:
            img = ('<figure class="final"><img loading="lazy" src="' + thumb(final, out, r['id'] + '-final.jpg')
                   + '" alt="Capture finale du jeu, run ' + esc(r['id']) + '"><figcaption>Capture finale prise par le '
                   'pilote, juste avant de quitter.</figcaption></figure>')
        sections.append('<section class="run" id="' + esc(r['id']) + '"><h3><span class="mono">' + esc(stamp)
                        + '</span> · ' + esc(r['what']) + '</h3><p class="meta">Dossier <span class="mono">'
                        + esc('tools/autoclient/runs/' + r['id']) + '</span>'
                        + (' · rapport <span class="mono">' + esc(r['report'].name) + '</span>' if r['report'] else '')
                        + '</p>' + (tests_table(r['tests']) if r['tests'] else '<p class="meta">Aucune ligne de test.</p>')
                        + img + '</section>')

    server_sections = []
    for s in servers:
        tests = parse_report(s)
        if not tests:
            continue
        n = len(tests)
        p = sum(1 for t in tests if t['status'] == 'PASS')
        server_sections.append('<section class="run"><h3>Serveur dédié sans écran · ' + esc(s.name) + '</h3>'
                               '<p class="meta">' + f'{p} réussis sur {n}' + '</p>' + tests_table(tests) + '</section>')

    gallery = ''
    if gallery_run:
        figs = []
        for png in gallery_run['pngs']:
            if png.name.startswith('autoclient-'):
                continue
            label = png.stem.replace('rs_notebook_', '').replace('_', ' ')
            figs.append('<figure><a href="' + thumb(png, out, gallery_run['id'] + '-' + png.stem + '.jpg')
                        + '"><img loading="lazy" src="img/' + esc(gallery_run['id'] + '-' + png.stem + '.jpg')
                        + '" alt="' + esc(label) + '"></a><figcaption class="mono">' + esc(label) + '</figcaption></figure>')
        gallery = ('<h2 id="captures">Captures du carnet</h2><p class="lede">Prises par la suite '
                   '<span class="mono">rs.notebook.visual</span> pendant le run <a href="#' + esc(gallery_run['id'])
                   + '">' + esc(gallery_run['id']) + '</a>, en 1280×720 puis au plus grand mode d\'écran. '
                   'Cliquez une image pour l\'ouvrir en grand.</p><div class="gallery">' + ''.join(figs) + '</div>')

    page = PAGE.replace('{{SUMMARY}}', ''.join(summary_rows)).replace('{{RUNS}}', ''.join(sections)) \
        .replace('{{SERVER}}', ''.join(server_sections) or '<p class="meta">Aucun rapport de serveur fourni.</p>') \
        .replace('{{GALLERY}}', gallery).replace('{{COUNT}}', str(len(runs)))
    (out / 'index.html').write_text(page, encoding='utf-8')
    print('written', out / 'index.html', len(runs), 'runs')


PAGE = '''<title>Preuves de tests RadioSurvivor</title>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=IBM+Plex+Sans:wght@400;600&family=IBM+Plex+Mono:wght@400;500&family=Bitter:wght@600;700&display=swap">
<style>
/* Layout: one reading column; summary table first, then one block per run, then the screenshot gallery. */
:root {
  --bg: #f3f4f1; --surface: #ffffff; --fg: #1d2420; --muted: #5d6862; --line: #d5dbd6;
  --accent: #2f6f5e; --good: #2e7d4f; --bad: #b3402e; --warn: #9a6b12; --chipbg: #e7ece8;
  --display: "Bitter", Georgia, serif; --body: "IBM Plex Sans", "Segoe UI", sans-serif;
  --mono: "IBM Plex Mono", Consolas, monospace;
}
@media (prefers-color-scheme: dark) { :root:not([data-theme="light"]) {
  --bg: #141917; --surface: #1c2320; --fg: #e3e8e4; --muted: #9aa69f; --line: #2f3833;
  --accent: #6fbfa7; --good: #6cc48e; --bad: #ef8a76; --warn: #e2b75c; --chipbg: #26302b; color-scheme: dark } }
:root[data-theme="dark"] {
  --bg: #141917; --surface: #1c2320; --fg: #e3e8e4; --muted: #9aa69f; --line: #2f3833;
  --accent: #6fbfa7; --good: #6cc48e; --bad: #ef8a76; --warn: #e2b75c; --chipbg: #26302b; color-scheme: dark }
body { background: var(--bg); color: var(--fg); font: 15px/1.55 var(--body); padding-inline: 16px; padding-block: 28px 64px }
main { max-width: 1040px; margin: 0 auto; display: grid; gap: 28px }
h1, h2, h3 { font-family: var(--display); text-wrap: balance; margin: 0 }
h1 { font-size: 1.9rem } h2 { font-size: 1.35rem; margin-top: 12px } h3 { font-size: 1.05rem }
.lede { color: var(--muted); max-width: 68ch; margin: 6px 0 0 }
.meta { color: var(--muted); font-size: .9rem; margin: 4px 0 10px }
.mono { font-family: var(--mono); font-size: .9em }
a { color: var(--accent) }
.tablewrap { overflow-x: auto; border: 1px solid var(--line); border-radius: 6px; background: var(--surface) }
table { border-collapse: collapse; width: 100%; font-size: .9rem }
th, td { text-align: left; padding: 7px 10px; border-bottom: 1px solid var(--line); vertical-align: top }
th { font-size: .75rem; letter-spacing: .05em; text-transform: uppercase; color: var(--muted); font-weight: 600 }
tbody tr:last-child td { border-bottom: 0 }
.num { font-variant-numeric: tabular-nums; white-space: nowrap; text-align: right }
.chip { display: inline-block; padding: 1px 9px; border-radius: 999px; font-size: .8rem; font-weight: 600; background: var(--chipbg) }
.chip.good { color: var(--good) } .chip.bad { color: var(--bad) } .chip.warn { color: var(--warn) }
.tag { font-size: .72rem; padding: 0 6px; border: 1px solid var(--line); border-radius: 4px; color: var(--muted) }
.st { font-family: var(--mono); font-size: .8rem; font-weight: 500 }
tr.s-pass .st { color: var(--good) } tr.s-fail .st, tr.s-error .st { color: var(--bad) } tr.s-skip .st { color: var(--warn) }
tr.s-fail td, tr.s-error td { background: color-mix(in srgb, var(--bad) 7%, transparent) }
.why { color: var(--muted); font-size: .82rem; margin-top: 2px; overflow-wrap: anywhere }
.run { display: grid; gap: 4px; padding-top: 6px; border-top: 1px solid var(--line) }
figure { margin: 0 }
.final { margin-top: 10px; max-width: 560px }
.final img, .gallery img { border: 1px solid var(--line); border-radius: 4px; display: block; width: 100% }
figcaption { color: var(--muted); font-size: .8rem; margin-top: 4px }
.gallery { display: grid; grid-template-columns: repeat(auto-fill, minmax(240px, 1fr)); gap: 14px }
.notes { background: var(--surface); border: 1px solid var(--line); border-radius: 6px; padding: 12px 16px }
.notes li { margin: 4px 0 }
</style>
<main>
<header>
<h1>Preuves de tests RadioSurvivor</h1>
<p class="lede">Résultats réels du client de jeu automatique (E01-T14) : le vrai Project Zomboid 42.21 lancé sans
personne devant le PC, sur une copie de la partie de test, avec ou sans le pont Python et le vrai modèle.
{{COUNT}} runs. Les rapports complets sont dans <span class="mono">RadioSurvivor/tools/autoclient/runs/</span>.</p>
</header>
<section class="notes">
<h2>À lire avant</h2>
<ul>
<li>Le client tourne sans Steam et avec nos seuls mods : les tests qui ont besoin d'un mod d'armes sont ignorés (SKIP).</li>
<li>Un run « sans pont » ne peut pas réussir les suites de dialogue (<span class="mono">rs.npctalk</span>, envoi radio à Walt) : ces échecs sont attendus.</li>
<li>Ce qu'aucun script ne juge reste à votre œil : rendu des captures, sons, lisibilité.</li>
</ul>
</section>
<section>
<h2>Runs du jour</h2>
<div class="tablewrap"><table><thead><tr><th>Début</th><th>Contenu</th><th>Réussis</th><th>Échecs</th><th>État</th><th></th></tr></thead>
<tbody>{{SUMMARY}}</tbody></table></div>
</section>
{{GALLERY}}
<h2>Serveur dédié sans écran</h2>
{{SERVER}}
<h2>Détail des runs</h2>
{{RUNS}}
</main>
'''

if __name__ == '__main__':
    main()
