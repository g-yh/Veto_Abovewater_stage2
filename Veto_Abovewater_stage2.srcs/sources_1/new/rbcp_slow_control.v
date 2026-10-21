`timescale 1ns / 1ps
///////////////////////////////////////////////////////////////////////////////
// Module Name: rbcp_slow_control
// Description: RBCP write+read slave.
//   Write: parses host RBCP write packets, fans out to one FIFO per GT channel.
//          main reads each FIFO on its own GT clock domain and sends the
//          16-bit word down to stage1.
//   Read : on RBCP_RE, pops one byte from fifo_sc_tx[ch] when the address
//          high byte is 1~8, or from fifo_ptp[ch] when it is F1~F8.
//   Ack  : normal W packets wait for ack_empty[ch]. PTP-start W packets
//          (address high byte F1~F8) are acknowledged immediately by stage2.
//
//   RBCP_ADDR[7:0]   (1~8)  : GT channel select
//   RBCP_ADDR[15:8]  (1~8)  : underwater board select (write payload high byte)
//   RBCP_ADDR[15:8]  (F1~F8): stage1 PTP start / stage2 fifo_ptp read mode
//   RBCP_WD [7:0]    (1~8)  : write payload low byte
//
//   Write clock is CLK_200M (clk); each FIFO's read clock is that GT
//   channel's clk_txoutclk_bufg.
///////////////////////////////////////////////////////////////////////////////

module rbcp_slow_control (
    input wire clk,   // 200MHz system clock (RBCP / FIFO wr clock)
    input wire rst_n, // active-low reset

    // RBCP bus (active in 200MHz clk domain)
    input  wire        RBCP_WE,
    input  wire [ 7:0] RBCP_WD,
    input  wire [31:0] RBCP_ADDR,
    input  wire        RBCP_RE,
    output wire [ 7:0] RBCP_RD,
    output wire        RBCP_ACK,

    // sc_to_stage1: read ports of fifo_rbcp (data flows toward stage1 boards)
    input  wire [  7:0] sc_to_stage1_clk,
    input  wire [  7:0] sc_to_stage1_fifo_rd_en,
    output wire [127:0] sc_to_stage1,                   // packed [ch*16 +: 16]
    output wire [  7:0] sc_to_stage1_fifo_empty,
    output wire [  7:0] sc_to_stage1_fifo_rd_rst_busy,
    output wire [  7:0] sc_to_stage1_valid,

    // sc_to_sitcp: read interface of fifo_sc_tx (data flows from stage1 back to sitcp)
    input  wire [63:0] sc_to_sitcp_dout,         // packed [ch*8 +: 8]
    input  wire [ 7:0] sc_to_sitcp_valid,
    input  wire [ 7:0] sc_to_sitcp_empty,
    input  wire [ 7:0] sc_to_sitcp_rd_rst_busy,
    output reg  [ 7:0] sc_to_sitcp_rd_en,

    // ptp_to_sitcp: read interface of fifo_ptp (8-in/8-out)
    input  wire [63:0] ptp_to_sitcp_dout,
    input  wire [ 7:0] ptp_to_sitcp_valid,
    input  wire [ 7:0] ptp_to_sitcp_empty,
    input  wire [ 7:0] ptp_to_sitcp_rd_rst_busy,
    output reg  [ 7:0] ptp_to_sitcp_rd_en,

    // ack_empty: low means ack FIFO (u_fifo_ack in main) has data for this channel
    input wire [7:0] ack_empty
);

    // ------------------------------------------
    // WRITE SLAVE: RBCP 2-stage pipeline
    // ------------------------------------------
    wire       addr_sel = (RBCP_ADDR[7:0] >= 8'd1) && (RBCP_ADDR[7:0] <= 8'd8);

    reg        P0WE;
    reg        P1WE;
    reg  [7:0] P0_WD;
    reg  [7:0] P0_UW;

    always @(posedge clk) begin
        if (!rst_n) begin
            P0WE  <= 0;
            P1WE  <= 0;
            P0_WD <= 0;
            P0_UW <= 0;
        end else begin
            P0WE  <= RBCP_WE;
            P0_WD <= RBCP_WD;
            P0_UW <= RBCP_ADDR[15:8];
            P1WE  <= P0WE;
        end
    end

    wire [7:0] wr_en;
    wire [7:0] fifo_full;
    wire [7:0] fifo_wr_rst_busy;
    generate
        genvar i;
        for (i = 0; i < 8; i = i + 1) begin : g_rbcp_fifo
            assign wr_en[i] = addr_sel && (RBCP_ADDR[7:0] == (i + 8'd1)) && P0WE && !fifo_full[i];

            fifo_rbcp u_fifo_rbcp (
                .rst        (~rst_n),
                .wr_clk     (clk),
                .rd_clk     (sc_to_stage1_clk[i]),
                .din        ({P0_UW, P0_WD}),
                .wr_en      (wr_en[i]),
                .rd_en      (sc_to_stage1_fifo_rd_en[i]),
                .dout       (sc_to_stage1[i*16+:16]),
                .full       (fifo_full[i]),
                .empty      (sc_to_stage1_fifo_empty[i]),
                .wr_rst_busy(fifo_wr_rst_busy[i]),
                .rd_rst_busy(sc_to_stage1_fifo_rd_rst_busy[i]),
                .valid      (sc_to_stage1_valid[i])
            );
        end
    endgenerate

    // ------------------------------------------
    // READ SLAVE: on RBCP_RE, read one byte from fifo_sc_tx
    // ------------------------------------------
    localparam RD_IDLE    = 3'd0;
    localparam RD_WAIT    = 3'd1;
    localparam RD_CAP     = 3'd2;
    localparam RD_ACK     = 3'd3;
    localparam RD_CAP_LOW = 3'd4;

    reg  [2:0] read_state;
    reg  [2:0] ch;
    reg  [7:0] data_reg;
    reg        read_ptp;
    reg  [63:0] sc_low_cache;   // packed [ch*8 +: 8]
    reg  [7:0] sc_low_pending;
    reg [24:0] read_wait_cnt;
    reg        re_ff;
    reg  [7:0] rbcp_rd_r;
    reg        rbcp_ack_r;

    wire [7:0] ch_addr = RBCP_ADDR[7:0];
    wire       ch_valid = (ch_addr >= 8'd1) && (ch_addr <= 8'd8);
    wire [7:0] ch_sel = ch_addr - 8'd1;
    wire       re_pedge = RBCP_RE && !re_ff;
    wire       is_ptp_addr = (RBCP_ADDR[15:8] >= 8'hF1) &&
                             (RBCP_ADDR[15:8] <= 8'hF8);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            re_ff             <= 1'b0;
            read_state        <= RD_IDLE;
            ch                <= 3'd0;
            data_reg          <= 8'h0;
            read_ptp          <= 1'b0;
            sc_low_cache      <= 64'h0;
            sc_low_pending    <= 8'h0;
            read_wait_cnt     <= 25'd0;
            rbcp_rd_r         <= 8'h0;
            rbcp_ack_r        <= 1'b0;
            sc_to_sitcp_rd_en <= 8'h0;
            ptp_to_sitcp_rd_en <= 8'h0;
        end else begin
            re_ff             <= RBCP_RE;
            sc_to_sitcp_rd_en <= 8'h0;
            ptp_to_sitcp_rd_en <= 8'h0;
            rbcp_ack_r        <= 1'b0;
            case (read_state)
                RD_IDLE: begin
                    if (re_pedge) begin
                        if (ch_valid) begin
                            read_wait_cnt <= 25'd0;
                            if (RBCP_ADDR[15:8] == 8'hF9) begin
                                // Non-blocking PTP FIFO availability check.
                                data_reg   <= {7'd0, ~ptp_to_sitcp_empty[ch_sel[2:0]]};
                                read_state <= RD_ACK;
                            end else if (RBCP_ADDR[15:8] == 8'hFA) begin
                                // Non-blocking slow-control result availability check.
                                data_reg   <= {7'd0, ~sc_to_sitcp_empty[ch_sel[2:0]]};
                                read_state <= RD_ACK;
                            end else if (!is_ptp_addr && sc_low_pending[ch_sel[2:0]]) begin
                                // Return the low byte captured together with the
                                // preceding high-byte read.
                                data_reg               <= sc_low_cache[ch_sel*8+:8];
                                sc_low_pending[ch_sel[2:0]] <= 1'b0;
                                read_state             <= RD_ACK;
                            end else begin
                                ch         <= ch_sel[2:0];
                                read_ptp   <= is_ptp_addr;
                                read_state <= RD_WAIT;
                            end
                        end else begin
                            data_reg   <= 8'h00;
                            read_state <= RD_ACK;
                        end
                    end
                end
                RD_WAIT: begin
                    if (read_ptp) begin
                        if (!ptp_to_sitcp_empty[ch] && !ptp_to_sitcp_rd_rst_busy[ch]) begin
                            ptp_to_sitcp_rd_en <= (8'd1 << ch);
                            read_state          <= RD_CAP;
                        end else if (read_wait_cnt >= 25'd20_000_000) begin
                            data_reg   <= 8'h00;
                            read_state <= RD_ACK;
                        end else begin
                            read_wait_cnt <= read_wait_cnt + 25'd1;
                        end
                    end else begin
                        if (!sc_to_sitcp_empty[ch] && !sc_to_sitcp_rd_rst_busy[ch]) begin
                            sc_to_sitcp_rd_en <= (8'd1 << ch);
                            read_state        <= RD_CAP;
                        end else if (read_wait_cnt >= 25'd20_000_000) begin
                            data_reg   <= 8'h00;
                            read_state <= RD_ACK;
                        end else begin
                            read_wait_cnt <= read_wait_cnt + 25'd1;
                        end
                    end
                end
                RD_CAP: begin
                    if (read_ptp) begin
                        if (ptp_to_sitcp_valid[ch]) begin
                            data_reg   <= ptp_to_sitcp_dout[ch*8+:8];
                            read_state <= RD_ACK;
                        end
                    end else begin
                        if (sc_to_sitcp_valid[ch]) begin
                            data_reg   <= sc_to_sitcp_dout[ch*8+:8];
                            ptp_to_sitcp_rd_en <= 8'h0;
                            sc_to_sitcp_rd_en  <= (8'd1 << ch);
                            read_state <= RD_CAP_LOW;
                        end
                    end
                end
                RD_CAP_LOW: begin
                    if (sc_to_sitcp_valid[ch]) begin
                        sc_low_cache[ch*8+:8] <= sc_to_sitcp_dout[ch*8+:8];
                        sc_low_pending[ch] <= 1'b1;
                        read_state        <= RD_ACK;
                    end
                end
                RD_ACK: begin
                    rbcp_rd_r  <= data_reg;
                    rbcp_ack_r <= 1'b1;
                    read_state <= RD_IDLE;
                end
                default: read_state <= RD_IDLE;
            endcase
        end
    end

    // ------------------------------------------
    // W-packet ACK: when ack_empty[ch] is low, assert RBCP_ACK for one cycle
    // ------------------------------------------
    reg     rbcp_ack_w;
    reg     rbcp_ack_ptp;
    reg     ptp_start_req_d;
    integer ach;

    wire is_ptp_start_wr = RBCP_WE && addr_sel &&
                           (RBCP_ADDR[15:8] >= 8'hF1) &&
                           (RBCP_ADDR[15:8] <= 8'hF8);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rbcp_ack_w <= 1'b0;
            rbcp_ack_ptp <= 1'b0;
            ptp_start_req_d <= 1'b0;
        end else begin
            rbcp_ack_w <= 1'b0;
            // ACK after the P0WE pipeline has written the word to fifo_rbcp.
            rbcp_ack_ptp <= ptp_start_req_d;
            ptp_start_req_d <= is_ptp_start_wr;
            for (ach = 0; ach < 8; ach = ach + 1) begin
                if (!ack_empty[ach]) begin
                    rbcp_ack_w <= 1'b1;
                end
            end
        end
    end

    // ------------------------------------------
    // Merged outputs
    // ------------------------------------------
    assign RBCP_ACK = rbcp_ack_w | rbcp_ack_r | rbcp_ack_ptp;
    assign RBCP_RD  = rbcp_rd_r;

    // ------------------------------------------
    // Slow-control send counter (CLK_200M domain):
    // number of 16-bit words accepted into fifo_rbcp (i.e. sent toward stage1)
    // ------------------------------------------
    reg [15:0] sc_tx_cnt;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            sc_tx_cnt <= 16'd0;
        else if (|wr_en)
            sc_tx_cnt <= sc_tx_cnt + 16'd1;
    end

    // RBCP_ACK counter (CLK_200M domain): one per RBCP_ACK rising edge
    reg [15:0] rbcp_ack_cnt;
    reg        rbcp_ack_d;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rbcp_ack_cnt <= 16'd0;
            rbcp_ack_d   <= 1'b0;
        end else begin
            rbcp_ack_d <= RBCP_ACK;
            if (RBCP_ACK && !rbcp_ack_d)
                rbcp_ack_cnt <= rbcp_ack_cnt + 16'd1;
        end
    end

    ila_sc u_ila_sc (
        .clk    (clk),
        .probe0 (RBCP_WE),
        .probe1 (RBCP_WD),
        .probe2 (RBCP_ADDR),
        .probe3 (RBCP_RE),
        .probe4 (RBCP_RD),
        .probe5 (RBCP_ACK),
        .probe6 (wr_en[0]),
        .probe7 ({P0_UW, P0_WD}),
        .probe8 (rbcp_ack_w),
        .probe9 (rbcp_ack_r),
        .probe10(ack_empty[0]),
        .probe11(sc_to_sitcp_valid[0]),
        .probe12(sc_to_sitcp_rd_en[0]),
        .probe13(sc_to_sitcp_dout[7:0]),
        .probe14(sc_tx_cnt),
        .probe15(rbcp_ack_cnt)
    );

    ila_sc_fifo_rd u_ila_sc_fifo_rd (
        .clk   (sc_to_stage1_clk[0]),
        .probe0(sc_to_stage1_fifo_rd_en[0]),
        .probe1(sc_to_stage1_fifo_empty[0]),
        .probe2(sc_to_stage1[15:0]),
        .probe3(sc_to_stage1_valid[0])
    );

endmodule
