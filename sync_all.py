"""
Bucks Global Intelligence — Master Data Sync
Runs every 6 hours via GitHub Actions
Writes JSON files to /data/ folder served statically
"""
import requests, json, os
from datetime import datetime, timedelta, timezone

# ── API KEYS (set as GitHub Secrets, injected as env vars) ──
FRED_KEY     = os.environ.get("FRED_API_KEY", "")
METALS_KEY   = os.environ.get("METALS_API_KEY", "")
COMTRADE_KEY           = os.environ.get("COMTRADE_API_KEY", "")
COMTRADE_KEY_SECONDARY = os.environ.get("COMTRADE_API_KEY_SECONDARY", "")
DATAGOV_KEY  = os.environ.get("DATAGOV_API_KEY", "")

os.makedirs("data", exist_ok=True)

def save(filename, data):
    path = f"data/{filename}"
    with open(path, "w") as f:
        json.dump(data, f, indent=2)
    print(f"  ✓ Saved {path}")

def utcnow():
    return datetime.now(timezone.utc).isoformat()

# ═══════════════════════════════════════
# 1. GOLD PRICE — gold-api.com (free, no key)
# ═══════════════════════════════════════
def sync_price():
    print("→ Gold price (gold-api.com)...")
    try:
        xau = requests.get("https://www.gold-api.com/price/XAU", timeout=10).json()
        xag = requests.get("https://www.gold-api.com/price/XAG", timeout=10).json()
        price = float(xau.get("price", 0))
        silver = float(xag.get("price", 0))
        inr_rate = 84.1
        inr_10g = round(price * inr_rate / 31.1035 * 10, 2)
        aed_10g = round(price * 3.67 / 31.1035 * 10, 2)
        coin_inr = round(price * inr_rate / 31.1035 * 4.25, 2)
        save("gold_price.json", {
            "updated": utcnow(),
            "source": "gold-api.com",
            "xau_usd": price,
            "xag_usd": silver,
            "gold_silver_ratio": round(price / silver, 2) if silver else 0,
            "inr_per_10g": inr_10g,
            "aed_per_10g": aed_10g,
            "sovereign_coin_inr": coin_inr,
            "smuggling_incentive_per_kg": round((inr_10g - inr_10g * 0.945) * 100, 0)
        })
    except Exception as e:
        print(f"  ✗ gold-api.com error: {e}")

# ═══════════════════════════════════════
# 2. MULTI-CURRENCY PRICES — metals.dev
# ═══════════════════════════════════════
def sync_metals():
    print("→ Multi-currency prices (metals.dev)...")
    if not METALS_KEY:
        print("  ✗ METALS_API_KEY not set"); return
    try:
        url = f"https://api.metals.dev/v1/latest?api_key={METALS_KEY}&currency=USD&unit=toz"
        r = requests.get(url, timeout=10).json()
        metals = r.get("metals", {})
        # Also fetch INR
        url_inr = f"https://api.metals.dev/v1/latest?api_key={METALS_KEY}&currency=INR&unit=toz"
        r_inr = requests.get(url_inr, timeout=10).json()
        save("metals_prices.json", {
            "updated": utcnow(),
            "source": "metals.dev",
            "usd": {
                "gold": metals.get("gold"),
                "silver": metals.get("silver"),
                "platinum": metals.get("platinum"),
                "palladium": metals.get("palladium")
            },
            "inr": r_inr.get("metals", {}),
            "currencies": r.get("currencies", {})
        })
    except Exception as e:
        print(f"  ✗ metals.dev error: {e}")

# ═══════════════════════════════════════
# 3. FRED MACRO DATA — St. Louis Fed
# Series: GOLDAMGBD228NLBM, DTWEXBGS, FEDFUNDS, DFF
# ═══════════════════════════════════════
def fred_series(series_id, limit=365):
    if not FRED_KEY:
        return []
    try:
        url = f"https://api.stlouisfed.org/fred/series/observations"
        params = {
            "series_id": series_id,
            "api_key": FRED_KEY,
            "file_type": "json",
            "sort_order": "desc",
            "limit": limit
        }
        r = requests.get(url, params=params, timeout=15).json()
        obs = r.get("observations", [])
        return [{"date": o["date"], "value": o["value"]} for o in obs if o["value"] != "."]
    except Exception as e:
        print(f"  ✗ FRED {series_id} error: {e}")
        return []

