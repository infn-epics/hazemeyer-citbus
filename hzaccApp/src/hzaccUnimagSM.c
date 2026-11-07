/* hzaccUnimagSM.c - UNIMAG state machine of a Hazemeyer CITBus channel
 *
 * The MMU does not always apply a command (current setting or MAU Power
 * On/Off): this aSub routine checks that every command takes effect and
 * sends it again (RETRY times) when it does not.
 *
 * STATE_SM (VALA):
 *   0 READY        idle, last command done
 *   1 GOTOSET      waiting for CURRENT_RB to reach CURRENT_SP (SET_TOLERANCE)
 *   2 GOTOSTATE    waiting for STATE_BASE to reach the commanded state
 *   3 GOZERO       waiting for the current to reach zero (ZERO_TOLERANCE):
 *                  zero setpoint, or ramp down before Power Off
 *   4 GOPOS        (polarity change, not used: the MAUs are bipolar)
 *   5 GONEG        (polarity change, not used)
 *   6 SPNOTSET     setpoint not reached after RETRY retries (warning)
 *   7 STATENOTSET  state not reached after RETRY retries, or lost (error)
 * SPNOTSET and STATENOTSET stay until the next command; RESET always brings
 * the machine back to READY and drops any retry in progress.
 *
 * Inputs (all double, NPP):
 *   A CURRENT_SP      B CURRENT_RB      C STATE_SP (0 OFF 1 ON 2 STANDBY 3 RESET)
 *   D STATE_BASE (0 OFF 1 ON 2 STANDBY 3 FAULT 4 EXT_INTLK 5 CONN_FAULT)
 *   E SET_TOLERANCE   F ZERO_TOLERANCE  G SET_TIMEOUT_S     H RETRY
 *   I SP_EVT (counts CURRENT_SP writes)  J ST_EVT (counts STATE_SP writes)
 * Outputs (all double):
 *   VALA STATE_SM     VALB RETRY_COUNT  VALC current to send (A, changes
 *   only with action 1)
 *   VALD action: 0 none, 1 send VALC, 2 channel ON, 3 channel OFF
 */

#include <math.h>
#include <stdlib.h>
#include <string.h>

#include <aSubRecord.h>
#include <menuFtype.h>
#include <epicsTime.h>
#include <errlog.h>
#include <recGbl.h>
#include <registryFunction.h>
#include <epicsExport.h>

enum { SM_READY, SM_GOTOSET, SM_GOTOSTATE, SM_GOZERO, SM_GOPOS, SM_GONEG,
       SM_SPNOTSET, SM_STATENOTSET };
enum { ACT_NONE, ACT_SET, ACT_ON, ACT_OFF };
enum { WANT_NONE = -1, WANT_OFF = 0, WANT_ON = 1 };

static const char *smName[] = { "READY", "GOTOSET", "GOTOSTATE", "GOZERO",
                                "GOPOS", "GONEG", "SPNOTSET", "STATENOTSET" };

typedef struct {
    int    init;
    int    state;
    int    retries;
    int    want;         /* commanded state, WANT_NONE after RESET / boot */
    int    spArmed;      /* CURRENT_SP written since boot */
    int    offAfterZero; /* GOZERO is the ramp down before Power Off */
    int    spPending;    /* CURRENT_SP write still to send */
    double lastSpEvt, lastStEvt;
    double t0;           /* timer start (s) */
    double best;         /* best setpoint error since t0 */
    double mismatchT0;   /* READY: state mismatch since (0 = none) */
    double iset;         /* last current sent (VALC) */
} smCtx;

static double nowS(void)
{
    return epicsMonotonicGet() * 1e-9;
}

static double in(aSubRecord *prec, int i)
{
    return *(double *)(&prec->a)[i];
}

static void out(aSubRecord *prec, int i, double v)
{
    *(double *)(&prec->vala)[i] = v;
}

