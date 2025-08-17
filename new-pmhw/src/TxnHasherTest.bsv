import BasicTypes::*;
import MainTypes::*;
import GetPut::*;
import ClientServer::*;
import Vector::*;
import FIFO::*;
import SpecialFIFOs::*;

// Import the TxnHasher module and related functions
import TxnHasher::*;

module mkTxnHasherTest();
  // Create the transaction hasher module
  TxnHasher hasher <- mkTxnHasher;
  
  // Create a counter for test sequencing
  Reg#(Bit#(32)) testCounter <- mkReg(0);
  
  // Helper function to create a simple transaction
  function Transaction makeSimpleTxn(TransactionId id, TCount#(MaxTxnReadObjs) numReads, TCount#(MaxTxnWriteObjs) numWrites);
    Transaction txn = unpack(0);  // Initialize all to zeros
    
    // Set the transaction ID and auxiliary data
    txn.txnId = id;
    txn.auxData = zeroExtend(id);  // Just using a pattern based on the ID
    
    // Set the number of read and write objects
    txn.numReadObjs = numReads;
    txn.numWriteObjs = numWrites;
    
    // Generate some read objects based on the transaction ID
    for (Integer i = 0; i < valueOf(MaxTxnReadObjs); i = i + 1) begin
      if (fromInteger(i) < numReads) begin
        // Create object IDs with some pattern based on txn ID
        txn.readObjs[i] = id + fromInteger(i) * 100;
      end else begin
        txn.readObjs[i] = 0;
      end
    end
    
    // Generate some write objects based on the transaction ID
    for (Integer i = 0; i < valueOf(MaxTxnWriteObjs); i = i + 1) begin
      if (fromInteger(i) < numWrites) begin
        // Create object IDs with some pattern based on txn ID
        txn.writeObjs[i] = id + 1000 + fromInteger(i) * 100;
      end else begin
        txn.writeObjs[i] = 0;
      end
    end
    
    return txn;
  endfunction
  
  // Helper function to print a transaction
  function Action printTransaction(Transaction txn);
    return action
      $display("Transaction ID: %0d", txn.txnId);
      $display("Aux data: 0x%0h", txn.auxData);
      $display("Number of read objects: %0d", txn.numReadObjs);
      $display("Number of write objects: %0d", txn.numWriteObjs);
      
      for (Integer i = 0; i < valueOf(MaxTxnReadObjs); i = i + 1) begin
        if (fromInteger(i) < txn.numReadObjs) begin
          $display("  Read object %0d: %0h", i, txn.readObjs[i]);
        end
      end
      
      for (Integer i = 0; i < valueOf(MaxTxnWriteObjs); i = i + 1) begin
        if (fromInteger(i) < txn.numWriteObjs) begin
          $display("  Write object %0d: %0h", i, txn.writeObjs[i]);
        end
      end
    endaction;
  endfunction
  
  // Helper function to print a transaction fingerprint
  function Action printTxnFingerprint(TxnFingerprint fp);
    return action
      $display("Transaction Fingerprint:");
      
      $display("  Txn ID: %0d", fp.txnId);
      $display("  Aux data: %0d", fp.auxData);
      for (Integer i = 0; i < valueOf(MaxTxnReadObjs); i = i + 1) begin
        if (isValid(fp.readObjs[i])) begin
          BloomLocation loc = fromMaybe(?, fp.readObjs[i]);
          $display("  Read object %0d hash:", i);
          for (Integer j = 0; j < valueOf(NumBloomParts); j = j + 1) begin
            let part = loc[j];
            let chunkIndex = tpl_1(part);
            let bitIndex = tpl_2(part);
            $display("    Part %0d: chunk=%0d, bit=%0d", j, chunkIndex, bitIndex);
          end
        end
      end
      
      for (Integer i = 0; i < valueOf(MaxTxnWriteObjs); i = i + 1) begin
        if (isValid(fp.writeObjs[i])) begin
          BloomLocation loc = fromMaybe(?, fp.writeObjs[i]);
          $display("  Write object %0d hash:", i);
          for (Integer j = 0; j < valueOf(NumBloomParts); j = j + 1) begin
            let part = loc[j];
            let chunkIndex = tpl_1(part);
            let bitIndex = tpl_2(part);
            $display("    Part %0d: chunk=%0d, bit=%0d", j, chunkIndex, bitIndex);
          end
        end
      end
    endaction;
  endfunction
  
  // Test sequence
  rule test;
    case (testCounter)
      0: begin
        $display("\n=== Starting TxnHasher Test ===\n");
        testCounter <= testCounter + 1;
      end
      
      1: begin
        // Create and send first test transaction
        Transaction txn1 = makeSimpleTxn(32'h12345678, 2, 1);
        $display("\n--- Test Transaction 1 ---");
        printTransaction(txn1);
        hasher.request.put(txn1);
        testCounter <= testCounter + 1;
      end
      
      2: begin
        // Get and print the hash for first transaction
        let fp1 <- hasher.response.get();
        $display("\n--- Hash Result for Transaction 1 ---");
        printTxnFingerprint(fp1);
        testCounter <= testCounter + 1;
      end
      
      3: begin
        // Create and send second test transaction - one that shows boundary effects
        Transaction txn2 = makeSimpleTxn(32'hABCDEF01, fromInteger(valueOf(MaxTxnReadObjs)-1), 3);
        $display("\n--- Test Transaction 2 ---");
        printTransaction(txn2);
        hasher.request.put(txn2);
        testCounter <= testCounter + 1;
      end
      
      4: begin
        // Get and print the hash for second transaction
        let fp2 <- hasher.response.get();
        $display("\n--- Hash Result for Transaction 2 ---");
        printTxnFingerprint(fp2);
        testCounter <= testCounter + 1;
      end
      
      5: begin
        // Create and send third test transaction with no objects
        Transaction txn3 = makeSimpleTxn(32'h00000000, 0, 0);
        $display("\n--- Test Transaction 3 (Empty) ---");
        printTransaction(txn3);
        hasher.request.put(txn3);
        testCounter <= testCounter + 1;
      end
      
      6: begin
        // Get and print the hash for third transaction
        let fp3 <- hasher.response.get();
        $display("\n--- Hash Result for Transaction 3 ---");
        printTxnFingerprint(fp3);
        testCounter <= testCounter + 1;
      end
      
      7: begin
        // Create transaction that tests hash distribution
        Transaction txn4 = unpack(0);
        txn4.txnId = 32'h55555555;
        txn4.auxData = 64'hAAAAAAAAAAAAAAAA;
        txn4.numReadObjs = 1;
        txn4.numWriteObjs = 1;
        
        // Testing a sequence of consecutive object IDs
        txn4.readObjs[0] = 32'h00000001;
        txn4.writeObjs[0] = 32'h00000002;
        
        $display("\n--- Test Transaction 4 (Distribution Test) ---");
        printTransaction(txn4);
        hasher.request.put(txn4);
        testCounter <= testCounter + 1;
      end
      
      8: begin
        // Get and print the hash for fourth transaction
        let fp4 <- hasher.response.get();
        $display("\n--- Hash Result for Transaction 4 ---");
        printTxnFingerprint(fp4);
        testCounter <= testCounter + 1;
      end
      
      9: begin
        $display("\n=== TxnHasher Test Completed ===\n");
        $finish(0);
      end
    endcase
  endrule
  
endmodule
