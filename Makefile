TARGET=fpga20

SRC_DIR:=src
BIN_DIR:=bin

SOURCES:=$(wildcard $(SRC_DIR)/*.v)
PLOTS=$(patsubst $(SRC_DIR)/%.v,$(BIN_DIR)/%.png,$(SOURCES))
PCF_SOURCE=trs20-fpga.pcf

all: $(BIN_DIR)/$(TARGET).bin

$(BIN_DIR)/$(TARGET).json: $(SOURCES)
	@yosys -q -p "synth_ice40 -json $@ -top $(TARGET)" $^

#$(BIN_DIR)/$(TARGET).txt: $(BIN_DIR)/$(TARGET).json $(PCF_SOURCE)
#@arachne-pnr -P vq100 -d 1k -p $(PCF_SOURCE) $(TARGET).blif -o $@

$(BIN_DIR)/$(TARGET).asc: $(BIN_DIR)/$(TARGET).json $(PCF_SOURCE)
	@nextpnr-ice40 -q --hx1k --package vq100 --top $(TARGET) --json $< \
	    --pcf $(PCF_SOURCE) --asc $@ --log $(BIN_DIR)/$(TARGET).log

$(BIN_DIR)/%.bin: $(BIN_DIR)/%.asc
	@icepack $^ $@

$(BIN_DIR)/%.dot: $(SRC_DIR)/%.v
	@yosys -q -p 'proc; opt; show -prefix $* -format dot;' $<

$(BIN_DIR)/%.png: $(BIN_DIR)/%.dot
	@dot -Tpng $< > $@

plots: .PHONY $(PLOTS)
	@imgcat $(PLOTS)

clean:
	@rm -f bin/*

.PHONY:
