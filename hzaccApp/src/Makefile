TOP=../..

include $(TOP)/configure/CONFIG
#----------------------------------------
#  ADD MACRO DEFINITIONS BELOW HERE

# Use typed rset structure (see 3.16.1 release notes)
USR_CPPFLAGS += -DUSE_TYPED_RSET

# Build the IOC application
PROD_IOC = hzacc

# hzacc.dbd will be created and installed
DBD += hzacc.dbd

# hzacc.dbd will include these files:
hzacc_DBD += base.dbd
hzacc_DBD += modbusSupport.dbd
hzacc_DBD += asyn.dbd
hzacc_DBD += drvAsynIPPort.dbd
hzacc_DBD += drvAsynSerialPort.dbd
hzacc_SRCS += hzacc_registerRecordDeviceDriver.cpp

# Build the main IOC entry point where needed
hzacc_SRCS_DEFAULT += hzaccMain.cpp
hzacc_SRCS_vxWorks += -nil-

hzacc_LIBS += modbus
hzacc_LIBS += asyn

# Link QSRV (pvAccess Server) if available
ifdef EPICS_QSRV_MAJOR_VERSION
    hzacc_LIBS += qsrv
    hzacc_LIBS += $(EPICS_BASE_PVA_CORE_LIBS)
    hzacc_DBD += PVAServerRegister.dbd
    hzacc_DBD += qsrv.dbd
endif

# Finally link IOC to the EPICS Base libraries
hzacc_LIBS += $(EPICS_BASE_IOC_LIBS)

include $(TOP)/configure/RULES
#----------------------------------------
#  ADD EXTRA GNUMAKE RULES BELOW HERE
