#!/usr/bin/env python3
"""Netice Pro abonelik fiyatını mağazalarda her yıl %30 artırır.

`.github/workflows/fiyat-artisi.yml` her yıl 19 Kasım'da bu betiği çalıştırır.

* Google Play: netice_pro_yillik aboneliğinin ve netice_donem_3ay (3 aylık
  sınav dönemi paketi, tek seferlik ürün) her bölgedeki fiyatı %30
  artırılır (Android Publisher API). Eski aylık abonelik artık satılmıyor.
* App Store: Türkiye fiyatı %30 artırılır, diğer ülkeler Apple'ın eşdeğer
  fiyatlarıyla güncellenir (App Store Connect API).

App Store'daki sınav dönemi paketi (tek seferlik ürün) bu betikle değil,
App Store Connect'ten elle güncellenir.

Mevcut aboneler ESKİ fiyatla devam eder; yeni fiyat yalnızca yeni
abonelere uygulanır. Böylece mağazaların "fiyat artışı bildirimi ve onayı"
kurallarına takılmaz, kimsenin aboneliği kesilmez.

Aynı yılın artışı iki kez yapılmasın diye her mağaza için kaç yıllık artış
uygulandığı `tool/fiyat/durum.json` dosyasında tutulur.

Ortam değişkenleri (GitHub secrets):
  PLAY_SERVICE_ACCOUNT_JSON    Google Play hizmet hesabı anahtarı (JSON metni)
  ASC_KEY_ID, ASC_ISSUER_ID    App Store Connect API anahtarı kimlikleri
  ASC_PRIVATE_KEY              .p8 dosyasının içeriği
  DRY_RUN=1                    Yalnızca ne yapılacağını yaz, değiştirme
  FORCE=1                      Bu yılın artışı yapılmış olsa da bir kez daha uygula
"""

from __future__ import annotations

import datetime as dt
import json
import os
import sys
import time
from decimal import ROUND_HALF_UP, Decimal
from pathlib import Path

import requests

PACKAGE = "com.netice.netice"
BUNDLE_ID = "com.netice.netice"
PRODUCTS = ["netice_pro_yillik"]
ONE_TIME_PRODUCTS = ["netice_donem_3ay"]  # tek seferlik (yenilenmeyen) ürünler
BASE_DATE = dt.date(2026, 11, 19)  # lib/core/price_increase.dart ile aynı
INCREASE = Decimal("1.30")
APPLE_BASE_TERRITORY = os.environ.get("ASC_BASE_TERRITORY", "TUR")

STATE_FILE = Path(__file__).with_name("durum.json")
DRY_RUN = os.environ.get("DRY_RUN") == "1"
FORCE = os.environ.get("FORCE") == "1"


def years_due(today: dt.date) -> int:
    if today < BASE_DATE:
        return 0
    y = today.year - BASE_DATE.year
    if (today.month, today.day) < (BASE_DATE.month, BASE_DATE.day):
        y -= 1
    return max(y, 0)


def nice_round(old: Decimal, new: Decimal) -> Decimal:
    """Yeni fiyatı eski fiyatın biçimine benzetir: 799 → 1039, 79.99 → 103.99."""
    if old != old.to_integral_value():
        if (old * 100) % 100 == 99:
            return new.quantize(Decimal(1), ROUND_HALF_UP) - Decimal("0.01")
        return new.quantize(Decimal("0.01"), ROUND_HALF_UP)
    n = int(old)
    zeros, m = 0, n
    while m > 0 and m % 10 == 0:
        zeros += 1
        m //= 10
    step = 10**zeros * (10 if m % 10 == 9 else 1)
    rest = n % step
    return Decimal(int(((new - rest) / step).quantize(Decimal(1), ROUND_HALF_UP)) * step + rest)


def load_state() -> dict:
    if STATE_FILE.exists():
        return json.loads(STATE_FILE.read_text(encoding="utf-8"))
    return {}


