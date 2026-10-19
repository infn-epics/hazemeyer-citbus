#!../../bin/linux-x86_64/hzacc

# hazemeyer-acc-SER18006 - ACCUMULATOR correctors
# Two CIT modules (MMU Modbus slaves 1 and 2) behind the gateway
# 192.168.192.32:4005, 8 channels each, 10 A full scale. Each cubicle is
# named after its slave address (CIT<id>), as the ibek hazemeyer.cit entity does.

< envPaths

epicsEnvSet("P",       "ACC:MAG:COR")
epicsEnvSet("TIMEOUT", "1000")
epicsEnvSet("IMAX",    "10")
epicsEnvSet("VMAX",    "20")
# raw setting / readback at full scale (see hzacc_channel.template)
epicsEnvSet("RAWMAX_SP", "2048")
epicsEnvSet("RAWMAX_RB", "8192")
# dbLoadRecords looks for included templates here
epicsEnvSet("EPICS_DB_INCLUDE_PATH", "$(TOP)/db")

## Register all support components
dbLoadDatabase "$(TOP)/dbd/hzacc.dbd"
hzacc_registerRecordDeviceDriver(pdbbase)

# Serial/Ethernet gateway on the MMU RS485 link (Modbus RTU over raw TCP)
drvAsynIPPortConfigure("SER18006", "192.168.192.32:4005", 0, 0, 1)
# modbusInterposeConfig(portName, linkType, timeoutMsec, writeDelayMsec) linkType 1 = RTU
modbusInterposeConfig("SER18006", 1, 2000, 50)

# drvModbusAsynConfigure(portName, tcpPortName, slaveAddress, modbusFunction,
#                        modbusStartAddress, modbusLength, dataType, pollMsec, plcType)
# Per module: word area $0080-$00CB (read in two blocks, $0080 and $00A0: the
# gateway splits TCP segments at 104 bytes and the modbus RTU layer needs each
# reply in one piece, so every read stays at or below 48 words), bit area $0020-$003F (as words),
# commands $0000-$001F, current settings $0060-$0067 (see README.md)
# Each named channel also gets the position aliases $(P):CIT<id>:CH1..CH8:...
# (hzacc_channel_alias.template) used by opi/hzacc.bob

## Cubicle CIT1 (CITA1001 in DEVIL630) - Modbus slave 1
drvModbusAsynConfigure("CIT1_MEAS",  "SER18006", 1, 3, 0x80, 32, 0, 500, "HAZEMEYER")
drvModbusAsynConfigure("CIT1_MEAS2", "SER18006", 1, 3, 0xA0, 44, 0, 500, "HAZEMEYER")
drvModbusAsynConfigure("CIT1_STS",  "SER18006", 1, 3, 0x20, 32, 0, 1000, "HAZEMEYER")
drvModbusAsynConfigure("CIT1_CMD",  "SER18006", 1, 6, 0x00, 32, 0, 1, "HAZEMEYER")
drvModbusAsynConfigure("CIT1_ISET", "SER18006", 1, 6, 0x60, 8, 0, 1, "HAZEMEYER")
epicsEnvSet("CIT1", "CUB=CIT1,PORT_MEAS2=CIT1_MEAS2,PORT_STS=CIT1_STS,PORT_CMD=CIT1_CMD,PORT_ISET=CIT1_ISET,TIMEOUT=$(TIMEOUT),IMAX=$(IMAX),VMAX=$(VMAX),RAWMAX_SP=$(RAWMAX_SP),RAWMAX_RB=$(RAWMAX_RB)")

