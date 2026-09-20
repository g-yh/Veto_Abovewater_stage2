`timescale 1ns / 1ps
////////////////////////////////////////////////////////////////////////////////
// Module Name: rbcp_slow_control
// Description: RBCP write+read slave, merged from rbcp_slow_control + rbcp_read_slave.
//   Write: parses host RBCP write packets, fans out to one FIFO per GT channel.
//   Read : on RBCP_RE, pops one byte from fifo_sc_tx[ch] and answers
//          with a delayed ACK (RBCP_RD = byte, RBCP_ACK = 2 clocks).
//
//   RBCP_ADDR[7:0]   (1~8)  : GT channel select
//   RBCP_ADDR[15:8]  (1~8)  : underwater board select (write payload high byte)
//   RBCP_WD [7:0]    (1~8)  : write payload low byte
//
//   Write: each RBCP write pushes ONE 16-bit word into the selected channel FIFO:
//     din[15:0] = {RBCP_ADDR[15:8], RBCP_WD}
//   Read : each RBCP read pops 1 byte from fifo_sc_tx[ch].
//     The host must send 2 collects per 16-bit word (low byte first).
//
//   Write clock is CLK_200M (clk); each FIFO's read clock is that GT
//   channel's clk_txoutclk_bufg (sc_to_stage1_clk[ch]). main.v drains each FIFO
//   on its own GT clock domain and sends the 16-bit word down that GT link.
//
//   RBCP timing: write ACK = 3 cycles from WE (fixed, independent of FIFO-full).
//                read ACK = delayed 2 clocks (waits for data to arrive).
////////////////////////////////////////////////////////////////////////////////

module rbcp_slow_control (
    input  wire        clk,          // 200MHz system clock (RBCP / FIFO wr clock)
    input  wire        rst_n,        // active-low reset

    // RBCP bus (active in 200MHz clk domain)
    input  wire        RBCP_WE,
    input  wire [7:0]  RBCP_WD,
    input  wire [31:0] RBCP_ADDR,
    input  wire        RBCP_RE,
    output wire [7:0]  RBCP_RD,
    output wire        RBCP_ACK,

    // sc_to_stage1: read ports of fifo_rbcp (data flows toward stage1 boards)
    input  wire [7:0]  sc_to_stage1_clk,
    input  wire [7:0]  sc_to_stage1_rd_en,
    output wire [127:0] sc_to_stage1_rd_data,     // packed [ch*16 +: 16]
    output wire [7:0]  sc_to_stage1_empty,
    output wire [7:0]  sc_to_stage1_rd_rst_busy,

    // sc_to_sitcp: read interface of fifo_sc_tx (data flows from stage1 back to sitcp)
    input  wire [127:0] sc_to_sitcp_dout,       // packed [ch*8 +: 8]
    input  wire [7:0]   sc_to_sitcp_valid,
    input  wire [7:0]   sc_to_sitcp_rd_rst_busy,
    output reg  [7:0]   sc_to_sitcp_rd_en
);

    // ------------------------------------------
    // WRITE SLAVE: RBCP 2-stage pipeline
    // ------------------------------------------
    wire addr_sel = (RBCP_ADDR[7:0] >= 8'd1) && (RBCP_ADDR[7:0] <= 8'd8);

    reg        P0WE;
    reg        P1WE;
    reg [7:0]  P0_WD;
    reg [7:0]  P0_UW;

    always @(posedge clk) begin
        if (!rst_n) begin
            P0WE <= 0; P1WE <= 0; P0_WD <= 0; P0_UW <= 0;
        end else begin
            P0WE <= RBCP_WE;
            P0_WD <= RBCP_WD;
            P0_UW <= RBCP_ADDR[15:8];
            P1WE <= P0WE;
        end
    end

    wire [7:0] wr_en;
    // fifo_full / fifo_wr_rst_busy are internal wires (not exposed to main.v)
    wire [7:0] fifo_full;
    wire [7:0] fifo_wr_rst_busy;
    generate
        genvar i;
        for (i = 0; i < 8; i = i + 1) begin : g_rbcp_fifo
            assign wr_en[i] = addr_sel && (RBCP_ADDR[7:0] == (i + 8'd1)) &&
                              P0WE && !fifo_full[i];

            fifo_rbcp u_fifo_rbcp (
                .rst         (~rst_n),
                .wr_clk      (clk),
                .rd_clk      (sc_to_stage1_clk[i]),
                .din         ({P0_UW, P0_WD}),
                .wr_en       (wr_en[i]),
                .rd_en       (sc_to_stage1_rd_en[i]),
                .dout        (sc_to_stage1_rd_data[i*16 +: 16]),
                .full        (fifo_full[i]),
                .empty       (sc_to_stage1_empty[i]),
                .wr_rst_busy (fifo_wr_rst_busy[i]),
                .rd_rst_busy (sc_to_stage1_rd_rst_busy[i])
            );
        end
    endgenerate

    // Write ACK: 3 cycles after WE (fixed, independent of FIFO-full)
    reg rbcp_ack_w;
    always @(posedge clk) begin
        if (!rst_n)
            rbcp_ack_w <= 0;
        else
            rbcp_ack_w <= P1WE;
    end

    // RBCP_RD (write side): always 0
    wire rbcp_rd_w = 8'h00;

    // ------------------------------------------
    // READ SLAVE: delayed ACK from fifo_sc_tx
    // ------------------------------------------
    localparam RD_IDLE = 2'd0;
    localparam RD_WAIT = 2'd1;
    localparam RD_ACK  = 2'd2;

    reg  [1:0]  read_state;
    reg  [2:0]  ch;
    reg  [7:0]  data_reg;
    reg  [1:0]  ack_cnt;
    reg         re_ff;
    reg  [7:0]  rbcp_rd_r;
    reg         rbcp_ack_r;

    wire [7:0]  ch_addr   = RBCP_ADDR[7:0];
    wire       ch_valid   = (ch_addr >= 8'd1) && (ch_addr <= 8'd8);
    wire [7:0]  ch_sel    = ch_addr - 8'd1;
    wire       re_pedge   = RBCP_RE && !re_ff;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            re_ff      <= 1'b0;
            read_state <= RD_IDLE;
            ch         <= 3'd0;
            data_reg   <= 8'h0;
            ack_cnt    <= 2'd0;
            rbcp_rd_r  <= 8'h0;
            rbcp_ack_r <= 1'b0;
            sc_to_sitcp_rd_en <= 8'h0;
        end else begin
            re_ff         <= RBCP_RE;
            sc_to_sitcp_rd_en <= 8'h0;
            rbcp_ack_r    <= 1'b0;
            case (read_state)
                RD_IDLE: begin
                    if (re_pedge) begin
                        if (ch_valid) begin
                            ch    <= ch_sel[2:0];
                            read_state <= RD_WAIT;
                        end else begin
                            data_reg <= 8'h00;
                            read_state <= RD_ACK;
                        end
                    end
                end
                RD_WAIT: begin
                    if (sc_to_sitcp_valid[ch] && !sc_to_sitcp_rd_rst_busy[ch]) begin
                        data_reg            <= sc_to_sitcp_dout[ch*8 +: 8];
                        sc_to_sitcp_rd_en   <= (8'd1 << ch);
                        read_state          <= RD_ACK;
                    end
                end
                RD_ACK: begin
                    rbcp_rd_r     <= data_reg;
                    rbcp_ack_r    <= 1'b1;
                    if (ack_cnt == 2'd1) begin
                        ack_cnt <= 2'd0;
                        read_state <= RD_IDLE;
                    end else begin
                        ack_cnt <= ack_cnt + 2'd1;
                    end
                end
                default: read_state <= RD_IDLE;
            endcase
        end
    end

    // ------------------------------------------
    // Merged outputs
    // ------------------------------------------
    assign RBCP_ACK = rbcp_ack_w | rbcp_ack_r;
    assign RBCP_RD  = rbcp_rd_w  | rbcp_rd_r;

endmodule