def save_state(state: dict) -> None:
    STATE_FILE.write_text(json.dumps(state, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


# --------------------------------------------------------------------------
# Google Play
# --------------------------------------------------------------------------


def money_to_dec(m: dict) -> Decimal:
    return Decimal(m.get("units", "0")) + Decimal(m.get("nanos", 0)) / Decimal(10**9)


def dec_to_money(currency: str, d: Decimal) -> dict:
    units = int(d)
    nanos = int(((d - units) * 10**9).quantize(Decimal(1), ROUND_HALF_UP))
    return {"currencyCode": currency, "units": str(units), "nanos": nanos}


def raise_money(m: dict) -> dict:
    old = money_to_dec(m)
    return dec_to_money(m["currencyCode"], nice_round(old, old * INCREASE))


def google_play() -> bool:
    raw = os.environ.get("PLAY_SERVICE_ACCOUNT_JSON", "").strip()
    if not raw:
        print("Google Play: PLAY_SERVICE_ACCOUNT_JSON yok, atlandı.")
        return False
    from google.oauth2 import service_account
    from google.auth.transport.requests import Request

    creds = service_account.Credentials.from_service_account_info(
        json.loads(raw), scopes=["https://www.googleapis.com/auth/androidpublisher"]
    )
    creds.refresh(Request())
    h = {"Authorization": f"Bearer {creds.token}"}
    base = f"https://androidpublisher.googleapis.com/androidpublisher/v3/applications/{PACKAGE}/subscriptions"

    for pid in PRODUCTS:
        r = requests.get(f"{base}/{pid}", headers=h, timeout=60)
        r.raise_for_status()
        sub = r.json()
        for bp in sub.get("basePlans", []):
            for rc in bp.get("regionalConfigs", []):
                if "price" in rc:
                    old = rc["price"]
                    rc["price"] = raise_money(old)
                    if rc["regionCode"] in ("TR", "US", "DE"):
                        print(f"  {pid} {rc['regionCode']}: {money_to_dec(old)} → {money_to_dec(rc['price'])} {old['currencyCode']}")
            other = bp.get("otherRegionsConfig")
            if other:
                for k in ("usdPrice", "eurPrice"):
                    if k in other:
                        other[k] = raise_money(other[k])
        print(f"Google Play: {pid} için {sum(len(b.get('regionalConfigs', [])) for b in sub.get('basePlans', []))} bölge fiyatı hazır.")
        if DRY_RUN:
            continue
        r = requests.patch(
            f"{base}/{pid}",
            headers=h,
            params={"updateMask": "basePlans", "regionsVersion.version": "2022/02"},
            json=sub,
            timeout=120,
        )
        if not r.ok:
            print(r.text)
        r.raise_for_status()
        print(f"Google Play: {pid} güncellendi.")

    # Tek seferlik ürünler (sınav dönemi paketi): fiyatlar mikro birimde.
    iap = f"https://androidpublisher.googleapis.com/androidpublisher/v3/applications/{PACKAGE}/inappproducts"
    for sku in ONE_TIME_PRODUCTS:
        r = requests.get(f"{iap}/{sku}", headers=h, timeout=60)
        if r.status_code == 404:
            print(f"Google Play: {sku} henüz tanımlı değil, atlandı.")
            continue
        r.raise_for_status()
        prod = r.json()

        def raise_micros(p: dict) -> dict:
            old = Decimal(p["priceMicros"]) / Decimal(10**6)
            new = nice_round(old, old * INCREASE)
            return {"currency": p["currency"], "priceMicros": str(int(new * 10**6))}

        if "defaultPrice" in prod:
            prod["defaultPrice"] = raise_micros(prod["defaultPrice"])
        for region, price in list(prod.get("prices", {}).items()):
            prod["prices"][region] = raise_micros(price)
            if region in ("TR", "US", "DE"):
                print(f"  {sku} {region}: {Decimal(price['priceMicros']) / 10**6} → {Decimal(prod['prices'][region]['priceMicros']) / 10**6} {price['currency']}")
        if DRY_RUN:
            continue
        r = requests.put(f"{iap}/{sku}", headers=h, params={"autoConvertMissingPrices": "true"}, json=prod, timeout=120)
        if not r.ok:
            print(r.text)
        r.raise_for_status()
        print(f"Google Play: {sku} güncellendi.")
    return True


# --------------------------------------------------------------------------
# App Store Connect
# --------------------------------------------------------------------------

ASC = "https://api.appstoreconnect.apple.com"


def asc_headers() -> dict | None:
    kid = os.environ.get("ASC_KEY_ID", "").strip()
    iss = os.environ.get("ASC_ISSUER_ID", "").strip()
    key = os.environ.get("ASC_PRIVATE_KEY", "").strip()
    if not (kid and iss and key):
        return None
    import jwt

    now = int(time.time())
    token = jwt.encode(
        {"iss": iss, "iat": now, "exp": now + 1100, "aud": "appstoreconnect-v1"},
        key,
        algorithm="ES256",
        headers={"kid": kid, "typ": "JWT"},
    )
    return {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}


def asc_get_all(h: dict, url: str, params: dict | None = None) -> tuple[list, list]:
    data, included = [], []
    p = dict(params or {})
    while url:
        r = requests.get(url, headers=h, params=p, timeout=60)
        if not r.ok:
            print(r.text)
        r.raise_for_status()
        j = r.json()
        data += j.get("data", [])
        included += j.get("included", [])
        url, p = j.get("links", {}).get("next"), None
    return data, included


def app_store() -> bool:
    h = asc_headers()
    if h is None:
        print("App Store: ASC_KEY_ID / ASC_ISSUER_ID / ASC_PRIVATE_KEY yok, atlandı.")
        return False

    apps, _ = asc_get_all(h, f"{ASC}/v1/apps", {"filter[bundleId]": BUNDLE_ID})
    if not apps:
        raise SystemExit(f"App Store: {BUNDLE_ID} uygulaması bulunamadı.")
    app_id = apps[0]["id"]
    groups, inc = asc_get_all(
        h, f"{ASC}/v1/apps/{app_id}/subscriptionGroups", {"include": "subscriptions", "limit": 50}
    )
    subs = {s["attributes"]["productId"]: s["id"] for s in inc if s["type"] == "subscriptions"}

    today = dt.date.today().isoformat()
    for pid in PRODUCTS:
        sid = subs.get(pid)
        if not sid:
            print(f"App Store: {pid} aboneliği bulunamadı, atlandı.")
            continue

        # Şu anki temel ülke fiyatı.
        prices, inc = asc_get_all(
            h,
            f"{ASC}/v1/subscriptions/{sid}/prices",
            {"filter[territory]": APPLE_BASE_TERRITORY, "include": "subscriptionPricePoint", "limit": 200},
        )
        points = {p["id"]: p for p in inc if p["type"] == "subscriptionPricePoints"}
        current = [
            p for p in prices if (p["attributes"].get("startDate") or "0000") <= today
        ]
        if not current:
            print(f"App Store: {pid} için {APPLE_BASE_TERRITORY} fiyatı yok, atlandı.")
            continue
        current.sort(key=lambda p: p["attributes"].get("startDate") or "0000")
        pp_id = current[-1]["relationships"]["subscriptionPricePoint"]["data"]["id"]
        old = Decimal(points[pp_id]["attributes"]["customerPrice"])
        target = nice_round(old, old * INCREASE)

        # Apple yalnızca hazır fiyat basamaklarını kabul eder: hedefe en yakını.
        all_points, _ = asc_get_all(
            h, f"{ASC}/v1/subscriptions/{sid}/pricePoints", {"filter[territory]": APPLE_BASE_TERRITORY, "limit": 200}
        )
        best = min(all_points, key=lambda p: abs(Decimal(p["attributes"]["customerPrice"]) - target))
        print(f"App Store: {pid} {APPLE_BASE_TERRITORY}: {old} → {best['attributes']['customerPrice']} (hedef {target})")

        eq, inc = asc_get_all(
            h, f"{ASC}/v1/subscriptionPricePoints/{best['id']}/equalizations", {"include": "territory", "limit": 200}
        )
        targets = [(APPLE_BASE_TERRITORY, best["id"])] + [
            (p["relationships"]["territory"]["data"]["id"], p["id"]) for p in eq
        ]
        print(f"App Store: {pid} için {len(targets)} ülke fiyatı hazır.")
        if DRY_RUN:
            continue
        for terr, ppid in targets:
            body = {
                "data": {
                    "type": "subscriptionPrices",
                    "attributes": {"preserveCurrentPrice": True},
                    "relationships": {
                        "subscription": {"data": {"type": "subscriptions", "id": sid}},
                        "subscriptionPricePoint": {"data": {"type": "subscriptionPricePoints", "id": ppid}},
                        "territory": {"data": {"type": "territories", "id": terr}},
                    },
                }
            }
            r = requests.post(f"{ASC}/v1/subscriptionPrices", headers=h, json=body, timeout=60)
            if not r.ok:
                print(f"  {terr}: {r.status_code} {r.text[:300]}")
                r.raise_for_status()
        print(f"App Store: {pid} güncellendi.")
    return True


def main() -> int:
    due = years_due(dt.date.today())
    state = load_state()
    print(f"Başlangıç {BASE_DATE}, bugüne kadar {due} yıllık artış gerekiyor. Durum: {state}")
    if DRY_RUN:
        print("DENEME: mağazada hiçbir şey değiştirilmeyecek.")

    for name, fn in (("google_play", google_play), ("app_store", app_store)):
        done = int(state.get(name, 0))
        if done >= due and not FORCE:
            print(f"{name}: bu yılın artışı zaten yapılmış ({done}/{due}).")
            continue
        # Her çalışmada en fazla bir artış: görev bir yıl çalışmadıysa
        # artışlar üst üste binmesin. Mağazaya yeni girilen fiyat o yılın
        # fiyatı sayılır.
        if fn() and not DRY_RUN:
            state[name] = due
            save_state(state)
    return 0


if __name__ == "__main__":
    sys.exit(main())
