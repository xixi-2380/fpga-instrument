"""Reproduce the bundled simulator from exact URLs and SHA-256 values."""
import pathlib,json,hashlib,urllib.request,urllib.parse,tarfile
root=pathlib.Path(__file__).resolve().parents[1];dest=root/'tools'
for p in json.loads((dest/'manifest.json').read_text()):
    archive=dest/p['name']
    if not archive.exists():
        archive.write_bytes(urllib.request.urlopen(urllib.parse.quote(p['url'],safe=':/%'),timeout=45).read())
    if hashlib.sha256(archive.read_bytes()).hexdigest()!=p['sha256']:
        raise SystemExit('Hash mismatch: '+p['name'])
    with tarfile.open(archive) as t:t.extractall(dest,filter='data')
    print('Verified',p['name'])
