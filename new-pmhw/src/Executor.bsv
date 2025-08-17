import BasicTypes::*;
import MainTypes::*;
import Puppetmaster::*;
import GetPut::*;
import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;
import Vector::*;
import ClientServer::*;
import Assert::*;
import Arbitrate::*;

/*
Output side of the Puppetmaster scheduler.
*/
typedef Server#(ScheduleMessage, WorkDoneMessage) Executor;


/*
Output MUX
*/
interface ExecutorMux#(numeric type n);
    method TIndex#(n) selected;
    method Action select(TIndex#(n) idx);
    interface Executor executor;
endinterface

module mkExecutorMux(Vector#(n, Executor) execs, ExecutorMux#(n) ifc);
    Reg#(TIndex#(n)) index <- mkRegU;

    method TIndex#(n) selected = index;

    method Action select(TIndex#(n) idx);
        index <= idx;
    endmethod

    interface executor = execs[index];
endmodule


/*
Real executor that relays work message to host CPU to perform actual work.
*/
interface RealExecutor;
    interface Executor executor;
    interface Get#(TransactionId) toHost;
    interface Put#(TransactionId) fromHost;
endinterface

(* synthesize *)
module mkRealExecutor(RealExecutor);
    FIFO#(TransactionId) reqFF <- mkBypassFIFO;
    FIFO#(TransactionId) doneFF <- mkBypassFIFO;

    interface toHost = toGet(reqFF);
    interface fromHost = toPut(doneFF);

    interface Executor executor;
        interface Put request;
            method Action put(ScheduleMessage msg);
                reqFF.enq(msg.txnId);
            endmethod
        endinterface
        interface Get response;
            method ActionValue#(WorkDoneMessage) get;
                let txnId = doneFF.first;
                doneFF.deq;
                // TODO: fix
                return WorkDoneMessage { txnId: txnId, puppetId: 0 };
            endmethod
        endinterface
    endinterface
endmodule


/*
Fake executor that just busy-waits.
*/
interface FakeExecutor;
    interface Executor executor;
    method Action setDuration(Timestamp n);
    method Timestamp getDuration;
    method Action setNumPuppets(TCount#(MaxNumPuppets) n);
    method TCount#(MaxNumPuppets) getNumPuppets;
endinterface

typedef struct {
    Timestamp endTime;
    TransactionId txnId;
} PuppetData deriving (Bits, Eq, FShow);

(* synthesize *)
(* descending_urgency = "reportDone, startWork" *)
module mkFakeExecutor(FakeExecutor);
    Reg#(TCount#(MaxNumPuppets)) numPuppets <- mkReg(8);
    Reg#(Timestamp) duration <- mkReg(0);

    Reg#(Timestamp) cycle <- mkReg(0);
    Vector#(MaxNumPuppets, Array#(Reg#(Maybe#(PuppetData)))) puppets <- replicateM(mkCReg(3, Invalid));

    FIFO#(ScheduleMessage) schedFF <- mkBypassFIFO;
    FIFO#(WorkDoneMessage) doneFF <- mkBypassFIFO;

    (* no_implicit_conditions, fire_when_enabled *)
    rule tick;
        cycle <= cycle+1;
    endrule

    Vector#(MaxNumPuppets, FIFOF#(ScheduleMessage)) puppetQ <- replicateM(mkSizedBypassFIFOF(16));

    rule fanout;
        let msg = schedFF.first;
        schedFF.deq;
        puppetQ[msg.puppetId].enq(msg);
    endrule

    function Bool isDone(Maybe#(PuppetData) mPuppet);
        case (mPuppet) matches
            tagged Valid .puppet: begin
                return cycle >= puppet.endTime;
            end
            tagged Invalid: begin
                return False;
            end
        endcase
    endfunction

    function Vector#(MaxNumPuppets, Bool) puppetIsDone;
         Vector#(MaxNumPuppets, Bool) res = unpack(0);
         for (Integer i = 0; i < valueOf(MaxNumPuppets); i = i+1) begin
             if (fromInteger(i) < numPuppets && isDone(puppets[i][2])) begin
                 res[i] = True;
             end
         end
         return res;
    endfunction
    Arbitrate#(MaxNumPuppets) donePuppetArb <- mkRoundRobin;
    rule donePuppetArbReq;
        donePuppetArb.request(puppetIsDone);
    endrule
    Reg#(Vector#(MaxNumPuppets, Bool)) donePuppetArbResult <- mkReg(unpack(0));
    rule pipeArbResult;
        donePuppetArbResult <= donePuppetArb.grant;
    endrule

    let donePuppet = findElem(True, donePuppetArbResult);

    rule reportDone if (donePuppet matches tagged Valid .mPuppetId);
        PuppetId puppetId = pack(mPuppetId);
        dynamicAssert(isValid(puppets[puppetId][0]), "arb wrong puppet");
        let puppet = fromMaybe(?, puppets[puppetId][0]);
        doneFF.enq(WorkDoneMessage { txnId: puppet.txnId, puppetId: pack(puppetId) });
        puppets[puppetId][0] <= Invalid;
        `ifdef DEBUG_EXEC
        $fdisplay(stderr, "[%0d] FakeExecutor: txn id=", cycle, fshow(puppet.txnId), " finished executing on puppet ", puppetId);
        `endif
        $display("[%0d] txn_id=%0d done on puppet_id=%0d", cycle, puppet.txnId, puppetId);
    endrule

     for (Integer i = 0; i < valueOf(MaxNumPuppets); i = i+1) begin
        rule startWork if (!isValid(puppets[i][1]));
            let msg = puppetQ[i].first; puppetQ[i].deq;
            dynamicAssert(extend(pack(msg.puppetId)) < numPuppets, "bad puppet id");
            puppets[msg.puppetId][1] <= Valid(PuppetData { endTime: cycle + duration, txnId: msg.txnId });
            $display("[%0d] txn_id=%0d executing on puppet_id=%0d", cycle, msg.txnId, msg.puppetId);
        endrule
    end
    
    interface Executor executor;
        interface request = toPut(schedFF);
        interface response = toGet(doneFF);
    endinterface

    method Action setDuration(Timestamp n);
        duration <= n;
    endmethod

    method Timestamp getDuration;
        return duration;
    endmethod

    method Action setNumPuppets(TCount#(MaxNumPuppets) n);
        numPuppets <= n;
    endmethod

    method TCount#(MaxNumPuppets) getNumPuppets;
        return numPuppets;
    endmethod

endmodule
