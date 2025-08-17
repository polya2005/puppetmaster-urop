import FIFOF::*;
import Vector::*;
import Assert::*;
import StmtFSM::*;
import VisibleFIFOF::*;

// Test module for the VisibleFIFOF
module mkVisibleFIFOFTest(Empty);
    // Create a VisibleFIFOF instance with Int#(32) elements and depth 15
    VisibleFIFOF#(Bit#(32), 15) fifo <- mkVisibleFIFOF;
    
    // For tracking test status
    Reg#(Bool) testPassed <- mkReg(True);
    Reg#(UInt#(32)) testCount <- mkReg(0);
    
    // Helper function to report test failures
    function Action testFailed(String message);
        action
            $display("TEST FAILED: %s", message);
            testPassed <= False;
        endaction
    endfunction

    Reg#(UInt#(4)) i <- mkReg(0);
    
    // Sequence of test operations using StmtFSM
    Stmt testSeq = seq
        // Test 1: Initial conditions
        $display("Test 1: Checking initial conditions");
        if (!fifo.notFull) testFailed("FIFO should be initially empty and not full");
        if (fifo.notEmpty) testFailed("FIFO should be initially empty");
        if (fifo.count != 0) testFailed("FIFO count should be 0");
        testCount <= testCount + 1;
        
        // Test 2: Basic enqueue and dequeue operations
        $display("Test 2: Testing basic enq/deq operations");
        // Enqueue a value
        fifo.enq(42);
        if (!fifo.notEmpty) testFailed("FIFO should not be empty after enqueue");
        if (fifo.count != 1) testFailed("FIFO count should be 1 after single enqueue");
        if (fifo.first != 42) testFailed("FIFO first element should be 42");
        if (fifo.peek(0) != 42) testFailed("FIFO peek(0) should return 42");
        
        // Dequeue the value
        fifo.deq();
        if (fifo.notEmpty) testFailed("FIFO should be empty after dequeuing only element");
        if (fifo.count != 0) testFailed("FIFO count should be 0 after dequeuing all elements");
        testCount <= testCount + 1;
        
        // Test 3: Fill FIFO to capacity
        $display("Test 3: Testing FIFO at full capacity");
        // Fill the FIFO
        for (i <= 0; i < 15; i <= i + 1) seq
            fifo.enq(extend(pack(i)));
        endseq
        
        if (fifo.notFull) testFailed("FIFO should be full after enqueueing 15 elements");
        if (fifo.count != 15) testFailed("FIFO count should be 15");
        
        // Check peek functionality for all elements
        for (i <= 0; i < 15; i <= i + 1) seq
            if (fifo.peek(i) != extend(pack(i)))
                testFailed("FIFO peek returned incorrect value");
        endseq
        testCount <= testCount + 1;
        
        // Test 4: Dequeue and enqueue in a cycle
        $display("Test 4: Testing dequeue followed by enqueue");
        fifo.deq();  // Remove first element (0)
        if (!fifo.notFull) testFailed("FIFO should not be full after one dequeue");
        if (fifo.count != 14) testFailed("FIFO count should be 14 after one dequeue");
        if (fifo.first != 1) testFailed("FIFO first element should be 1 after dequeue");
        
        fifo.enq(100);  // Add a new element
        if (fifo.notFull) testFailed("FIFO should be full again after enqueueing");
        if (fifo.count != 15) testFailed("FIFO count should be 15");
        testCount <= testCount + 1;
        
        // Test 5: Wrap-around behavior
        $display("Test 5: Testing wrap-around behavior");
        // Dequeue all elements
        for (i <= 0; i < 15; i <= i + 1) seq
            fifo.deq();
        endseq
        
        if (fifo.notEmpty) testFailed("FIFO should be empty after dequeuing all elements");
        if (fifo.count != 0) testFailed("FIFO count should be 0");
        
        // Re-fill the FIFO to test wrap-around
        for (i <= 0; i < 15; i <= i + 1) seq
            fifo.enq(pack(200 + extend(i)));
        endseq
        
        if (fifo.notFull) testFailed("FIFO should be full after re-filling");
        if (fifo.count != 15) testFailed("FIFO count should be 15");
        if (fifo.first != 200) testFailed("FIFO first element should be 200");
        testCount <= testCount + 1;
        
        // Test 6: Mixed enqueue/dequeue operations
        $display("Test 6: Testing mixed enqueue/dequeue operations");
        // Dequeue half the elements
        for (i <= 0; i < 7; i <= i + 1) seq
            fifo.deq();
        endseq
        
        if (fifo.count != 8) testFailed("FIFO count should be 8 after dequeuing 7 elements");
        if (fifo.first != 207) testFailed("FIFO first element should be 207");
        
        // Enqueue some new elements
        for (i <= 0; i < 5; i <= i + 1) seq
            fifo.enq(pack(300 + extend(i)));
        endseq
        
        if (fifo.count != 13) testFailed("FIFO count should be 13 after mixed operations");
        // Check peek for the newly added elements
        if (fifo.peek(8) != 300) testFailed("FIFO peek(8) should be 300");
        testCount <= testCount + 1;
        
        // Test 7: Edge case - empty then fill to capacity
        $display("Test 7: Testing edge case - empty then fill to capacity");
        // Dequeue all elements
        for (i <= 0; i < 13; i <= i + 1) seq
            fifo.deq();
        endseq
        
        if (fifo.notEmpty) testFailed("FIFO should be empty");
        
        // Fill to capacity again
        for (i <= 0; i < 15; i <= i + 1) seq
            fifo.enq(pack(400 + extend(i)));
        endseq
        
        if (fifo.notFull) testFailed("FIFO should be full after filling to capacity");
        if (fifo.count != 15) testFailed("FIFO count should be 15");
        if (fifo.first != 400) testFailed("FIFO first element should be 400");
        testCount <= testCount + 1;
        
        // Final results
        if (testPassed) 
            $display("ALL TESTS PASSED! (%0d test cases)", testCount);
        else
            $display("SOME TESTS FAILED! Check logs for details");
        
        $finish(0);
    endseq;
    
    // Create the test FSM
    FSM testFSM <- mkFSM(testSeq);
    
    // Rule to start the tests
    rule startTests (True);
        testFSM.start();
    endrule
    
endmodule
