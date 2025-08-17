I experimentally showed that bypass+pipelined FIFO = pipelined+bypass FIFO + CF FIFO.

Here's the bypass+pipelined version. You can make the rest by easily swapping the top.

Then diff the outputs. Note that the outputs may be off by one near the end, but other than that everything should be good.

`ComposeFIFOF.bsv`:
```
import FIFOF::*;
import SpecialFIFOs::*;
import Connectable::*;
import GetPut::*;

module mkComposeFIFOF(FIFOF#(elem_t))
    provisos (Bits#(elem_t, _size_elem_t));
    FIFOF#(elem_t) f0 <- mkBypassFIFOF;
    FIFOF#(elem_t) f1 <- mkPipelineFIFOF;

    mkConnection(toGet(f0), toPut(f1));

    method Action enq(elem_t x1);
        f0.enq(x1);
    endmethod

    method Action deq;
        f1.deq();
    endmethod

    method elem_t first;
        return f1.first;
    endmethod

    method Bool notFull;
        return f0.notFull && f1.notFull;
    endmethod

    method Bool notEmpty;
        return f0.notEmpty && f1.notEmpty;
    endmethod

    method Action clear;
        f0.clear;
        f1.clear;
    endmethod
endmodule
```

`ComposeFIFOFTest.bsv`:
```
import ComposeFIFOF::*;
import FIFOF::*;
import LFSR::*;

(* execution_order = "print_enq, print_deq, end_test" *)
module mkComposeFIFOFTest(Empty);
    Bit#(1024) seed = 1024'h8004080008000400000200040001001000010000100020004000000100001000000040000400000010000000400000010000000400000010000000400000010000000400000010000000400000010000000400000010000000400000010000000400000010000000401;
    LFSR#(Bit#(1024)) rng <- mkFeedLFSR(seed);

    FIFOF#(Bit#(16)) ff <- mkComposeFIFOF;

    Reg#(Bit#(20)) cycle <- mkReg(0);
    Reg#(Bit#(16)) enq_idx <- mkReg(0);

    rule update_rng;
        cycle <= cycle+1;
        rng.next;
    endrule

    Wire#(Bit#(16)) enq_value <- mkWire;
    Wire#(Bit#(16)) deq_value <- mkWire;

    rule stream_enq if (rng.value[0] == 1'b1);
        enq_value <= enq_idx;
        ff.enq(enq_idx);
        enq_idx <= enq_idx + 1;
    endrule

    rule stream_deq if (rng.value[1] == 1'b1);
        deq_value <= ff.first;
        ff.deq;
    endrule

    rule print_enq;
        $display("[%d] enqueued %d", cycle, enq_value);
    endrule

    rule print_deq;
        $display("[%d] dequeued %d", cycle, deq_value);
    endrule

    rule end_test;
        if (enq_idx == maxBound) begin
            $finish;
        end
    endrule

endmodule
```
