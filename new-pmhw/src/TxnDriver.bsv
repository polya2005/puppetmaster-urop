import BasicTypes::*;
import MainTypes::*;
import GetPut::*;
import FIFO::*;
import SpecialFIFOs::*;
import Vector::*;
import BRAMFIFO::*;

/*
Input side of the Puppetmaster scheduler.
*/
interface TxnDriver;
    /*
    Transactions to be made available to Puppetmaster.
    */
    interface Get#(Transaction) transactions;
endinterface


/*
Input MUX
*/
interface TxnDriverMux#(numeric type n);
    method Action select(TIndex#(n) idx);
    method TIndex#(n) selected;
    interface TxnDriver txnDriver;
endinterface

module mkTxnDriverMux(Vector#(n, TxnDriver) txnDrivers, TxnDriverMux#(n) ifc);
    Reg#(TIndex#(n)) index <- mkRegU;

    method Action select(TIndex#(n) idx);
        index <= idx;
    endmethod

    method TIndex#(n) selected = index;

    interface txnDriver = txnDrivers[index];
endmodule


/*
Real transaction driver that takes data from the host CPU.
*/
interface RealTxnDriver;
    interface Put#(Transaction) fromHost;
    interface TxnDriver txnDriver;
endinterface

(* synthesize *)
module mkRealTxnDriver(RealTxnDriver);
    FIFO#(Transaction) hostFF <- mkBypassFIFO;

    interface fromHost = toPut(hostFF);
    interface TxnDriver txnDriver;
        interface transactions = toGet(hostFF);
    endinterface
endmodule

/*
Fake transaction driver
*/
interface FakeTxnDriver;
    method Action resetState;
    interface Put#(Transaction) fromHost;
    method Action trigger;
    interface TxnDriver txnDriver;
    method Action setDuration(Timestamp duration);
    method Timestamp getDuration;
endinterface

// 432 * 2^12 = 1.7 Mb
typedef 12 LogFakeTxnBRAMSize;
typedef TExp#(LogFakeTxnBRAMSize) FakeTxnBRAMSize;
typedef Bit#(LogFakeTxnBRAMSize) FakeTxnBRAMAddr;

(* synthesize *)
module mkFakeTxnDriver(FakeTxnDriver);
    Reg#(Timestamp) cycle <- mkReg(0);
    FIFO#(Transaction) txns <- mkSizedBRAMFIFO(valueOf(FakeTxnBRAMSize));
    Reg#(Bool) started <- mkReg(False);
    Reg#(FakeTxnBRAMAddr) outCount <- mkReg(0);

    Reg#(Timestamp) totalWaitTime <- mkReg(0);
    Reg#(Timestamp) waitTimer <- mkReg(0);

    FIFO#(Transaction) outFF <- mkBypassFIFO;

    (* no_implicit_conditions, fire_when_enabled *)
    rule tick;
        cycle <= cycle+1;
    endrule

    rule populate_txn if (started);
        if (waitTimer >= totalWaitTime) begin
            let txn <- toGet(txns).get;
            outCount <= outCount+1;
            `ifdef DEBUG_DRIVER
            $fdisplay(stderr, "[%0d] FakeTxnDriver: Txn returned ", cycle, fshow(txn));
            `endif
            $display("[%0d] txn_id=%0d submitted", cycle, txn.txnId);
            outFF.enq(txn);
            waitTimer <= 0;
        end else begin
            waitTimer <= waitTimer+1;
        end
    endrule

    method Action resetState;
        txns.clear();
        started <= False;
        outCount <= 0;
        waitTimer <= 0;
        `ifdef DEBUG_DRIVER
        $fdisplay(stderr, "[%0d] FakeTxnDriver: resetState", cycle);
        `endif
    endmethod

    interface Put fromHost;
        method Action put(Transaction txn);
            txns.enq(txn);
            `ifdef DEBUG_DRIVER
            $fdisplay(stderr, "[%0d] FakeTxnDriver: enqueued ", cycle, fshow(txn));
            `endif
        endmethod
    endinterface

    method Action trigger;
        started <= True;
        `ifdef DEBUG_DRIVER
        $fdisplay(stderr, "[%0d] FakeTxnDriver: triggered", cycle);
        `endif
    endmethod

    interface TxnDriver txnDriver;
        interface transactions = toGet(outFF);
    endinterface

    method Action setDuration(Timestamp duration);
        totalWaitTime <= duration;
    endmethod

    method Timestamp getDuration;
        return totalWaitTime;
    endmethod
endmodule
