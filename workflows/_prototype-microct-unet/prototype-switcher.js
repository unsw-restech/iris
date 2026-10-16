// PROTOTYPE, throwaway. Floating ?variant= switcher. Branch prototype/reference-form-page only.
// Each variant is an element with data-variant="<key>" and data-name="<label>".
(function () {
  var els = Array.prototype.slice.call(document.querySelectorAll('[data-variant]'));
  var keys = els.map(function (e) { return e.dataset.variant; });
  function current() {
    var v = new URLSearchParams(location.search).get('variant');
    return keys.indexOf(v) >= 0 ? v : keys[0];
  }
  var bar = document.createElement('div');
  bar.style.cssText = 'position:fixed;bottom:20px;left:50%;transform:translateX(-50%);z-index:999;' +
    'display:flex;gap:14px;align-items:center;padding:8px 16px;border-radius:999px;' +
    'background:#ff0;color:#000;font:600 13px system-ui;box-shadow:0 4px 18px rgba(0,0,0,.6)';
  bar.innerHTML = '<button id="pv-prev">&larr;</button><span id="pv-label"></span><button id="pv-next">&rarr;</button>';
  document.body.appendChild(bar);
  bar.querySelectorAll('button').forEach(function (b) {
    b.style.cssText = 'border:0;background:#000;color:#ff0;border-radius:999px;width:28px;height:28px;cursor:pointer';
  });
  function show(v) {
    els.forEach(function (e) { e.style.display = e.dataset.variant === v ? '' : 'none'; });
    var el = els[keys.indexOf(v)];
    document.getElementById('pv-label').textContent = 'PROTOTYPE  ' + v + ' (' + el.dataset.name + ')';
    var u = new URL(location); u.searchParams.set('variant', v); history.replaceState(null, '', u);
  }
  function step(d) { var i = keys.indexOf(current()); show(keys[(i + d + keys.length) % keys.length]); }
  document.getElementById('pv-prev').onclick = function () { step(-1); };
  document.getElementById('pv-next').onclick = function () { step(1); };
  document.addEventListener('keydown', function (e) {
    var t = e.target;
    if (t.matches && t.matches('input,textarea,[contenteditable]')) return;
    if (e.key === 'ArrowLeft') step(-1);
    if (e.key === 'ArrowRight') step(1);
  });
  show(current());
})();
