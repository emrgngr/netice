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
  // Neden Netice? süre hesaplayıcı: elle 1,5 dk, Netice ile 5 sn / kâğıt.
  var ogr = document.getElementById('c-ogr'), sinav = document.getElementById('c-sinav');
  if (ogr && sinav) {
    var fmt = function (n) { return Math.round(n).toLocaleString('tr-TR'); };
    var calc = function () {
      var k = Math.max(0, +ogr.value || 0) * Math.max(0, +sinav.value || 0);
      var saat = k * (90 - 5) / 3600;
      document.getElementById('c-saat').textContent = fmt(saat);
      document.getElementById('c-gun').textContent = fmt(saat / 8);
      document.getElementById('c-kagit').textContent = fmt(k);
    };
    ogr.addEventListener('input', calc); sinav.addEventListener('input', calc); calc();
  }
})();
