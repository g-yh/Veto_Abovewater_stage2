`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2022/06/14 14:47:47
// Design Name: 
// Module Name: ad9528_spi
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


module ad9528_spi#(parameter addr_width = 15 , parameter data_width = 8)
	(
		input clk,                    			// 50MHz main clk
		input rst_n,                  			// globle reset low efficient
		input enable,							// read enable
		input RorW,                   			// write or read bit
		input [addr_width-1:0] addr,  			// address write to the register
		input [data_width-1:0] data_in, 		// date write to the register
		output reg [data_width-1:0] data_out,   // date read from the register
		output reg pullhighz,					// set the sdio to high z
		output reg r_done, 							// read done
		output reg w_done, 							// write done
		
		// standard 4-wire spi input and output
		input sdi,       // input
		output reg sdo,  // output
		output wire sclk, // serial clk
		output reg cs    // slave select
		
		//output reg clk_1mhz,
		//output wire read_enable_pulse,
		//output reg [4:0] bit_cnt
		

    );
	

	wire [addr_width+data_width:0] 	 config_data={RorW,addr,data_in};
	
	
	reg [4:0] bit_cnt;
	
	always @(posedge clk or negedge rst_n) begin
		if(!rst_n) begin
			bit_cnt <= 5'b0;
			cs <= 1'b1;
			r_done <= 1'b0;
			w_done <= 1'b0;
			sdo <= 1'b0;
		end
		else if(bit_cnt > addr_width + data_width) begin
			bit_cnt <= 5'b0;
			cs <= 1'b1;
			r_done <= 1'b1;
			w_done <= 1'b1;
			sdo <= 1'b0;
			pullhighz <= 1'b0;
		end
		else if(enable) begin
			cs <= 1'b0;
			bit_cnt <= bit_cnt + 1'b1;
			sdo <= config_data[addr_width + data_width - bit_cnt];
			//bit_cnt <= bit_cnt + 1'b1;
		end
		else if(bit_cnt > 5'b0) begin
			cs <= 1'b0;
			bit_cnt <= bit_cnt + 1'b1;
			sdo <= config_data[addr_width + data_width - bit_cnt];
			if(bit_cnt > addr_width) begin
				if(RorW) pullhighz <= 1'b1;
				else pullhighz <= 1'b0;
			end
			else pullhighz <= 1'b0;
		end
		else begin
			bit_cnt <= 5'b0;
			cs <= 1'b1;
			r_done <= 1'b0;
			w_done <= 1'b0;
			pullhighz <= 1'b0;
			sdo <= 1'b0;
		end
	end
	
	
	assign sclk = ~clk & ~cs;
	
	always@(posedge sclk) begin
		if(pullhighz) begin
			if(bit_cnt > addr_width + 1)  data_out[addr_width + data_width + 1 - bit_cnt] <= sdi;
			else data_out <= 0;
		end
		else data_out <= 0;
	end
	
endmodule
