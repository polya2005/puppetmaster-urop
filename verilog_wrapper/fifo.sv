`timescale 1ns / 1ps
`default_nettype none

module fifo #(
    parameter DEPTH = 16,
    parameter WIDTH = 16
) (
    input wire clk,
    input wire rst,
    input wire write,
    input wire [WIDTH-1:0] data_in,
    output logic full,

    output logic [WIDTH-1:0] data_out,
    input wire read,
    output logic empty
);

  logic [$clog2(DEPTH)-1:0] write_pointer;
  logic [$clog2(DEPTH)-1:0] read_pointer;
  logic [WIDTH-1:0] fifo_[0:DEPTH-1];  //makes BRAM with one unpacked and one packed dimension

  assign full = write_pointer + 1'b1 == read_pointer;
  assign empty = write_pointer == read_pointer;

  assign data_out = fifo_[read_pointer];

  always_ff @(posedge clk) begin
    if (rst) begin
      write_pointer <= 0;
      read_pointer  <= 0;
    end else if (read && !empty) begin
      read_pointer <= read_pointer + 1;
      if (write) begin
        fifo_[write_pointer] <= data_in;
        write_pointer <= write_pointer + 1;
      end
    end else if (write && !full) begin
      fifo_[write_pointer] <= data_in;
      write_pointer <= write_pointer + 1;
    end
  end

endmodule
`default_nettype wire
