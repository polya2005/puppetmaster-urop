# Bluespec passthrough (bypass + pipelined) FIFO of size 1

When you learned Bluespec, you learned about
- How to create a bypass FIFO (size 1 or above)
- How to create a pipelined FIFO (size 1 or above)
- How to create a conflict-free FIFO (somehow suspiciously size 2 or above).

So, you thought, could I make CF FIFO of size 1?

It actually simply isn't possible.

The key issue is causality. Bypass FIFO means the decision whether downstream can dequeue depends on whether upstream enqueued (combinationally). Pipelined FIFO means whether upstream can enqueue depends on whether downstream enqueued. If you want to have both, then you have a cycle in whether rule A causes rule B to fire or whether rule B cause rule A to fire.

In general, it isn't impossible to enforce that "rule A and rule B always fire together" without a clear initiator (either outside of A and B entirely, or one or the other) due to atomicity.

Here's my implementation:
```bsv
import FIFO::*;
import Vector::*;

interface PassFIFO#(type t);
  (* always_ready, always_enabled *)
  method Bool isEmpty();

  (* always_ready, always_enabled *)
  method Bool isFull();

  method Action enq_empty(t x1);
  method ActionValue#(t) deq_empty();
  method ActionValue#(t) deq_full();
  method Action enq_full(t x1);
endinterface

module mkPassFIFO(PassFIFO#(t)) provisos (Bits#(t, tsize), DefaultValue#(t));
  Array#(Reg#(Maybe#(t))) state <- mkCReg(2, tagged Invalid);

  method Bool isEmpty();
    return !isValid(state[0]);
  endmethod

  method Bool isFull();
    return isValid(state[0]);
  endmethod

  method Action enq_empty(t x1)
    if (state[0] matches tagged Invalid);

    state[0] <= tagged Valid x1;
  endmethod

  method ActionValue#(t) deq_empty()
    if (state[0] matches tagged Invalid
    &&& state[1] matches tagged Valid .data);

    state[1] <= tagged Invalid;
    return data;
  endmethod

  method ActionValue#(t) deq_full()
    if (state[0] matches tagged Valid .data);

    state[0] <= tagged Invalid;
    return data;
  endmethod

  method Action enq_full(t x1)
    if (state[0] matches tagged Valid .data
    &&& state[1] matches tagged Invalid);

    state[1] <= tagged Valid x1;
  endmethod
endmodule

interface PassFIFOTest;
endinterface

module mkPassFIFOTest(PassFIFOTest);
  PassFIFO#(Bit#(32)) fifo <- mkPassFIFO;

  (* aggressive_implicit_conditions *)
  rule feed;
    fifo.enq_full(10);
  endrule

endmodule
```

And my attempt at compiling it:
```
bsc +RTS -Ksize -RTS -vdir build/verilog -bdir build/bluespec -simdir build/sim -info-dir build/info -remove-dollar --aggressive-conditions --show-schedule -suppress-warnings G0046 -show-range-conflict -p +:%/Libraries/FPGA/Xilinx:src -verilog -g mkPassFIFOTest -u src/mkPassFIFO.bsv
checking package dependencies
compiling src/mkPassFIFO.bsv
code generation for mkPassFIFOTest starts
Error: "src/mkPassFIFO.bsv", line 64, column 8: (G0004)
  Rule `RL_feed' uses methods that conflict in parallel:
    if (! fifo_state.port1__read[32])
      fifo_state.port0__read()
  and
    fifo_state.port1__write(33'd4294967306)
Error: "src/mkPassFIFO.bsv", line 64, column 8: (G0004)
  Rule `RL_feed' uses methods that conflict in parallel:
    if (! fifo_state.port1__read[32])
      fifo_state.port0__read()
  and
    if (fifo_state.port0__read[32])
      fifo_state.port1__read()
Schedule dump file created: build/info/mkPassFIFOTest.sched
```
