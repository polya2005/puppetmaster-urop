import BasicTypes::*;
import MainTypes::*;
import Puppetmaster::*;
import TxnDriver::*;
import Executor::*;
import Vector::*;
import GetPut::*;
import Connectable::*;
import ClientServer::*;
import Clocks::*;
import Assert::*;

/*
Top-level configuration for testing
*/
typedef struct {
    Bool useSimulatedTxnDriver;
    Bool useSimulatedPuppets;
    Bit#(16) numPuppets; // 16 is hardcoded because Connectal doesn't like TCount
    Timestamp puppetSimCycles;
    Timestamp txnDriverWaitCycles;
} TopConfig deriving (Bits, Eq, FShow);

/*
Connectal software-to-hardware interface.
*/
interface S2HMessage;
    /*
    Force reset everything
    */
    method Action systemReset;
    /*
    Get current configuration values.
    */
    method Action fetchConfig;
    /*
    Set configuration values.
    */
    method Action setConfig(TopConfig cfg);
    /*
    Add transaction to Puppetmaster.
    */
    method Action addTransaction(
        TransactionId txnId,
        AuxData auxData,
        Bit#(4) numReadObjs, // 4 is hardcoded because Connectal doesn't like TCount
        ObjectId readObj0, // Connectal also doesn't like Array or Vector
        ObjectId readObj1,
        ObjectId readObj2,
        ObjectId readObj3,
        ObjectId readObj4,
        ObjectId readObj5,
        ObjectId readObj6,
        ObjectId readObj7,
        Bit#(4) numWriteObjs, // 4 is hardcoded because Connectal doesn't like TCount
        ObjectId writeObj0,
        ObjectId writeObj1,
        ObjectId writeObj2,
        ObjectId writeObj3,
        ObjectId writeObj4,
        ObjectId writeObj5,
        ObjectId writeObj6,
        ObjectId writeObj7
    );
    /*
    For fake transactions, a trigger is needed to send transactions to Puppetmaster.
    */
    method Action triggerDriver;
    /*
    For host to report that it has completed a transaction
    */
    method Action reportWorkDone(TransactionId txnId);
endinterface

/*
Connectal hardware-to-software interface.
*/
interface H2SMessage;
    method Action configData(TopConfig cfg);
    method Action transactionScheduled(TransactionId txnId);
endinterface

/*
Connectal automatically sets up software-to-host communication based on this interface.
We simply need to implement those interfaces so the hardware knows what to do with these messages.
*/
interface Connectal;
    interface S2HMessage s2h;
endinterface

module mkConnectal#(
    /*
    Connectal automatically sets up host-to-software communication based on this interface.
    Hardware can call these "indication" methods to send messages.
    */
    H2SMessage h2s
)(Connectal);

    // Input side
    RealTxnDriver realTxnDriver <- mkRealTxnDriver;
    FakeTxnDriver fakeTxnDriver <- mkFakeTxnDriver;
    TxnDriver allTxnDrivers[2] = {
        realTxnDriver.txnDriver,
        fakeTxnDriver.txnDriver
    };
    TxnDriverMux#(2) txnDriverMux <- mkTxnDriverMux(arrayToVector(allTxnDrivers));

    // Processing component
    // Create the actual Puppetmaster instance.
    Puppetmaster pm <- mkPuppetmaster;

    // Output side
    RealExecutor realExecutor <- mkRealExecutor;
    FakeExecutor fakeExecutor <- mkFakeExecutor;
    Executor allExecutors[2] = {
        realExecutor.executor,
        fakeExecutor.executor
    };
    ExecutorMux#(2) executorMux <- mkExecutorMux(arrayToVector(allExecutors));

    /*
    Internal connections
    */

    // Input side to processing component
    mkConnection(txnDriverMux.txnDriver.transactions, pm.transactions);

    // Processing component to output side
    mkConnection(pm.scheduled, executorMux.executor.request);

    // Output side back to processing component (free the completed transactions)
    mkConnection(executorMux.executor.response, toPut(pm.workDone));

    // Real executor controller pipes result back to host
    // so host can do the work
    mkConnection(realExecutor.toHost, toPut(h2s.transactionScheduled));

    /*
    External interfaces
    */
    interface S2HMessage s2h;
        method Action systemReset();
            // TODO
        endmethod

        method Action fetchConfig();
            h2s.configData(TopConfig {
                useSimulatedTxnDriver: txnDriverMux.selected == 1,
                useSimulatedPuppets: executorMux.selected == 1,
                numPuppets: extend(pm.getNumPuppets),
                puppetSimCycles: fakeExecutor.getDuration,
                txnDriverWaitCycles: fakeTxnDriver.getDuration
            });
        endmethod

        method Action setConfig(TopConfig cfg);
            dynamicAssert(cfg.numPuppets < fromInteger(valueOf(MaxNumPuppets)), "cfg.numPuppets must not exceed MaxNumPuppets");
            txnDriverMux.select(cfg.useSimulatedTxnDriver ? 1 : 0);
            executorMux.select(cfg.useSimulatedPuppets ? 1 : 0);
            pm.setNumPuppets(truncate(cfg.numPuppets));
            fakeExecutor.setNumPuppets(truncate(cfg.numPuppets));
            fakeExecutor.setDuration(cfg.puppetSimCycles);
            fakeTxnDriver.setDuration(cfg.txnDriverWaitCycles);
        endmethod

        method Action addTransaction(
            TransactionId txnId,
            AuxData auxData,
            Bit#(4) numReadObjs,
            ObjectId readObj0,
            ObjectId readObj1,
            ObjectId readObj2,
            ObjectId readObj3,
            ObjectId readObj4,
            ObjectId readObj5,
            ObjectId readObj6,
            ObjectId readObj7,
            Bit#(4) numWriteObjs,
            ObjectId writeObj0,
            ObjectId writeObj1,
            ObjectId writeObj2,
            ObjectId writeObj3,
            ObjectId writeObj4,
            ObjectId writeObj5,
            ObjectId writeObj6,
            ObjectId writeObj7
        );
            ObjectId readObjs[8] = {
                readObj0,
                readObj1,
                readObj2,
                readObj3,
                readObj4,
                readObj5,
                readObj6,
                readObj7
            };
            ObjectId writeObjs[8] = {
                writeObj0,
                writeObj1,
                writeObj2,
                writeObj3,
                writeObj4,
                writeObj5,
                writeObj6,
                writeObj7
            };
            let txn = Transaction {
                txnId: txnId,
                auxData: auxData,
                numReadObjs: numReadObjs,
                readObjs: arrayToVector(readObjs),
                numWriteObjs: numWriteObjs,
                writeObjs: arrayToVector(writeObjs)
            };

            if (txnDriverMux.selected == 0) begin
                realTxnDriver.fromHost.put(txn);
            end else if (txnDriverMux.selected == 1) begin
                fakeTxnDriver.fromHost.put(txn);
            end

        endmethod

        method Action triggerDriver;
            fakeTxnDriver.trigger;
        endmethod

        method Action reportWorkDone(TransactionId txnId);
            realExecutor.fromHost.put(txnId);
        endmethod
    endinterface

endmodule