def sync_fred():
    print("→ FRED macro data (St. Louis Fed)...")
    if not FRED_KEY:
        print("  ✗ FRED_API_KEY not set"); return
    lbma      = fred_series("GOLDAMGBD228NLBM", 365)   # LBMA gold price daily
    dxy       = fred_series("DTWEXBGS", 365)            # USD broad index
    fedfunds  = fred_series("FEDFUNDS", 60)             # Fed funds rate monthly
    save("fred_macro.json", {
        "updated": utcnow(),
        "source": "FRED — St. Louis Fed",
        "attribution": "Source: FRED, Federal Reserve Bank of St. Louis",
        "lbma_gold_usd": lbma[:90],       # last 90 days for charts
        "usd_index": dxy[:90],
        "fed_funds_rate": fedfunds[:24],   # last 24 months
        "latest_gold": lbma[0] if lbma else None,
        "latest_dxy": dxy[0] if dxy else None,
        "latest_fed_rate": fedfunds[0] if fedfunds else None
    })

# ═══════════════════════════════════════
# 4. UN COMTRADE — HS 7108 Gold flows
# India (356), UAE (784), Switzerland (756)
# ═══════════════════════════════════════
def sync_comtrade():
    print("→ UN Comtrade HS 7108 trade flows...")
    key = COMTRADE_KEY or COMTRADE_KEY_SECONDARY
    if not key:
        print("  ✗ COMTRADE_API_KEY not set"); return
    if not COMTRADE_KEY and COMTRADE_KEY_SECONDARY:
        print("  ℹ Using secondary Comtrade key")
    try:
        # India gold imports (last available year)
        headers = {"Ocp-Apim-Subscription-Key": key}
        url = "https://comtradeapi.un.org/data/v1/get/C/A/HS"
        params = {
            "reporterCode": "356",     # India
            "cmdCode": "7108",         # Gold
            "flowCode": "M",           # Imports
            "period": "2023",
            "partnerCode": "0",        # World
            "includeDesc": "true"
        }
        r = requests.get(url, params=params, headers=headers, timeout=30)
        india_data = r.json().get("data", [])[:10]

        # UAE gold exports
        params2 = {**params, "reporterCode": "784", "flowCode": "X"}
        r2 = requests.get(url, params=params2, headers=headers, timeout=30)
        uae_data = r2.json().get("data", [])[:10]

        save("comtrade_gold.json", {
            "updated": utcnow(),
            "source": "UN Comtrade — HS 7108",
            "note": "Annual data, HS classification, 2023",
            "india_imports_2023": india_data,
            "uae_exports_2023": uae_data
        })
    except Exception as e:
        print(f"  ✗ Comtrade error: {e}")

# ═══════════════════════════════════════
# 5. DATA.GOV.IN — India open gold datasets
# ═══════════════════════════════════════
def sync_datagov():
    print("→ data.gov.in (India DGFT/MoCI)...")
    if not DATAGOV_KEY:
        print("  ✗ DATAGOV_API_KEY not set"); return
    try:
        # Search for gold-related datasets
        # Using a known DGFT gold import dataset
        url = "https://api.data.gov.in/resource/9ef84268-d588-465a-a308-a864a43d0070"
        params = {
            "api-key": DATAGOV_KEY,
            "format": "json",
            "limit": "50",
            "filters[commodity]": "GOLD"
        }
        r = requests.get(url, params=params, timeout=15)
        if r.status_code == 200:
            data = r.json()
            save("datagov_gold.json", {
                "updated": utcnow(),
                "source": "data.gov.in",
                "total": data.get("total", 0),
                "records": data.get("records", [])[:20]
            })
        else:
            # Fallback: save status
            save("datagov_gold.json", {
                "updated": utcnow(),
                "source": "data.gov.in",
                "status": r.status_code,
                "note": "Dataset may require specific resource ID"
            })
    except Exception as e:
        print(f"  ✗ data.gov.in error: {e}")

