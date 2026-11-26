// Netice web sitesi: mobil menü, e-posta kopyalama ve video sekmeleri.
(function () {
  var btn = document.querySelector('.menu-btn');
  var menu = document.querySelector('.menu');
  if (btn && menu) {
    btn.addEventListener('click', function () {
      var open = menu.classList.toggle('open');
      btn.setAttribute('aria-expanded', open ? 'true' : 'false');
    });
  }
  document.querySelectorAll('[data-copy]').forEach(function (b) {
    b.addEventListener('click', function () {
      var text = b.getAttribute('data-copy');
      var done = function () { b.textContent = 'Kopyalandı'; setTimeout(function () { b.textContent = 'Kopyala'; }, 1800); };
      var select = function () {
        var code = b.parentElement.querySelector('code');
        if (!code) return;
        var r = document.createRange(); r.selectNodeContents(code);
        var s = window.getSelection(); s.removeAllRanges(); s.addRange(r);
        b.textContent = 'Seçildi, kopyalayın';
      };
      try {
        navigator.clipboard.writeText(text).then(done, select);
      } catch (e) { select(); }
    });
  });
  document.querySelectorAll('[data-video]').forEach(function (tab) {
    tab.addEventListener('click', function () {
      var key = tab.getAttribute('data-video');
      document.querySelectorAll('[data-video]').forEach(function (t) { t.setAttribute('aria-selected', t === tab ? 'true' : 'false'); });
      document.querySelectorAll('[data-video-panel]').forEach(function (v) {
        var on = v.getAttribute('data-video-panel') === key;
        v.hidden = !on;
        if (!on) v.pause();
      });
    });
  });
})();
