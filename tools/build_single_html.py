#!/usr/bin/env python3
"""Build a self-contained DroidSiege.html that boots from file:// (no local server).

Reads the Godot 4 web export in ../droid-siege-web (or --web-dir) and writes a single
HTML file with:
  - gzip+base64 embedded index.wasm and index.pck (in non-JS <script> tags)
  - fetch() interceptor returning decompressed bytes with Content-Length
  - AudioWorklet.addModule rewritten to data: URLs (file:// safe)
  - inlined icons/splash + index.js
"""
from __future__ import annotations

import argparse
import base64
import gzip
import re
import sys
from pathlib import Path


def b64(data: bytes) -> str:
    return base64.b64encode(data).decode("ascii")


def gzip9(path: Path) -> bytes:
    raw = path.read_bytes()
    # Prefer a pre-built .gz if present and smaller/equal source; else compress.
    gz_path = path.with_suffix(path.suffix + ".gz") if path.suffix != ".gz" else path
    if path.name.endswith(".wasm") and (path.parent / "index.wasm.gz").is_file():
        return (path.parent / "index.wasm.gz").read_bytes()
    return gzip.compress(raw, compresslevel=9)


def data_url(mime: str, path: Path) -> str:
    return f"data:{mime};base64,{b64(path.read_bytes())}"


def escape_script(js: str) -> str:
    # Prevent </script> in the source from closing the HTML script tag.
    return js.replace("</", "<\\/")


def build(web_dir: Path, out: Path) -> None:
    wasm = web_dir / "index.wasm"
    pck = web_dir / "index.pck"
    js_path = web_dir / "index.js"
    html_path = web_dir / "index.html"
    for p in (wasm, pck, js_path, html_path):
        if not p.is_file():
            raise SystemExit(f"missing {p}")

    wasm_gz = (web_dir / "index.wasm.gz").read_bytes() if (web_dir / "index.wasm.gz").is_file() else gzip.compress(wasm.read_bytes(), 9)
    pck_gz = gzip.compress(pck.read_bytes(), compresslevel=9)
    worklet = (web_dir / "index.audio.worklet.js").read_text(encoding="utf-8")
    worklet_pos = (web_dir / "index.audio.position.worklet.js").read_text(encoding="utf-8")
    icon = data_url("image/png", web_dir / "index.icon.png")
    apple = data_url("image/png", web_dir / "index.apple-touch-icon.png")
    splash = data_url("image/png", web_dir / "index.png")
    index_js = escape_script(js_path.read_text(encoding="utf-8"))

    # Pull styles + GODOT_CONFIG bootstrap from the export HTML (drop external refs / old hooks).
    src_html = html_path.read_text(encoding="utf-8")
    style_m = re.search(r"<style>([\s\S]*?)</style>", src_html)
    style = style_m.group(1) if style_m else ""
    cfg_m = re.search(r"(const GODOT_CONFIG = \{[\s\S]*?\};[\s\S]*?</script>)", src_html)
    if not cfg_m:
        raise SystemExit("could not find GODOT_CONFIG bootstrap in index.html")
    bootstrap = cfg_m.group(1)
    # Drop the closing </script> — we wrap ourselves.
    bootstrap = bootstrap[: bootstrap.rfind("</script>")].strip()
    # On file:// service workers / COOP headers are unavailable; don't chase them.
    bootstrap = bootstrap.replace('"ensureCrossOriginIsolationHeaders":true', '"ensureCrossOriginIsolationHeaders":false')
    bootstrap = re.sub(r'"serviceWorker"\s*:\s*"[^"]*"', '"serviceWorker":""', bootstrap)
    bootstrap = escape_script(bootstrap)

    loader = r'''
(function () {
  function b64ToU8(b64) {
    var bin = atob(b64);
    var len = bin.length;
    var bytes = new Uint8Array(len);
    for (var i = 0; i < len; i++) bytes[i] = bin.charCodeAt(i);
    return bytes;
  }
  function gunzipU8(u8) {
    if (typeof DecompressionStream === 'undefined') {
      return Promise.reject(new Error('Browser missing DecompressionStream (need a recent Chrome/Edge/Firefox/Safari)'));
    }
    var ds = new DecompressionStream('gzip');
    var ab = u8.buffer.slice(u8.byteOffset, u8.byteOffset + u8.byteLength);
    var stream = new Response(ab).body.pipeThrough(ds);
    return new Response(stream).arrayBuffer().then(function (buf) {
      return new Uint8Array(buf);
    });
  }
  function readEmbedded(id) {
    var el = document.getElementById(id);
    if (!el) throw new Error('missing embedded asset #' + id);
    return b64ToU8((el.textContent || '').replace(/\s+/g, ''));
  }

  var assets = { wasm: null, pck: null };
  window.__DS_SINGLE_READY = gunzipU8(readEmbedded('gd-wasm-gz')).then(function (w) {
    assets.wasm = w;
    return gunzipU8(readEmbedded('gd-pck-gz'));
  }).then(function (p) {
    assets.pck = p;
    return assets;
  });

  // Match index.wasm / index.pck no matter what the HTML file is named or where it lives.
  function matchAsset(url) {
    var u = String(url || '');
    if (/index\.wasm(\?|$)/.test(u) && !/index\.wasm\.gz/.test(u)) return 'wasm';
    if (/index\.pck(\?|$)/.test(u)) return 'pck';
    return null;
  }

  var origFetch = window.fetch.bind(window);
  window.fetch = function (input, init) {
    var url = (typeof input === 'string') ? input : (input && input.url) || '';
    var kind = matchAsset(url);
    if (!kind) return origFetch(input, init);
    return window.__DS_SINGLE_READY.then(function (a) {
      var bytes = a[kind];
      var mime = kind === 'wasm' ? 'application/wasm' : 'application/octet-stream';
      // Content-Length is required: Godot loadFetch uses it for the progress bar.
      return new Response(bytes, {
        status: 200,
        headers: {
          'Content-Type': mime,
          'Content-Length': String(bytes.byteLength)
        }
      });
    });
  };

  // AudioWorklet on file:// cannot load relative sibling .js files. data: URLs work on opaque origins.
  var WORKLETS = {
    'index.audio.worklet.js': 'DATA_WORKLET',
    'index.audio.position.worklet.js': 'DATA_WORKLET_POS',
    'godot.audio.worklet.js': 'DATA_WORKLET',
    'godot.audio.position.worklet.js': 'DATA_WORKLET_POS'
  };
  // placeholders replaced by the builder:
  WORKLETS['index.audio.worklet.js'] = '__WORKLET__';
  WORKLETS['index.audio.position.worklet.js'] = '__WORKLET_POS__';
  WORKLETS['godot.audio.worklet.js'] = WORKLETS['index.audio.worklet.js'];
  WORKLETS['godot.audio.position.worklet.js'] = WORKLETS['index.audio.position.worklet.js'];

  // file:// cannot use Service Workers — stub so Godot's optional COOP probe does not throw.
  if (location.protocol === 'file:' && navigator.serviceWorker) {
    try {
      Object.defineProperty(navigator, 'serviceWorker', {
        configurable: true,
        get: function () { return undefined; }
      });
    } catch (e) {}
  }

  if (window.AudioWorklet && AudioWorklet.prototype) {
    var origAdd = AudioWorklet.prototype.addModule;
    AudioWorklet.prototype.addModule = function (url, opts) {
      var name = String(url || '').split('/').pop().split('?')[0];
      if (WORKLETS[name]) {
        return origAdd.call(this, WORKLETS[name], opts);
      }
      // Also match full paths ending with the filename.
      for (var k in WORKLETS) {
        if (String(url).indexOf(k) !== -1) return origAdd.call(this, WORKLETS[k], opts);
      }
      return origAdd.call(this, url, opts);
    };
  }
})();
'''.strip()

    # Inject data URLs for worklets into the loader.
    worklet_data = "data:application/javascript;base64," + b64(worklet.encode("utf-8"))
    worklet_pos_data = "data:application/javascript;base64," + b64(worklet_pos.encode("utf-8"))
    loader = loader.replace("'__WORKLET__'", repr(worklet_data)).replace("'__WORKLET_POS__'", repr(worklet_pos_data))
    # Fix the placeholder assignment mess — rebuild WORKLETS cleanly in loader
    loader = re.sub(
        r"var WORKLETS = \{[\s\S]*?WORKLETS\['godot\.audio\.position\.worklet\.js'\] = WORKLETS\['index\.audio\.position\.worklet\.js'\];",
        "var WORKLETS = {\n"
        f"    'index.audio.worklet.js': {repr(worklet_data)},\n"
        f"    'index.audio.position.worklet.js': {repr(worklet_pos_data)},\n"
        f"    'godot.audio.worklet.js': {repr(worklet_data)},\n"
        f"    'godot.audio.position.worklet.js': {repr(worklet_pos_data)}\n"
        "  };",
        loader,
        count=1,
    )

    html = f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, user-scalable=no, initial-scale=1.0">
