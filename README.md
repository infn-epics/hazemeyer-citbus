# Hazemeyer CHV TL "accumulatore" EPICS IOC

EPICS IOC for the Hazemeyer CHV TL cubicle with 8 channels (10 A, 15/20 V),
controlled through the Main Monitoring Unit (MMU) Modbus link
(see `docs/Hazemeyer CHV TL-accumulatore 10A 15o20V remote.pdf`).

The other Hazemeyer families (serial, IOCast) live in `../hazemeyer-lnf`; this
IOC follows the same layout and the same UNIMAG PV interface.

## Architecture

Each channel is driven by a Monitoring Auxiliary Unit (MAU0..MAU7, chanel #1..#8
of the drawings). The MAUs talk to the MMU over the internal CITBus, and the MMU
is the Modbus slave (RS485, top panel DB9) for the whole cubicle.

The IOC therefore exposes:

- **the cubicle** (`$(P):$(CUB):...`, `hzacc_cubicle.db`): general state machine
  (Off / Energized / Standby / Power On / Faulty), general faults, mains measurements;
- **8 channels** (`$(P):$(CUB):CHn:...` by default, `hzacc_channel.template` loaded
  by `hzacc_channels.substitutions`). Each one is a UNIMAG power supply.

## Modbus map

| Word address | Access | Content | Port (asyn addr 0) |
|--------------|--------|---------|--------------------|
| `$0000` | write | general commands: B0 Standby, B1 Power On, B2 Power Off, B3 Reset, B4 active energy reset, B5 reactive energy reset | `HZACC_CMD` (`$0000`) |
| `$0010+2n` | write | MAUn commands: B0 Power On, B1 Power Off, B2 Reset | `HZACC_CMD` |
| `$0020` / `$0021` | read | general faults / general statuses (bit area) | `HZACC_STS` (`$0020`) |
| `$0030+2n` | read | MAUn faults: B0 ballast over-temp, B1 fuses, B2 DC over-voltage, B3 DC over-current, B4 communication failure | `HZACC_STS` |
| `$0031+2n` | read | MAUn status: B0 power, B1 local/remote | `HZACC_STS` |
| `$0060+n` | write | MAUn current setting | `HZACC_ISET` (`$0060`) |
| `$0080-$009D` | read | mains: U, I, P, Q, S, PF per phase and total/average, energies (MSW/LSW), earth fault current, frequency | `HZACC_MEAS` (`$0080`) |
| `$00A0+4n` / `$00A1+4n` | read | MAUn output current / voltage | `HZACC_MEAS2` (`$00A0`) |
| `$00C0` / `$00C1` | read | copies of `$0020` / `$0021` | `HZACC_MEAS2` |
| `$00C2` / `$00C3` | read | MAU ready (bit n: 1 Ready, 0 Faulty) / MAU power (bit n: 1 On, 0 Off) | `HZACC_MEAS` |
| `$00C4+n` | read | MAUn output current (copy of `$00A0+4n`) | `HZACC_MEAS2` |

The bit areas are read and written as words (FC3 / FC6) at their word
addresses, like the other Hazemeyer IOCs. The states and readbacks only use
the word area (`$0080-$00CB`); the bit area port `HZACC_STS` only adds the
detailed MAU faults. If the MMU refuses word access to the bit area, only those
detailed faults are lost.

The word area is read in two blocks, `$0080-$009F` (32 words) and
`$00A0-$00CB` (44 words). Serial/Ethernet gateways such as the Moxa NPort
split a long reply into TCP segments of at most 104 bytes, and the modbus RTU
layer reads the reply in a single `read()` and checks its CRC, so a 76-word
reply (157 bytes) always fails with a CRC error. Keep every read at or below 48
words (101 bytes).

Commands are pulsed: the IOC writes the code to the command word and clears it
after `PULSE` seconds (default 0.5). A command issued while a pulse is still
running goes out as soon as that pulse ends (the latest command wins).

## UNIMAG interface

Every channel and the cubicle have `STATE_SP` / `STATE_RB` with the shared
UNIMAG states:

