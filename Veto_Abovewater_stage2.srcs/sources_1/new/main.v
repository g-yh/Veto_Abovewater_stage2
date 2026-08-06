`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/08/04
// Design Name: 
// Module Name: main
// Project Name: Veto_Abovewater_stage2
// Target Devices: xc7k325tffg900-2
// Tool Versions: Vivado 2024.1
// Description: 
//   stage2: aggregate 8x stage1 boards over 8ch GTX, talk to host PC via SiTCP
//   - SiTCP (GMII, 1000BASE-X over eth SFP) <-> host
//   - 8ch GTX (plain data link, no time_sync) <-> 8x stage1 boards
//   Data bridge (8ch GTX <-> SiTCP TCP) is placeholder, not built yet.
// Dependencies: 
// 
// Revision: 0.01 - File Created
// 
//////////////////////////////////////////////////////////////////////////////////


module main (
    // System
    input wire SYSCLK_200MP_IN,  // From 200MHz Oscillator module
    input wire SYSCLK_200MN_IN,
    // GT refclk 125M for 8ch GTX (to 8x stage1 boards)
    input wire gt_refclk2_p,
    input wire gt_refclk2_n,
    // GT refclk 125M for SiTCP ethernet (1000BASE-X)
    input wire gt_refclk4_p,
    input wire gt_refclk4_n,

    // 8ch GT to 8x stage1 boards
    output wire [7:0] FE_SFP_TX_P,
    output wire [7:0] FE_SFP_TX_N,
    input  wire [7:0] FE_SFP_RX_P,
    input  wire [7:0] FE_SFP_RX_N,

    // ethernet SFP (SiTCP to host PC)
    output wire       ETH_SFP_TXP,
    output wire       ETH_SFP_TXN,
    input  wire       ETH_SFP_RXP,
    input  wire       ETH_SFP_RXN,
    output wire       ETH_SFP_TX_DISABLE,

    // spi interface (ad9528 clock config -> 125M refclks)
    output wire       cs_ad9528,
    output wire       sclk_ad9528,
    inout  wire       sdio_ad9528,
    output wire       ad9528_rst_n,

    // TCP data (placeholder: host <-> 8ch GTX bridge TBD)
    output wire       TCP_OPEN_ACK,
    output wire       TCP_RX_WR,
    output wire [7:0] TCP_RX_DATA,
    output wire       TCP_TX_FULL,
    input  wire       TCP_TX_WR,
    input  wire [7:0] TCP_TX_DATA,

    // RBCP slow control
    output wire       RBCP_ACT,
    output wire       RBCP_WE,

    // LED
    // output wire [4:1] LED,
    // fan
    output wire FAN_PWM
);

    wire [1:0] cfg_state_ad9528;

    wire       CLK_200M;
    wire       CLK_100M;
    wire       CLK_5M;
    wire       SYSCLK_200M_buff;

    wire       sysrst;
    wire       pll_locked;
    wire       sysrst_glb_n;
    wire       cfg_ad9528;

    assign ad9528_rst_n = sysrst_glb_n;
    assign sysrst       = 1'b0;
    assign FAN_PWM      = 1'b1;

    // 200M clk input buff
    IBUFDS #(
        .DIFF_TERM("TRUE"),
        .IBUF_LOW_PWR("FALSE")
    ) IBUFDS_200M (
        .O (SYSCLK_200M_buff),
        .I (SYSCLK_200MP_IN),
        .IB(SYSCLK_200MN_IN)
    );
    BUFG BUFG_200M (
        .O(CLK_200M),
        .I(SYSCLK_200M_buff)
    );

    clk_wiz_aurora clk_wiz_aurora_inst (
        // Clock out ports
        .clk_out1(CLK_100M),    // output clk_out1
        .clk_out2(CLK_5M),      // output clk_out2
        // Status and control signals
        .locked  (pll_locked),  // output locked
        // Clock in ports
        .clk_in1 (CLK_200M)
    );

    rst_dis rst_dis_inst (
        .clk_in      (CLK_5M),
        .sysrst      (sysrst),
        .pll_locked  (pll_locked),
        .cfg_ad9528  (cfg_ad9528),
        .rst_aurura  (),
        .sysrst_glb_n(sysrst_glb_n)
    );

    // spi configure ad9528 clock (125M refclks)
    spi_top spi_top_inst (
        .clk  (CLK_5M),
        .rst_n(sysrst_glb_n),

        .cs_ad9528  (cs_ad9528),
        .sclk_ad9528(sclk_ad9528),
        .sdio_ad9528(sdio_ad9528),

        .cfg_ad9528(cfg_ad9528),

        .cfg_state_ad9528(cfg_state_ad9528)
    );

    //--------------------------------
    // RBCP slow control (parse host RBCP writes, extract channel + data into FIFO)
    //--------------------------------
    wire        rbcp_we;
    wire [31:0] rbcp_addr;
    wire [7:0]  rbcp_wd;
    wire        rbcp_ack;
    wire [7:0]  rbcp_rd;

    // FIFO read interface (GT clk_txoutclk_bufg domain), driven by TX SM below
    wire        fifo_rd_clk;
    wire        fifo_rd_en;
    wire [15:0] fifo_rd_data;
    wire        fifo_empty;
    wire        fifo_rd_rst_busy;

    rbcp_slow_control u_rbcp_slow_control (
        .clk           (CLK_200M),
        .rst_n         (sysrst_glb_n),

        .RBCP_WE       (rbcp_we),
        .RBCP_WD       (rbcp_wd),
        .RBCP_ADDR     (rbcp_addr),
        .RBCP_RD       (rbcp_rd),
        .RBCP_ACK      (rbcp_ack),

        .fifo_full       (),
        .fifo_wr_rst_busy(),

        .fifo_rd_clk     (fifo_rd_clk),
        .fifo_rd_en      (fifo_rd_en),
        .fifo_rd_data    (fifo_rd_data),
        .fifo_empty      (fifo_empty),
        .fifo_rd_rst_busy(fifo_rd_rst_busy)
    );

    //--------------------------------
    // SiTCP subsystem (GMII, ethernet via 1000BASE-X SFP)
    //--------------------------------
    sitcp_top sitcp_top_inst (
        .CLK_200M    (CLK_200M),
        .SYS_RST     (~sysrst_glb_n),
        .SiTCP_RST_out(),

        // GT REFCLK (125M)
        .SGMII_CLK_P (gt_refclk4_p),
        .SGMII_CLK_N (gt_refclk4_n),

        // SFP
        .TX_DISABLE  (ETH_SFP_TX_DISABLE),
        .SFP_TXP     (ETH_SFP_TXP),
        .SFP_TXN     (ETH_SFP_TXN),
        .SFP_RXP     (ETH_SFP_RXP),
        .SFP_RXN     (ETH_SFP_RXN),

        // TCP IO
        .TCP_OPEN_ACK(TCP_OPEN_ACK),
        .TCP_RX_WC   (16'hFFFF),  // Rx path unused, fill count all 1s
        .TCP_RX_WR   (TCP_RX_WR),
        .TCP_RX_DATA (TCP_RX_DATA),
        .TCP_TX_FULL (TCP_TX_FULL),
        .TCP_TX_WR   (TCP_TX_WR),
        .TCP_TX_DATA (TCP_TX_DATA),

        // RBCP IO (active in 200MHz clk domain)
        .RBCP_ACT    (RBCP_ACT),
        .RBCP_ADDR   (rbcp_addr),
        .RBCP_WD     (rbcp_wd),
        .RBCP_WE     (rbcp_we),
        .RBCP_RE     (),
        .RBCP_ACK    (rbcp_ack),
        .RBCP_RD     (rbcp_rd)
    );

    assign RBCP_WE = rbcp_we;

    //--------------------------------
    // 8ch GTX interface (plain data link to 8x stage1 boards, no time_sync)
    //--------------------------------
    // 125M GTX ref clk input
    wire clk_gtx_125M;
    IBUFDS_GTE2 instance_ibufgds_gtx_refclk (
        .I    (gt_refclk2_p),
        .IB   (gt_refclk2_n),
        .O    (clk_gtx_125M),
        .CEB  (1'b0),
        .ODIV2()
    );

    wire [  7:0] rx_pma_rst_n;
    wire [  7:0] clk_txoutclk_bufg;
    wire [  7:0] clk_rxoutclk_bufg;
    reg  [127:0] gt_tx_data;
    reg  [  7:0] gt_tx_data_valid;
    wire [127:0] gt_rx_data;
    wire [  7:0] gt_rx_data_valid;
    wire [  7:0] gtx_cpll_is_lock;
    wire [  7:0] rx_reset_done;
    wire [ 15:0] rx_data_is_comma;
    wire [  7:0] gtx_rx_error;

    // no time_sync on this link: tie PMA reset to global active-low reset
    assign rx_pma_rst_n = {8{sysrst_glb_n}};

    //--------------------------------
    // GT TX slow-control state machine (GT clk_txoutclk_bufg domain)
    //   Sends the 16-bit slow-control payload on the selected GT channel.
    //   FIFO entry pairs: word1={8'h00,channel} (routing only), word2={underwater,data}.
    //   When not sending slow-control data, all channels drive 16'hbc3c idle
    //   (interface forces txcharisk=11 when gt_tx_data_valid=0 => K28.7|K28.3).
    // NOTE: this FSM runs on clk_txoutclk_bufg[0]; all 8 GT TX paths share the same
    //   125M refclk/line rate, so TXUSRCLKs are same frequency. Cross-channel phase
    //   is not aligned - acceptable for occasional slow-control words, but not for
    //   a continuous high-rate data bridge.
    //--------------------------------
    assign fifo_rd_clk = clk_txoutclk_bufg[0];

    localparam S_IDLE   = 2'd0;
    localparam S_RD_CH  = 2'd1;
    localparam S_SEND   = 2'd2;

    reg [1:0]  slow_state;
    reg [7:0]  slow_ch;
    reg [15:0] slow_dat;

    // Standard-mode async FIFO: dout = head word whenever empty=0.
    // A pop happens at the next rising edge while rd_en is high, then
    // dout updates to the following word. So:
    //   S_IDLE:  dout=word1={8'h00,channel}; capture channel; rd_en=1 pops word1
    //   S_RD_CH: dout=word2={underwater,data}; capture data; rd_en=1 pops word2
    //   S_SEND:  drive selected channel with word2, valid=1 for one TX cycle
    // Both reads wait on !fifo_empty so a word2 not yet written by the async
    // write side never causes a garbage capture. Reads also gated on
    // !fifo_rd_rst_busy so a spurious empty=0 during the FIFO reset window
    // cannot trigger a bogus read.
    assign fifo_rd_en = !fifo_rd_rst_busy &&
                        ((slow_state == S_IDLE && !fifo_empty) ||
                         (slow_state == S_RD_CH && !fifo_empty));

    always @(posedge fifo_rd_clk or negedge sysrst_glb_n) begin
        if (!sysrst_glb_n) begin
            slow_state       <= S_IDLE;
            slow_ch          <= 8'd0;
            slow_dat         <= 16'h0000;
            gt_tx_data       <= {8{16'hbc3c}};
            gt_tx_data_valid <= 8'b0;
        end else begin
            gt_tx_data       <= {8{16'hbc3c}};   // default: idle on all channels
            gt_tx_data_valid <= 8'b0;
            case (slow_state)
                S_IDLE: begin
                    if (!fifo_empty && !fifo_rd_rst_busy) begin
                        slow_ch    <= fifo_rd_data[7:0];   // word1 = channel
                        slow_state <= S_RD_CH;
                    end
                end
                S_RD_CH: begin
                    if (!fifo_empty && !fifo_rd_rst_busy) begin
                        slow_dat   <= fifo_rd_data;        // word2 = {underwater,data}
                        slow_state <= S_SEND;
                    end
                end
                S_SEND: begin
                    // send the 16-bit payload once on the selected channel
                    if ((slow_ch >= 8'd1) && (slow_ch <= 8'd8)) begin
                        gt_tx_data[slow_ch*16 +: 16] <= slow_dat;
                        gt_tx_data_valid[slow_ch]   <= 1'b1;
                    end
                    slow_state <= S_IDLE;
                end
                default: slow_state <= S_IDLE;
            endcase
        end
    end

    interface_gtx_8ch instance_gtx_interface_8ch (
        .rx_pma_rst_n     (rx_pma_rst_n),
        .clk_drp_100M     (CLK_100M),
        .clk_gtx_125M     (clk_gtx_125M),
        .gtx_tx_p         (FE_SFP_TX_P),
        .gtx_tx_n         (FE_SFP_TX_N),
        .gtx_rx_p         (FE_SFP_RX_P),
        .gtx_rx_n         (FE_SFP_RX_N),
        .clk_txoutclk_bufg(clk_txoutclk_bufg),
        .clk_rxoutclk_bufg(clk_rxoutclk_bufg),
        .gt_tx_data       (gt_tx_data),
        .gt_tx_data_valid (gt_tx_data_valid),
        .gt_rx_data       (gt_rx_data),
        .gt_rx_data_valid (gt_rx_data_valid),
        .gtx_cpll_is_lock (gtx_cpll_is_lock),
        .rx_reset_done    (rx_reset_done),
        .rx_data_is_comma (rx_data_is_comma),
        .gtx_rx_error     (gtx_rx_error)
    );

endmodule