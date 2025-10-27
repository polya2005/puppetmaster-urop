`timescale 1ns / 1ps
`default_nettype none

module uart_transmit #(
    parameter INPUT_CLOCK_FREQ = 100_000_000,
    parameter BAUD_RATE = 9600
) (
    input wire clk,
    input wire rst,
    input wire [7:0] din,
    input wire trigger,
    output logic busy,
    output logic dout
);
  localparam CLOCKS_PER_BIT = INPUT_CLOCK_FREQ / BAUD_RATE;
  localparam CLOCK_COUNTER_WIDTH = $clog2(CLOCKS_PER_BIT);

  logic [7:0] saved_din;
  logic [CLOCK_COUNTER_WIDTH-1:0] clock_counter;
  logic [3:0] bit_counter;

  always_ff @(posedge clk) begin
    if (rst) begin
      busy <= 1'b0;
      dout <= 1'b1;
      clock_counter <= {CLOCK_COUNTER_WIDTH{1'b0}};
      bit_counter <= 0;
    end else begin
      if (trigger && !busy) begin
        busy <= 1'b1;
        saved_din <= din;
        dout <= 1'b0;  // Start bit
        clock_counter <= {CLOCK_COUNTER_WIDTH{1'b0}};
        bit_counter <= 0;
      end else if (busy) begin
        if (clock_counter == CLOCKS_PER_BIT - 1) begin
          clock_counter <= 0;  // reset clock before next bit
          if (bit_counter < 8) begin
            dout <= saved_din[0];  // lsb first
            saved_din <= {1'b0, saved_din[7:1]};
          end else if (bit_counter == 8) begin  // stop bit
            dout <= 1'b1;
          end else begin  // end of transmission
            busy <= 1'b0;
            dout <= 1'b1;
          end
          bit_counter <= bit_counter + 1;
        end else begin
          clock_counter <= clock_counter + 1;
        end
      end
    end
  end

endmodule  // uart_transmit

`default_nettype wire
