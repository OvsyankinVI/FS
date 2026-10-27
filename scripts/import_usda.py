#!/usr/bin/env python3
"""Import USDA FoodData Central Foundation Foods / SR Legacy CSV archives.

Usage:
  python3 scripts/import_usda.py path/to/foundation.zip path/to/sr_legacy.zip --dry-run
  SUPABASE_URL=... SUPABASE_SECRET_KEY=... python3 scripts/import_usda.py path/to/*.zip --apply

Requires Python 3.10+; no third-party dependencies. Never run --apply from a browser.
"""
import argparse, csv, io, json, os, sys, time, urllib.request, zipfile

NUTRIENTS = {
    "protein": (1003,),
    "fat": (1004,),
    "carbs": (1005,),
    "energy": (1008, 2047, 2048),
}
def open_csv(archive, filename):
    names = [n for n in archive.namelist() if n.lower().endswith("/" + filename) or n.lower() == filename]
    if len(names) != 1:
        raise ValueError(f"Expected one {filename}, found {names}")
    return csv.DictReader(io.TextIOWrapper(archive.open(names[0]), encoding="utf-8-sig", newline=""))

def parse_archive(path):
    with zipfile.ZipFile(path) as z:
        foods = {}
        for row in open_csv(z, "food.csv"):
            if row.get("data_type") in ("Foundation", "SR Legacy"):
                foods[row["fdc_id"]] = {"fdc_id": int(row["fdc_id"]), "data_type": row["data_type"],
                    "name_en": row["description"], "name_ru": None, "source_release": os.path.basename(path)}
        vals = {}
        for row in open_csv(z, "food_nutrient.csv"):
            fid = row.get("fdc_id")
            if fid not in foods: continue
            try: amount = float(row["amount"])
            except (TypeError, ValueError): continue
            if amount < 0: continue
            nutrient = int(row["nutrient_id"])
            vals.setdefault(fid, {})[nutrient] = amount
        result = []
        for fid, food in foods.items():
            v = vals.get(fid, {})
            def first(ids):
                return next((v[i] for i in ids if i in v), None)
            p, f, c, e = (first(NUTRIENTS[k]) for k in ("protein", "fat", "carbs", "energy"))
            if None in (p, f, c, e): continue
            if not (0 <= p <= 100 and 0 <= f <= 100 and 0 <= c <= 100 and 0 <= e <= 900): continue
            food.update(kcal_per_100g=round(e, 3), protein_per_100g=round(p, 3),
                        fat_per_100g=round(f, 3), carbs_per_100g=round(c, 3))
            result.append(food)
        return result

def upload(rows, url, key):
    base = url.rstrip("/") + "/rest/v1/usda_foods?on_conflict=fdc_id"
    headers = {"apikey": key, "Content-Type": "application/json",
               "Content-Profile": "fitness", "Prefer": "resolution=merge-duplicates,return=minimal"}
    if not key.startswith("sb_secret_"): headers["Authorization"] = "Bearer " + key
    for offset in range(0, len(rows), 100):
        data = json.dumps(rows[offset:offset+100], ensure_ascii=False).encode("utf-8")
        req = urllib.request.Request(base, data=data, headers=headers, method="POST")
        for attempt in range(3):
            try:
                with urllib.request.urlopen(req, timeout=30) as res:
                    if res.status not in (200, 201, 204): raise RuntimeError(res.status)
                break
            except Exception:
                if attempt == 2: raise
                time.sleep(2 ** attempt)
        print(f"Imported {min(offset+100,len(rows))}/{len(rows)}", file=sys.stderr)

def main():
    p = argparse.ArgumentParser()
    p.add_argument("archives", nargs="+")
    g = p.add_mutually_exclusive_group(required=True)
    g.add_argument("--dry-run", action="store_true")
    g.add_argument("--apply", action="store_true")
    a = p.parse_args()
    rows = {}
    for path in a.archives:
        for row in parse_archive(path): rows[row["fdc_id"]] = row
    result = list(rows.values())
    by_type = {t: sum(r["data_type"] == t for r in result) for t in ("Foundation", "SR Legacy")}
    print(json.dumps({"valid_foods":len(result),"by_type":by_type,"sample":result[:3]}, ensure_ascii=False, indent=2))
    if a.apply:
        url, key = os.getenv("SUPABASE_URL"), os.getenv("SUPABASE_SECRET_KEY")
        if not url or not key: raise SystemExit("SUPABASE_URL and SUPABASE_SECRET_KEY required")
        upload(result, url, key)
if __name__ == "__main__": main()
