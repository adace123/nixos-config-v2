#!/usr/bin/env python3
"""Compute the car's mileage rate (mi/month) from recorder odometer history.

Reads the Home Assistant recorder database read-only (WAL mode allows
concurrent readers) and estimates miles driven per month over the last
60 days. Falls back to 870 mi/month when there isn't enough history yet.
"""
import datetime
import pathlib
import sqlite3

LOG = pathlib.Path("/config/home-assistant_v2.db")
ENTITY = "sensor.2022_elantra_odometer"
WINDOW_DAYS = 60
FALLBACK = 870

if not LOG.exists():
    print(FALLBACK)
    raise SystemExit

con = sqlite3.connect(f"file:{LOG}?mode=ro", uri=True)
cur = con.cursor()

row = cur.execute(
    "SELECT metadata_id FROM states_meta WHERE entity_id=?", (ENTITY,)
).fetchone()
if row is None:
    print(FALLBACK)
    raise SystemExit

mid = row[0]
now = datetime.datetime.now().timestamp()
rows = cur.execute(
    "SELECT state, last_updated_ts FROM states WHERE metadata_id=? AND last_updated_ts > ? ORDER BY last_updated_ts",
    (mid, now - WINDOW_DAYS * 86400),
).fetchall()

vals = [(float(s), t) for s, t in rows if s not in ("unknown", "unavailable")]
try:
    if len(vals) >= 2:
        (v0, t0), (v1, t1) = vals[0], vals[-1]
        days = (t1 - t0) / 86400
        if days > 3 and v1 >= v0:
            print(round((v1 - v0) / days * 30.44))
            raise SystemExit
except (ValueError, TypeError):
    pass

print(FALLBACK)
