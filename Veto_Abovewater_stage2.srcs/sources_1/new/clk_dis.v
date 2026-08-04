`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2022/08/31 11:49:34
// Design Name: 
// Module Name: clk_dis
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module rst_dis(

    input               clk_in,
    input               sysrst,


    //output              clk_6P25M,
    input               pll_locked,
    output  reg         cfg_ad9528,
    output  reg         rst_aurura,
    output              sysrst_glb_n                             

    );

    //wire    CLK_200M_GLB;

    reg     [22:0]   WAIT_CNT;
    
    // reg     clk_5mhz_buff;

	//IBUFGDS #(.IOSTANDARD ("LVDS"))		LVDS_BUF_0(.O(CLK_200M_GLB), .I(sysclk_in_p), .IB(sysclk_in_n));

    // clk_wiz_axi100M clk_wiz_axi100M_inst
    // (
    //      // Clock out ports
    //      .clk_out1(sysclk_200mhz),     
    //      .clk_out2(sysclk_100mhz), 
    //      // Status and control signals
    //      .locked(pll_locked),       // output locked
    //      // Clock in ports
    //      .clk_in1(CLK_200M_GLB)    
    // );

    // clk_wiz_sys clk_wiz_sys_inst (
    //     // Clock out ports
    //     .clk_out1(clk_6P25M),     // output clk_out1
    //     // Status and control signals
    //     .locked(pll_locked),       // output locked
    //     // Clock in ports
    //     .clk_in1(clk_in)
    // );      // input clk_in1





    // always@(posedge sysclk_200mhz) begin
    //     if(~pll_locked) begin
    //         clk_cnt <= 5'b0;
    //         clk_5mhz_buff <= 1'b0;
    //     end
    //     else if(clk_cnt>=5'd19) begin
    //         clk_cnt <= 5'b0;
    //         clk_5mhz_buff <= ~clk_5mhz_buff;
    //     end
    //     else begin
    //         clk_cnt <= clk_cnt + 1'b1;
    //         clk_5mhz_buff <= clk_5mhz_buff;
    //     end
    // end

    // BUFG BUFG_clk_5M
    // (
    //     .O (clk_5mhz),
    //     .I (clk_5mhz_buff)
    // );

    reg     [28:0]  start_rst_cnt = 0 ;
    wire            start_rst_out_buff;
    wire            sysrst_buff;

    always @(posedge clk_in) begin
        if (~pll_locked) begin
            start_rst_cnt <= 0;
        end
        else if (~start_rst_cnt[23]) begin
            start_rst_cnt <= start_rst_cnt + 1'b1;
        end
        else if (start_rst_cnt[23]) begin
            start_rst_cnt <= start_rst_cnt;
        end
    end

    assign  sysrst_glb_n    = start_rst_cnt[23];


    pulse_edg_check pulse_edg_check_inst0(
		.clk(clk_in),
		.rst_n(1'b1),
		.enable(sysrst),
		.enable_pulse(sysrst_buff)
    ); 

    pulse_edg_check pulse_edg_check_inst1(
		.clk(clk_in),
		.rst_n(1'b1),
		.enable(sysrst_glb_n),
		.enable_pulse(start_rst_out_buff)
    ); 


    // main state 
    reg     [2:0]   curr_st;
    reg     [2:0]   next_st; 

    //localparam  INIT            = 3'b110;
    localparam  IDLE            = 3'b000;
    localparam  WAIT            = 3'b001;
    localparam  CFGC            = 3'b010;
    localparam  RSTA            = 3'b011;
    localparam  DONE            = 3'b111;

    always @(posedge clk_in) begin
        if(~pll_locked) begin
            curr_st <= IDLE;
        end
        else begin
            curr_st <= next_st;
        end
    end

    always @(*) begin
        case (curr_st)
            IDLE : begin
                next_st = (sysrst_buff | start_rst_out_buff)? WAIT : IDLE;
            end
            WAIT : begin
                next_st = (WAIT_CNT == 1000000)? CFGC : WAIT;
            end
            CFGC : begin
                next_st = (WAIT_CNT == 2000000)? RSTA : CFGC;
            end
            RSTA : begin
                next_st = (WAIT_CNT == 2000200)? DONE : RSTA;
            end
            DONE : begin
                next_st = IDLE;
            end
            default : begin
                next_st = IDLE;
            end
        endcase
    end

    always @(posedge clk_in) begin

        case (next_st)
            IDLE : begin
                cfg_ad9528      <=  1'b0;
                rst_aurura      <=  1'b0;
                WAIT_CNT        <=  0;
            end
            WAIT : begin
                cfg_ad9528      <=  1'b0;
                rst_aurura      <=  1'b0;
                WAIT_CNT        <=  WAIT_CNT + 1'b1;
            end
            CFGC : begin
                cfg_ad9528      <=  1'b1;
                rst_aurura      <=  1'b0;
                WAIT_CNT        <=  WAIT_CNT + 1'b1;
            end
            RSTA : begin
                cfg_ad9528      <=  1'b0;
                rst_aurura      <=  1'b1;
                WAIT_CNT        <=  WAIT_CNT + 1'b1;
            end
            DONE : begin
                cfg_ad9528      <=  1'b0;
                rst_aurura      <=  1'b0;
                WAIT_CNT        <=  0;
            end
        endcase
    end
	
	
endmodule
