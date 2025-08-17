import FIFOF::*;
import Vector::*;
import Assert::*;

interface VisibleFIFOF#(type element_type, numeric type fifo_depth);
    // Standard FIFO methods
    method Action enq(element_type x);
    method Action deq;
    method element_type first;
    method Bool notFull;
    method Bool notEmpty;

    // Additional visibility methods
    method UInt#(TLog#(TAdd#(fifo_depth, 1))) count;
    method element_type peek(UInt#(TLog#(fifo_depth)) idx);
endinterface

// MAKE SURE TO USE WITH POWER OF TWO BUFFER_SIZE ONLY
module mkVisibleFIFOF(VisibleFIFOF#(element_type, fifo_depth))
    provisos (NumAlias#(TAdd#(1, fifo_depth), buffer_size),
              Alias#(UInt#(TLog#(TAdd#(fifo_depth, 1))), index_t),
              Bits#(element_type, _sz),
              Log#(TAdd#(fifo_depth, 1), TLog#(fifo_depth)),
              FShow#(element_type));

    Reg#(Vector#(buffer_size, element_type)) buffer <- mkReg(?);
    Reg#(index_t) head <- mkReg(0);
    Reg#(index_t) tail <- mkReg(0);

    function UInt#(TLog#(TAdd#(fifo_depth, 1))) computeCount;
        if (tail >= head) return tail-head;
        else return -(head-tail);
    endfunction

    RWire#(element_type) do_enq <- mkRWire;
    PulseWire do_deq <- mkPulseWire;

    rule canonicalize;
        let newHead = head;
        let newTail = tail;
        let newBuf = buffer;

        if (do_deq) begin
            newBuf[newHead] = ?;
            newHead = newHead+1;
        end

        case (do_enq.wget()) matches
            tagged Invalid: begin
                // nothing
            end
            tagged Valid .data: begin
                newBuf[newTail] = data;
                newTail = newTail+1;
            end
        endcase

        head <= newHead;
        tail <= newTail;
        buffer <= newBuf;
    endrule

    // Reg#(Bit#(32)) cycle <- mkReg(0);
    // (* no_implicit_conditions, fire_when_enabled *)
    // rule tick;
    //     $write("[%d] head=%d, tail=%d, count=%d, buf=[", cycle, head, tail, computeCount);
    //     for (Integer i = 0; i < valueOf(buffer_size); i = i+1) begin
    //         if (i != 0) $write(", ");
    //         $write("%d", buffer[i]);
    //     end
    //     $display("");
    //     cycle <= cycle+1;
    // endrule

    method Action enq(element_type x) if (tail+1 != head);
        do_enq.wset(x);
    endmethod

    method Action deq() if (head != tail);
        do_deq.send();
    endmethod

    method element_type first() if (head != tail);
        return buffer[head];
    endmethod

    method Bool notFull = tail+1 != head;
    method Bool notEmpty = head != tail;

    method UInt#(TLog#(TAdd#(fifo_depth, 1))) count = computeCount;

    // Only correct if idx < count
    method element_type peek(UInt#(TLog#(fifo_depth)) idx);
        let realIdx = head+idx;
        return buffer[realIdx];
    endmethod

endmodule
