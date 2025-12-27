import BasicTypes::*;
import MainTypes::*;
import GetPut::*;
import ClientServer::*;
import Vector::*;
import FIFO::*;
import SpecialFIFOs::*;
import Real::*;

// Optimized hash function focused on strong avalanche effect in lower 11 bits
// (3 bits for chunk index + 8 bits for bit index)
// TODO: careful, this only works well for 4x8x256 config (4x11 bits) rn
// This is not used currently.
// function BloomPartLocation hash(ObjectId obj, Bit#(32) seed);
//     // Initialize with seed
//     Bit#(32) h = seed;

//     // Split 32-bit object ID into 4 bytes for processing
//     Bit#(8) byte0 = obj[7:0];
//     Bit#(8) byte1 = obj[15:8];
//     Bit#(8) byte2 = obj[23:16];
//     Bit#(8) byte3 = obj[31:24];

//     // First mixing stage - focus on affecting lower bits
//     h = h ^ zeroExtend(byte0);
//     h = {h[26:0], h[31:27]}; // 5-bit right rotation

//     h = h ^ zeroExtend(byte1);
//     h = {h[20:0], h[31:21]}; // 11-bit right rotation

//     h = h ^ zeroExtend(byte2);
//     h = {h[13:0], h[31:14]}; // 18-bit right rotation

//     h = h ^ zeroExtend(byte3);

//     // Final mixing focused specifically on the lower 11 bits
//     // Extract upper bits and mix them into lower bits
//     Bit#(21) upper_bits = h[31:11];
//     Bit#(11) lower_bits = h[10:0];

//     // Strong mixing for the lower 11 bits by folding upper bits onto them
//     lower_bits = lower_bits ^ truncate(upper_bits);
//     lower_bits = lower_bits ^ truncate(upper_bits >> 10);

//     // Additional mixing within the lower bits
//     lower_bits = {lower_bits[7:0], lower_bits[10:8]} ^ {lower_bits[2:0], lower_bits[10:3]};

//     // Reconstruct the h with well-mixed lower bits
//     h = {upper_bits, lower_bits};

//     // Translate into location within the part
//     return tuple2(h[10:8], h[7:0]);
// endfunction

// Generate all hash values for an object
// function BloomLocation hashObject(ObjectId obj);
//     Vector#(NumBloomParts, Bit#(32)) seeds = newVector;
//     seeds[0] = 32'h9e3779b1;
//     seeds[1] = 32'h85ebca77;
//     seeds[2] = 32'hc2b2ae3d;
//     seeds[3] = 32'h27d4eb2f;

//     BloomLocation h = newVector;
//     for (Integer i = 0; i < valueOf(NumBloomParts); i = i + 1) begin
//         h[i] = hash(obj, seeds[i]);
//     end
//     return h;
// endfunction

typedef TMul#(NumBloomParts, TLog#(BloomPartSize)) NBits;
function BloomLocation hashObject(ObjectId obj);
    // Integer nBits = valueOf(NBits);
    Integer fibConstant = trunc(fromInteger(valueOf(TExp#(NBits))) / (1.0 + sqrt(5.0)) * 2.0);
    if (fibConstant % 2 == 0) begin
        fibConstant = fibConstant + 1; // Make it odd
    end
    Bit#(NBits) fibConstantBit = fromInteger(fibConstant);
    Bit#(TAdd#(NBits, 32)) objBit = zeroExtend(obj);
    Bit#(NBits) fullHash = truncate(objBit) * fibConstantBit;
    BloomLocation h = newVector;
    for (Integer i = 0; i < valueOf(NumBloomParts); i = i + 1) begin
        BloomChunkIndex chunkIdx = 0;
        BloomBitIndex bitIdx = 0;
        for(Integer j = 0; j < log2(valueOf(NumBloomChunks)); j = j + 1) begin
            chunkIdx[j] = fullHash[j * valueOf(NumBloomParts) + i + log2(valueOf(BloomChunkSize))];
        end
        for(Integer j = 0; j < log2(valueOf(BloomChunkSize)); j = j + 1) begin
            bitIdx[j] = fullHash[j * valueOf(NumBloomParts) + i];
        end
        h[i] = tuple2(chunkIdx, bitIdx);
    end
    return h;
endfunction

function TxnFingerprint hashTxn(Transaction txn);
    TxnFingerprint res = unpack(0);
    res.txnId = txn.txnId;
    res.auxData = txn.auxData;
    for (Integer i = 0; i < valueOf(MaxTxnReadObjs); i = i + 1) begin
        if (fromInteger(i) < txn.numReadObjs) begin
            res.readObjs[i] = Valid(hashObject(txn.readObjs[i]));
        end else begin
            res.readObjs[i] = Invalid;
        end
    end
    for (Integer i = 0; i < valueOf(MaxTxnWriteObjs); i = i + 1) begin
        if (fromInteger(i) < txn.numWriteObjs) begin
            res.writeObjs[i] = Valid(hashObject(txn.writeObjs[i]));
        end else begin
            res.writeObjs[i] = Invalid;
        end
    end
    return res;
endfunction

typedef Server#(Transaction, TxnFingerprint) TxnHasher;

(* synthesize *)
module mkTxnHasher(TxnHasher);
    FIFO#(Transaction) in <- mkBypassFIFO;
    FIFO#(TxnFingerprint) out <- mkPipelineFIFO;

    rule doHash;
        let x = in.first;
        in.deq;
        let y = hashTxn(x);
        out.enq(y);
    endrule

    interface request = toPut(in);
    interface response = toGet(out);
endmodule