dbLoadRecords("$(TOP)/db/hzacc_cubicle.db", "P=$(P),R=CIT1,PORT_MEAS=CIT1_MEAS,PORT_MEAS2=CIT1_MEAS2,PORT_CMD=CIT1_CMD,TIMEOUT=$(TIMEOUT)")
dbLoadRecords("$(TOP)/db/hzacc_channel.template", "P=$(P),R=CHHA1002,$(CIT1),CH=0,IRB=36,VRB=1,FLT=16,STS=17,CMD=16,ISET=0")
dbLoadRecords("$(TOP)/db/hzacc_channel_alias.template", "P=$(P),R=CHHA1002,CUB=CIT1,CHN=1")
dbLoadRecords("$(TOP)/db/hzacc_channel.template", "P=$(P),R=CVVA1002,$(CIT1),CH=1,IRB=37,VRB=5,FLT=18,STS=19,CMD=18,ISET=1")
dbLoadRecords("$(TOP)/db/hzacc_channel_alias.template", "P=$(P),R=CVVA1002,CUB=CIT1,CHN=2")
dbLoadRecords("$(TOP)/db/hzacc_channel.template", "P=$(P),R=CHHA4001,$(CIT1),CH=2,IRB=38,VRB=9,FLT=20,STS=21,CMD=20,ISET=2")
dbLoadRecords("$(TOP)/db/hzacc_channel_alias.template", "P=$(P),R=CHHA4001,CUB=CIT1,CHN=3")
dbLoadRecords("$(TOP)/db/hzacc_channel.template", "P=$(P),R=CVVA4001,$(CIT1),CH=3,IRB=39,VRB=13,FLT=22,STS=23,CMD=22,ISET=3")
dbLoadRecords("$(TOP)/db/hzacc_channel_alias.template", "P=$(P),R=CVVA4001,CUB=CIT1,CHN=4")
dbLoadRecords("$(TOP)/db/hzacc_channel.template", "P=$(P),R=CHHA1001,$(CIT1),CH=4,IRB=40,VRB=17,FLT=24,STS=25,CMD=24,ISET=4")
dbLoadRecords("$(TOP)/db/hzacc_channel_alias.template", "P=$(P),R=CHHA1001,CUB=CIT1,CHN=5")
dbLoadRecords("$(TOP)/db/hzacc_channel.template", "P=$(P),R=CVVA1001,$(CIT1),CH=5,IRB=41,VRB=21,FLT=26,STS=27,CMD=26,ISET=5")
dbLoadRecords("$(TOP)/db/hzacc_channel_alias.template", "P=$(P),R=CVVA1001,CUB=CIT1,CHN=6")
dbLoadRecords("$(TOP)/db/hzacc_channel.template", "P=$(P),R=CHHA2001,$(CIT1),CH=6,IRB=42,VRB=25,FLT=28,STS=29,CMD=28,ISET=6")
dbLoadRecords("$(TOP)/db/hzacc_channel_alias.template", "P=$(P),R=CHHA2001,CUB=CIT1,CHN=7")
dbLoadRecords("$(TOP)/db/hzacc_channel.template", "P=$(P),R=CVVA2001,$(CIT1),CH=7,IRB=43,VRB=29,FLT=30,STS=31,CMD=30,ISET=7")
dbLoadRecords("$(TOP)/db/hzacc_channel_alias.template", "P=$(P),R=CVVA2001,CUB=CIT1,CHN=8")

## Cubicle CIT2 (CITA3001 in DEVIL630) - Modbus slave 2
drvModbusAsynConfigure("CIT2_MEAS",  "SER18006", 2, 3, 0x80, 32, 0, 500, "HAZEMEYER")
drvModbusAsynConfigure("CIT2_MEAS2", "SER18006", 2, 3, 0xA0, 44, 0, 500, "HAZEMEYER")
drvModbusAsynConfigure("CIT2_STS",  "SER18006", 2, 3, 0x20, 32, 0, 1000, "HAZEMEYER")
drvModbusAsynConfigure("CIT2_CMD",  "SER18006", 2, 6, 0x00, 32, 0, 1, "HAZEMEYER")
drvModbusAsynConfigure("CIT2_ISET", "SER18006", 2, 6, 0x60, 8, 0, 1, "HAZEMEYER")
epicsEnvSet("CIT2", "CUB=CIT2,PORT_MEAS2=CIT2_MEAS2,PORT_STS=CIT2_STS,PORT_CMD=CIT2_CMD,PORT_ISET=CIT2_ISET,TIMEOUT=$(TIMEOUT),IMAX=$(IMAX),VMAX=$(VMAX),RAWMAX_SP=$(RAWMAX_SP),RAWMAX_RB=$(RAWMAX_RB)")


