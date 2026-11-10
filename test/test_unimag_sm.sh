#!/bin/bash
# test_unimag_sm.sh - checks the UNIMAG state machine against a simulated
# channel (test/sim_channel.db), without hardware.
#
# Run from the top of the built IOC (needs caget / caput):
#   test/test_unimag_sm.sh
# In the development container:
#   docker run --rm -v $PWD:/app/hz -w /app/hz \
#       ghcr.io/infn-epics/infn-epics-ioc-base bash test/test_unimag_sm.sh

TOP=$(cd "$(dirname "$0")/.." && pwd)
D=TEST:SM:CH
TMO=2      # SET_TIMEOUT_S used by the test (s)
FAIL=0

export EPICS_CA_AUTO_ADDR_LIST=NO EPICS_CA_ADDR_LIST=127.0.0.1
export EPICS_CAS_INTF_ADDR_LIST=127.0.0.1

cat > /tmp/sm_test.cmd <<EOF
dbLoadDatabase "$TOP/dbd/hzacc.dbd"
hzacc_registerRecordDeviceDriver(pdbbase)
epicsEnvSet("EPICS_DB_INCLUDE_PATH", "$TOP/db")
dbLoadRecords("$TOP/test/sim_channel.db", "P=TEST:SM,R=CH,SET_TIMEOUT_S=$TMO,SET_TOLERANCE=0.1,ZERO_TOLERANCE=0.05,RETRY=2,SM_SCAN=.1 second")
iocInit
EOF
"$TOP/bin/linux-x86_64/hzacc" /tmp/sm_test.cmd > /tmp/sm_test.log 2>&1 < <(sleep 3600) &
IOC=$!
trap 'kill $IOC 2>/dev/null' EXIT
sleep 2

put() { caput -t "$D:$1" "$2" > /dev/null; }
get() { caget -t "$D:$1"; }
check() {   # check <pv> <expected> <what>
    local v; v=$(get "$1")
    if [ "$v" == "$2" ]; then echo "  ok   $3: $1 = $v"
    else echo "  FAIL $3: $1 = $v (expected $2)"; FAIL=1; fi
}

echo "== boot: idle"
check STATE_SM READY "not armed at boot"

echo "== setpoint reached at once"
put STATE_BASE 1; put CURRENT_RB 0
put CURRENT_SP 5; sleep 0.3
check STATE_SM GOTOSET "setpoint sent"
check I_SET 5 "current sent"
put CURRENT_RB 5; sleep 0.3
check STATE_SM READY "setpoint reached"
check STATE_RB ON "state"

echo "== setting lost by the MMU: retry"
put CURRENT_RB 5; put CURRENT_SP 3; sleep 0.3
n=$(get I_SET_CNT)
sleep $((TMO + 1))
check RETRY_COUNT 1 "first retry"
check I_SET_CNT $(echo "$n + 1" | bc) "setting sent again"
put CURRENT_RB 3; sleep 0.3
check STATE_SM READY "reached after the retry"

echo "== setpoint never reached: SPNOTSET after RETRY=2"
put CURRENT_SP 7; sleep $((TMO * 3 + 2))
check STATE_SM SPNOTSET "retries exhausted"
check RETRY_COUNT 2 "retries"
check STATE_RB ON "STATE_RB keeps the device state"
put STATE_SP RESET; sleep 0.3
check STATE_SM READY "RESET"
check STATE_RB ON "STATE_RB after RESET"

echo "== RESET interrupts retries"
put CURRENT_SP 8; sleep $((TMO + 1))
check RETRY_COUNT 1 "retrying"
put STATE_SP RESET; sleep $((TMO + 1))
check STATE_SM READY "RESET stops the retries"
check RETRY_COUNT 0 "retry counter cleared"

echo "== OFF from ON with current: GOZERO then Power Off"
put CURRENT_SP 5; put CURRENT_RB 5; sleep 0.3
check STATE_SM READY "at 5 A"
off=$(get OFF_CNT)
put STATE_SP OFF; sleep 0.3
check STATE_SM GOZERO "ramp down first"
check I_SET 0 "zero sent"
check OFF_CNT $off "no Power Off yet"
put CURRENT_RB 0.02; sleep 0.3
check STATE_SM GOTOSTATE "zero reached"
check OFF_CNT $((off + 1)) "Power Off sent"
put STATE_BASE 0; sleep 0.3
check STATE_SM READY "OFF reached"
check STATE_RB OFF "state"

echo "== ON lost by the MMU: retry, then setpoint sent again"
on=$(get ON_REQ)
put STATE_SP ON; sleep 0.3
check STATE_SM GOTOSTATE "going ON"
check ON_REQ $((on + 1)) "ON sent"
sleep $((TMO + 1))
check ON_REQ $((on + 2)) "ON sent again"
put STATE_BASE 1; sleep 0.3
check STATE_SM GOTOSET "ON reached, setpoint again"
check I_SET 5 "CURRENT_SP sent again"
put CURRENT_RB 5; sleep 0.3
check STATE_SM READY "done"

echo "== zero setpoint: GOZERO"
put CURRENT_SP 0; sleep 0.3
check STATE_SM GOZERO "zero setpoint"
put CURRENT_RB 0.04; sleep 0.3
check STATE_SM READY "within ZERO_TOLERANCE"

echo "== ON never reached: STATENOTSET"
put STATE_BASE 0; put STATE_SP OFF; sleep 0.3
put STATE_SP ON; sleep $((TMO * 3 + 2))
check STATE_SM STATENOTSET "retries exhausted"
check STATE_RB OFF "STATE_RB keeps the device state"
put STATE_SP RESET; sleep 0.3
check STATE_SM READY "RESET"

echo "== fault during a sequence: STATENOTSET"
put STATE_SP ON; sleep 0.3
put STATE_BASE 3; sleep 0.3
check STATE_SM STATENOTSET "fault"
check STATE_RB FAULT "faults win in STATE_RB"
put STATE_BASE 0; put STATE_SP RESET; sleep 0.3
check STATE_SM READY "RESET"

echo "== commanded state lost in READY: STATENOTSET, no automatic ON"
put STATE_SP OFF; sleep 0.3
check STATE_SM READY "off"
on=$(get ON_REQ)
put STATE_BASE 1; sleep $((TMO + 1))
check STATE_SM STATENOTSET "ON while OFF commanded"
check ON_REQ $on "nothing sent"
put STATE_BASE 0; put STATE_SP RESET; sleep 0.3

echo
grep -c "SM:" /tmp/sm_test.log > /dev/null && echo "state machine log:" && grep "TEST:SM" /tmp/sm_test.log | sed 's/^/  /'
[ $FAIL == 0 ] && echo "ALL OK" || echo "SOME TESTS FAILED"
exit $FAIL
