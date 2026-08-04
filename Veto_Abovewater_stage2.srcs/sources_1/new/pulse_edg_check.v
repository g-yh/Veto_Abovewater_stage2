`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2022/03/03 16:04:41
// Design Name: 
// Module Name: pulse_edg_check
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


//-----------------pulse rising edge check, generate 1 clk width pulse-----------------------//

module pulse_edg_check(
	input clk,
	input rst_n,
	input enable,
	output enable_pulse
    );
	
	reg pulse1;
	reg pulse2;
    reg pulse3;
	
	always @(posedge clk or negedge rst_n) begin
		if(!rst_n) begin
		    pulse1 <= 1'b0;
		    pulse2 <= 1'b0;
            pulse3 <= 1'b0;
		end
		else begin
			pulse1 <= enable;
			pulse2 <= pulse1;
            pulse3 <= pulse2;
		end
	end
	
	assign enable_pulse = pulse2 & ~pulse3;
	
endmodule
