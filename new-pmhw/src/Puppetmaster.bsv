import BasicTypes::*;
import MainTypes::*;
import Assert::*;
import GetPut::*;
import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;
import ClientServer::*;
import Connectable::*;
import Vector::*;
import Summary::*;
import StmtFSM::*;
import TxnHasher::*;
import VisibleFIFOF::*;
import Arbitrate::*;
import Cntrs::*;

typedef 56 InputBufferSize;
typedef 8 LookaheadBufferSize;
typedef 7 ActivePerPuppet; // has to be power of two-1
typedef TMul#(ActivePerPuppet, MaxNumPuppets) SchedSize;
typedef TIndex#(MaxNumPuppets) PuppetId;
typedef TCount#(MaxNumPuppets) PuppetCount;

/*
Output scheduling message from Puppetmaster
*/
typedef struct {
    TransactionId txnId;
    PuppetId puppetId;
} ScheduleMessage deriving (Bits, Eq, FShow);

/*
Input work-done message back into Puppetmaster
*/
typedef struct {
    TransactionId txnId;
    PuppetId puppetId;
} WorkDoneMessage deriving (Bits, Eq, FShow);

(* synthesize *)
module mkFixedVisibleFIFOF(VisibleFIFOF#(TxnFingerprint, ActivePerPuppet));
    let x <- mkVisibleFIFOF;
    return x;
endmodule

/*
Puppetmaster interface
*/
interface Puppetmaster;
    method Action setNumPuppets(PuppetCount numPuppets);
    method PuppetCount getNumPuppets;

    interface Put#(Transaction) transactions;
    interface Get#(ScheduleMessage) scheduled;
    interface Put#(WorkDoneMessage) workDone;
endinterface

typedef enum {
    Normal, // Normal operation
    Switching // Copying
} PuppetmasterState deriving (Bits, Eq, FShow);

(* synthesize *)
(* descending_urgency = "startRefresh, switchDone, drainLookahead, shadowUpdateNew, shadowUpdateExisting" *)
module mkPuppetmaster(Puppetmaster);
    // For debugging purposes
    Reg#(Timestamp) cycle <- mkReg(0);
    (* no_implicit_conditions, fire_when_enabled *)
    rule incrementCycle;
        cycle <= cycle + 1;
    endrule

    // Configuration
    PuppetCount defaultNumPuppets = 8;
    Reg#(TCount#(MaxNumPuppets)) numPuppets <- mkReg(defaultNumPuppets);

    // All inputs go through a preprocessor
    FIFO#(TxnFingerprint) inputQ <- mkSizedFIFO(valueOf(InputBufferSize));
    let hasher <- mkTxnHasher;
    mkConnection(hasher.response, toPut(inputQ));

    // State (whether we're in copying mode or not)
    Reg#(PuppetmasterState) state <- mkReg(Normal);

    // Arbitrate inputs into the lookahead buffer
    FIFOF#(TxnFingerprint) lookaheadReinsert <- mkPipelineFIFOF;
    FIFOF#(TxnFingerprint) lookaheadBuffer <- mkSizedFIFOF(valueOf(LookaheadBufferSize));
    rule drainInput if (state == Normal);
        // Always prioritize re-inserts first
        if (lookaheadReinsert.notEmpty) begin
            let txn = lookaheadReinsert.first;
            lookaheadReinsert.deq;
            lookaheadBuffer.enq(txn);
            `ifdef DEBUG_PMHW
            $fdisplay(stderr, "[%0d] drainInput: Re-inserting transaction txnId=%0d", cycle, txn.txnId);
            `endif
        end else begin
            let txn = inputQ.first;
            inputQ.deq;
            lookaheadBuffer.enq(txn);
            `ifdef DEBUG_PMHW
            $fdisplay(stderr, "[%0d] drainInput: New transaction from inputQ txnId=%0d", cycle, txn.txnId);
            `endif
        end
    endrule

    // Summaries and queues into summaries
    Summary mainSummary <- mkSummary;
    Summary shadowSummary <- mkSummary;
    FIFOF#(TxnFingerprint) shadowQ <- mkFIFOF;

    // Output queue
    FIFO#(ScheduleMessage) schedQ <- mkSizedFIFO(valueOf(SchedSize)+1);

    // Active list
    // i.e., FIFOs for storing each Puppet's active transactions
    Vector#(MaxNumPuppets, VisibleFIFOF#(TxnFingerprint, ActivePerPuppet)) puppetTxns <- replicateM(mkFixedVisibleFIFOF);
    function Bool checkPuppetIsFree(VisibleFIFOF#(TxnFingerprint, ActivePerPuppet) p) = p.notFull;

    // Arbitrate for fairness into active list (i.e. selecting puppet)
    function Vector#(MaxNumPuppets, Bool) puppetIsFree;
        Vector#(MaxNumPuppets, Bool) res = newVector;
        for (Integer i = 0; i < valueOf(MaxNumPuppets); i = i+1) begin
            if (fromInteger(i) < numPuppets && puppetTxns[i].notFull) begin
                res[i] = True;
            end
        end
        return res;
    endfunction
    Arbitrate#(MaxNumPuppets) puppetArb <- mkRoundRobin;
    rule puppetRequest;
        puppetArb.request(puppetIsFree);
    endrule
    Reg#(Vector#(MaxNumPuppets, Bool)) puppetArbResult <- mkReg(unpack(0));
    rule pipePuppetArbResult;
        puppetArbResult <= puppetArb.grant;
    endrule

    // Puppet we can use for scheduling in this cycle
    let freePuppetId = findElem(True, puppetArbResult);
    // Whether there's any puppet available at all
    Bool hasFreePuppet = isValid(freePuppetId) && extend(pack(fromMaybe(?, freePuppetId))) < numPuppets;

    // Just helper variable for the FSM
    Reg#(Bool) isCompat <- mkRegU;
    Count#(TCount#(SchedSize)) numTxnScheduled <- mkCount(0);
    Count#(TCount#(LookaheadBufferSize)) lookaheadFailCount <- mkCount(0);

    // New item from lookahead buffer goes through states:
    Stmt lookaheadSteps = seq
        // 1. send request to summary
        // do it when starting the fsm for performance

        // 2. wait for summary result, put summary result in reg
        action
            let res <- mainSummary.checks.response.get;
            isCompat <= res;
            `ifdef DEBUG_PMHW
            $fdisplay(stderr, "[%0d] lookaheadSteps 2: Check result received", cycle);
            `endif
        endaction

        // 3.a if compat, add to current summary, shadowQ, schedQ, and puppet's activel ist
        if (isCompat) action
            dynamicAssert(hasFreePuppet, "Expected to have free puppet");
            lookaheadFailCount <= 0; // reset
            let pid = fromMaybe(?, freePuppetId);

            let txn = lookaheadBuffer.first;
            lookaheadBuffer.deq;

            mainSummary.txns.put(txn);
            shadowQ.enq(txn);

            schedQ.enq(ScheduleMessage { txnId: txn.txnId, puppetId: pack(pid) });
            numTxnScheduled.incr(1);
            puppetTxns[pid].enq(txn);

            $display("[%0d] txn_id=%0d scheduled on puppet_id=%0d", cycle, txn.txnId, pid);
            `ifdef DEBUG_PMHW
            $fdisplay(stderr, "[%0d] lookaheadSteps 3.a: Transaction compatible, scheduled txn_id=%0d on puppet_id=%0d", cycle, txn.txnId, pid);
            `endif
        endaction
        // 3.b if not compat, put it back into the lookahead buffer
        else action
           let txn = lookaheadBuffer.first;
           lookaheadBuffer.deq;

           lookaheadFailCount.incr(1);
           lookaheadReinsert.enq(txn);

           `ifdef DEBUG_PMHW
           $fdisplay(stderr, "[%0d] lookaheadSteps 3.b: Transaction incompatible, re-inserted txnId=%0d", cycle, txn.txnId);
           `endif
        endaction
    endseq;

    let lookaheadFSM <- mkFSMWithPred(lookaheadSteps, lookaheadBuffer.notEmpty && hasFreePuppet);

    // Only start the checking process when
    // - we actually have something to look at
    // - there's space in activeTxns
    // We also want to make sure that when the refresh timer triggers,
    // we don't consider any new transactions. This to ensure that the
    // shadow summary has the chance to finish going through all active transactions.
    rule drainLookahead if (lookaheadBuffer.notEmpty && hasFreePuppet && state == Normal);
        let txn = lookaheadBuffer.first;
        mainSummary.checks.request.put(txn);
        lookaheadFSM.start;
        `ifdef DEBUG_PMHW
        $fdisplay(stderr, "[%0d] drainLookahead: State is normal and FSM can be started", cycle);
        $fdisplay(stderr, "[%0d] lookaheadSteps 1: Checking transaction txn=%0d", cycle, txn.txnId);
        `endif
    endrule

    FIFOF#(WorkDoneMessage) workDoneQ <- mkSizedFIFOF(valueOf(TAdd#(1, SchedSize)));

    // We always prioritize adding new transactions to the shadow summary (over active txns)
    rule shadowUpdateNew;
        let txn = shadowQ.first;
        shadowQ.deq;
        shadowSummary.txns.put(txn);
        `ifdef DEBUG_PMHW
        $fdisplay(stderr, "[%0d] shadowUpdateNew: Adding new transaction to shadow summary txnId=%0d", cycle, txn.txnId);
        `endif
    endrule

    // Go through all puppets' active txn list and add them to shadow summary
    Reg#(Vector#(MaxNumPuppets, TCount#(ActivePerPuppet))) recordedActiveTxnSize <- mkReg(unpack(0));
    Reg#(PuppetId) shadowPuppetIndex <- mkReg(0);
    Reg#(TIndex#(ActivePerPuppet)) shadowEntryIndex <- mkReg(0);
    Reg#(Bool) shadowComplete <- mkReg(False);

    rule shadowUpdateExisting if (!shadowComplete); // Doesn't make sense to hog up the summary if we're already done
        let txns = puppetTxns[shadowPuppetIndex];
        let valid = unpack(extend(shadowEntryIndex)) < txns.count && unpack(extend(shadowEntryIndex)) < recordedActiveTxnSize[shadowPuppetIndex];
        let txn = puppetTxns[shadowPuppetIndex].peek(unpack(shadowEntryIndex));
        if (valid) begin
            shadowSummary.txns.put(txn);
            shadowEntryIndex <= shadowEntryIndex+1;
        end else if (unpack(extend(shadowPuppetIndex)) < numPuppets-1) begin
            shadowPuppetIndex <= shadowPuppetIndex+1;
            shadowEntryIndex <= 0;
        end else begin
            shadowPuppetIndex <= 0;
            shadowEntryIndex <= 0;
            shadowComplete <= True;
        end
    endrule

    rule clearWorkDone if (workDoneQ.notEmpty);
        let done = workDoneQ.first;
        dynamicAssert(puppetTxns[done.puppetId].notEmpty && done.txnId == puppetTxns[done.puppetId].first.txnId, "work done must match txn order");
        numTxnScheduled.decr(1);
        puppetTxns[done.puppetId].deq;
        $display("[%0d] txn_id=%0d removed", cycle, done.txnId);
        workDoneQ.deq;
    endrule

    // Tick refresh timer
    rule startRefresh if (state == Normal && mainSummary.getCount() > 200 && shadowComplete);
        `ifdef DEBUG_PMHW
        $fdisplay(stderr, "[%0d] startRefresh: Lookahead has failed often enough. Starting the refresh process.", cycle);
        $fdisplay(stderr, "[%0d] Number of elements in the Bloom filter: %d", cycle, mainSummary.getCount());
        `endif
        $display("[%0d] refreshing", cycle);
        lookaheadFailCount <= 0;
        let cnt <- shadowSummary.startCopy(0);
        let _ <- mainSummary.startCopy(cnt);
        state <= Switching;
    endrule

    // When switching, we need to make sure to provide or drain some values.
    rule clearShadow if (state == Switching);
        shadowSummary.setChunk.put(unpack(0));
    endrule
    mkConnection(shadowSummary.getChunk, mainSummary.setChunk);
    rule drainMain if (state == Switching);
        let _ <- mainSummary.getChunk.get;
    endrule

    // When the switch is done (main summary is now active), reinitialize stuff
    rule switchDone if (state == Switching && mainSummary.isFree && shadowSummary.isFree);
        shadowPuppetIndex <= 0;
        shadowEntryIndex <= 0;
        shadowComplete <= False;
        state <= Normal;
        `ifdef DEBUG_PMHW
        $fdisplay(stderr, "[%0d] switchDone: Switching is done. Going back to normal state.", cycle);
        `endif
    endrule

    method Action setNumPuppets(PuppetCount _numPuppets);
        numPuppets <= _numPuppets;
        `ifdef DEBUG_PMHW
        $fdisplay(stderr, "[%0d] setNumPuppets: Updated puppets to %0d", cycle, _numPuppets);
        `endif
    endmethod
    
    method PuppetCount getNumPuppets = numPuppets;

    interface Put transactions;
        method Action put(Transaction txn);
            hasher.request.put(txn);
            `ifdef DEBUG_PMHW
            $fdisplay(stderr, "[%0d] transactions.put: New transaction received txnId=%0d", cycle, txn.txnId);
            `endif
        endmethod
    endinterface
    
    interface Get scheduled;
        method ActionValue#(ScheduleMessage) get;
            let msg = schedQ.first;
            schedQ.deq;
            `ifdef DEBUG_PMHW
            $fdisplay(stderr, "[%0d] scheduled.get: Scheduling transaction txn_id=%0d, puppet_id=%0d", cycle, msg.txnId, msg.puppetId);
            `endif
            return msg;
        endmethod
    endinterface
    
    interface Put workDone;
        method Action put(WorkDoneMessage msg);
            workDoneQ.enq(msg);
            `ifdef DEBUG_PMHW
            $fdisplay(stderr, "[%0d] workDone.put: Work done message received txnId=%0d, puppet_id=%0d", cycle, msg.txnId, msg.puppetId);
            `endif
        endmethod
    endinterface

endmodule
