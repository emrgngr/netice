// Videolarda ileri/geri sarma: tarayıcı videonun bir parçasını (Range) ister;
// sunucu 206 ile yalnız o parçayı vermezse video sarılamaz. Yalnız /video/* için
// çalışır (_routes.json); diğer her şey doğrudan statik dosyadır.
export default {
  async fetch(request, env) {
    // Google Search Console doğrulama dosyası: Pages "/x.html"i "/x"e
    // yönlendirir; Google dosyayı yönlendirmesiz, tam adıyla görmek ister.
    const url = new URL(request.url);
    if (/^\/google[0-9a-f]+\.html$/.test(url.pathname)) {
      const r = await env.ASSETS.fetch(new Request(new URL(url.pathname.slice(0, -5), url), request));
      return new Response(r.status === 200 ? r.body : null, {
        status: r.status === 200 ? 200 : 404,
        headers: { 'Content-Type': 'text/html; charset=utf-8' },
      });
    }
    const res = await env.ASSETS.fetch(request);
    const range = request.headers.get('Range');
    if (res.status === 206 || res.status >= 300 || request.method !== 'GET' && request.method !== 'HEAD') return res;
    const h = new Headers(res.headers);
    h.set('Accept-Ranges', 'bytes');
    h.set('Cache-Control', 'public, max-age=86400');
    const m = range && /^bytes=(\d*)-(\d*)$/.exec(range.trim());
    if (!m || request.method === 'HEAD') return new Response(request.method === 'HEAD' ? null : res.body, { status: res.status, headers: h });
    const buf = await res.arrayBuffer();
    const size = buf.byteLength;
    let start, end;
    if (m[1] === '') {
      start = Math.max(0, size - Number(m[2] || 0));
      end = size - 1;
    } else {
      start = Number(m[1]);
      end = m[2] === '' ? size - 1 : Math.min(Number(m[2]), size - 1);
    }
    if (start >= size || start > end) {
      return new Response(null, { status: 416, headers: { 'Content-Range': `bytes */${size}` } });
    }
    h.set('Content-Range', `bytes ${start}-${end}/${size}`);
    h.set('Content-Length', String(end - start + 1));
    h.delete('Content-Encoding');
    return new Response(buf.slice(start, end + 1), { status: 206, headers: h });
  },
};
