import FIFOF::*;
import Vector::*;
import VisibleFIFOF::*;

(* synthesize *)
module mkVisibleFIFOFSynth(VisibleFIFOF#(Bit#(32), 15));
    VisibleFIFOF#(Bit#(32), 15) fifo <- mkVisibleFIFOF;
    return fifo;
endmodule
