import BasicTypes::*;
import MainTypes::*;
import Vector::*;
import ClientServer::*;
import BRAM::*;
import UniqueWrappers::*;

// TODO: add counter
/*
In general, only one operation at a time can be processed.
Request ports will block if there is an incomplete operation.
*/
interface Summary;
    // Add a transaction to the summary.
    interface Put#(TxnFingerprint) txns;

    // Check whether a transaction is compatible with the summary or not.
    interface Server#(TxnFingerprint, Bool) checks;

    // Switch to copy mode. Only succeeds when no other operations are in progress.
    // In copy mode, one chunk at a time is returned through getChunk and replaced b y data from setChunk.
    // This should take about NumBloomPartChunks cycles.
    method ActionValue#(BloomObjCount) startCopy(BloomObjCount newCount);
    interface Get#(BloomChunkParts) getChunk;
    interface Put#(BloomChunkParts) setChunk;

    // Return true if can accept operation.
    method Bool isFree;

    // Number of elements inserted.
    method BloomObjCount getCount;
endinterface

typedef struct {
    Vector#(MaxTxnReadObjs, Bit#(NumBloomParts)) readObjFound;
    Vector#(MaxTxnWriteObjs, Bit#(NumBloomParts)) writeObjFound;
} CheckResult deriving (Bits, Eq, FShow, DefaultValue);

function Bool checkResultIsGood(CheckResult check);
    // for any object
    // if all four bits are set, then we're sad
    Bool compat = True;
    Bit#(MaxTxnReadObjs) readAllSet = 0;
    for (Integer i = 0; i < valueOf(MaxTxnReadObjs); i = i + 1) begin
        readAllSet[i] = (&(check.readObjFound[i]));
    end
    Bit#(MaxTxnWriteObjs) writeAllSet = 0;
    for (Integer i = 0; i < valueOf(MaxTxnWriteObjs); i = i + 1) begin
        writeAllSet[i] = (&(check.writeObjFound[i]));
    end
    // must all be false
    return ((|readAllSet) | (|writeAllSet)) == 0;
endfunction

