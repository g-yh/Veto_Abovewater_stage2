`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: rbcp_slow_control
// Description: RBCP write slave. Parses host RBCP write packets, extracts
//   address[7:0]  (1~8) as GT channel select,
//   address[15:8] (1~8) as underwater board select,
//   data[7:0] as payload.
//
//   Each RBCP write pushes ONE 32-bit word into the async FIFO:
//     write data[31:0] = {underwater[7:0], data[7:0], 8'h00, channel[7:0]}
//   FIFO is width-converting (write 32, read 16, LSB-first):
//     read word 1 = [15:0]  = {8'h00, channel[7:0]}        : channel routing, NOT sent on GT
//     read word 2 = [31:16] = {underwater[7:0], data[7:0]} : the 16-bit slow-control
//                                                            payload actually sent on GT.
//   Downstream logic (in main.v) reads word 1 to learn the channel, then reads
//   word 2 and sends it on that channel. The single atomic 32-bit write means a
//   command pair can never be torn at the async boundary, and ordering is
//   preserved by the FIFO, so ACK timing is irrelevant to routing correctness.
//
// FIFO (IP fifo_rbcp): async, write 32-bit / read 16-bit, standard.
//   write clock = RBCP 200MHz (clk),
//   read  clock = GT clk_txoutclk_bufg (rd_clk).
//
// RBCP timing: ACK delayed 3 cycles from WE (2 pipeline stages + ACK reg).
//////////////////////////////////////////////////////////////////////////////////

module rbcp_slow_control (
    input  wire        clk,          // 200MHz system clock (RBCP / FIFO wr clock)
    input  wire        rst_n,        // active-low reset

    // RBCP bus (active in 200MHz clk domain)
    input  wire        RBCP_WE,
    input  wire [7:0]  RBCP_WD,
    input  wire [31:0] RBCP_ADDR,
    output wire [7:0]  RBCP_RD,
    output reg         RBCP_ACK,

    // FIFO write port (200MHz)
    output wire        fifo_full,
    output wire        fifo_wr_rst_busy,

    // FIFO read port (GT clk_txoutclk_bufg domain)
    input  wire        fifo_rd_clk,
    input  wire        fifo_rd_en,
    output wire [15:0] fifo_rd_data,
    output wire        fifo_empty,
    output wire        fifo_rd_rst_busy
);
    wire addr_sel = (RBCP_ADDR[7:0] >= 8'd1) && (RBCP_ADDR[7:0] <= 8'd8);

    // ------------------------------------------
    // RBCP 2-stage pipeline (matching reference)
    // ------------------------------------------
    reg        P0WE;
    reg        P1WE;
    reg [7:0]  P0_WD;
    reg [7:0]  P0_CH;
    reg [7:0]  P0_UW;

    always @(posedge clk) begin
        if (!rst_n) begin
            P0WE <= 0;
            P1WE <= 0;
            P0_WD <= 0;
            P0_CH <= 0;
            P0_UW <= 0;
        end else begin
            // 1st stage: latch WE + fields (RBCP_ADDR held until ACK, so stable)
            P0WE <= RBCP_WE;
            P0_WD <= RBCP_WD;
            P0_CH <= RBCP_ADDR[7:0];      // channel select
            P0_UW <= RBCP_ADDR[15:8];     // underwater board select
            // 2nd stage
            P1WE <= P0WE;
        end
    end

    // Single 32-bit FIFO write per RBCP write (addr_sel held stable until ACK).
    // din[31:0] = {underwater, data, 8'h00, channel}
    // FIFO width-converts 32->16 LSB-first, so the read side first gets
    // [15:0] = {8'h00, channel} (routing), then [31:16] = {underwater, data}.
    assign fifo_wr_en  = addr_sel && P0WE;
    wire  fifo_wr_data = {P0_UW, P0_WD, 8'h00, P0_CH};

    // ACK: 3 cycles after WE (2-stage pipeline + ACK register)
    always @(posedge clk) begin
        if (!rst_n)
            RBCP_ACK <= 0;
        else
            RBCP_ACK <= P1WE;
    end

    // RBCP_RD: always 0 (write-only slave)
    assign RBCP_RD = 8'h00;

    // ------------------------------------------
    // Async FIFO (IP fifo_rbcp): wr=CLK_200M, rd=GT clk_txoutclk_bufg
    // ------------------------------------------
    fifo_rbcp u_fifo_rbcp (
        .rst         (~rst_n),
        .wr_clk      (clk),
        .rd_clk      (fifo_rd_clk),
        .din         (fifo_wr_data),
        .wr_en       (fifo_wr_en),
        .rd_en       (fifo_rd_en),
        .dout        (fifo_rd_data),
        .full        (fifo_full),
        .empty       (fifo_empty),
        .wr_rst_busy (fifo_wr_rst_busy),
        .rd_rst_busy (fifo_rd_rst_busy)
    );

endmodule