static long hzaccSmInit(aSubRecord *prec)
{
    int i;
    for (i = 0; i < 10; i++) {
        if ((&prec->fta)[i] != menuFtypeDOUBLE) {
            errlogPrintf("%s: input %c must be DOUBLE\n", prec->name, 'A' + i);
            return -1;
        }
    }
    for (i = 0; i < 4; i++) {
        if ((&prec->ftva)[i] != menuFtypeDOUBLE) {
            errlogPrintf("%s: output VAL%c must be DOUBLE\n", prec->name, 'A' + i);
            return -1;
        }
    }
    prec->dpvt = calloc(1, sizeof(smCtx));
    return prec->dpvt ? 0 : -1;
}

static void go(aSubRecord *prec, smCtx *c, int state)
{
    if (c->state != state)
        errlogPrintf("%s: %s -> %s (retries %d)\n", prec->name,
                     smName[c->state], smName[state], c->retries);
    c->state = state;
}

/* distance from the target; a target within ZERO_TOLERANCE is zero */
static double spErr(double tgt, double rb, double ztol)
{
    return fabs(tgt) <= ztol ? fabs(rb) : fabs(rb - tgt);
}

static double spTol(double tgt, double tol, double ztol)
{
    return fabs(tgt) <= ztol ? ztol : tol;
}

