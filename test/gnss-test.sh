#!/bin/bash
# The GNSS jamming indicator (~/AGENTS.md "GNSS alert semantics"): among airborne aircraft
# with a NACp value, count NACp < 8. One is noise (uncertified GA sets), two is LOW, three
# with more than a 10% share is JAMMED. Surface targets never count.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_python_test <<'PY'
status = load_script("status/aeris-status")
gnss = status.gnss_status

def ac(nac, alt=35000):
    return {"nac_p": nac, "alt_baro": alt}

assert_equal(gnss([]), status.NA, "no aircraft gives the not-available mark")
assert_equal(gnss([ac(0, alt=0), ac(0, alt=500)]), status.NA, "surface targets alone give the not-available mark")
assert_equal(gnss([{"alt_baro": 30000}, {"nac_p": "8", "alt_baro": 30000}]), status.NA,
             "aircraft without an integer NACp are not rated")

assert_equal(gnss([ac(9)] * 10), "OK 0/10", "all accurate is OK")
assert_equal(gnss([ac(0)] + [ac(9)] * 9), "OK 1/10", "one bad contact is still OK")
assert_equal(gnss([ac(0), ac(7)] + [ac(9)] * 8), "LOW 2/10", "two bad contacts are LOW")
assert_equal(gnss([ac(0)] * 3 + [ac(9)] * 7), "JAMMED 3/10", "three bad with a 30% share is JAMMED")
assert_equal(gnss([ac(0)] * 3 + [ac(9)] * 37), "LOW 3/40", "three bad with a 7.5% share is only LOW")
assert_equal(gnss([ac(0)] * 3 + [ac(9)] * 26), "JAMMED 3/29", "three bad just over a 10% share is JAMMED")
assert_equal(gnss([ac(0, alt=0)] * 5 + [ac(9)] * 5), "OK 0/5", "a tower beacon and ground vehicles are excluded")
assert_equal(gnss([ac(0, alt=999), ac(0, alt=1000), ac(9)]), "OK 1/2", "the airborne cut is 1,000 ft inclusive")
PY
