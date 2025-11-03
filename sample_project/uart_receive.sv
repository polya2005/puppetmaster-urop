`timescale 1ns / 1ps
`default_nettype none

module uart_receive #(
    parameter INPUT_CLOCK_FREQ = 100_000_000,
    parameter BAUD_RATE = 9600
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        din,
    output logic       dout_valid,
    output logic [7:0] dout
);

  typedef enum {
    IDLE = 0,
    START,
    DATA,
    STOP,
    TRANSMIT
  } uart_state;

  localparam CLOCKS_PER_BIT = INPUT_CLOCK_FREQ / BAUD_RATE;
  localparam CLOCKS_PER_HALF_BIT = CLOCKS_PER_BIT / 2;
  localparam CLOCK_COUNTER_WIDTH = $clog2(CLOCKS_PER_BIT);

  // note: for the online checker, don't rename this variable
  uart_state state;
  logic [CLOCK_COUNTER_WIDTH-1:0] clock_counter;
  logic [3:0] bit_counter;

  initial begin
    state = IDLE;
    dout_valid = 0;
    dout = 0;
    clock_counter = 0;
    bit_counter = 0;
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      state <= IDLE;
      dout_valid <= 0;
      dout <= 0;
      clock_counter <= 0;
      bit_counter <= 0;
    end else begin
      case (state)
        IDLE: begin
          dout_valid <= 0;
          if (din == 0) begin
            state <= START;
            clock_counter <= {CLOCK_COUNTER_WIDTH{1'b0}};
          end
        end
        START: begin
          if ((clock_counter == CLOCKS_PER_HALF_BIT - 1) && din == 1) begin
            state <= IDLE;
          end else if (clock_counter == CLOCKS_PER_BIT - 1) begin
            clock_counter <= 0;
            bit_counter <= 0;
            state <= DATA;
          end else begin
            clock_counter <= clock_counter + 1;
          end
        end
        DATA: begin
          if (clock_counter == CLOCKS_PER_HALF_BIT - 1) begin
            clock_counter <= clock_counter + 1;
            dout <= {din, dout[7:1]};
            bit_counter <= bit_counter + 1;
          end else if (clock_counter == CLOCKS_PER_BIT - 1) begin
            clock_counter <= {CLOCK_COUNTER_WIDTH{1'b0}};
            if (bit_counter == 8) state <= STOP;
          end else begin
            clock_counter <= clock_counter + 1;
          end
        end
        STOP: begin
          if (clock_counter == CLOCKS_PER_HALF_BIT - 1) begin
            state <= (din == 1) ? TRANSMIT : IDLE;
          end else begin
            clock_counter <= clock_counter + 1;
          end
        end
        TRANSMIT: begin
          dout_valid <= 1;
          state <= IDLE;
        end
      endcase
    end
  end

endmodule  // uart_receive

`default_nettype wire