dbLoadRecords("$(TOP)/db/hzacc_cubicle.db", "P=$(P),R=CIT2,PORT_MEAS=CIT2_MEAS,PORT_MEAS2=CIT2_MEAS2,PORT_CMD=CIT2_CMD,TIMEOUT=$(TIMEOUT)")
dbLoadRecords("$(TOP)/db/hzacc_channel.template", "P=$(P),R=CHHA3001,$(CIT2),CH=0,IRB=36,VRB=1,FLT=16,STS=17,CMD=16,ISET=0")
dbLoadRecords("$(TOP)/db/hzacc_channel_alias.template", "P=$(P),R=CHHA3001,CUB=CIT2,CHN=1")
dbLoadRecords("$(TOP)/db/hzacc_channel.template", "P=$(P),R=CVVA3001,$(CIT2),CH=1,IRB=37,VRB=5,FLT=18,STS=19,CMD=18,ISET=1")
dbLoadRecords("$(TOP)/db/hzacc_channel_alias.template", "P=$(P),R=CVVA3001,CUB=CIT2,CHN=2")
dbLoadRecords("$(TOP)/db/hzacc_channel.template", "P=$(P),R=CHHA3002,$(CIT2),CH=2,IRB=38,VRB=9,FLT=20,STS=21,CMD=20,ISET=2")
dbLoadRecords("$(TOP)/db/hzacc_channel_alias.template", "P=$(P),R=CHHA3002,CUB=CIT2,CHN=3")
dbLoadRecords("$(TOP)/db/hzacc_channel.template", "P=$(P),R=CVVA3002,$(CIT2),CH=3,IRB=39,VRB=13,FLT=22,STS=23,CMD=22,ISET=3")
dbLoadRecords("$(TOP)/db/hzacc_channel_alias.template", "P=$(P),R=CVVA3002,CUB=CIT2,CHN=4")
dbLoadRecords("$(TOP)/db/hzacc_channel.template", "P=$(P),R=CHHA4002,$(CIT2),CH=4,IRB=40,VRB=17,FLT=24,STS=25,CMD=24,ISET=4")
dbLoadRecords("$(TOP)/db/hzacc_channel_alias.template", "P=$(P),R=CHHA4002,CUB=CIT2,CHN=5")
dbLoadRecords("$(TOP)/db/hzacc_channel.template", "P=$(P),R=CVVA4002,$(CIT2),CH=5,IRB=41,VRB=21,FLT=26,STS=27,CMD=26,ISET=5")
dbLoadRecords("$(TOP)/db/hzacc_channel_alias.template", "P=$(P),R=CVVA4002,CUB=CIT2,CHN=6")
dbLoadRecords("$(TOP)/db/hzacc_channel.template", "P=$(P),R=CHHA4003,$(CIT2),CH=6,IRB=42,VRB=25,FLT=28,STS=29,CMD=28,ISET=6")
dbLoadRecords("$(TOP)/db/hzacc_channel_alias.template", "P=$(P),R=CHHA4003,CUB=CIT2,CHN=7")
dbLoadRecords("$(TOP)/db/hzacc_channel.template", "P=$(P),R=CVVA4003,$(CIT2),CH=7,IRB=43,VRB=29,FLT=30,STS=31,CMD=30,ISET=7")
dbLoadRecords("$(TOP)/db/hzacc_channel_alias.template", "P=$(P),R=CVVA4003,CUB=CIT2,CHN=8")

iocInit

# Modbus traffic debugging
#asynSetTraceIOMask("SER18006", 0, 4)
#asynSetTraceMask("SER18006", 0, 9)
