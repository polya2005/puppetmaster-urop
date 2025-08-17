# Bluespec `Stmt` quirks

`repeat` and `for` don't add extra cycles.

`.start` starts FSM _in the next cycle_.

```
import StmtFSM::*;

module mkTest(Empty);
  Reg#(Bit#(32)) cycle <- mkReg(0);
  rule tick;
    cycle <= cycle+1;
  endrule

  Wire#(Bit#(1)) w <- mkWire;
  FSM fsm <- mkFSM(seq
    $display("[%d] %d\n", cycle, w);
    $finish;
  endseq);

  rule start;
    $display("[%d] start\n", cycle);
    w <= 1;
    fsm.start;
  endrule
endmodule
```