# ═══════════════════════════════════════
# 6. OFAC SDN — US Sanctions (free, no key)
# ═══════════════════════════════════════
def sync_ofac():
    print("→ OFAC SDN list (US Treasury)...")
    try:
        r = requests.get(
            "https://ofac.treasury.gov/downloads/sdn.json",
            timeout=30
        )
        sdn = r.json()
        entries = sdn.get("sdnList", {}).get("sdnEntry", [])
        # Filter gold-relevant
        keywords = ["gold", "precious", "bullion", "jewel", "metal", "mineral"]
        gold_entries = [
            e for e in entries
            if any(k in json.dumps(e).lower() for k in keywords)
        ][:30]
        save("ofac_gold.json", {
            "updated": utcnow(),
            "source": "OFAC — US Treasury",
            "total_sdn": len(entries),
            "gold_relevant_count": len(gold_entries),
            "gold_entries": gold_entries[:10]
        })
    except Exception as e:
        print(f"  ✗ OFAC error: {e}")

# ═══════════════════════════════════════
# 7. DRI PRESS RELEASES — India seizures
# ═══════════════════════════════════════
def sync_dri():
    print("→ DRI press releases (dri.nic.in)...")
    try:
        import re
        from html.parser import HTMLParser
        r = requests.get(
            "https://dri.nic.in/main/prelease",
            headers={"User-Agent": "Mozilla/5.0"},
            timeout=15
        )
        text = r.text
        # Simple extraction — find gold mentions
        lines = text.split('\n')
        gold_items = []
        for line in lines:
            if 'gold' in line.lower() and ('seize' in line.lower() or 'recover' in line.lower() or 'arrest' in line.lower()):
                clean = re.sub(r'<[^>]+>', '', line).strip()
                if len(clean) > 20:
                    wt = re.search(r'(\d+(?:\.\d+)?)\s*(?:kg|grams?|g)\b', clean, re.I)
                    gold_items.append({
                        "text": clean[:200],
                        "weight": wt.group(0) if wt else None,
                        "kerala": any(k in clean.lower() for k in ["calicut","kochi","trivandrum","kerala","kozhikode","thrissur"])
                    })
        save("dri_seizures.json", {
            "updated": utcnow(),
            "source": "dri.nic.in",
            "total_found": len(gold_items),
            "kerala_count": sum(1 for i in gold_items if i.get("kerala")),
            "seizures": gold_items[:20]
        })
    except Exception as e:
        print(f"  ✗ DRI scraper error: {e}")

# ═══════════════════════════════════════
# 8. MASTER MANIFEST
# ═══════════════════════════════════════
def write_manifest():
    save("manifest.json", {
        "last_sync": utcnow(),
        "version": "2.0",
        "sources": [
            {"id": "gold_price", "name": "gold-api.com", "free": True},
            {"id": "metals_prices", "name": "metals.dev", "free": True},
            {"id": "fred_macro", "name": "FRED — St. Louis Fed", "free": True},
            {"id": "comtrade_gold", "name": "UN Comtrade HS 7108", "free": True},
            {"id": "datagov_gold", "name": "data.gov.in DGFT", "free": True},
            {"id": "ofac_gold", "name": "OFAC SDN — US Treasury", "free": True},
            {"id": "dri_seizures", "name": "DRI — dri.nic.in", "free": True}
        ]
    })

if __name__ == "__main__":
    print("═" * 50)
    print("Bucks Intelligence Sync — starting")
    print(f"Time: {utcnow()}")
    print("═" * 50)
    sync_price()
    sync_metals()
    sync_fred()
    sync_comtrade()
    sync_datagov()
    sync_ofac()
    sync_dri()
    write_manifest()
    print("═" * 50)
    print("All syncs complete.")
