import BasicTypes::*;
import MainTypes::*;
import Vector::*;
import Summary::*;
import StmtFSM::*;
import GetPut::*;
import ClientServer::*;

module mkSummaryTest(Empty);
    let summary <- mkSummary;

    Reg#(Bit#(16)) testCount <- mkReg(0);
    
    // Flag to switch between behaviors
    Bool useSeparateReadWrite = False; // Change to True when implementing separate read-write handling
    
    // Helper function to print a bloom location
    function Action printBloomLocation(BloomLocation loc);
        return action
            for (Integer i = 0; i < valueOf(NumBloomParts); i = i + 1) begin
                Tuple2#(BloomChunkIndex, BloomBitIndex) part = loc[i];
                $display("    Part %0d: chunk=%0d, bit=%0d", i, tpl_1(part), tpl_2(part));
            end
        endaction;
    endfunction
    
    // Helper function to print a fingerprint in detail
    function Action printFingerprint(TxnFingerprint fp);
        return action
            $display("  TxnFingerprint Details:");
            $display("  Read Objects:");
            for (Integer i = 0; i < valueOf(MaxTxnReadObjs); i = i + 1) begin
                if (isValid(fp.readObjs[i])) begin
                    $display("    Read Obj %0d:", i);
                    printBloomLocation(fromMaybe(?, fp.readObjs[i]));
                end
            end
            $display("  Write Objects:");
            for (Integer i = 0; i < valueOf(MaxTxnWriteObjs); i = i + 1) begin
                if (isValid(fp.writeObjs[i])) begin
                    $display("    Write Obj %0d:", i);
                    printBloomLocation(fromMaybe(?, fp.writeObjs[i]));
                end
            end
        endaction;
    endfunction
    
    // Helper function to check result against expected outcome
    function Action checkResult(Bool expected, String testName);
        return action
            let compat <- summary.checks.response.get;
            $display("\n=== Test %0d Result: %s ===", testCount, testName);
            $display("Expected: %s, Got: %s", expected ? "Compatible" : "Conflict", compat ? "Compatible" : "Conflict");
            
            if (compat != expected) begin
                $display("TEST FAILED: Expected %s but got %s for test %0d: %s", 
                    expected ? "Compatible" : "Conflict", 
                    compat ? "Compatible" : "Conflict", 
                    testCount, testName);
                $finish;
            end else begin
                $display("TEST PASSED!");
            end
            testCount <= testCount + 1;
        endaction;
    endfunction
    
    // Helper function to create a TxnFingerprint with specific locations
    function TxnFingerprint makeFingerprint(Vector#(MaxTxnReadObjs, Maybe#(BloomLocation)) rLocs, 
                                          Vector#(MaxTxnWriteObjs, Maybe#(BloomLocation)) wLocs);
        TxnFingerprint fp = unpack(0);
        fp.readObjs = rLocs;
        fp.writeObjs = wLocs;
        return fp;
    endfunction
    
    // Helper function to create a BloomLocation for a specific object ID
    function Maybe#(BloomLocation) makeLocationForObject(ObjectId objId, Bool isValid);
        if (!isValid) begin
            return Invalid;
        end else begin
            // Create a deterministic but unique bloom location for each object
            BloomLocation loc = newVector;
            
            // Use lower bits of the objId to create chunk and bit indices
            // This creates predictable but distinct patterns for different objects
            for (Integer part = 0; part < valueOf(NumBloomParts); part = part + 1) begin
                // Use different parts of the objId for different bloom parts
                Bit#(8) chunk_seed = objId[7:0] + fromInteger(part * 37);
                Bit#(8) bit_seed = objId[15:8] + fromInteger(part * 41);
                
                // Ensure we stay within valid range
                BloomChunkIndex chunkIdx = truncate(chunk_seed);
                BloomBitIndex bitIdx = truncate(bit_seed);
                
                loc[part] = tuple2(chunkIdx, bitIdx);
            end
            
            return Valid(loc);
        end
    endfunction
    
    // Helper to print object IDs in a readable format
    function Action printObjectIds(Vector#(n, ObjectId) objs, TCount#(n) numObjs, String prefix);
        return action
            $write("  %s: [", prefix);
            Bool first = True;
            for (Integer i = 0; i < valueOf(n); i = i + 1) begin
                if (fromInteger(i) < numObjs) begin
                    if (!first) $write(", ");
                    $write("%0d", objs[i]);
                    first = False;
                end
            end
            $display("]");
        endaction;
    endfunction
    
    // Helper to add a transaction fingerprint to the summary
    function Action addFingerprint(Vector#(MaxTxnReadObjs, ObjectId) rObjs, TCount#(MaxTxnReadObjs) numR, 
                                 Vector#(MaxTxnWriteObjs, ObjectId) wObjs, TCount#(MaxTxnWriteObjs) numW,
                                 String desc);
        return action
            $display("\n\n=== Adding Transaction %0d: %s ===", testCount, desc);
            $display("  Current count: %0d", summary.getCount);
            printObjectIds(rObjs, numR, "Read Objects");
            printObjectIds(wObjs, numW, "Write Objects");
            
            // Create bloom locations for each read object
            Vector#(MaxTxnReadObjs, Maybe#(BloomLocation)) readLocs = newVector;
            for (Integer i = 0; i < valueOf(MaxTxnReadObjs); i = i + 1) begin
                if (fromInteger(i) < numR) begin
                    readLocs[i] = makeLocationForObject(rObjs[i], True);
                end else begin
                    readLocs[i] = Invalid;
                end
            end
            
            // Create bloom locations for each write object
            Vector#(MaxTxnWriteObjs, Maybe#(BloomLocation)) writeLocs = newVector;
            for (Integer i = 0; i < valueOf(MaxTxnWriteObjs); i = i + 1) begin
                if (fromInteger(i) < numW) begin
                    writeLocs[i] = makeLocationForObject(wObjs[i], True);
                end else begin
                    writeLocs[i] = Invalid;
                end
            end
            
            // Create the fingerprint and add it to the summary
            let fp = makeFingerprint(readLocs, writeLocs);
            printFingerprint(fp);
            $display("  Adding fingerprint to summary...");
            summary.txns.put(fp);
        endaction;
    endfunction
    
    // Helper to check compatibility of a transaction fingerprint
    function Action checkFingerprint(Vector#(MaxTxnReadObjs, ObjectId) rObjs, TCount#(MaxTxnReadObjs) numR, 
                                   Vector#(MaxTxnWriteObjs, ObjectId) wObjs, TCount#(MaxTxnWriteObjs) numW,
                                   Bool shouldBeCompatible, String desc);
        return action
            $display("\n\n=== Checking Transaction %0d: %s ===", testCount, desc);
            printObjectIds(rObjs, numR, "Read Objects");
            printObjectIds(wObjs, numW, "Write Objects");
            $display("  Expected Result: %s (useSeparateReadWrite = %s)", 
                shouldBeCompatible ? "Compatible" : "Conflict",
                useSeparateReadWrite ? "True" : "False");
            
            // Create bloom locations for each read object
            Vector#(MaxTxnReadObjs, Maybe#(BloomLocation)) readLocs = newVector;
            for (Integer i = 0; i < valueOf(MaxTxnReadObjs); i = i + 1) begin
                if (fromInteger(i) < numR) begin
                    readLocs[i] = makeLocationForObject(rObjs[i], True);
                end else begin
                    readLocs[i] = Invalid;
                end
            end
            
            // Create bloom locations for each write object
            Vector#(MaxTxnWriteObjs, Maybe#(BloomLocation)) writeLocs = newVector;
            for (Integer i = 0; i < valueOf(MaxTxnWriteObjs); i = i + 1) begin
                if (fromInteger(i) < numW) begin
                    writeLocs[i] = makeLocationForObject(wObjs[i], True);
                end else begin
                    writeLocs[i] = Invalid;
                end
            end
            
            // Create the fingerprint and check compatibility
            let fp = makeFingerprint(readLocs, writeLocs);
            printFingerprint(fp);
            $display("  Checking fingerprint against summary...");
            summary.checks.request.put(fp);
        endaction;
    endfunction
    
    let fsm <- mkAutoFSM(seq
        $display("\n===== SUMMARY TEST STARTING =====");
        $display("Mode: useSeparateReadWrite = %s", useSeparateReadWrite ? "True" : "False");
        
        // Basic setup - add initial transactions
        
        // CASE 1: Add transaction with reads = {100, 101}, writes = {200}
        action
            Vector#(MaxTxnReadObjs, ObjectId) readObjs = replicate(0);
            readObjs[0] = 100;
            readObjs[1] = 101;
            
            Vector#(MaxTxnWriteObjs, ObjectId) writeObjs = replicate(0);
            writeObjs[0] = 200;
            
            addFingerprint(readObjs, 2, writeObjs, 1, "Initial transaction");
        endaction
        
        $display("\n----- TEST GROUP 1: Read-Read Compatibility Tests -----");
        
        // CASE 2: Read-Read overlap: different behavior based on mode
        action
            Vector#(MaxTxnReadObjs, ObjectId) readObjs = replicate(0);
            readObjs[0] = 100; // Overlaps with read from Case 1
            
            Vector#(MaxTxnWriteObjs, ObjectId) writeObjs = replicate(0);
            
            // NOTE: This test specifically respects useSeparateReadWrite
            checkFingerprint(readObjs, 1, writeObjs, 0, useSeparateReadWrite ? True : False, "Read-Read overlap");
        endaction
        checkResult(useSeparateReadWrite ? True : False, "Read-Read overlap");
        
        // CASE 3: Read-Read with different objects: should always be compatible
        action
            Vector#(MaxTxnReadObjs, ObjectId) readObjs = replicate(0);
            readObjs[0] = 102; // New object, no overlap
            
            Vector#(MaxTxnWriteObjs, ObjectId) writeObjs = replicate(0);
            
            checkFingerprint(readObjs, 1, writeObjs, 0, True, "Read-Read different objects");
        endaction
        checkResult(True, "Read-Read different objects");
        
        $display("\n----- TEST GROUP 2: Read-Write Conflict Tests -----");
        
        // CASE 4: Read-Write conflict (read existing write)
        action
            Vector#(MaxTxnReadObjs, ObjectId) readObjs = replicate(0);
            readObjs[0] = 200; // Tries to read object that is written by Case 1
            
            Vector#(MaxTxnWriteObjs, ObjectId) writeObjs = replicate(0);
            
            // This should be a conflict regardless of useSeparateReadWrite
            checkFingerprint(readObjs, 1, writeObjs, 0, False, "Read-Write conflict (read existing write)");
        endaction
        checkResult(False, "Read-Write conflict (read existing write)");
        
        // CASE 5: Read-Write conflict (write existing read)
        action
            Vector#(MaxTxnReadObjs, ObjectId) readObjs = replicate(0);
            
            Vector#(MaxTxnWriteObjs, ObjectId) writeObjs = replicate(0);
            writeObjs[0] = 101; // Tries to write object that is read by Case 1
            
            // This should be a conflict regardless of useSeparateReadWrite
            checkFingerprint(readObjs, 0, writeObjs, 1, False, "Read-Write conflict (write existing read)");
        endaction
        checkResult(False, "Read-Write conflict (write existing read)");
        
        $display("\n----- TEST GROUP 3: Write-Write Conflict Tests -----");
        
        // CASE 6: Write-Write conflict
        action
            Vector#(MaxTxnReadObjs, ObjectId) readObjs = replicate(0);
            
            Vector#(MaxTxnWriteObjs, ObjectId) writeObjs = replicate(0);
            writeObjs[0] = 200; // Tries to write object that is written by Case 1
            
            // This should be a conflict regardless of useSeparateReadWrite
            checkFingerprint(readObjs, 0, writeObjs, 1, False, "Write-Write conflict");
        endaction
        checkResult(False, "Write-Write conflict");
        
        // CASE 7: Write to different object: should be compatible in both modes
        action
            Vector#(MaxTxnReadObjs, ObjectId) readObjs = replicate(0);
            
            Vector#(MaxTxnWriteObjs, ObjectId) writeObjs = replicate(0);
            writeObjs[0] = 201; // New object, no overlap
            
            checkFingerprint(readObjs, 0, writeObjs, 1, True, "Write to different object");
        endaction
        checkResult(True, "Write to different object");
        
        $display("\n----- Setting Up Complex Scenario -----");
        
        // CASE 8: Add a transaction with multiple reads and writes
        action
            Vector#(MaxTxnReadObjs, ObjectId) readObjs = replicate(0);
            readObjs[0] = 300;
            readObjs[1] = 301;
            readObjs[2] = 302;
            
            Vector#(MaxTxnWriteObjs, ObjectId) writeObjs = replicate(0);
            writeObjs[0] = 400;
            writeObjs[1] = 401;
            
            addFingerprint(readObjs, 3, writeObjs, 2, "Complex transaction");
        endaction
        
        $display("\n----- TEST GROUP 4: Complex Scenarios -----");
        
        // CASE 9: Mixed scenario - read existing read, write new object
        action
            Vector#(MaxTxnReadObjs, ObjectId) readObjs = replicate(0);
            readObjs[0] = 301; // Read from Case 8
            
            Vector#(MaxTxnWriteObjs, ObjectId) writeObjs = replicate(0);
            writeObjs[0] = 500; // New write
            
            // NOTE: This test specifically respects useSeparateReadWrite
            checkFingerprint(readObjs, 1, writeObjs, 1, useSeparateReadWrite ? True : False, "Read existing read, write new object");
        endaction
        checkResult(useSeparateReadWrite ? True : False, "Read existing read, write new object");
        
        // CASE 10: Mixed scenario - read one existing read, write one existing write
        action
            Vector#(MaxTxnReadObjs, ObjectId) readObjs = replicate(0);
            readObjs[0] = 302; // Read from Case 8
            
            Vector#(MaxTxnWriteObjs, ObjectId) writeObjs = replicate(0);
            writeObjs[0] = 400; // Write from Case 8
            
            // This should be a conflict regardless of useSeparateReadWrite
            checkFingerprint(readObjs, 1, writeObjs, 1, False, "Read existing read, write existing write");
        endaction
        checkResult(False, "Read existing read, write existing write");
        
        // CASE 11: Mixed scenario - read new object, write existing read
        action
            Vector#(MaxTxnReadObjs, ObjectId) readObjs = replicate(0);
            readObjs[0] = 303; // New read
            
            Vector#(MaxTxnWriteObjs, ObjectId) writeObjs = replicate(0);
            writeObjs[0] = 300; // Read from Case 8
            
            // This should be a conflict regardless of useSeparateReadWrite
            checkFingerprint(readObjs, 1, writeObjs, 1, False, "Read new object, write existing read");
        endaction
        checkResult(False, "Read new object, write existing read");
        
        $display("\n----- TEST GROUP 5: Edge Cases -----");
        
        // CASE 12: Empty transaction - should always be compatible
        action
            Vector#(MaxTxnReadObjs, ObjectId) readObjs = replicate(0);
            Vector#(MaxTxnWriteObjs, ObjectId) writeObjs = replicate(0);
            
            checkFingerprint(readObjs, 0, writeObjs, 0, True, "Empty transaction");
        endaction
        checkResult(True, "Empty transaction");
        
        // CASE 13: Max objects transaction - testing boundary
        action
            Vector#(MaxTxnReadObjs, ObjectId) readObjs = replicate(0);
            for (Integer i = 0; i < valueOf(MaxTxnReadObjs); i = i + 1) begin
                readObjs[i] = fromInteger(1000 + i);
            end
            
            Vector#(MaxTxnWriteObjs, ObjectId) writeObjs = replicate(0);
            for (Integer i = 0; i < valueOf(MaxTxnWriteObjs); i = i + 1) begin
                writeObjs[i] = fromInteger(2000 + i);
            end
            
            addFingerprint(readObjs, fromInteger(valueOf(MaxTxnReadObjs)), 
                         writeObjs, fromInteger(valueOf(MaxTxnWriteObjs)), 
                         "Max objects transaction");
        endaction
        
        // CASE 14: Test with same max transaction - should conflict in both modes
        action
            Vector#(MaxTxnReadObjs, ObjectId) readObjs = replicate(0);
            for (Integer i = 0; i < valueOf(MaxTxnReadObjs); i = i + 1) begin
                readObjs[i] = fromInteger(1000 + i);
            end
            
            Vector#(MaxTxnWriteObjs, ObjectId) writeObjs = replicate(0);
            for (Integer i = 0; i < valueOf(MaxTxnWriteObjs); i = i + 1) begin
                writeObjs[i] = fromInteger(2000 + i);
            end
            
            // This should be a conflict regardless of useSeparateReadWrite
            // since it's writing to the same objects as Case 13
            checkFingerprint(readObjs, fromInteger(valueOf(MaxTxnReadObjs)), 
                           writeObjs, fromInteger(valueOf(MaxTxnWriteObjs)), 
                           False, "Same max objects transaction");
        endaction
        checkResult(False, "Same max objects transaction");
        
        $display("\n----- TEST GROUP 6: Bug Detection Tests -----");
        
        // Test specifically targeting the bug in checkOrAddToChunk
        // CASE 15: Write object test - verify writeObjFound is checked correctly
        action
            // First, add a transaction with only write objects
            Vector#(MaxTxnReadObjs, ObjectId) readObjs1 = replicate(0);
            
            Vector#(MaxTxnWriteObjs, ObjectId) writeObjs1 = replicate(0);
            writeObjs1[0] = 600;
            
            addFingerprint(readObjs1, 0, writeObjs1, 1, "Write-only transaction");
        endaction
        
        action
            // Now check if a transaction with the same write object is incompatible
            Vector#(MaxTxnReadObjs, ObjectId) readObjs2 = replicate(0);
            
            Vector#(MaxTxnWriteObjs, ObjectId) writeObjs2 = replicate(0);
            writeObjs2[0] = 600;
            
            // This should be a conflict regardless of useSeparateReadWrite
            // Critical bug check: if writeObjFound array is not checked correctly
            // this test will fail
            checkFingerprint(readObjs2, 0, writeObjs2, 1, False, "Write-Write conflict with previous test");
        endaction
        checkResult(False, "Write-Write conflict with previous test");
        
        // Final display
        action
            $display("\n\n===== TEST SUMMARY =====");
            $display("All %0d tests passed!", testCount);
            $display("Mode: useSeparateReadWrite = %s", useSeparateReadWrite ? "True" : "False");
            $display("======= END OF TEST =======\n");
        endaction
        
    endseq);
endmodule