| Value | State | Cubicle | Channel |
|-------|-------|---------|---------|
| 0 | `OFF` | Energized (001) | power bit 0 |
| 1 | `ON` | Power On (111) | power bit 1, cubicle in Power On |
| 2 | `STANDBY` | Standby (011) | power bit 1, cubicle not in Power On (no current) |
| 3 | `FAULT` | Faulty (000 / 010) | MAU not ready |
| 4 | `EXT_INTLK` | - | cubicle faulty |
| 5 | `CONN_FAULT` | status word cannot be read | ready word cannot be read, or MAU CITBus failure |
| 6 | `SP_NOT_REACHED` | - | current setpoint not reached |
| 7 | `ST_NOT_REACHED` | commanded state not reached | commanded state not reached |

`STATE_SP` accepts `OFF`, `ON`, `STANDBY` and `RESET`.

- Cubicle: `OFF` sends Power Off, `STANDBY` Standby, `RESET` Remote Reset. `ON`
  sends Standby first when the cubicle is energized, then Power On after `ON_DLY`
  seconds (default 3), since Power On is only accepted from Standby.
- Channel: `ON` sends MAU Power On, `OFF` and `STANDBY` MAU Power Off, `RESET` MAU Reset.
  The MAUs only deliver current with the cubicle in Power On, so a channel `ON`
  also switches the cubicle `ON` when it is energized or in standby, and sends
  MAU Power On once the cubicle power bit is set (`ON_PENDING` meanwhile). With
  the cubicle faulty or unreachable nothing is sent: reset the cubicle first.
  A channel `OFF` never switches the cubicle off.

The watchdog settings `SET_TOLERANCE` (default 0.1 A), `ZERO_TOLERANCE`
(default 0.05 A) and `SET_TIMEOUT_S` (default 30 s) are db macros and live PVs,
as in `../hazemeyer-lnf`.

### Channel PVs (`$(P):$(R):`)

| PV | Description |
|----|-------------|
| `CURRENT_SP` | current setpoint (A) |
| `SET_CURRENT_RB` | current setting held by the MMU (A) |
| `CURRENT_RB`, `VOLTAGE_RB` | output current (A) / voltage (V) |
| `STATE_SP`, `STATE_RB` | UNIMAG state |
| `READY`, `OPERATIONAL`, `ALL_FAULT` | MAU ready, power status, fault (= not ready) |
| `BALLAST_OT`, `FUSE_FAULT`, `DC_OVERVOLTAGE`, `DC_OVERCURRENT`, `COMM_FAIL` | MAU detailed faults |
| `LOC_REM` | local / remote (copy of the cubicle `LOC_REM`) |
| `ON_PENDING` | channel ON waiting for the cubicle to reach Power On |
| `RAW_*`, `CMD_WORD`, `MAU_FAULTS`, `MAU_STATUS` | raw Modbus values |

### Cubicle PVs (`$(P):$(CUB):`)

| PV | Description |
|----|-------------|
| `STATE_SP`, `STATE_RB` | UNIMAG state of the cubicle |
| `READY`, `STANDBY_STS`, `POWER_STS`, `LOC_REM`, `RESET_PB` | general statuses |
| `TRANSFO_OT`, `RECTIFIER_OT`, `CHOKE_OT`, `FUSE_FAULT`, `EARTH_FAULT`, `USER_FAULT1..5`, `DOOR_OPEN`, `CABINET_OT` | general faults |
| `ALL_FAULT` | any general fault, or cubicle not ready |
| `MAINS_U1..3`, `MAINS_U_AVG`, `MAINS_I1..3`, `MAINS_I_AVG`, `MAINS_P1..3`, `MAINS_P_TOT`, `MAINS_Q*`, `MAINS_S*`, `MAINS_PF*`, `MAINS_FREQ`, `EARTH_CURRENT_RB` | mains measurements |
| `MAINS_ACT_ENERGY`, `MAINS_REACT_ENERGY` | energy counters (32 bit, MSW first) |
| `ACT_ENERGY_RST`, `REACT_ENERGY_RST` | write 1 to reset the energy counters |
| `MAU_READY`, `MAU_POWER` | raw MAU ready / power words |
| `SWVER` | IOC software version |

## Macros

