`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2022/07/06 19:38:21
// Design Name: 
// Module Name: spi_top
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


module spi_top(

        input  wire         clk,
        input  wire         rst_n,
        
        inout               sdio_ad9528,
        output              cs_ad9528,
        output              sclk_ad9528,
        
        input  wire         cfg_ad9528,
        
        output wire [1:0]   cfg_state_ad9528
    );

    wire        pullhighz_ad9528;
    wire        sdi_ad9528;
    wire        sdo_ad9528;
    wire [23:0] read_data_all_ad9528;

    ad9528_spi_top ad9528_spi_top_inst
    (
        .clk(clk),
        .cfg_start(cfg_ad9528),
        .rst_n(rst_n),
        .RorW(1'b0),
        .sdi(sdi_ad9528),
        .sdo(sdo_ad9528),
        .sclk(sclk_ad9528),
        .cs(cs_ad9528),
        .pullhighz(pullhighz_ad9528),
        .cfg_state(cfg_state_ad9528),
        .read_data_all(read_data_all_ad9528)
    );

    assign sdio_ad9528 = pullhighz_ad9528? 1'bz : sdo_ad9528;
    assign sdi_ad9528  = pullhighz_ad9528? sdio_ad9528 : 1'b0;

endmodule
