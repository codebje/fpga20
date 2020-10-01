CPPFLAGS+=-std=c++11 -I../obj_dir $(shell pkg-config --cflags verilator) -MMD -MP
LDFLAGS+=$(pkg-config --libs verilator)
CXX=clang++

MODULES=fpga20

all:	main
	@./main

main:	main.o spiflash.o verilated.o verilated_vcd_c.o $(patsubst %,../obj_dir/V%__ALL.o,$(MODULES))
	$(CXX) $(LDFLAGS) -o $@ $^

main.o: $(patsubst %,../obj_dir/V%.h,$(MODULES))

verilated.o: $(shell pkg-config --variable=includedir verilator)/verilated.cpp
	$(CXX) $(CPPFLAGS) -c -o $@ $^

verilated_vcd_c.o: $(shell pkg-config --variable=includedir verilator)/verilated_vcd_c.cpp
	$(CXX) $(CPPFLAGS) -c -o $@ $^

verilated_trace.o: $(shell pkg-config --variable=includedir verilator)/verilated_trace.cpp
	$(CXX) $(CPPFLAGS) -c -o $@ $^

../obj_dir/V%.h: ../src/*.v
	@(cd .. ; verilator -Wall -Isrc --trace -cc src/$*.v)

../obj_dir/V%__ALL.o: ../obj_dir/V%.h
	echo making $*
	@(cd ../obj_dir ; make -f V$*.mk)

-include $(patsubst %,../obj_dir/V%__ALL.d,$(MODULES))
-include main.d
-include spiflash.d