static long hzaccSmProcess(aSubRecord *prec)
{
    smCtx *c = (smCtx *)prec->dpvt;
    double sp = in(prec, 0), rb = in(prec, 1);
    int    stSp = (int)in(prec, 2), base = (int)in(prec, 3);
    double tol = in(prec, 4), ztol = in(prec, 5), tmo = in(prec, 6);
    int    maxr = (int)in(prec, 7);
    double spEvtCnt = in(prec, 8), stEvtCnt = in(prec, 9);
    double now = nowS(), iset = sp, tgt, e;
    int    act = ACT_NONE, stEvt, spEvt;
    int    isOn = base == 1, fault = base >= 3 && base <= 5;
    int    verify = tol > 0;

    if (!c)
        return -1;
    if (!c->init) {
        /* the counters may already be non zero: no event at boot */
        c->init = 1;
        c->want = WANT_NONE;
        c->lastSpEvt = spEvtCnt;
        c->lastStEvt = stEvtCnt;
    }
    stEvt = stEvtCnt != c->lastStEvt;
    spEvt = spEvtCnt != c->lastSpEvt || c->spPending;
    c->lastStEvt = stEvtCnt;
    c->lastSpEvt = spEvtCnt;
    c->spPending = 0;
    if (maxr < 0)
        maxr = 0;

    /* ---------- state command ---------- */
    if (stEvt) {
        c->retries = 0;
        c->offAfterZero = 0;
        c->mismatchT0 = 0;
        c->t0 = now;
        if (stSp == 3) {                        /* RESET */
            c->want = WANT_NONE;
            go(prec, c, SM_READY);
        } else if (stSp == 1) {                 /* ON */
            c->want = WANT_ON;
            act = ACT_ON;
            go(prec, c, SM_GOTOSTATE);
        } else {                                /* OFF, STANDBY */
            c->want = WANT_OFF;
            if (isOn && verify && c->spArmed && fabs(rb) > ztol) {
                /* ramp down first; CURRENT_SP is sent again at the next ON */
                c->offAfterZero = 1;
                c->best = fabs(rb);
                iset = 0;
                act = ACT_SET;
                go(prec, c, SM_GOZERO);
            } else {
                act = ACT_OFF;
                go(prec, c, SM_GOTOSTATE);
            }
        }
    }

    /* ---------- setpoint command ---------- */
    if (spEvt) {
        c->spArmed = 1;
        if (c->offAfterZero) {
            /* going off: keep the new setpoint for the next ON */
        } else if (act != ACT_NONE) {
            c->spPending = 1;                   /* one action per pass */
        } else {
            act = ACT_SET;
            iset = sp;
            if (isOn && c->state != SM_GOTOSTATE) {
                c->retries = 0;
                c->t0 = now;
                c->best = spErr(sp, rb, ztol);
                go(prec, c, !verify ? SM_READY :
                            fabs(sp) <= ztol ? SM_GOZERO : SM_GOTOSET);
            }
        }
    }

    /* ---------- progress ---------- */
    if (!stEvt && !spEvt) {
        switch (c->state) {
        case SM_READY:
            if (fault || c->want == WANT_NONE) {
                c->mismatchT0 = 0;
                break;
            }
            /* commanded state lost without a fault (e.g. local operation) */
            if ((c->want == WANT_ON) != isOn) {
                if (c->mismatchT0 == 0)
                    c->mismatchT0 = now;
                else if (now - c->mismatchT0 >= tmo)
                    go(prec, c, SM_STATENOTSET);
            } else {
                c->mismatchT0 = 0;
            }
            break;

        case SM_GOTOSTATE:
            if (fault) {
                go(prec, c, SM_STATENOTSET);
            } else if (c->want == WANT_ON ? isOn : !isOn) {
                if (c->want == WANT_ON && verify && c->spArmed) {
                    /* the MMU may not hold the setting: send it again */
                    act = ACT_SET;
                    iset = sp;
                    c->retries = 0;
                    c->t0 = now;
                    c->best = spErr(sp, rb, ztol);
                    go(prec, c, fabs(sp) <= ztol ? SM_GOZERO : SM_GOTOSET);
                } else {
                    go(prec, c, SM_READY);
                }
            } else if (now - c->t0 >= tmo) {
                if (c->retries < maxr) {
                    c->retries++;
                    c->t0 = now;
                    act = c->want == WANT_ON ? ACT_ON : ACT_OFF;
                    errlogPrintf("%s: state not reached, retry %d/%d\n",
                                 prec->name, c->retries, maxr);
                } else {
                    go(prec, c, SM_STATENOTSET);
                }
            }
            break;

        case SM_GOTOSET:
        case SM_GOZERO:
            tgt = c->offAfterZero ? 0 : sp;
            e = spErr(tgt, rb, ztol);
            if (fault) {
                go(prec, c, SM_STATENOTSET);
            } else if (!isOn) {
                if (c->offAfterZero) {          /* off anyway: done */
                    c->offAfterZero = 0;
                    go(prec, c, SM_READY);
                } else {
                    go(prec, c, SM_STATENOTSET);
                }
            } else if (e <= spTol(tgt, tol, ztol)) {
                if (c->offAfterZero) {
                    c->offAfterZero = 0;
                    c->retries = 0;
                    c->t0 = now;
                    act = ACT_OFF;
                    go(prec, c, SM_GOTOSTATE);
                } else {
                    go(prec, c, SM_READY);
                }
            } else if (e < c->best - spTol(tgt, tol, ztol) / 20) {
                c->best = e;                    /* progress: restart timer */
                c->t0 = now;
            } else if (now - c->t0 >= tmo) {
                if (c->retries < maxr) {
                    c->retries++;
                    c->t0 = now;
                    c->best = e;
                    act = ACT_SET;
                    iset = tgt;
                    errlogPrintf("%s: setpoint %.3f not reached (rb %.3f), "
                                 "retry %d/%d\n", prec->name, tgt, rb,
                                 c->retries, maxr);
                } else if (c->offAfterZero) {
                    /* zero not reached: switch off all the same */
                    c->offAfterZero = 0;
                    c->retries = 0;
                    c->t0 = now;
                    act = ACT_OFF;
                    go(prec, c, SM_GOTOSTATE);
                } else {
                    go(prec, c, SM_SPNOTSET);
                }
            }
            break;

        default:                                /* SPNOTSET, STATENOTSET */
            break;
        }
    }

    out(prec, 0, c->state);
    out(prec, 1, c->retries);
    /* VALC only changes with a send: SM_ACT reads it from a callback */
    if (act == ACT_SET)
        c->iset = iset;
    out(prec, 2, c->iset);
    out(prec, 3, act);
    return 0;
}

epicsRegisterFunction(hzaccSmInit);
epicsRegisterFunction(hzaccSmProcess);
