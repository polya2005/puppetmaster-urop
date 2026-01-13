import BasicTypes::*;
import Vector::*;

/*
Utility
*/
typedef Bit#(TLog#(size)) TIndex#(numeric type size);
typedef Bit#(TAdd#(1, TLog#(size))) TCount#(numeric type size);

/*
Input transaction into Puppetmaster
*/
Integer maxTxnReadObjs = valueOf(MaxTxnReadObjs);
Integer maxTxnWriteObjs = valueOf(MaxTxnWriteObjs);

typedef struct {
    TransactionId txnId;
    AuxData auxData;
    // TODO: is it less circuit to use vector of maybe type than add a comparator for num objs?
    TCount#(MaxTxnReadObjs) numReadObjs;
    Vector#(MaxTxnReadObjs, ObjectId) readObjs;
    TCount#(MaxTxnWriteObjs) numWriteObjs;
    Vector#(MaxTxnWriteObjs, ObjectId) writeObjs;
} Transaction deriving (Bounded, Bits, Eq, FShow);

typedef 4 NumBloomParts;
typedef 4 NumBloomChunks;  // Tweak this
typedef 256 BloomChunkSize;  // Tweak this

typedef TIndex#(NumBloomParts) BloomPartIndex;
typedef TIndex#(NumBloomChunks) BloomChunkIndex;
typedef TIndex#(BloomChunkSize) BloomBitIndex;

typedef TMul#(NumBloomChunks, BloomChunkSize) BloomPartSize;
typedef Bit#(BloomChunkSize) BloomChunk;
typedef Vector#(NumBloomParts, Bit#(BloomChunkSize)) BloomChunkParts;

// Location within one part (chunk, big)
typedef Tuple2#(BloomChunkIndex, BloomBitIndex) BloomPartLocation;

// Location for all parts
typedef Vector#(NumBloomParts, BloomPartLocation) BloomLocation;

typedef struct {
    TransactionId txnId;
    AuxData auxData;
    // TODO: is it less circuit to use vector of maybe type than add a comparator for num objs?
    // i decided to use vector of maybe here for fun.
    Vector#(MaxTxnReadObjs, Maybe#(BloomLocation)) readObjs;
    Vector#(MaxTxnWriteObjs, Maybe#(BloomLocation)) writeObjs;
} TxnFingerprint deriving (DefaultValue, Bits, Eq, FShow);

typedef Bit#(20) BloomObjCount;
