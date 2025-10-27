module top_level (
    input wire clk_125mhz_p,
    input wire clk_125mhz_n,
    input wire rst,
    input wire uart_rxd,
    output wire uart_txd
);

    // Differential clock input buffer
    wire clk;
    IBUFDS IBUFDS_clk (
        .I  (clk_125mhz_p),
        .IB (clk_125mhz_n),
        .O  (clk)
    );

    wire data_valid;
    wire [7:0] data_rx;
    wire fifo_empty;
    wire [7:0] data_tx;
    wire tx_busy;
    wire can_write;

    assign can_write = !fifo_empty && !tx_busy;

    fifo #(
        .DEPTH(2),
        .WIDTH(8)
    ) fifo_inst (
        .clk   (clk),
        .rst   (rst),
        .write (data_valid),
        .data_in (data_rx),
        .full  (),
        .read  (can_write),
        .data_out (data_tx),
        .empty (fifo_empty)
    );

    uart_receive #(
        .INPUT_CLOCK_FREQ(125_000_000),
        .BAUD_RATE(115200)
    ) uart_rx_inst (
        .clk       (clk),
        .rst       (rst),
        .din       (uart_rxd),
        .dout_valid(data_valid),
        .dout      (data_rx)
    );

    uart_transmit #(
        .INPUT_CLOCK_FREQ(125_000_000),
        .BAUD_RATE(115200)
    ) uart_tx_inst (
        .clk    (clk),
        .rst    (rst),
        .din    (data_tx),
        .trigger(can_write),
        .busy   (tx_busy),
        .dout   (uart_txd)
    );
endmodule