// Can e used to either add objects to this Bloom filter chunk or check whether objects exist
function Tuple2#(CheckResult, BloomChunkParts) checkOrAddToChunk(BloomChunkParts parts, BloomChunkIndex currentChunk, TxnFingerprint txn);
    // We'll modify a copy of the input parts
    BloomChunkParts res = parts;

    CheckResult check = unpack(0);

    // Go through each object
    // For each object, check the (chunk, bit) pairs for each part
    // For each pair, if exists in the current chunk, mark True
    for (Integer i = 0; i < valueOf(MaxTxnReadObjs); i = i + 1) begin
        case (txn.readObjs[i]) matches
            tagged Invalid: begin
                // easy
            end
            tagged Valid .locs: begin  // loc is vector of (chunk, bit)
                for (Integer j = 0; j < valueOf(NumBloomParts); j = j+1) begin
                    BloomPartLocation loc = locs[j];
                    BloomChunkIndex chunkIdx = tpl_1(loc);
                    BloomBitIndex bitIdx = tpl_2(loc);
                    if (chunkIdx == currentChunk) begin // for modification
                        res[j][bitIdx] = 1'b1;
                    end
                    if (chunkIdx == currentChunk && parts[j][bitIdx] == 1'b1) begin // for checking
                        check.readObjFound[i][j] = 1'b1;
                    end
                end
            end
        endcase
    end

    // Same thing but with write objects
    for (Integer i = 0; i < valueOf(MaxTxnWriteObjs); i = i + 1) begin
        case (txn.writeObjs[i]) matches
            tagged Invalid: begin
                // easy
            end
            tagged Valid .locs: begin  // loc is vector of (chunk, bit)
                for (Integer j = 0; j < valueOf(NumBloomParts); j = j+1) begin
                    BloomPartLocation loc = locs[j];
                    BloomChunkIndex chunkIdx = tpl_1(loc);
                    BloomBitIndex bitIdx = tpl_2(loc);
                    if (chunkIdx == currentChunk) begin // for modification
                        res[j][bitIdx] = 1'b1;
                    end
                    if (chunkIdx == currentChunk && parts[j][bitIdx] == 1'b1) begin // for checking
                        check.writeObjFound[i][j] = 1'b1;
                    end
                end
            end
        endcase
    end
    
    return tuple2(check, res);
endfunction


typedef enum {
    Resetting,
    Free,
    Adding,
    Checking,
    Copying
} SummaryState deriving (Bits, Eq, FShow);

(* synthesize *)
(* preempts = "(addDone, resetDone, copyDone, checks_response_get), requestChunks" *)
module mkSummary(Summary);
    let checkOrAdd <- mkUniqueWrapper3(checkOrAddToChunk);

    let cfg = BRAM_Configure {
        memorySize: valueOf(NumBloomChunks),
        latency: 1,
        outFIFODepth: 3,
        loadFormat: None,
        allowWriteResponseBypass: False
    };
    BRAM2Port#(BloomChunkIndex, BloomChunkParts) bloom <- mkBRAM2Server(cfg);

    Reg#(SummaryState) state <- mkReg(Resetting);
    Reg#(TxnFingerprint) txn <- mkRegU;
    Reg#(Timestamp) cycle <- mkReg(0);

    Reg#(CheckResult) compat <- mkRegU;
    Reg#(BloomObjCount) count <- mkReg(0);
    
    rule incrementCycle;
        cycle <= cycle + 1;
    endrule

    // All operations use the same means of traversal
    // They go through each chunk, one by one
    Reg#(Maybe#(BloomChunkIndex)) mReqChunk <- mkReg(Invalid);
    rule requestChunks if (mReqChunk matches tagged Valid .reqChunk &&& state != Free);
        bloom.portB.request.put(BRAMRequest {
            write: False,
            responseOnWrite: False,
            address: reqChunk,
            datain: ?
        });
        `ifdef DEBUG_SUMMARY
        $fdisplay(stderr, "[%0d] requestChunks: state=", 
            cycle, fshow(state), ", chunk=", fshow(reqChunk));
        `endif

        mReqChunk <= reqChunk < fromInteger(valueOf(NumBloomChunks)-1)
                     ? Valid(reqChunk+1)
                     : Invalid;
    endrule

    // Similar counter for going through the responses.
    // If Invalid and not Free, it means we're done with the operation.
    Reg#(Maybe#(BloomChunkIndex)) mRespChunk <- mkReg(Valid(0));

    rule doReset if (mRespChunk matches tagged Valid .respChunk &&& state == Resetting);
        bloom.portA.request.put(BRAMRequest {
            write: True,
            responseOnWrite: False,
            address: respChunk,
            datain: unpack(0)
        });
        mRespChunk <= respChunk < fromInteger(valueOf(NumBloomChunks)-1)
                      ? Valid(respChunk+1)
                      : Invalid;
    endrule

    rule resetDone if (mRespChunk matches tagged Invalid &&& state == Resetting);
        `ifdef DEBUG_SUMMARY
        $fdisplay(stderr, "[%0d] resetDone", cycle);
        `endif
        txn <= ?;
        state <= Free;
        mReqChunk <= Invalid;
        mRespChunk <= Invalid;
        compat <= ?;
    endrule

    // For add operation, we read and then write the modifications
    rule doAdd_resp if (mRespChunk matches tagged Valid .respChunk &&& state == Adding);
        let data <- bloom.portB.response.get;
        let wrapRes <- checkOrAdd.func(data, respChunk, txn);
        let newData = tpl_2(wrapRes);
        `ifdef DEBUG_SUMMARY
        $fdisplay(stderr, "[%0d] doAdd_resp: chunk=", cycle, fshow(respChunk), ", newData=", fshow(newData));
        `endif

        bloom.portA.request.put(BRAMRequest {
            write: True,
            responseOnWrite: False,
            address: respChunk,
            datain: newData
        });
        mRespChunk <= respChunk < fromInteger(valueOf(NumBloomChunks)-1)
                      ? Valid(respChunk+1)
                      : Invalid;
    endrule

    rule addDone if (mRespChunk matches tagged Invalid &&& state == Adding);
        `ifdef DEBUG_SUMMARY
        $fdisplay(stderr, "[%0d] addDone", cycle);
        `endif
        txn <= ?;
        state <= Free;
        mReqChunk <= Invalid;
        mRespChunk <= Invalid;
        compat <= ?;
    endrule

    // For check operation, we read and update compat register
    rule doCheck_resp if (mRespChunk matches tagged Valid .respChunk &&& state == Checking);
        let data <- bloom.portB.response.get;
        let wrapRes <- checkOrAdd.func(data, respChunk, txn);
        let chunkCompat = tpl_1(wrapRes);
        CheckResult newCompat = unpack(pack(compat) | pack(chunkCompat));
        compat <= newCompat;
        `ifdef DEBUG_SUMMARY
        $fdisplay(stderr, "[%0d] doCheck_resp: chunk=", cycle, fshow(respChunk),
                          ", chunkCompat=", fshow(chunkCompat), ", overall=", fshow(newCompat),
                          ", which is good?:", fshow(checkResultIsGood(newCompat)));
        `endif
        mRespChunk <= respChunk < fromInteger(valueOf(NumBloomChunks)-1)
                      ? Valid(respChunk+1)
                      : Invalid;
    endrule

    rule copyDone if (mRespChunk matches tagged Invalid &&& state == Copying);
        `ifdef DEBUG_SUMMARY
        $fdisplay(stderr, "[%0d] copyDone", cycle);
        `endif
        txn <= ?;
        state <= Free;
        mReqChunk <= Invalid;
        mRespChunk <= Invalid;
        compat <= ?;
    endrule

    interface Put txns;
        method Action put(TxnFingerprint t) if (state == Free);
            txn <= t;
            state <= Adding;
            mReqChunk <= Valid(0);
            mRespChunk <= Valid(0);
            compat <= ?;
            BloomObjCount newObjs = 0;
            for (Integer i = 0; i < valueOf(MaxTxnReadObjs); i = i+1) begin
                if (isValid(t.readObjs[i]))
                    newObjs = newObjs+1;
            end
            for (Integer i = 0; i < valueOf(MaxTxnWriteObjs); i = i+1) begin
                if (isValid(t.writeObjs[i]))
                    newObjs = newObjs+1;
            end
            count <= count+newObjs;
            `ifdef DEBUG_SUMMARY
            $fdisplay(stderr, "[%0d] Summary.txns.put: Starting Add operation, txn fingerprint=", cycle, fshow(t));
            `endif
        endmethod
    endinterface

    interface Server checks;
        interface Put request;
            method Action put(TxnFingerprint t) if (state == Free);
                txn <= t;
                state <= Checking;
                mReqChunk <= Valid(0);
                mRespChunk <= Valid(0);
                compat <= unpack(0);
                `ifdef DEBUG_SUMMARY
                $fdisplay(stderr, "[%0d] Summary.checks.request.put: Starting Check operation, txn fingerprint=", cycle, fshow(t));
                `endif
            endmethod
        endinterface

        interface Get response;
            method ActionValue#(Bool) get if (mRespChunk matches tagged Invalid &&& state == Checking);
                `ifdef DEBUG_SUMMARY
                $fdisplay(stderr, "[%0d] Summary.checks.response.get: Completing Check operation, compat=", cycle, fshow(compat));
                `endif
                txn <= ?;
                state <= Free;
                mReqChunk <= Invalid;
                mRespChunk <= Invalid;
                Bool res = checkResultIsGood(compat);
                compat <= ?;
                return res;
            endmethod
        endinterface
    endinterface

    method ActionValue#(BloomObjCount) startCopy(BloomObjCount newCount) if (state == Free);
        txn <= ?;
        state <= Copying;
        mReqChunk <= Valid(0); // use for reading
        mRespChunk <= Valid(0); // use for writing
        compat <= ?;
        count <= newCount;
        `ifdef DEBUG_SUMMARY
        $fdisplay(stderr, "[%0d] startCopy: Starting Copy operation.", cycle);
        `endif
        return count;
    endmethod

    interface Get getChunk;
        method ActionValue#(BloomChunkParts) get if (state == Copying);
            let data <- bloom.portB.response.get;
            `ifdef DEBUG_SUMMARY
            $fdisplay(stderr, "[%0d] getChunk.get: Got chunk data", cycle);
            `endif
            return data;
        endmethod
    endinterface

    interface Put setChunk;
        method Action put(BloomChunkParts data) if (mRespChunk matches tagged Valid .respChunk &&& state == Copying);
            `ifdef DEBUG_SUMMARY
            $fdisplay(stderr, "[%0d] setChunk.put: Setting chunk ", cycle, fshow(respChunk));
            `endif
            bloom.portA.request.put(BRAMRequest {
                write: True,
                responseOnWrite: False,
                address: respChunk,
                datain: data
            });
            mRespChunk <= respChunk < fromInteger(valueOf(NumBloomChunks)-1)
                          ? Valid(respChunk+1)
                          : Invalid;
        endmethod
    endinterface

    method Bool isFree = state == Free;
    method BloomObjCount getCount = count;
endmodule
