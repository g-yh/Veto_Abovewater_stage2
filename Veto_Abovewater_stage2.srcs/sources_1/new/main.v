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

    wire [7:0] gt_link_up;
    wire       tcp_open_ack;

    // assign gt_link_up_led1 = &gt_link_up;
    assign gt_link_up_led1 = gt_link_up[0];
    assign sitcp_led2 = tcp_open_ack;

    assign SFP_TX_DISABLE = 1'b0;

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

    // assign sysrst_glb_n     = pll_locked;
    vio_0 vio_0_inst (
        .clk(CLK_200M),
        .probe_out0(sysrst_glb_n)
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
    wire         rbcp_act;  // sitcp_top -> user (internal, not a top port)
    wire         rbcp_we;
    wire         rbcp_re;  // sitcp_top -> user (RBCP read request)
    wire [ 31:0] rbcp_addr;
    wire [  7:0] rbcp_wd;
    wire         rbcp_ack;  // write+read ACK -> sitcp_top
    wire [  7:0] rbcp_rd;  // write+read data -> sitcp_top

    // Per-channel FIFO read ports (data flows toward stage1 boards)
    wire [  7:0] sc_to_stage1_clk;
    reg  [  7:0] sc_to_stage1_fifo_rd_en;
    wire [127:0] sc_to_stage1;  // packed [ch*16 +: 16]
    wire [  7:0] sc_to_stage1_fifo_empty;
    wire [  7:0] sc_to_stage1_fifo_rd_rst_busy;
    wire [  7:0] sc_to_stage1_valid;

    // PTP result FIFO read side (declared before rbcp_slow_control).
    wire [63:0] ptp_dout;   // packed [ch*8 +: 8]
    wire [ 7:0] ptp_empty;
    wire [ 7:0] ptp_valid;
    wire [ 7:0] ptp_rd_rst_busy;
    wire [ 7:0] ptp_rd_en;

    // Declared before rbcp_slow_control and sitcp_top instantiations.
    wire [ 7:0] ack_empty;              // packed [ch]
    wire [63:0] sc_to_sitcp_dout;       // packed [ch*8 +: 8]
    wire [ 7:0] sc_to_sitcp_empty;
    wire [ 7:0] sc_to_sitcp_valid;
    wire [ 7:0] sc_to_sitcp_rd_rst_busy;
    wire [ 7:0] sc_to_sitcp_rd_en;
    reg         tcp_wr;
    reg  [7:0]  tcp_data;

    rbcp_slow_control u_rbcp_slow_control (
        .clk  (CLK_200M),
        .rst_n(sysrst_glb_n),

        .RBCP_WE  (rbcp_we),
        .RBCP_WD  (rbcp_wd),
        .RBCP_ADDR(rbcp_addr),
        .RBCP_RE  (rbcp_re),
        .RBCP_RD  (rbcp_rd),
        .RBCP_ACK (rbcp_ack),

        .sc_to_stage1_clk             (sc_to_stage1_clk),
        .sc_to_stage1_fifo_rd_en      (sc_to_stage1_fifo_rd_en),
        .sc_to_stage1                 (sc_to_stage1),
        .sc_to_stage1_fifo_empty      (sc_to_stage1_fifo_empty),
        .sc_to_stage1_fifo_rd_rst_busy(sc_to_stage1_fifo_rd_rst_busy),
        .sc_to_stage1_valid           (sc_to_stage1_valid),

        .sc_to_sitcp_dout       (sc_to_sitcp_dout),
        .sc_to_sitcp_valid      (sc_to_sitcp_valid),
        .sc_to_sitcp_empty      (sc_to_sitcp_empty),
        .sc_to_sitcp_rd_rst_busy(sc_to_sitcp_rd_rst_busy),
        .sc_to_sitcp_rd_en      (sc_to_sitcp_rd_en),

        .ptp_to_sitcp_dout       (ptp_dout),
        .ptp_to_sitcp_valid      (ptp_valid),
        .ptp_to_sitcp_empty      (ptp_empty),
        .ptp_to_sitcp_rd_rst_busy(ptp_rd_rst_busy),
        .ptp_to_sitcp_rd_en      (ptp_rd_en),

        .ack_empty(ack_empty)
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
    //     0xFFF2 -> 48x 16-bit PTP (only low 8 bit of each word is used) -> fifo_ptp
    //     0xFFF1 -> 1x 16-bit slow-control (return)                      -> fifo_sc_tx
    //     0xFFF0 -> 1x 16-bit board word (uw_addr) + EVT_ADW 16-bit words -> fifo_adc
    //   fifo_adc write is gated on prog_full so a full event (EVT_ADW words)
    //   always has room before the first word is written.
    //--------------------------------
    localparam RX_PTP_HDR = 16'hFFF2;
    localparam [5:0] RX_PTP_BYTES = 6'd48;
    localparam RX_SC_HDR = 16'hFFF1;
    localparam RX_ADC_HDR = 16'hFFF0;
    localparam RX_ACK_HDR = 16'hFFF3;
    localparam RX_ADC_WORDS = 7'd64;  // 64 x 16-bit ADC words / event

    localparam [10:0] ADC_FIFO_FULL_THRESH = 11'd1984;  // write side >=1 event free (2048-64)
    localparam [11:0] ADC_FIFO_EMPT_THRESH = 12'd128;  // read side >=1 event (128 x 8-bit)

    // fifo_ack (8-in/8-out): W-packet acks from underwater via 0xFFF3
    reg  [  7:0] ack_wr_en;
    reg  [127:0] ack_din;  // per-channel ack header
    wire [  7:0] ack_rd_en;  // driven by ~ack_empty
    assign ack_rd_en = ~ack_empty;
    wire [  7:0] ack_valid;
    wire [127:0] ack_dout;
    wire [  7:0] ack_full;
    wire [  7:0] ack_wr_rst_busy;
    wire [  7:0] ack_rd_rst_busy;

    // per-channel captured board word (uw_addr); only low 8 bit meaningful
    reg  [ 63:0] uw_addr_reg;  // packed [ch*8 +: 8]

    // fifo_ptp (8-in/8-out): write side on rxoutclk, read side on CLK_200M.
    // Its read side is now consumed by rbcp_slow_control (UDP R packets).
    reg  [ 7:0] ptp_wr_en;
    reg  [63:0] ptp_din;  // packed [ch*8 +: 8]
    wire [ 7:0] ptp_full;
    wire [ 7:0] ptp_wr_rst_busy;

    // fifo_sc_tx (16-in/8-out): write side rxoutclk, read side CLK_200M
    reg  [  7:0] sc_wr_en;
    reg  [127:0] sc_to_sitcp_din;  // packed [ch*16 +: 16]
    wire [  7:0] sc_to_sitcp_full;
    wire [  7:0] sc_to_sitcp_wr_rst_busy;

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

    reg [15:0] ack_cnt_main;

    // RX parser per-channel state (declared outside generate, indexed by channel)
    reg  [  7:0] rx_ptp_state;  // [ch]          0=IDLE,1=in PTP body
    reg  [  7:0] rx_sc_state;   // [ch]          0=IDLE,1=in SC body
    reg  [  7:0] rx_adc_state;  // [ch]          0=IDLE,1=in ADC body(addr or data)
    reg  [ 47:0] rx_ptp_cnt;    // [ch*6 +: 6], count 0..47
    reg  [ 55:0] rx_adc_cnt;    // [ch*7 +: 7]

    //--------------------------------
    // RX parser (per-channel, each on its own clk_rxoutclk_bufg[ch])
    //   Demuxes the three frame headers into the per-channel FIFOs.
    //--------------------------------
    genvar rxc;
    generate
        for (rxc = 0; rxc < 8; rxc = rxc + 1) begin : g_rx_parse
            always @(posedge clk_rxoutclk_bufg[rxc] or negedge sysrst_glb_n) begin
                if (!sysrst_glb_n) begin
                    rx_ptp_state[rxc]    <= 1'b0;
                    rx_sc_state[rxc]     <= 1'b0;
                    rx_adc_state[rxc]    <= 1'b0;
                    rx_ptp_cnt[rxc*6+:6] <= 6'd0;
                    rx_adc_cnt[rxc*7+:7] <= 7'd0;
                    ptp_wr_en[rxc] <= 1'b0;
                    sc_wr_en[rxc]  <= 1'b0;
                    adc_wr_en[rxc] <= 1'b0;
                    ack_wr_en[rxc] <= 1'b0;
                end else begin
                    ptp_wr_en[rxc] <= 1'b0;
                    sc_wr_en[rxc]  <= 1'b0;
                    adc_wr_en[rxc] <= 1'b0;
                    ack_wr_en[rxc] <= 1'b0;
                    if (gt_rx_data_valid[rxc]) begin
                        // IDLE (no active body): watch for a frame header
                        if (!rx_ptp_state[rxc] && !rx_sc_state[rxc] && !rx_adc_state[rxc]) begin
                            if (gt_rx_data[rxc*16+:16] == RX_ACK_HDR) begin
                                ack_wr_en[rxc] <= 1'b1;
                                ack_din[rxc*16+:16] <= gt_rx_data[rxc*16+:16];
                            end else if (gt_rx_data[rxc*16+:16] == RX_PTP_HDR) begin
                                rx_ptp_state[rxc]    <= 1'b1;
                                rx_ptp_cnt[rxc*6+:6] <= 6'd0;
                            end else if (gt_rx_data[rxc*16+:16] == RX_SC_HDR) begin
                                rx_sc_state[rxc] <= 1'b1;
                            end else if (gt_rx_data[rxc*16+:16] == RX_ADC_HDR) begin
                                if (!adc_prog_full[rxc]) begin
                                    rx_adc_state[rxc]    <= 1'b1;  // first body word is the addr word
                                    rx_adc_cnt[rxc*7+:7] <= 7'd0;
                                end
                                // else: fifo_adc has no room for a whole event, drop frame
                            end
                        end else begin
                            // in a frame body: dispatch by which header started it
                            if (rx_ptp_state[rxc]) begin
                                // A new FFF2 during a body means the previous
                                // non-fragmented frame timed out or was truncated.
                                // Abandon it and start counting this frame again.
                                if (gt_rx_data[rxc*16+:16] == RX_PTP_HDR) begin
                                    rx_ptp_cnt[rxc*6+:6] <= 6'd0;
                                    ptp_wr_en[rxc]       <= 1'b0;
                                end else begin
                                    ptp_wr_en[rxc]    <= 1'b1;
                                    ptp_din[rxc*8+:8] <= gt_rx_data[rxc*16+:8];
                                    if (rx_ptp_cnt[rxc*6+:6] == RX_PTP_BYTES - 6'd1) begin
                                        rx_ptp_state[rxc] <= 1'b0;
                                    end else begin
                                        rx_ptp_cnt[rxc*6+:6] <= rx_ptp_cnt[rxc*6+:6] + 6'd1;
                                    end
                                end
                            end else if (rx_sc_state[rxc]) begin
                                sc_wr_en[rxc]               <= 1'b1;
                                sc_to_sitcp_din[rxc*16+:16] <= gt_rx_data[rxc*16+:16];
                                rx_sc_state[rxc]            <= 1'b0;
                            end else begin  // rx_adc_state
                                if (rx_adc_cnt[rxc*7+:7] == 7'd0) begin
                                    // first word = board addr (uw_addr), not stored
                                    uw_addr_reg[rxc*8+:8] <= gt_rx_data[rxc*16+:8];
                                    rx_adc_cnt[rxc*7+:7]  <= 7'd1;
                                end else begin
                                    adc_wr_en[rxc]      <= 1'b1;
                                    adc_din[rxc*16+:16] <= gt_rx_data[rxc*16+:16];
                                    if (rx_adc_cnt[rxc*7+:7] == RX_ADC_WORDS) begin
                                        rx_adc_state[rxc] <= 1'b0;
                                    end else begin
                                        rx_adc_cnt[rxc*7+:7] <= rx_adc_cnt[rxc*7+:7] + 7'd1;
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    endgenerate

    // ack frames (0xFFF3) received on channel 0 (clk_rxoutclk_bufg[0] domain),
    // one per ack_wr_en[0] pulse. Single always block -> no multi-driver.
    always @(posedge clk_rxoutclk_bufg[0] or negedge sysrst_glb_n) begin
        if (!sysrst_glb_n)
            ack_cnt_main <= 16'd0;
        else if (ack_wr_en[0])
            ack_cnt_main <= ack_cnt_main + 16'd1;
    end

    //--------------------------------
    // Per-channel RX FIFOs (write: clk_rxoutclk_bufg[ch], read: CLK_200M)
    //--------------------------------
    genvar fif;
    generate
        for (fif = 0; fif < 8; fif = fif + 1) begin : g_rx_fifo
            fifo_ptp u_fifo_ptp (
                .rst        (~sysrst_glb_n),
                .wr_clk     (clk_rxoutclk_bufg[fif]),
                .rd_clk     (CLK_200M),
                .din        (ptp_din[fif*8+:8]),
                .wr_en      (ptp_wr_en[fif] && ~ptp_full[fif]),
                .rd_en      (ptp_rd_en[fif]),
                .dout       (ptp_dout[fif*8+:8]),
                .full       (ptp_full[fif]),
                .empty      (ptp_empty[fif]),
                .valid      (ptp_valid[fif]),
                .wr_rst_busy(ptp_wr_rst_busy[fif]),
                .rd_rst_busy(ptp_rd_rst_busy[fif])
            );

            fifo_sc_tx u_fifo_sc_tx (
                .rst        (~sysrst_glb_n),
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
                .rst              (~sysrst_glb_n),
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
            fifo_sc_ack u_fifo_ack (
                .rst        (~sysrst_glb_n),
                .wr_clk     (clk_rxoutclk_bufg[fif]),
                .rd_clk     (CLK_200M),
                .din        (ack_din[fif*16+:16]),
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
    //   rd_en pops at the next rising edge.  SC_IDLE asserts rd_en,
    //   SC_WAIT waits for sc_to_stage1_valid, then pushes the word out once.
    //--------------------------------
    genvar sc;
    generate
        for (sc = 0; sc < 8; sc = sc + 1) begin : g_sc_tx
            localparam SC_IDLE = 2'b00;
            localparam SC_WAIT = 2'b01;

            assign sc_to_stage1_clk[sc] = clk_txoutclk_bufg[sc];

            reg [ 1:0] sc_state;

            always @(posedge clk_txoutclk_bufg[sc] or negedge sysrst_glb_n) begin
                if (!sysrst_glb_n) begin
                    sc_state                    <= SC_IDLE;
                    sc_to_stage1_fifo_rd_en[sc] <= 1'b0;
                    gt_tx_data[sc*16+:16]       <= 16'hbc3c;
                    gt_tx_data_valid[sc]        <= 1'b0;
                end else begin
                    sc_to_stage1_fifo_rd_en[sc] <= 1'b0;
                    gt_tx_data[sc*16+:16] <= 16'hbc3c;  // default: idle
                    gt_tx_data_valid[sc] <= 1'b0;
                    case (sc_state)
                        SC_IDLE: begin
                            if (!sc_to_stage1_fifo_empty[sc] && !sc_to_stage1_fifo_rd_rst_busy[sc]) begin
                                sc_to_stage1_fifo_rd_en[sc] <= 1'b1;
                                sc_state                    <= SC_WAIT;
                            end
                        end
                        SC_WAIT: begin
                            if (sc_to_stage1_valid[sc]) begin
                                gt_tx_data[sc*16+:16] <= sc_to_stage1[sc*16+:16];
                                gt_tx_data_valid[sc]  <= 1'b1;
                                sc_state              <= SC_IDLE;
                            end
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
    //   优先级: ADC 事件(fifo_adc) > 空闲；PTP 已改为 RBCP UDP 读取
    //   仲裁 round-robin 扫描 rr_idx[0..7]
    //   每字节受 TCP_TX_FULL 背压;FIFO 读用 valid 握手(与 stage1 相同)
    //   - ADC: 头 {stage1_addr(=ch+1), uw_addr} + 固定读 128 字节
    //   - IDLE: 无数据则 rr_idx 递增轮询(不发任何字节)
    //   (慢控返回已改走 UDP,由 rbcp_slow_control 读从处理,fifo_sc_tx 不再进 TCP)
    //   PTP results are stored in fifo_ptp and read through RBCP UDP R packets.
    //   The TCP state machine below now carries ADC event data only.
    //--------------------------------
    localparam TX_IDLE = 3'd0;
    localparam TX_ADSET = 3'd1;  // ADC 头字节0: stage1_addr
    localparam TX_ADUW = 3'd2;  // ADC 头字节1: uw_addr
    localparam TX_ADATA = 3'd3;  // ADC 数据 128 字节

    reg [2:0] tx_state;
    reg [2:0] rr_idx;
    reg [7:0] evt_tx_cnt;  // 0..129 (2 头 + 128 数据)

    always @(posedge CLK_200M or negedge sysrst_glb_n) begin
        if (!sysrst_glb_n) begin
            tx_state   <= TX_IDLE;
            rr_idx     <= 3'd0;
            evt_tx_cnt <= 8'd0;
            tcp_wr     <= 1'b0;
            tcp_data   <= 8'd0;
            adc_rd_en  <= 8'd0;
        end else begin
            tcp_wr    <= 1'b0;
            adc_rd_en <= 8'd0;
            case (tx_state)
                TX_IDLE: begin
                    if (~adc_prog_empty[rr_idx]) begin
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
                default: tx_state <= TX_IDLE;
            endcase
        end
    end

    ila_gt_tx u_ila_gt_tx (
        .clk   (clk_txoutclk_bufg[0]),
        .probe0(gt_tx_data[15:0]),
        .probe1(gt_tx_data_valid[0])
    );

    ila_gt_rx u_ila_gt_rx (
        .clk   (clk_rxoutclk_bufg[0]),
        .probe0(gt_rx_data[15:0]),
        .probe1(gt_rx_data_valid[0]),
        .probe2(gt_link_up[0]),
        .probe3(gtx_cpll_is_lock[0]),
        .probe4(ack_cnt_main),
        .probe5(rx_sc_state[0]),
        .probe6(sc_to_sitcp_din[15:0]),
        .probe7(sc_wr_en[0])
    );

endmodule
