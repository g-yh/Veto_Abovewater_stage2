`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2022/07/14 13:53:50
// Design Name: 
// Module Name: ad9528_spi_top
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


module ad9528_spi_top(
        
        input           clk,
        
        input           cfg_start,
        input           rst_n,
        input           RorW,
        
        input           sdi,
        output          sdo,
        output          sclk,
        output          cs,
        output          pullhighz,
        
        output  [1:0]   cfg_state,
        
        output  [23:0]  read_data_all
    );
    
    reg [14:0]  addr;
    reg [7:0]   data_in;
    wire[7:0]   data_out;
    wire        enable_pulse;
    wire        W_done;
    //wire        RorW;
    
	ad9528_spi#(.addr_width(15), .data_width(8)) ad9528_spi_inst
	(
		.clk(clk),                    	// in  : clk
		.rst_n(rst_n),                // in  :globle reset low efficient
		.enable(enable_pulse),			// in  :read enable
		.RorW(RorW),                 // in  : 1'b0 for write 
		.addr(addr),  	            // in  :address write to the register
		.data_in(data_in), 		    // in  :date write to the register
		.data_out(data_out),   	             // out :date read from the register
		.pullhighz(pullhighz),		// out :set the sdio to high z
		.r_done(), 			        // out :read done
		.w_done(W_done), 			// out :write done
		
		// standard 4-wire spi input and output
		.sdi(sdi),             // in  :input
		.sdo(sdo),  	       // out :output
		.sclk(sclk), 	       // out :serial clk
		.cs(cs)    	          // out :slave select
		
    );    
    
    wire cfg_start_pulse;
	pulse_edg_check pulse_edg_check_inst_1(
		.clk(clk),
		.rst_n(rst_n),
		.enable(cfg_start),
		.enable_pulse(cfg_start_pulse)
    );    
    
    reg     enable;
	pulse_edg_check pulse_edg_check_inst_2(
		.clk(clk),
		.rst_n(rst_n),
		.enable(enable),
		.enable_pulse(enable_pulse)
    );
     
    parameter n_addr= 48;
    wire [22:0] spi_addr_data[n_addr-1:0];
    assign spi_addr_data[0 ]  = 23'h0500_14;     //  PLL1 power down 
    assign spi_addr_data[1 ]  = 23'h0204_04;     //  PLL2 vco divider M1 = 4;
    assign spi_addr_data[2 ]  = 23'h0201_14;     //  PLL2 vco cal feedback divider (4*B)+A = (4*20)+0 = 80
    assign spi_addr_data[3 ]  = 23'h0108_01;     //  PLL1 VCXO differential receiver enable
    assign spi_addr_data[4 ]  = 23'h0208_13;     //  PLL2 feedback divider N2 = 20;
    assign spi_addr_data[5 ]  = 23'h0205_07;     //  PLL2 loop filter Cpole1 = 48pF
    assign spi_addr_data[6 ]  = 23'h0501_00;     //  output channel power down  
    assign spi_addr_data[7 ]  = 23'h0502_00;     //  output channel power down
    assign spi_addr_data[8 ]  = 23'h0402_C0;     //  sysref control
    assign spi_addr_data[9 ]  = 23'h0403_82;     //  sysref control N-shot mode : 1 pulse
    //assign spi_addr_data[9 ]  = 23'h0403_90;     //  sysref control continuous mode
    assign spi_addr_data[10]  = 23'h0400_08;     //  sysref K divider

    assign spi_addr_data[11]  = 23'h0300_00;     //  channel 0 output setup
    assign spi_addr_data[12]  = 23'h0302_07;     //  channel 0 output divider

    assign spi_addr_data[13]  = 23'h0303_00;     //  channel 1 output setup
    assign spi_addr_data[14]  = 23'h0305_07;     //  channel 1 output divider

    assign spi_addr_data[15]  = 23'h0306_00;     //  channel 2 output setup
    assign spi_addr_data[16]  = 23'h0308_07;     //  channel 2 output divider

    assign spi_addr_data[17]  = 23'h0309_00;     //  channel 3 output setup
    assign spi_addr_data[18]  = 23'h030B_07;     //  channel 3 output divider

    assign spi_addr_data[19]  = 23'h030C_40;     //  channel 4 output setup : sysref
    assign spi_addr_data[20]  = 23'h030E_00;     //  channel 4 output divider

    assign spi_addr_data[21]  = 23'h030F_00;     //  channel 5 output setup
    assign spi_addr_data[22]  = 23'h0311_03;     //  channel 5 output divider

    assign spi_addr_data[23]  = 23'h0312_00;     //  channel 6 output setup
    assign spi_addr_data[24]  = 23'h0314_00;     //  channel 6 output divider

    assign spi_addr_data[25]  = 23'h0315_40;     //  channel 7 output setup : sysref
    assign spi_addr_data[26]  = 23'h0317_00;     //  channel 7 output divider

    assign spi_addr_data[27]  = 23'h0318_00;     //  channel 8 output setup
    assign spi_addr_data[28]  = 23'h031A_00;     //  channel 8 output divider

    assign spi_addr_data[29]  = 23'h031B_40;     //  channel 9 output setup : sysref
    assign spi_addr_data[30]  = 23'h031D_00;     //  channel 9 output divider

    assign spi_addr_data[31]  = 23'h031E_00;     //  channel 10 output setup
    assign spi_addr_data[32]  = 23'h0320_00;     //  channel 10 output divider

    assign spi_addr_data[33]  = 23'h0321_40;     //  channel 11 output setup : sysref
    assign spi_addr_data[34]  = 23'h0323_00;     //  channel 11 output divider

    assign spi_addr_data[35]  = 23'h0324_00;     //  channel 12 output setup
    assign spi_addr_data[36]  = 23'h0326_00;     //  channel 12 output divider

    assign spi_addr_data[37]  = 23'h0327_40;     //  channel 13 output setup : sysref
    assign spi_addr_data[38]  = 23'h0329_00;     //  channel 13 output divider

    assign spi_addr_data[39]  = 23'h0301_00;     //  channel 0 Coarse digital delay
    assign spi_addr_data[40]  = 23'h0304_00;     //  channel 1 Coarse digital delay

    
    assign spi_addr_data[41]  = 23'h0508_00;     //  status of pll1 and pll2
    assign spi_addr_data[42]  = 23'h0200_E5;     //  PLL2 charge pump 805uA  
    assign spi_addr_data[43]  = 23'h000F_01;     //  update the reg_value from buffer to reg

    assign spi_addr_data[44]  = 23'h0203_00;     //  Manual VCO calibrate
    assign spi_addr_data[45]  = 23'h000F_01;     //  update the reg_value from buffer to reg
    assign spi_addr_data[46]  = 23'h0203_01;     //  Manual VCO calibrate
    assign spi_addr_data[47]  = 23'h000F_01;     //  update the reg_value from buffer to reg
    //assign spi_addr_data[24]  = 23'h032A_00;
    //assign spi_addr_data[24]  = 23'h000F_01;     //  update the reg_value from buffer to reg
    //assign spi_addr_data[25]  = 23'h010036;
    //assign spi_addr_data[26]  = 23'h01025C;
    //assign spi_addr_data[27]  = 23'h01047B;
    //assign spi_addr_data[28]  = 23'h000F01;
    //assign spi_addr_data[29]  = 23'h000F01;
    
    reg [7:0] read_data[n_addr-1:0];
    
    assign read_data_all = {read_data[1],read_data[2],read_data[39]};
    //vio_1 vio_1_inst (
    //  .clk(clk),                // input wire clk
    //  .probe_in0(read_data[0]),    // input wire [7 : 0] probe_in0
    //  .probe_in1(read_data[1]),    // input wire [7 : 0] probe_in1
    //  .probe_in2(read_data[2]),    // input wire [7 : 0] probe_in2
    //  .probe_in3(read_data[3]),    // input wire [7 : 0] probe_in3
    //  .probe_out0(RorW)  // output wire [0 : 0] probe_out0
    //);

        
    localparam  INIT = 2'b00;
    localparam  CONF = 2'b01;
    localparam  WAIT = 2'b10;
    localparam  DONE = 2'b11;
    
    reg  [1:0]   curr_st;
    reg  [1:0]   next_st;
    reg  [5:0]   addr_cnt;
    
    assign cfg_state = curr_st;
    
    always@(posedge clk or negedge rst_n) begin
        if(~rst_n) begin
            curr_st <= INIT;
        end
        else begin
            curr_st <= next_st;
        end
    end
        
    always@(*) begin
        case(curr_st)
            INIT : begin
                if(cfg_start_pulse) begin
                    next_st = CONF;
                end
                else begin
                    next_st = INIT;
                end
            end
            CONF : begin
                next_st = WAIT;
            end
            WAIT : begin
                if(W_done) begin
                    if(addr_cnt>=n_addr) begin
                        next_st = DONE;
                    end
                    else begin
                        next_st = CONF;
                    end
                end
                else begin
                    next_st = WAIT;
                end
            end
            DONE : begin
                next_st = INIT;
            end
            default : begin
                next_st = INIT;
            end
        endcase
    end
    
    always@(posedge clk) begin
        case(curr_st)
            INIT : begin
                addr     <= 15'h0;
                data_in  <= 8'h0;
                enable   <= 1'b0;
                addr_cnt <= 6'b0;
            end
            CONF : begin
                addr     <= spi_addr_data[addr_cnt][22:8];
                data_in  <= spi_addr_data[addr_cnt][7:0];
                read_data[addr_cnt][7:0] <= data_out;
                enable   <= 1'b1;
                addr_cnt <= addr_cnt + 1'b1;
            end
            WAIT : begin
                addr     <= addr;
                data_in  <= data_in;
                enable   <= 1'b0;
                addr_cnt <= addr_cnt;
            end
            DONE : begin
                addr     <= 15'h0;
                data_in  <= 8'h0;
                enable   <= 1'b0;
                addr_cnt <= 6'b0;
            end
            default : begin
                addr     <= 15'h0;
                data_in  <= 8'h0;
                enable   <= 1'b0;
                addr_cnt <= 6'b0;
            end
        endcase
    end
    
    
endmodule
