# neticeoptik.com web sitesi

Sitenin asıl kaynağı bu klasördür. Buradaki bir değişiklik `ilk-surum` veya `main`
dalına girince `.github/workflows/web-sitesi.yml` siteyi Cloudflare Pages'teki
**neticeoptik** projesine kendiliğinden yayınlar (www.neticeoptik.com).
Bir PR açıldığında aynı iş sitenin önizlemesini ayrı bir adrese koyar
(`https://onizleme.neticeoptik.pages.dev`); adres işin özetinde yazar.

Gerekli secret'lar: `CLOUDFLARE_API_TOKEN` (Cloudflare Pages: Edit izni olmalı),
`CLOUDFLARE_ACCOUNT_ID`.
