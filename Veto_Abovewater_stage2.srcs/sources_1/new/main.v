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
    output wire BE_SFP_TX_P,
    output wire BE_SFP_TX_N,
    input  wire BE_SFP_RX_P,
    input  wire BE_SFP_RX_N,
    output wire SFP_TX_DISABLE,

    // spi interface (ad9528 clock config -> 125M refclks)
    output wire cs_ad9528,
    output wire sclk_ad9528,
    inout  wire sdio_ad9528,
    output wire ad9528_rst_n,
    output wire ad9528_sysref_req,

    // GT link status LEDs
    output wire gt_link_up_led1,  // all 8 FE gt_link_up high
    output wire sitcp_led2,

    // LED
    // output wire [4:1] LED,
    // fan
    output wire FAN_PWM
);

    // assign gt_link_up_led1 = &gt_link_up;
    assign gt_link_up_led1 = gt_link_up[0];
    assign sitcp_led2 = tcp_open_ack;

    assign SFP_TX_DISABLE  = 1'b0;

    wire [1:0] cfg_state_ad9528;

    wire       CLK_200M;
    wire       CLK_100M;
    wire       CLK_5M;
    wire       SYSCLK_200M_buff;

    wire       sysrst;
    wire       pll_locked;
    wire       sysrst_glb_n;
    wire       cfg_ad9528;
    wire       ad9253_spi_rst_n;

    assign sysrst           = 1'b0;
    assign FAN_PWM          = 1'b1;

    assign ad9528_rst_n     = pll_locked;
    assign sysrst_glb_n     = pll_locked;

    assign ad9253_spi_rst_n = pll_locked;
    assign cfg_ad9528       = pll_locked;

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

    // spi configure ad9528 clock (125M refclks)
    spi_top spi_top_inst (
        .clk  (CLK_5M),
        .rst_n(ad9253_spi_rst_n),

        .cs_ad9528  (cs_ad9528),
        .sclk_ad9528(sclk_ad9528),
        .sdio_ad9528(sdio_ad9528),

        .cfg_ad9528(cfg_ad9528),

        .cfg_state_ad9528(cfg_state_ad9528)
    );

    //--------------------------------
    // RBCP slow control (parse host RBCP writes, extract channel + data into FIFO)
    //--------------------------------
    wire        rbcp_act;  // sitcp_top -> user (internal, not a top port)
    wire        rbcp_we;
    wire        rbcp_re;  // sitcp_top -> user (RBCP read request)
    wire [31:0] rbcp_addr;
    wire [ 7:0] rbcp_wd;
    wire        rbcp_ack;  // write+read ACK -> sitcp_top
    wire [  7:0] rbcp_rd;  // write+read data -> sitcp_top

    // Per-channel FIFO read ports (data flows toward stage1 boards)
    wire [  7:0] sc_to_stage1_clk;
    reg  [  7:0] sc_to_stage1_rd_en;
    wire [127:0] sc_to_stage1_rd_data;     // packed [ch*16 +: 16]
    wire [  7:0] sc_to_stage1_empty;
    wire [  7:0] sc_to_stage1_rd_rst_busy;

    rbcp_slow_control u_rbcp_slow_control (
        .clk  (CLK_200M),
        .rst_n(sysrst_glb_n),

        .RBCP_WE  (rbcp_we),
        .RBCP_WD  (rbcp_wd),
        .RBCP_ADDR(rbcp_addr),
        .RBCP_RE  (rbcp_re),
        .RBCP_RD  (rbcp_rd),
        .RBCP_ACK (rbcp_ack),

        .sc_to_stage1_clk       (sc_to_stage1_clk),
        .sc_to_stage1_rd_en     (sc_to_stage1_rd_en),
        .sc_to_stage1_rd_data   (sc_to_stage1_rd_data),
        .sc_to_stage1_empty     (sc_to_stage1_empty),
        .sc_to_stage1_rd_rst_busy (sc_to_stage1_rd_rst_busy),

        .sc_to_sitcp_dout       (sc_to_sitcp_dout),
        .sc_to_sitcp_valid      (sc_to_sitcp_valid),
        .sc_to_sitcp_rd_rst_busy (sc_to_sitcp_rd_rst_busy),
        .sc_to_sitcp_rd_en      (sc_to_sitcp_rd_en),

        .sc_to_sitcp_ack_dout   (ack_dout),
        .sc_to_sitcp_ack_valid  (ack_valid),
        .sc_to_sitcp_ack_rd_en  (ack_rd_en)
    );

    //--------------------------------
    // SiTCP subsystem (GMII, ethernet via 1000BASE-X SFP)
    //--------------------------------
    sitcp_top sitcp_top_inst (
        .CLK_200M     (CLK_200M),
        .SYS_RST      (~sysrst_glb_n),
        .SiTCP_RST_out(),

        // GT REFCLK (125M)
        .SGMII_CLK_P(gt_refclk4_p),
        .SGMII_CLK_N(gt_refclk4_n),

        // SFP
        .TX_DISABLE(),
        .SFP_TXP   (BE_SFP_TX_P),
        .SFP_TXN   (BE_SFP_TX_N),
        .SFP_RXP   (BE_SFP_RX_P),
        .SFP_RXN   (BE_SFP_RX_N),

        // TCP IO
        .TCP_OPEN_ACK(tcp_open_ack),
        .TCP_RX_WC   (tcp_rx_wc),     // Rx path unused, fill count left open
        .TCP_RX_WR   (tcp_rx_wr),
        .TCP_RX_DATA (tcp_rx_data),
        .TCP_TX_FULL (tcp_tx_full),
        .TCP_TX_WR   (tcp_wr),
        .TCP_TX_DATA (tcp_data),

        // RBCP IO (active in 200MHz clk domain)
        .RBCP_ACT (rbcp_act),
        .RBCP_ADDR(rbcp_addr),
        .RBCP_WD  (rbcp_wd),
        .RBCP_WE  (rbcp_we),
        .RBCP_RE  (rbcp_re),
        .RBCP_ACK (rbcp_ack),
        .RBCP_RD  (rbcp_rd)
    );


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

    wire [  7:0] gt_link_up;
    wire [ 15:0] rx_data_is_comma;
    wire [  7:0] gtx_rx_error;
    // GT interface outputs (per-channel clocks/data buses)
    wire [  7:0] clk_txoutclk_bufg;
    wire [  7:0] clk_rxoutclk_bufg;
    reg  [127:0] gt_tx_data;
    reg  [  7:0] gt_tx_data_valid;
    wire [127:0] gt_rx_data;
    wire [  7:0] gt_rx_data_valid;
    wire [  7:0] gtx_cpll_is_lock;

    //--------------------------------
    // RX data bridge: 8ch GTX (stage1) -> per-channel async FIFOs -> SiTCP TX
    //   Incoming frames (per channel ch, data clocked in clk_rxoutclk_bufg[ch]):
    //     0xFFF3 -> 1x W-packet ack -> fifo_ack
    //     0xFFF2 -> 6x 16-bit PTP (only low 8 bit of each word is used) -> fifo_ptp
    //     0xFFF1 -> 1x 16-bit slow-control (return)                      -> fifo_sc_tx
    //     0xFFF0 -> 1x 16-bit board word (uw_addr) + EVT_ADW 16-bit words -> fifo_adc
    //   fifo_adc write is gated on prog_full so a full event (EVT_ADW words)
    //   always has room before the first word is written.
    //--------------------------------
     localparam RX_PTP_HDR = 16'hFFF2;
     localparam RX_SC_HDR = 16'hFFF1;
     localparam RX_ADC_HDR = 16'hFFF0;
     localparam RX_ACK_HDR = 16'hFFF3;
     localparam RX_ADC_WORDS = 7'd64;  // 64 x 16-bit ADC words / event

    localparam [10:0] ADC_FIFO_FULL_THRESH = 11'd1984;  // write side >=1 event free (2048-64)
    localparam [11:0] ADC_FIFO_EMPT_THRESH = 12'd128;  // read side >=1 event (128 x 8-bit)

     // fifo_ack (8-in/8-out): W-packet acks from underwater via 0xFFF3
     reg  [  7:0] ack_wr_en;
     wire [  7:0] ack_empty;
     wire [  7:0] ack_valid;
     wire [127:0] ack_dout;
     wire [  7:0] ack_full;
     wire [  7:0] ack_wr_rst_busy;
     wire [  7:0] ack_rd_rst_busy;
     wire [  7:0] ack_rd_en;

     // per-channel captured board word (uw_addr); only low 8 bit meaningful
     reg  [ 63:0] uw_addr_reg;  // packed [ch*8 +: 8]

     // fifo_ptp (8-in/8-out): write side on rxoutclk, read side on CLK_200M
     reg  [  7:0] ptp_wr_en;
    reg  [  7:0] ptp_rd_en;
    reg  [ 63:0] ptp_din;  // packed [ch*8 +: 8]
    wire [ 63:0] ptp_dout;  // packed [ch*8 +: 8]
    wire [  7:0] ptp_empty;
    wire [  7:0] ptp_full;
    wire [  7:0] ptp_valid;
    wire [  7:0] ptp_wr_rst_busy;
    wire [  7:0] ptp_rd_rst_busy;

    // fifo_sc_tx (16-in/8-out): write side rxoutclk, read side CLK_200M
    reg  [  7:0] sc_wr_en;
    reg  [  7:0] sc_to_sitcp_rd_en;
    reg  [127:0] sc_to_sitcp_din;  // packed [ch*16 +: 16]
    wire [127:0] sc_to_sitcp_dout;  // packed [ch*8 +: 8]
    wire [  7:0] sc_to_sitcp_empty;
    wire [  7:0] sc_to_sitcp_full;
    wire [  7:0] sc_to_sitcp_valid;
    wire [  7:0] sc_to_sitcp_wr_rst_busy;
    wire [  7:0] sc_to_sitcp_rd_rst_busy;

    // fifo_adc (16-in/8-out): write side rxoutclk, read side CLK_200M
    reg  [  7:0] adc_wr_en;
    reg  [  7:0] adc_rd_en;
    reg  [127:0] adc_din;  // packed [ch*16 +: 16]
    wire [127:0] adc_dout;  // packed [ch*8 +: 8]
    wire [  7:0] adc_empty;
    wire [  7:0] adc_valid;
    wire [  7:0] adc_prog_empty;
    wire [  7:0] adc_prog_full;
    wire [  7:0] adc_full;
    wire [  7:0] adc_wr_rst_busy;
    wire [  7:0] adc_rd_rst_busy;

    //--------------------------------
    // RX parser (per-channel, each on its own clk_rxoutclk_bufg[ch])
    //   Demuxes the three frame headers into the per-channel FIFOs.
    //--------------------------------
    genvar rxc;
    generate
        for (rxc = 0; rxc < 8; rxc = rxc + 1) begin : g_rx_parse
            // three independent body-detection flags + counters
            reg       rx_ptp_state;  // 0=IDLE,1=in PTP body
            reg       rx_sc_state;  // 0=IDLE,1=in SC body
            reg       rx_adc_state;  // 0=IDLE,1=in ADC body(addr or data)
            reg [2:0] rx_ptp_cnt;
            reg [6:0] rx_adc_cnt;

            always @(posedge clk_rxoutclk_bufg[rxc] or negedge sysrst_glb_n) begin
                if (!sysrst_glb_n) begin
                    rx_ptp_state   <= 1'b0;
                    rx_sc_state    <= 1'b0;
                    rx_adc_state   <= 1'b0;
                    rx_ptp_cnt     <= 3'd0;
                    rx_adc_cnt     <= 7'd0;
                    ptp_wr_en[rxc] <= 1'b0;
                    sc_wr_en[rxc]  <= 1'b0;
                    adc_wr_en[rxc] <= 1'b0;
                end else begin
                    ptp_wr_en[rxc] <= 1'b0;
                    sc_wr_en[rxc]  <= 1'b0;
                    adc_wr_en[rxc] <= 1'b0;
                    if (gt_rx_data_valid[rxc]) begin
                        // IDLE (no active body): watch for a frame header
                        if (!rx_ptp_state && !rx_sc_state && !rx_adc_state) begin
                            if (gt_rx_data[rxc*16+:16] == RX_ACK_HDR) begin
                                ack_wr_en[rxc] <= 1'b1;
                            end else if (gt_rx_data[rxc*16+:16] == RX_PTP_HDR) begin
                                rx_ptp_state <= 1'b1;
                                rx_ptp_cnt   <= 3'd0;
                            end else if (gt_rx_data[rxc*16+:16] == RX_SC_HDR) begin
                                rx_sc_state <= 1'b1;
                            end else if (gt_rx_data[rxc*16+:16] == RX_ADC_HDR) begin
                                if (!adc_prog_full[rxc]) begin
                                    rx_adc_state <= 1'b1;  // first body word is the addr word
                                    rx_adc_cnt   <= 7'd0;
                                end
                                // else: fifo_adc has no room for a whole event, drop frame
                            end
                        end else begin
                            // in a frame body: dispatch by which header started it
                            if (g_rx_parse[0].rx_ptp_state) begin
                                ptp_wr_en[rxc]    <= 1'b1;
                                ptp_din[rxc*8+:8] <= gt_rx_data[rxc*16+:8];
                                if (rx_ptp_cnt == 3'd5) begin
                                    rx_ptp_state <= 1'b0;
                                end else begin
                                    rx_ptp_cnt <= rx_ptp_cnt + 3'd1;
                                end
                            end else if (g_rx_parse[0].rx_sc_state) begin
                                sc_wr_en[rxc]      <= 1'b1;
                                sc_to_sitcp_din[rxc*16+:16] <= gt_rx_data[rxc*16+:16];
                                rx_sc_state        <= 1'b0;
                            end else begin  // rx_adc_state
                                if (rx_adc_cnt == 7'd0) begin
                                    // first word = board addr (uw_addr), not stored
                                    uw_addr_reg[rxc*8+:8] <= gt_rx_data[rxc*16+:8];
                                    rx_adc_cnt <= 7'd1;
                                end else begin
                                    adc_wr_en[rxc]      <= 1'b1;
                                    adc_din[rxc*16+:16] <= gt_rx_data[rxc*16+:16];
                                    if (rx_adc_cnt == RX_ADC_WORDS) begin
                                        rx_adc_state <= 1'b0;
                                    end else begin
                                        rx_adc_cnt <= rx_adc_cnt + 7'd1;
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    endgenerate

    //--------------------------------
    // Per-channel RX FIFOs (write: clk_rxoutclk_bufg[ch], read: CLK_200M)
    //--------------------------------
    genvar fif;
    generate
        for (fif = 0; fif < 8; fif = fif + 1) begin : g_rx_fifo
            fifo_ptp u_fifo_ptp (
                .rst        (sysrst_glb_n == 1'b0),
                .wr_clk     (clk_rxoutclk_bufg[fif]),
                .rd_clk     (CLK_200M),
                .din        (ptp_din[fif*8+:8]),
                .wr_en      (ptp_wr_en[fif]),
                .rd_en      (ptp_rd_en[fif]),
                .dout       (ptp_dout[fif*8+:8]),
                .full       (ptp_full[fif]),
                .empty      (ptp_empty[fif]),
                .valid      (ptp_valid[fif]),
                .wr_rst_busy(ptp_wr_rst_busy[fif]),
                .rd_rst_busy(ptp_rd_rst_busy[fif])
            );

            fifo_sc_tx u_fifo_sc_tx (
                .rst        (sysrst_glb_n == 1'b0),
                .wr_clk     (clk_rxoutclk_bufg[fif]),
                .rd_clk     (CLK_200M),
                .din        (sc_to_sitcp_din[fif*16+:16]),
                .wr_en      (sc_wr_en[fif]),
                .rd_en      (sc_to_sitcp_rd_en[fif]),
                .dout       (sc_to_sitcp_dout[fif*8+:8]),
                .full       (sc_to_sitcp_full[fif]),
                .empty      (sc_to_sitcp_empty[fif]),
                .valid      (sc_to_sitcp_valid[fif]),
                .wr_rst_busy(sc_to_sitcp_wr_rst_busy[fif]),
                .rd_rst_busy(sc_to_sitcp_rd_rst_busy[fif])
            );

            fifo_adc u_fifo_adc (
                .rst              (sysrst_glb_n == 1'b0),
                .wr_clk           (clk_rxoutclk_bufg[fif]),
                .rd_clk           (CLK_200M),
                .din              (adc_din[fif*16+:16]),
                .wr_en            (adc_wr_en[fif]),
                .rd_en            (adc_rd_en[fif]),
                .prog_empty_thresh(ADC_FIFO_EMPT_THRESH),
                .prog_full_thresh (ADC_FIFO_FULL_THRESH),
                .dout             (adc_dout[fif*8+:8]),
                .full             (adc_full[fif]),
                .empty            (adc_empty[fif]),
                .valid            (adc_valid[fif]),
                .prog_full        (adc_prog_full[fif]),
                .prog_empty       (adc_prog_empty[fif]),
                .wr_rst_busy      (adc_wr_rst_busy[fif]),
                .rd_rst_busy      (adc_rd_rst_busy[fif])
            );

            // W-packet ack FIFO (0xFFF3 + 1 word)
            fifo_sc_tx u_fifo_ack (
                .rst        (~sysrst_glb_n),
                .wr_clk     (clk_rxoutclock_bufg[fif]),
                .rd_clk     (CLK_200M),
                .din        (user_rx_data[fif*16+:16]),
                .wr_en      (ack_wr_en[fif] && ~ack_full[fif] && ~ack_wr_rst_busy[fif]),
                .rd_en      (ack_rd_en[fif]),
                .dout       (ack_dout[fif*16+:16]),
                .full       (ack_full[fif]),
                .empty      (ack_empty[fif]),
                .valid      (ack_valid[fif]),
                .wr_rst_busy(ack_wr_rst_busy[fif]),
                .rd_rst_busy(ack_rd_rst_busy[fif])
            );
        end
    endgenerate

    //--------------------------------
    // GT TX slow-control drain (per-channel, each on its own clk_txoutclk_bufg)
    //   Each GT channel i has one fifo_rbcp written from the 200M RBCP side.
    //   When that FIFO is non-empty, this logic reads its 16-bit word and sends
    //   it out on GT channel i with valid=1 for one TX cycle.
    //   When idle, the channel drives 16'hbc3c idle; gt_tx_data_valid=0 makes the
    //   interface force txcharisk=11 (K28.7|K28.3 idle).
    //   Standard-mode async FIFO: dout = head word whenever empty=0; asserting
    //   rd_en fetches it now and pops at the next rising edge.  S_IDLE captures
    //   dout with rd_en=1, S_SEND pushes the captured word out exactly once.
    //--------------------------------
    genvar sc;
    generate
        for (sc = 0; sc < 8; sc = sc + 1) begin : g_sc_tx
            localparam SC_IDLE = 1'b0;
            localparam SC_SEND = 1'b1;

            assign sc_to_stage1_clk[sc] = clk_txoutclk_bufg[sc];

            reg        sc_state;
            reg [15:0] sc_dat;

            always @(posedge clk_txoutclk_bufg[sc] or negedge sysrst_glb_n) begin
                if (!sysrst_glb_n) begin
                    sc_state               <= SC_IDLE;
                    sc_dat                <= 16'h0000;
                    sc_to_stage1_rd_en[sc] <= 1'b0;
                    gt_tx_data[sc*16+:16] <= 16'hbc3c;
                    gt_tx_data_valid[sc]  <= 1'b0;
                end else begin
                    sc_to_stage1_rd_en[sc] <= 1'b0;
                    gt_tx_data[sc*16+:16] <= 16'hbc3c;  // default: idle
                    gt_tx_data_valid[sc]  <= 1'b0;
                    case (sc_state)
                        SC_IDLE: begin
                            if (!sc_to_stage1_empty[sc] && !sc_to_stage1_rd_rst_busy[sc]) begin
                                sc_to_stage1_rd_en[sc] <= 1'b1;
                                sc_dat                  <= sc_to_stage1_rd_data[sc*16+:16];
                                sc_state       <= SC_SEND;
                            end
                        end
                        SC_SEND: begin
                            // send the 16-bit payload once on this channel
                            gt_tx_data[sc*16+:16] <= sc_dat;
                            gt_tx_data_valid[sc]  <= 1'b1;
                            sc_state              <= SC_IDLE;
                        end
                        default: sc_state <= SC_IDLE;
                    endcase
                end
            end
        end
    endgenerate

    interface_gtx_8ch instance_gtx_interface_8ch (
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
        .gt_link_up       (gt_link_up),
        .rx_data_is_comma (rx_data_is_comma),
        .gtx_rx_error     (gtx_rx_error)
    );

    //--------------------------------
    // SiTCP TX 轮询发送状态机（CLK_200M 域）
    //   优先级: PTP > ADC 事件(fifo_adc) > 空闲
    //   仲裁 round-robin 扫描 rr_idx[0..7]
    //   每字节受 TCP_TX_FULL 背压;FIFO 读用 valid 握手(与 stage1 相同)
    //   - PTP: 固定读 6 字节(凑满 6 才发,中途空则等待)
    //   - ADC: 头 {stage1_addr(=ch+1), uw_addr} + 固定读 128 字节
    //   - IDLE: 无数据则 rr_idx 递增轮询(不发任何字节)
    //   (慢控返回已改走 UDP,由 rbcp_slow_control 读从处理,fifo_sc_tx 不再进 TCP)
    //--------------------------------
    localparam TX_IDLE = 3'd0;
    localparam TX_ADSET = 3'd1;  // ADC 头字节0: stage1_addr
    localparam TX_ADUW = 3'd2;  // ADC 头字节1: uw_addr
    localparam TX_ADATA = 3'd3;  // ADC 数据 128 字节
    localparam TX_PTP = 3'd4;  // PTP 固定读 6 次

    reg [2:0] tx_state;
    reg [2:0] rr_idx;
    reg [2:0] ptp_tx_cnt;
    reg [7:0] evt_tx_cnt;  // 0..129 (2 头 + 128 数据)
    reg       tcp_wr;
    reg [7:0] tcp_data;

    always @(posedge CLK_200M or negedge sysrst_glb_n) begin
        if (!sysrst_glb_n) begin
            tx_state   <= TX_IDLE;
            rr_idx     <= 3'd0;
            ptp_tx_cnt <= 3'd0;
            evt_tx_cnt <= 8'd0;
            tcp_wr     <= 1'b0;
            tcp_data   <= 8'd0;
            ptp_rd_en  <= 8'd0;
            adc_rd_en  <= 8'd0;
        end else begin
            tcp_wr    <= 1'b0;
            ptp_rd_en <= 8'd0;
            adc_rd_en <= 8'd0;
            case (tx_state)
                TX_IDLE: begin
                    if (~ptp_empty[rr_idx]) begin
                        ptp_tx_cnt <= 3'd0;
                        tx_state   <= TX_PTP;
                    end else if (~adc_prog_empty[rr_idx]) begin
                        evt_tx_cnt <= 8'd0;
                        tx_state   <= TX_ADSET;
                    end else begin
                        rr_idx <= rr_idx + 3'd1;
                    end
                end
                //---- ADC 事件：头 + 128 字节 ----
                TX_ADSET: begin
                    if (!tcp_tx_full) begin
                        tcp_data   <= {5'd0, rr_idx} + 8'd1;  // stage1_addr = ch+1
                        tcp_wr     <= 1'b1;
                        evt_tx_cnt <= 8'd1;
                        tx_state   <= TX_ADUW;
                    end
                end
                TX_ADUW: begin
                    if (!tcp_tx_full) begin
                        tcp_data   <= uw_addr_reg[rr_idx*8+:8];
                        tcp_wr     <= 1'b1;
                        evt_tx_cnt <= 8'd2;
                        tx_state   <= TX_ADATA;
                    end
                end
                TX_ADATA: begin
                    if (!tcp_tx_full) begin
                        adc_rd_en <= (8'd1 << rr_idx);
                        if (adc_valid[rr_idx]) begin
                            tcp_wr   <= 1'b1;
                            tcp_data <= adc_dout[rr_idx*8+:8];
                            if (evt_tx_cnt == 8'd129) begin
                                tx_state <= TX_IDLE;  // 128 字节发完
                                rr_idx   <= rr_idx + 3'd1;
                            end else begin
                                evt_tx_cnt <= evt_tx_cnt + 8'd1;
                            end
                        end else begin
                            tcp_wr <= 1'b0;
                        end
                    end
                end
                // ---- PTP：最高优先，读 6 字节 ----
                TX_PTP: begin
                    if (!tcp_tx_full) begin
                        ptp_rd_en <= (8'd1 << rr_idx);
                        if (ptp_valid[rr_idx]) begin
                            tcp_wr   <= 1'b1;
                            tcp_data <= ptp_dout[rr_idx*8+:8];
                            if (ptp_tx_cnt == 3'd5) begin
                                tx_state <= TX_IDLE;  // 6 字节发完
                                rr_idx   <= rr_idx + 3'd1;
                            end else begin
                                ptp_tx_cnt <= ptp_tx_cnt + 3'd1;
                            end
                        end else begin
                            tcp_wr <= 1'b0;
                        end
                    end
                end
                default: tx_state <= TX_IDLE;
            endcase
        end
    end

    // //========================================================================
    // // ILA 例化区 (4 核, 位宽/时钟与 .xci 逐一核对)
    // //  - ila_fe_rx   : 22探针/67bit, clk = clk_rxoutclk_bufg[0]      (ch0 RX 域)
    // //  - ila_fe_tx   :  8探针/53bit, clk = clk_txoutclk_bufg[0]      (ch0 TX 域)
    // //  - ila_tcp_tx  : 24探针/86bit, clk = CLK_200M                  (TCP TX 域)
    // //  - ila_sc_read : 11探针/60bit, clk = CLK_200M                  (SC 读/慢控域)
    // //========================================================================

    // //--------------------------------------------------
    // // 1) ila_fe_rx: FE RX 逐通道解析 (clk_rxoutclk_bufg[0] 域, ch0)
    // //    位宽 [16,1,8,8,1,2,1,1,1,3,7,1,1,1,1,1,1,1,8,1,1,1]=67
    // //--------------------------------------------------
    // ila_fe_rx u_ila_fe_rx (
    //     .clk      (clk_rxoutclk_bufg[0]),

    //     .probe0   (gt_rx_data[15:0]),        // 16 + gt_rx_data  ch0 原始GT RX数据
    //     .probe1   (gt_rx_data_valid[0]),     //  1   ch0 RX 数据有效
    //     .probe2   (ptp_din[7:0]),            //  8   ch0 PTP FIFO 写入字节
    //     .probe3   (uw_addr_reg[7:0]),        //  8   ch0 板地址字节
    //     .probe4   (g_rx_parse[0].g_rx_parse[0].rx_ptp_state),            //  1   ch0 PTP 解析状态
    //     .probe5   (rx_data_is_comma[1:0]),   //  2   ch0 comma 检测
    //     .probe6   (g_rx_parse[0].g_rx_parse[0].rx_sc_state),             //  1   ch0 SC 解析状态
    //     .probe7   (g_rx_parse[0].g_rx_parse[0].rx_adc_state),            //  1   ch0 ADC 解析状态
    //     .probe8   (ptp_wr_en[0]),            //  1   ch0 PTP FIFO 写使能
    //     .probe9   (g_rx_parse[0].g_rx_parse[0].rx_ptp_cnt),         //  3   ch0 PTP 字节计数
    //     .probe10  (g_rx_parse[0].g_rx_parse[0].rx_adc_cnt),         //  7   ch0 ADC 字节计数
    //     .probe11  (sc_wr_en[0]),             //  1   ch0 SC FIFO 写使能
    //     .probe12  (adc_wr_en[0]),            //  1   ch0 ADC FIFO 写使能
    //     .probe13  (adc_prog_full[0]),        //  1   ch0 ADC FIFO 预满
    //     .probe14  (gtx_rx_error[0]),          //  1   ch0 GT RX 错误
    //     .probe15  (gt_link_up[0]),           //  1   ch0 GT 链路建立
    //     .probe16  (rx_data_is_comma[0]),     //  1   ch0 comma 低位
    //     .probe17  (rx_data_is_comma[1]),     //  1   ch0 comma 高位
    //     .probe18  (sc_to_sitcp_din[7:0]),           //  8   ch0 SC 写入数据低字节
    //     .probe19  (gt_rx_data_valid[0]),     //  1   复用: ch0 RX 数据有效
    //     .probe20  (gt_link_up[0]),           //  1   复用: ch0 GT 链路建立
    //     .probe21  (gtx_rx_error[0])           //  1   复用: ch0 GT RX 错误
    // );

    // //--------------------------------------------------
    // // 2) ila_fe_tx: FE TX 逐通道发送 (clk_txoutclk_bufg[0] 域)
    // //    位宽 [1,1,1,1,16,16,16,1]=53  (PTP/ADC 数据走 RX 上行, TX 侧仅 SC 慢控)
    // //--------------------------------------------------
    // ila_fe_tx u_ila_fe_tx (
    //     .clk      (clk_txoutclk_bufg[0]),

    //     .probe0   (gt_tx_data_valid[0]),     //  1   ch0 TX 数据有效
    //     .probe1   (sc_to_stage1_rd_en[0]),        //  1   ch0 SC FIFO 读使能
    //     .probe2   (sc_to_stage1_empty[0]),        //  1   ch0 SC TX FIFO 空(读侧)
    //     .probe3   (sc_to_stage1_rd_rst_busy[0]),  //  1   ch0 SC FIFO 读复位忙
    //     .probe4   (gt_tx_data[15:0]),        // 16   ch0 TX 数据字节流
    //     .probe5   (gt_tx_data[31:16]),       // 16   ch1 TX 数据字节流
    //     .probe6   (gt_tx_data[47:32]),       // 16   ch2 TX 数据字节流
    //     .probe7   (gt_tx_data_valid[0])      //  1   复用: ch0 TX 数据有效
    // );

    // //--------------------------------------------------
    // // 3) ila_tcp_tx: TCP TX 慢控发送 (CLK_200M 域)
    // //    位宽 [3,3,1,8,1,1,3,8,1,1,1,8,1,1,8,1,1,8,8,1,1,1,8,8]=86
    // //--------------------------------------------------
    // ila_tcp_tx u_ila_tcp_tx (
    //     .clk      (CLK_200M),

    //     .probe0   (tx_state[2:0]),           //  3   TCP TX FSM 状态
    //     .probe1   (rr_idx[2:0]),             //  3   通道轮询索引
    //     .probe2   (tcp_wr),                  //  1   TCP TX 写使能
    //     .probe3   (tcp_data[7:0]),           //  8   TCP TX 数据
    //     .probe4   (tcp_tx_full),             //  1   TCP TX FIFO 满(背压)
    //     .probe5   (rbcp_act),                //  1   RBCP 活动
    //     .probe6   (ptp_tx_cnt[2:0]),         //  3   PTP 发送字节计数
    //     .probe7   (evt_tx_cnt[7:0]),         //  8   ADC 事件发送字节计数
    //     .probe8   (rbcp_we),                 //  1   RBCP 写使能
    //     .probe9   (rbcp_re),                 //  1   RBCP 读使能
    //     .probe10  (rbcp_ack),                //  1   RBCP 应答(合并)
    //     .probe11  (rbcp_wd[7:0]),            //  8   RBCP 写数据
    //     .probe12  (rbcp_ack),                //  1   RBCP 写应答
    //     .probe13  (rbcp_ack),                //  1   RBCP 读应答
    //     .probe14  (rbcp_rd[7:0]),            //  8   RBCP 读数据
    //     .probe15  (tcp_open_ack),            //  1   TCP 连接确认
    //     .probe16  (tcp_rx_wr),               //  1   TCP RX 写
    //     .probe17  (ptp_empty[7:0]),          //  8   PTP FIFO 空(8ch)
    //     .probe18  (ptp_valid[7:0]),          //  8   PTP FIFO 有效(8ch)
    //     .probe19  (ptp_empty[0]),            //  1   复用: ch0 PTP FIFO 空
    //     .probe20  (adc_valid[0]),            //  1   ch0 ADC FIFO 有效
    //     .probe21  (sc_empty[0]),             //  1   ch0 SC FIFO 空
    //     .probe22  (sc_to_stage1_empty[7:0]),     //  8   SC TX FIFO 空(8ch)
    //     .probe23  (adc_valid[7:0])           //  8   ADC FIFO 有效(8ch)
    // );

    // //--------------------------------------------------
    // // 4) ila_sc_read: SC 读通路/UDP-RBCP 读 (CLK_200M 域)
    // //    位宽 [1,8,8,8,8,8,1,1,1,8,8]=60
    // //--------------------------------------------------
    // ila_sc_read u_ila_sc_read (
    //     .clk      (CLK_200M),

    //     .probe0   (rbcp_re),                 //  1   RBCP 读请求
    //     .probe1   (sc_to_sitcp_rd_en[7:0]),          //  8   SC FIFO 读使能(8ch)
    //     .probe2   (sc_to_sitcp_valid[7:0]),          //  8   SC FIFO 有效(8ch)
    //     .probe3   (sc_to_sitcp_rd_rst_busy[7:0]),    //  8   SC FIFO 读复位忙(8ch)
    //     .probe4   (sc_to_sitcp_dout[7:0]),           //  8   SC 读数据 ch0
    //     .probe5   (sc_empty[7:0]),           //  8   SC FIFO 空(8ch)
    //     .probe6   (rbcp_ack),              //  1   RBCP 读应答
    //     .probe7   (rbcp_ack),                //  1   RBCP 应答(合并)
    //     .probe8   (rbcp_act),                //  1   RBCP 活动
    //     .probe9   (rbcp_rd[7:0]),          //  8   读从返回数据
    //     .probe10  (rbcp_rd[7:0])             //  8   合并读数据
    // );

endmodule
                    ptp_wr_en[rxc] <= 1'b0;
                    sc_wr_en[rxc]  <= 1'b0;
                    adc_wr_en[rxc] <= 1'b0;
                    ack_wr_en[rxc] <= 1'b0;
                end else begin
                    ptp_wr_en[rxc] <= 1'b0;
                    sc_wr_en[rxc]  <= 1'b0;
                    adc_wr_en[rxc] <= 1'b0;
                    ack_wr_en[rxc] <= 1'b0;
