`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: rbcp_slow_control
// Description: RBCP write slave. Parses host RBCP write packets and fans them out
//   to one FIFO per GT channel.
//
//   RBCP_ADDR[7:0]   (1~8)   : GT channel select  -> which fifo_rbcp to write
//   RBCP_ADDR[15:8]  (1~8)   : underwater board select (payload high byte)
//   RBCP_WD [7:0]    (1~8)   : payload low byte
//
//   Each RBCP write pushes ONE 16-bit word into the selected channel FIFO:
//     din[15:0] = {RBCP_ADDR[15:8], RBCP_WD}
//   The write clock is CLK_200M (clk); each FIFO's read clock is that GT
//   channel's clk_txoutclk_bufg (fifo_rd_clk[ch]).  main.v drains each FIFO on
//   its own GT clock domain and sends the 16-bit word down that GT link.
//
//   ive 8 instances of IP fifo_rbcp (16-bit in / 16-bit out, async):
//   wr_clk = clk (200M), rd_clk = fifo_rd_clk[ch].
//
// RBCP timing: ACK delayed 3 cycles from WE (2 pipeline stages + ACK reg),
// independent of FIFO-full (fixed 3-cycle ACK).
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

    // Per-channel FIFO write flags (200MHz) - optional debug
    output wire [7:0]  fifo_full,
    output wire [7:0]  fifo_wr_rst_busy,

    // Per-channel FIFO read ports (GT clk_txoutclk_bufg[ch] domain)
    input  wire [7:0]  fifo_rd_clk,
    input  wire [7:0]  fifo_rd_en,
    output wire [127:0] fifo_rd_data,     // packed [ch*16 +: 16]
    output wire [7:0]  fifo_empty,
    output wire [7:0]  fifo_rd_rst_busy
);
    // Channel select: RBCP_ADDR[7:0] in 1..8
    wire addr_sel = (RBCP_ADDR[7:0] >= 8'd1) && (RBCP_ADDR[7:0] <= 8'd8);

    // ------------------------------------------
    // RBCP 2-stage pipeline (matching reference)
    // ------------------------------------------
    reg        P0WE;
    reg        P1WE;
    reg [7:0]  P0_WD;
    reg [7:0]  P0_UW;

    always @(posedge clk) begin
        if (!rst_n) begin
            P0WE <= 0;
            P1WE <= 0;
            P0_WD <= 0;
            P0_UW <= 0;
        end else begin
            // 1st stage: latch WE + fields (RBCP_ADDR held until ACK, so stable)
            P0WE <= RBCP_WE;
            P0_WD <= RBCP_WD;
            P0_UW <= RBCP_ADDR[15:8];     // underwater board select
            // 2nd stage
            P1WE <= P0WE;
        end
    end

    // One 16-bit FIFO write per RBCP write, routed to the selected channel FIFO.
    // Full-gated so a full FIFO never drops a word.
    wire [7:0] wr_en;
    generate
        genvar i;
        for (i = 0; i < 8; i = i + 1) begin : g_rbcp_fifo
            assign wr_en[i] = addr_sel && (RBCP_ADDR[7:0] == (i + 8'd1)) &&
                              P0WE && !fifo_full[i];

            fifo_rbcp u_fifo_rbcp (
                .rst         (~rst_n),
                .wr_clk      (clk),
                .rd_clk      (fifo_rd_clk[i]),
                .din         ({P0_UW, P0_WD}),
                .wr_en       (wr_en[i]),
                .rd_en       (fifo_rd_en[i]),
                .dout        (fifo_rd_data[i*16 +: 16]),
                .full        (fifo_full[i]),
                .empty       (fifo_empty[i]),
                .wr_rst_busy (fifo_wr_rst_busy[i]),
                .rd_rst_busy (fifo_rd_rst_busy[i])
            );
        end
    endgenerate

    // ACK: 3 cycles after WE (2-stage pipeline + ACK register), fixed timing
    always @(posedge clk) begin
        if (!rst_n)
            RBCP_ACK <= 0;
        else
            RBCP_ACK <= P1WE;
    end

    // RBCP_RD: always 0 (write-only slave)
    assign RBCP_RD = 8'h00;

endmodule