<title>Droid Siege</title>
<style>{style}</style>
<link id="-gd-engine-icon" rel="icon" type="image/png" href="{icon}" />
<link rel="apple-touch-icon" href="{apple}" />
</head>
<body>
<canvas id="canvas">Your browser does not support the canvas tag.</canvas>
<noscript>Your browser does not support JavaScript.</noscript>
<div id="status">
<img id="status-splash" class="show-image--true fullsize--true use-filter--true" src="{splash}" alt="">
<progress id="status-progress"></progress>
<div id="status-notice"></div>
</div>

<!-- Gzip+base64 game payload (not executed as JS; read by the loader). -->
<script type="application/octet-stream" id="gd-wasm-gz">{b64(wasm_gz)}</script>
<script type="application/octet-stream" id="gd-pck-gz">{b64(pck_gz)}</script>

<script>
{loader}
</script>
<script>
{index_js}
</script>
<script>
// Wait for wasm/pck gunzip before starting the engine (fetch interceptor needs the bytes).
window.__DS_SINGLE_READY.then(function () {{
{bootstrap}
}}).catch(function (err) {{
  console.error(err);
  var n = document.getElementById('status-notice');
  var s = document.getElementById('status');
  if (s) s.style.visibility = 'visible';
  if (n) {{ n.style.display = 'block'; n.textContent = String(err && err.message ? err.message : err); }}
}});
</script>
</body>
</html>
"""
    out.write_text(html, encoding="utf-8")
    mb = out.stat().st_size / (1024 * 1024)
    print(f"wrote {out} ({out.stat().st_size} bytes, {mb:.1f} MiB)")
    print(f"  wasm.gz={len(wasm_gz)} pck.gz={len(pck_gz)}")


def main() -> None:
    ap = argparse.ArgumentParser()
    here = Path(__file__).resolve()
    default_web = here.parents[1].parent / "droid-siege-web"  # /workspace/droid-siege-web
    ap.add_argument("--web-dir", type=Path, default=default_web)
    ap.add_argument("-o", "--output", type=Path, default=Path("/workspace/DroidSiege.html"))
    args = ap.parse_args()
    build(args.web_dir, args.output)


if __name__ == "__main__":
    main()