| Macro | Where | Description | Default |
|-------|-------|-------------|---------|
| `P` | all | PV prefix | - |
| `CUB` / `R` | all | cubicle name (`CIT<slave address>`); `R` of each channel in `hzacc_channels.substitutions` | - / `$(CUB):CHn` |
| `PORT_MEAS`, `PORT_MEAS2`, `PORT_STS`, `PORT_CMD`, `PORT_ISET` | all | modbus ports | - |
| `TIMEOUT` | all | asyn timeout (ms) | - |
| `IMAX`, `VMAX` | channel | full scale current / voltage | 10 A / 20 V |
| `RAWMAX_SP` | channel | raw current setting at `IMAX` (signed) | 2048 |
| `RAWMAX_RB` | channel | raw current / voltage readback at `IMAX` / `VMAX` (signed) | 8192 |
| `PULSE` | all | command pulse width (s) | 0.5 |
| `ON_DLY` | cubicle | Standby to Power On delay (s) | 3 |
| `U_SLO`, `I_SLO`, `P_SLO`, `Q_SLO`, `S_SLO`, `PF_SLO`, `E_SLO`, `IE_SLO`, `F_SLO` | cubicle | raw to engineering scaling of the mains values | 1 |

## Build and run

```bash
make
cd iocBoot/iocHzAcc
../../bin/linux-x86_64/hzacc st.cmd
```

Edit `st.cmd` for the gateway address (or the local serial port), the Modbus
slave address (`SLAVE`), `P` and `CUB`. `accumulator.cmd` is the configuration
of the ACCUMULATOR correctors (two CIT modules, 16 named channels).

Phoebus panels:

- `opi/hzacc.bob`: the cubicle and its 8 channels, addressed by position as
  `$(P):CIT$(ID):CH1..CH8:...` (macros `P` and `ID` = cubicle slave address,
  default 1), e.g. `P=ACC:MAG:COR,ID=2`. With the default channel names
  these are the records; with named channels (`accumulator.cmd`, ibek) load
  `hzacc_channel_alias.template` (`P`, `R`, `CUB`, `CHN` = position 1-8) next to
  each channel to alias them, so the OPI works whatever the names;
- `opi/hzacc_channel.bob`: one channel by name (macros `P`, `R` = channel name,
  `ID` = slave address of its cubicle, shown for the cubicle state), e.g.
  `P=ACC:MAG:COR,R=CHHA1002,ID=1`.

## To check on the real cubicle

The manual leaves these open. Check them during commissioning:

1. **Raw scaling.** The manual does not say how the MAU values are encoded.
   The current scaling was measured against the reference control system:
   settings are signed with `RAWMAX_SP=2048` at `IMAX` (raw 410 = 2.000 A), and
   readbacks are signed with `RAWMAX_RB=8192` at `IMAX` (raw 1644 = 2.000 A), so
   the readback has 4 times the resolution of the setting. The voltage readback
   is assumed to use the same `RAWMAX_RB` at `VMAX`: compare it with a meter.
2. **Voltage address of MAU3..MAU7.** The handwritten table puts the current at
   `$00A0+4n` and the voltage at `$00A1+4n` for every MAU. The typed table swaps
   them for MAU3..MAU7. The IOC reads the current from `$00C4+n`, which both
   tables agree on, and the voltage from `$00A1+4n` (`VRB` column). If a voltage
   reads like a current, set `VRB` to `32+4n` for that channel.
3. **Word access to the bit areas** (`$0000-$003F`). If the MMU only accepts bit
   functions there, change `HZACC_CMD` to coils (FC5, bit addresses `$0000` and
   `$0100+$20n`) and `HZACC_STS` to FC1/FC2.
4. **Read function code** of the word area: FC3 is assumed. Use 4 in
   `drvModbusAsynConfigure` if the MMU wants input registers.
5. **Local/Remote polarity** (`LOC_REM`, `$0021` B3). 1 = REMOTE is assumed;
   the cubicle reads 0 while it accepts the remote commands.
6. **Command handshake.** The IOC assumes the command bits are read on a pulse
   (written, then cleared after `PULSE`). Lengthen `PULSE` if commands get missed.
7. **Mains scaling and units** (`*_SLO` macros, `EGU`).

## Testing without hardware

The databases were checked in a plain `softIoc` (EPICS 7.0.10), with the asyn
links stripped: all 400 records load and all 151 links connect. The state
decoding, scaling, pulsed commands, the Standby to Power On sequence and the
UNIMAG watchdogs were driven by hand and behave as described above.
