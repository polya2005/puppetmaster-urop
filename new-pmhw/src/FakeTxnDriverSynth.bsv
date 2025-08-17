import TxnDriver::*;

module mkFakeTxnDriverSynth(FakeTxnDriver);
    FakeTxnDriver d <- mkFakeTxnDriver;
    return d;
endmodule
