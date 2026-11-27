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
      var label = b.getAttribute('data-label') || 'Kopyala';
      var done = function () { b.textContent = b.getAttribute('data-ok') || 'Kopyalandı'; setTimeout(function () { b.textContent = label; }, 1800); };
      var select = function () {
        var code = b.parentElement.querySelector('code');
        if (!code) return;
        var r = document.createRange(); r.selectNodeContents(code);
        var s = window.getSelection(); s.removeAllRanges(); s.addRange(r);
        b.textContent = b.getAttribute('data-sel') || 'Seçildi, kopyalayın';
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
    var fmt = function (n) { return Math.round(n).toLocaleString(document.documentElement.lang || 'tr'); };
    var calc = function () {
      var k = Math.max(0, +ogr.value || 0) * Math.max(0, +sinav.value || 0);
      var saat = k * (90 - 5) / 3600;
      document.getElementById('c-saat').textContent = fmt(saat);
      document.getElementById('c-gun').textContent = fmt(saat / 8);
      document.getElementById('c-kagit').textContent = fmt(k);
    };
    ogr.addEventListener('input', calc); sinav.addEventListener('input', calc); calc();
  }
  // Örnek raporlar: karta tıklayınca sayfa büyük açılır (tarayıcı desteklemiyorsa görsel ayrı açılır).
  var dlg = document.getElementById('buyut');
  if (dlg && typeof dlg.showModal === 'function') {
    var big = dlg.querySelector('img');
    document.querySelectorAll('[data-rapor]').forEach(function (a) {
      a.addEventListener('click', function (e) {
        e.preventDefault();
        var im = a.querySelector('img');
        big.src = a.getAttribute('href');
        big.alt = im ? im.alt : '';
        dlg.showModal();
      });
    });
    dlg.querySelector('.kapat').addEventListener('click', function () { dlg.close(); });
    dlg.addEventListener('click', function (e) { if (e.target === dlg) dlg.close(); });
  }
  // Paylaş: telefonda paylaşım menüsü (WhatsApp, e-posta…); yoksa bağlantı kopyalanır.
  document.querySelectorAll('[data-paylas]').forEach(function (b) {
    b.addEventListener('click', function () {
      var url = new URL(b.getAttribute('data-paylas'), location.href).href;
      var title = b.getAttribute('data-baslik') || document.title;
      var label = b.getAttribute('data-label') || b.textContent;
      var done = function () { b.textContent = b.getAttribute('data-ok') || label; setTimeout(function () { b.textContent = label; }, 1800); };
      if (navigator.share) {
        navigator.share({ title: title, url: url }).catch(function () {});
        return;
      }
      try {
        navigator.clipboard.writeText(url).then(done, function () { window.prompt('', url); });
      } catch (e) { window.prompt('', url); }
    });
  });
})();
