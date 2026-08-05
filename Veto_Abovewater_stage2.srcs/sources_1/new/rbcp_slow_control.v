`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: rbcp_slow_control
// Description: RBCP write slave. Parses host RBCP write packets, extracts
//   address[7:0]  (1~8) as GT channel select,
//   address[15:8] (1~8) as underwater board select,
//   data[7:0] as payload.
//   Channel select output + {underwater_addr, data} written into async FIFO.
//   External module reads FIFO and routes data to the correct GT channel.
//
// FIFO (IP fifo_rbcp): async, 16-bit in/out, standard.
//   write clock = RBCP 200MHz (clk),
//   read  clock = GT clk_txoutclk_bufg (rd_clk).
//   Each entry = {address[15:8], data[7:0]}.
//
// RBCP timing: 2-stage pipeline, ACK delayed 2 cycles from WE/RE
//   (matches RBCP_SlowControl.v reference timing)
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

    // channel select (directly from address[7:0], combinational)
    output wire [3:0]  channel_select,

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

    // address[7:0] == 1~8 : stage1 board select (GT channel)
    wire addr_sel = (RBCP_ADDR[7:0] >= 8'd1) && (RBCP_ADDR[7:0] <= 8'd8);

    // channel select: directly from address[7:0]
    // (external module uses this to route FIFO read data to correct GT TX)
    assign channel_select = RBCP_ADDR[7:0];

    // ------------------------------------------
    // RBCP 2-stage pipeline (matching reference)
    // ------------------------------------------
    reg        P1WE;
    reg [7:0]  P1_WD;
    reg        P1_ADDR_SEL;

    always @(posedge clk) begin
        if (!rst_n) begin
            P1WE        <= 0;
            P1_WD       <= 0;
            P1_ADDR_SEL <= 0;
        end else begin
            P1WE        <= RBCP_WE;
            P1_WD       <= RBCP_WD;
            P1_ADDR_SEL <= addr_sel;
        end
    end

    // FIFO write: capture on P1 cycle (1 cycle after WE pulse)
    // write data = {underwater_addr, data} = {RBCP_ADDR[15:8], P1_WD}
    assign fifo_wr_en   = P1WE && P1_ADDR_SEL;
    wire  fifo_wr_data  = {RBCP_ADDR[15:8], P1_WD};

    // ACK: 2 cycles after WE (same as reference RBCP_SlowControl.v)
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