`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2022/08/25 13:36:58
// Design Name: 
// Module Name: sitcp_top
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

module sitcp_top(

        input               CLK_200M        ,
        input               SYS_RST         ,
        output              SiTCP_RST_out   ,
        // GT REFCLK
		input   			SGMII_CLK_P		,
		input   			SGMII_CLK_N		,
		// SFP 
		output  			TX_DISABLE		,
		output  			SFP_TXP			,	// out	: Tx signal line
		output  			SFP_TXN			,	// out	: 
		input   			SFP_RXP			,	// in	: Rx signal line
		input   			SFP_RXN			,	// in	: 
        // TCP IO
	    output			    TCP_OPEN_ACK	,
	    input	[15:0]	    TCP_RX_WC		,
	    output			    TCP_RX_WR		,
	    output	[7:0]	    TCP_RX_DATA		,
	    output			    TCP_TX_FULL		,
	    input			    TCP_TX_WR		,
	    input	[7:0]	    TCP_TX_DATA		,
        // RBCP IO
	    output			    RBCP_ACT		,
	    output	[31:0]	    RBCP_ADDR		,
	    output	[7:0]	    RBCP_WD			,
	    output			    RBCP_WE			,
	    output			    RBCP_RE			,
	    input			    RBCP_ACK		,
	    input	[7:0]	    RBCP_RD			

    );

	wire			SGMII_CLK;		// in : Tx clock
	wire			GMII_TX_EN;		// out: Tx enable
	wire	[ 7:0]	GMII_TXD;		// out: Tx data[7:0]
	wire			GMII_TX_ER;		// out: TX error
	wire			GMII_RX_DV;		// in : Rx data valid
	wire	[ 7:0]	GMII_RXD;		// in : Rx data[7:0]
	wire			GMII_RX_ER;		// in : Rx error
	wire	[15:0]	STATUS_VECTOR;	// out: Core status.[15:0]
	wire			TCP_CLOSE_REQ;

	WRAP_SiTCP_GMII_XC7K_32K	#(
		.TIM_PERIOD			(8'd200)			// = System clock frequency(MHz), integer only
	)
	SiTCP	(
		.CLK				(CLK_200M),			// in	: System Clock (MII: >15MHz, GMII>129MHz)
		.RST				(SYS_RST),		    // in	: System reset
	// Configuration parameters
		.FORCE_DEFAULTn		(1'b0),	            // in	: Load default parameters
		.EXT_IP_ADDR		(32'h0000_0000),	// in	: IP address[31:0]
		.EXT_TCP_PORT		(16'h0000),			// in	: TCP port #[15:0]
		.EXT_RBCP_PORT		(16'h0000),			// in	: RBCP port #[15:0]
		.PHY_ADDR			(5'b0_0111),		// in	: PHY-device MIF address[4:0]
	// EEPROM
		.EEPROM_CS			(	),		        // out	: Chip select
		.EEPROM_SK			(	),		        // out	: Serial data clock
		.EEPROM_DI			(	),		        // out	: Serial write data
		.EEPROM_DO			(	),		        // in	: Serial read data
	// user data, intialial values are stored in the EEPROM, 0xFFFF_FC3C-3F
		.USR_REG_X3C		(),					// out	: Stored at 0xFFFF_FF3C
		.USR_REG_X3D		(),					// out	: Stored at 0xFFFF_FF3D
		.USR_REG_X3E		(),					// out	: Stored at 0xFFFF_FF3E
		.USR_REG_X3F		(),					// out	: Stored at 0xFFFF_FF3F
	// MII interface
		.GMII_RSTn			(),		// out	: PHY reset
		.GMII_1000M			(1'b1),				// in	: GMII mode (0:MII, 1:GMII)
		// TX
		.GMII_TX_CLK		(SGMII_CLK),		// in	: Tx clock
		.GMII_TX_EN			(GMII_TX_EN),		// out	: Tx enable
		.GMII_TXD			(GMII_TXD[7:0]),	// out	: Tx data[7:0]
		.GMII_TX_ER			(GMII_TX_ER),		// out	: TX error
		// RX
		.GMII_RX_CLK		(SGMII_CLK),		// in	: Rx clock
		.GMII_RX_DV			(GMII_RX_DV),		// in	: Rx data valid
		.GMII_RXD			(GMII_RXD[7:0]),	// in	: Rx data[7:0]
		.GMII_RX_ER			(GMII_RX_ER),		// in	: Rx error
		.GMII_CRS			(1'b0),				// in	: Carrier sense
		.GMII_COL			(1'b0),				// in	: Collision detected
		// Management IF
		.GMII_MDC			(),					// out	: Clock for MDIO
		.GMII_MDIO_IN		(1'b1),				// in	: Data
		.GMII_MDIO_OUT		(),					// out	: Data
		.GMII_MDIO_OE		(),					// out	: MDIO output enable
	// User I/F
		.SiTCP_RST			(SiTCP_RST_out),		// out	: Reset for SiTCP and related circuits
		// TCP connection control
		.TCP_OPEN_REQ		(1'b0),				// in	: Reserved input, shoud be 0
		.TCP_OPEN_ACK		(TCP_OPEN_ACK),		// out	: Acknowledge for open (=Socket busy)
		.TCP_ERROR			(),					// out	: TCP error, its active period is equal to MSL
		.TCP_CLOSE_REQ		(TCP_CLOSE_REQ),	// out	: Connection close request
		.TCP_CLOSE_ACK		(TCP_CLOSE_REQ),	// in	: Acknowledge for closing
		// FIFO I/F
		.TCP_RX_WC			(TCP_RX_WC),	    // in	: Rx FIFO write count[15:0] (Unused bits should be set 1)
		.TCP_RX_WR			(TCP_RX_WR),		// out	: Write enable
		.TCP_RX_DATA		(TCP_RX_DATA),	    // out	: Write data[7:0]
		.TCP_TX_FULL		(TCP_TX_FULL),		// out	: Almost full flag
		.TCP_TX_WR			(TCP_TX_WR),	    // in	: Write enable
		.TCP_TX_DATA		(TCP_TX_DATA),	    // in	: Write data[7:0]
	// RBCP
		.RBCP_ACT			(RBCP_ACT),			// out	: RBCP active
		.RBCP_ADDR			(RBCP_ADDR[31:0]),	// out	: Address[31:0]
		.RBCP_WD			(RBCP_WD[7:0]),		// out	: Data[7:0]
		.RBCP_WE			(RBCP_WE),			// out	: Write enable
		.RBCP_RE			(RBCP_RE),			// out	: Read enable
		.RBCP_ACK			(RBCP_ACK),			// in	: Access acknowledge
		.RBCP_RD			(RBCP_RD[7:0])		// in	: Read data[7:0]
	);

    gig_ethernet_pcs_pma_inco gig_ethernet_pcs_pma_inco_inst (
        .gtrefclk_p(SGMII_CLK_P),                   // input wire gtrefclk_p
        .gtrefclk_n(SGMII_CLK_N),                   // input wire gtrefclk_n
        .gtrefclk_out(),                            // output wire gtrefclk_out
        .gtrefclk_bufg_out(),                       // output wire gtrefclk_bufg_out
        .txn(SFP_TXN),                              // output wire txn
        .txp(SFP_TXP),                              // output wire txp
        .rxn(SFP_RXN),                              // input wire rxn
        .rxp(SFP_RXP),                              // input wire rxp
        .independent_clock_bufg(CLK_200M),          // input wire independent_clock_bufg
        .userclk_out(),                             // output wire userclk_out
        .userclk2_out(SGMII_CLK),                   // output wire userclk2_out
        .rxuserclk_out(),                           // output wire rxuserclk_out
        .rxuserclk2_out(),                          // output wire rxuserclk2_out
        .resetdone(),                               // output wire resetdone
        .pma_reset_out(),                           // output wire pma_reset_out
        .mmcm_locked_out(),                         // output wire mmcm_locked_out
        .gmii_txd(GMII_TXD),                        // input wire [7 : 0] gmii_txd
        .gmii_tx_en(GMII_TX_EN),                    // input wire gmii_tx_en
        .gmii_tx_er(GMII_TX_ER),                    // input wire gmii_tx_er
        .gmii_rxd(GMII_RXD),                        // output wire [7 : 0] gmii_rxd
        .gmii_rx_dv(GMII_RX_DV),                    // output wire gmii_rx_dv
        .gmii_rx_er(GMII_RX_ER),                    // output wire gmii_rx_er
        .gmii_isolate(),                            // output wire gmii_isolate
        .configuration_vector(5'b0_0000),           // input wire [4 : 0] configuration_vector
        .status_vector(STATUS_VECTOR),              // output wire [15 : 0] status_vector
        .reset(SYS_RST),                          // input wire reset
        .signal_detect(1'b1),                       // input wire signal_detect
        .gt0_qplloutclk_out(),                      // output wire gt0_qplloutclk_out
        .gt0_qplloutrefclk_out()                    // output wire gt0_qplloutrefclk_out
    );

    assign  TX_DISABLE = 1'b0;

endmodule
