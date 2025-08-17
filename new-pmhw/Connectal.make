ifndef CONNECTALDIR
$(error CONNECTALDIR variable is not defined, aborting build)
endif

S2H_INTERFACES = S2HMessage:Connectal.s2h
H2S_INTERFACES = Connectal:H2SMessage

BSVFILES += src/BasicTypes.bsv src/Connectal.bsv
BSVPATH += ./src

CPPFILES += ./src/dummy_main.cpp
CONNECTALFLAGS += --mainclockperiod=8
CONNECTALFLAGS += --bscflags="+RTS -K1G -H6G -RTS"
CONNECTALFLAGS += --nonstrict
CONNECTALFLAGS += --verilatorflags="--no-timing"

include $(CONNECTALDIR)/Makefile.connectal
