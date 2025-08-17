import BasicTypes::*;
import MainTypes::*;
import Vector::*;
import Summary::*;
import LFSR::*;
import ClientServer::*;
import GetPut::*;

interface SummarySynth;
    method Bool isFree;
    method Bool checkResponse;
    method Bit#(1) getChunkData(Bit#(10) i);
endinterface


(* synthesize *)
module mkSummarySynth(SummarySynth);
    let summary <- mkSummary;

    Bit#(1024) seed = 1024'h8004080008000400000200040001001000010000100020004000000100001000000040000400000010000000400000010000000400000010000000400000010000000400000010000000400000010000000400000010000000400000010000000400000010000000401;
    LFSR#(Bit#(1024)) rng <- mkFeedLFSR(seed);

    Bit#(4) pickRule = rng.value[3:0];
    TxnFingerprint randTxn = unpack(truncate(rng.value));
    BloomChunkParts randChunk = unpack(truncate(rng.value));
    Wire#(Bool) resp <- mkWire;
    Wire#(BloomChunkParts) gotChunk <- mkWire;

    rule nextRng;
        rng.next;
    endrule

    Reg#(Bit#(32)) cnt <- mkReg(0);
    rule tick;
        cnt <= cnt+1;
    endrule

    rule addTxn if (pickRule == 0);
        summary.txns.put(randTxn);
    endrule

    rule checkTxn if (pickRule == 1);
        summary.checks.request.put(randTxn);
    endrule

    rule checkTxnDrain if (pickRule == 2);
        let r <- summary.checks.response.get;
        resp <= r;
    endrule

    rule startCopy if (pickRule == 3);
        let _ <- summary.startCopy(truncate(rng.value));
    endrule

    rule getChunk if (pickRule == 4);
        let r <- summary.getChunk.get;
        gotChunk <= r;
    endrule

    rule setChunk if (pickRule == 5);
        summary.setChunk.put(randChunk);
    endrule

    method Bool isFree = summary.isFree;

    method Bool checkResponse = resp;

    method Bit#(1) getChunkData(Bit#(10) i) = pack(gotChunk)[i];

endmodule


