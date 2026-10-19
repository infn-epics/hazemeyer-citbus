#!../../bin/linux-x86_64/hzacc

# Hazemeyer CHV TL "accumulatore" (8 channels 10 A, 15/20 V) - MMU Modbus

< envPaths

epicsEnvSet("P",       "SPARC:MAG")
epicsEnvSet("SLAVE",   "1")
# the cubicle is named after its slave address (as the ibek hazemeyer.cit entity)
epicsEnvSet("CUB",     "CIT$(SLAVE)")
epicsEnvSet("TIMEOUT", "1000")
# dbLoadRecords looks for included templates here
epicsEnvSet("EPICS_DB_INCLUDE_PATH", "$(TOP)/db")

## Register all support components
dbLoadDatabase "$(TOP)/dbd/hzacc.dbd"
hzacc_registerRecordDeviceDriver(pdbbase)

# The MMU speaks Modbus on its RS485 port (top panel DB9 connector).
# Through a serial/Ethernet gateway (Modbus RTU over raw TCP):
drvAsynIPPortConfigure("HZACC_ASYN", "192.168.197.102:4001", 0, 0, 1)
# or on a local serial port:
# drvAsynSerialPortConfigure("HZACC_ASYN", "/dev/ttyUSB0", 0, 0, 0)
# asynSetOption("HZACC_ASYN", 0, "baud",   "9600")
# asynSetOption("HZACC_ASYN", 0, "bits",   "8")
# asynSetOption("HZACC_ASYN", 0, "parity", "none")
# asynSetOption("HZACC_ASYN", 0, "stop",   "1")

# modbusInterposeConfig(portName, linkType, timeoutMsec, writeDelayMsec) linkType 1 = RTU
modbusInterposeConfig("HZACC_ASYN", 1, 2000, 50)

## Modbus Function Codes
# 3 Read Holding Registers | 4 Read Input Registers | 6 Write Single Register
#
# drvModbusAsynConfigure(portName, tcpPortName, slaveAddress, modbusFunction,
#                        modbusStartAddress, modbusLength, dataType, pollMsec, plcType)
# The record asyn addresses are relative to the start addresses below.

# Read word area $0080-$00CB in two blocks (keep each reply below the 104 bytes
# a gateway may put in one TCP segment: the modbus RTU layer needs it in one read)
# $0080-$009F: mains measurements
drvModbusAsynConfigure("HZACC_MEAS",  "HZACC_ASYN", $(SLAVE), 3, 0x80, 32, 0, 500, "HAZEMEYER")
# $00A0-$00CB: MAU output voltage/current, general and MAU statuses
drvModbusAsynConfigure("HZACC_MEAS2", "HZACC_ASYN", $(SLAVE), 3, 0xA0, 44, 0, 500, "HAZEMEYER")
# Read bit area $0020-$003F read as words: general and MAU fault / status words
drvModbusAsynConfigure("HZACC_STS",  "HZACC_ASYN", $(SLAVE), 3, 0x20, 32, 0, 1000, "HAZEMEYER")
# Write bit area $0000-$001F written as words: general and MAU commands
drvModbusAsynConfigure("HZACC_CMD",  "HZACC_ASYN", $(SLAVE), 6, 0x00, 32, 0, 1, "HAZEMEYER")
# Write word area $0060-$0067: MAU current settings (read once at boot)
drvModbusAsynConfigure("HZACC_ISET", "HZACC_ASYN", $(SLAVE), 6, 0x60, 8, 0, 1, "HAZEMEYER")

## Load databases
dbLoadRecords("$(TOP)/db/hzacc_cubicle.db", "P=$(P),R=$(CUB),PORT_MEAS=HZACC_MEAS,PORT_MEAS2=HZACC_MEAS2,PORT_CMD=HZACC_CMD,TIMEOUT=$(TIMEOUT)")
dbLoadTemplate("$(TOP)/db/hzacc_channels.substitutions", "P=$(P),CUB=$(CUB),PORT_MEAS2=HZACC_MEAS2,PORT_STS=HZACC_STS,PORT_CMD=HZACC_CMD,PORT_ISET=HZACC_ISET,TIMEOUT=$(TIMEOUT),IMAX=10,VMAX=20,RAWMAX_SP=2048,RAWMAX_RB=8192")

iocInit

# Modbus traffic debugging
#asynSetTraceIOMask("HZACC_ASYN", 0, 4)
#asynSetTraceMask("HZACC_ASYN", 0, 9)
