set_property PACKAGE_PIN AG10 [get_ports SYSCLK_200MP_IN]
set_property PACKAGE_PIN AH10 [get_ports SYSCLK_200MN_IN]
set_property IOSTANDARD DIFF_SSTL15 [get_ports SYSCLK_200MP_IN]
set_property IOSTANDARD DIFF_SSTL15 [get_ports SYSCLK_200MN_IN]
create_clock -period 5.000 -name SYSCLK_200MP_IN -waveform {0.000 2.500} [get_ports SYSCLK_200MP_IN]

# VIO global reset is asynchronous by design. Each GT RX/TX clock domain has
# a local asynchronous-assert/synchronous-release reset synchronizer.
set_false_path \
    -from [get_cells -hierarchical -filter {NAME =~ *vio_0_inst*Probe_out_reg*}]

# GT status flags cross into RXOUTCLK/DRP-clock synchronizers.
set_max_delay -datapath_only 5.000 \
    -from [get_cells -hierarchical -filter {NAME =~ *rx_pma_rst_n_flag_reg* && IS_SEQUENTIAL == 1}] \
    -to [get_cells -hierarchical -filter {NAME =~ *rx_pma_rst_n_flag_meta_reg*}]

# GTXE2 RXRESETDONE is an asynchronous status output without a directly
# constraining launch register in the fabric. It enters an ASYNC_REG two-flop
# synchronizer in the 100 MHz DRP-clock domain.
set_false_path \
    -to [get_cells -hierarchical -filter {NAME =~ *rx_reset_done_meta_reg*}]

# Bound the first stage of the quasi-static ADC board-address synchronizer.
# The source data is held constant for a complete 64-word ADC event.
set_max_delay -datapath_only 5.000 \
    -from [get_cells -hierarchical -filter {NAME =~ *uw_addr_reg_reg*}] \
    -to [get_cells -hierarchical -filter {NAME =~ *uw_addr_meta_reg*}]

# Vendor-provided constraints from the original aurora_to_sitcp project.
# They constrain the intentional 200 MHz <-> GMII 125 MHz resampling paths.
set SiPDMIN [expr [get_property -min PERIOD [get_clocks -of_objects [get_pins -hier -filter {name =~ */GMII/*}]]] - 1.5]

set_max_delay $SiPDMIN -datapath_only -from [get_pins -hier -filter {name =~ */GMII_RXBUF/cmpWrAddr*/C}] -to [get_pins -hier -filter {name =~ */GMII_RXBUF/smpWrStatusAddr*/D}]
set_max_delay $SiPDMIN -datapath_only -from [get_pins -hier -filter {name =~ */GMII_TXBUF/orRdAct*/C}] -to [get_pins -hier -filter {name =~ */GMII_TXBUF/irRdAct*/D}]
set_max_delay $SiPDMIN -datapath_only -from [get_pins -hier -filter {name =~ */GMII_TXBUF/muxEndTgl*/C}] -to [get_pins -hier -filter {name =~ */GMII_TXBUF/rsmpMuxTrnsEnd*/D}]

set_max_delay $SiPDMIN -datapath_only -from [get_pins -hier -filter {name =~ */SiTCP_INT_REG/regX10Data*/C}] -to [get_pins -hier -filter {name =~ */GMII_RXCNT/irMacFlowEnb*/D}]
set_max_delay $SiPDMIN -datapath_only -from [get_pins -hier -filter {name =~ */SiTCP_INT_REG/regX12Data*/C}] -to [get_pins -hier -filter {name =~ */GMII_RXCNT/muxMyMac*/D}]
set_max_delay $SiPDMIN -datapath_only -from [get_pins -hier -filter {name =~ */SiTCP_INT_REG/regX13Data*/C}] -to [get_pins -hier -filter {name =~ */GMII_RXCNT/muxMyMac*/D}]
set_max_delay $SiPDMIN -datapath_only -from [get_pins -hier -filter {name =~ */SiTCP_INT_REG/regX14Data*/C}] -to [get_pins -hier -filter {name =~ */GMII_RXCNT/muxMyMac*/D}]
set_max_delay $SiPDMIN -datapath_only -from [get_pins -hier -filter {name =~ */SiTCP_INT_REG/regX15Data*/C}] -to [get_pins -hier -filter {name =~ */GMII_RXCNT/muxMyMac*/D}]
set_max_delay $SiPDMIN -datapath_only -from [get_pins -hier -filter {name =~ */SiTCP_INT_REG/regX16Data*/C}] -to [get_pins -hier -filter {name =~ */GMII_RXCNT/muxMyMac*/D}]
set_max_delay $SiPDMIN -datapath_only -from [get_pins -hier -filter {name =~ */SiTCP_INT_REG/regX17Data*/C}] -to [get_pins -hier -filter {name =~ */GMII_RXCNT/muxMyMac*/D}]
set_max_delay $SiPDMIN -datapath_only -from [get_pins -hier -filter {name =~ */SiTCP_INT_REG/regX18Data*/C}] -to [get_pins -hier -filter {name =~ */GMII_RXCNT/muxMyIp*/D}]
set_max_delay $SiPDMIN -datapath_only -from [get_pins -hier -filter {name =~ */SiTCP_INT_REG/regX19Data*/C}] -to [get_pins -hier -filter {name =~ */GMII_RXCNT/muxMyIp*/D}]
set_max_delay $SiPDMIN -datapath_only -from [get_pins -hier -filter {name =~ */SiTCP_INT_REG/regX1AData*/C}] -to [get_pins -hier -filter {name =~ */GMII_RXCNT/muxMyIp*/D}]
set_max_delay $SiPDMIN -datapath_only -from [get_pins -hier -filter {name =~ */SiTCP_INT_REG/regX1BData*/C}] -to [get_pins -hier -filter {name =~ */GMII_RXCNT/muxMyIp*/D}]

set_max_delay $SiPDMIN -datapath_only -from [get_pins -hier -filter {name =~ */GMII_TXBUF/dlyBank0LastWrAddr*/C}] -to [get_pins -hier -filter {name =~ */GMII_TXBUF/rsmpBank0LastWrAddr*/D}]
set_max_delay $SiPDMIN -datapath_only -from [get_pins -hier -filter {name =~ */GMII_TXBUF/dlyBank1LastWrAddr*/C}] -to [get_pins -hier -filter {name =~ */GMII_TXBUF/rsmpBank1LastWrAddr*/D}]
set_max_delay $SiPDMIN -datapath_only -from [get_pins -hier -filter {name =~ */GMII_TXBUF/memRdReq*/C}] -to [get_pins -hier -filter {name =~ */GMII_TXBUF/irMemRdReq*/D}]

set_max_delay $SiPDMIN -datapath_only -from [get_pins -hier -filter {name =~ */GMII_RXCNT/orMacTim*/C}] -to [get_pins -hier -filter {name =~ */GMII_TXCNT/irMacPauseTime*/D}]
set_max_delay $SiPDMIN -datapath_only -from [get_pins -hier -filter {name =~ */GMII_RXCNT/orMacPause*/C}] -to [get_pins -hier -filter {name =~ */GMII_TXCNT/irMacPauseExe*/D}]

set_false_path -from [get_pins -hier -filter {name =~ */SiTCP_INT/SiTCP_RESET_OUT*/C}]

set_property PACKAGE_PIN G8 [get_ports gt_refclk2_p]
set_property PACKAGE_PIN G7 [get_ports gt_refclk2_n]
create_clock -period 8.000 -name gt_refclk2_p [get_ports gt_refclk2_p]

set_property PACKAGE_PIN U8 [get_ports gt_refclk4_p]
set_property PACKAGE_PIN U7 [get_ports gt_refclk4_n]
create_clock -period 8.000 -name gt_refclk4_p [get_ports gt_refclk4_p]


set_property PACKAGE_PIN L4     [get_ports FE_SFP_TX_P[0]]
set_property PACKAGE_PIN L3     [get_ports FE_SFP_TX_N[0]]
set_property PACKAGE_PIN P2     [get_ports FE_SFP_TX_P[1]]
set_property PACKAGE_PIN P1     [get_ports FE_SFP_TX_N[1]]
set_property PACKAGE_PIN N4     [get_ports FE_SFP_TX_P[2]]
set_property PACKAGE_PIN N3     [get_ports FE_SFP_TX_N[2]]
set_property PACKAGE_PIN M2     [get_ports FE_SFP_TX_P[3]]
set_property PACKAGE_PIN M1     [get_ports FE_SFP_TX_N[3]]
set_property PACKAGE_PIN D2     [get_ports FE_SFP_TX_P[4]]
set_property PACKAGE_PIN D1     [get_ports FE_SFP_TX_N[4]]
set_property PACKAGE_PIN B2     [get_ports FE_SFP_TX_P[5]]
set_property PACKAGE_PIN B1     [get_ports FE_SFP_TX_N[5]]
set_property PACKAGE_PIN C4     [get_ports FE_SFP_TX_P[6]]
set_property PACKAGE_PIN C3     [get_ports FE_SFP_TX_N[6]]
set_property PACKAGE_PIN A4     [get_ports FE_SFP_TX_P[7]]
set_property PACKAGE_PIN A3     [get_ports FE_SFP_TX_N[7]]

set_property PACKAGE_PIN M6     [get_ports FE_SFP_RX_P[0]]
set_property PACKAGE_PIN M5     [get_ports FE_SFP_RX_N[0]]
set_property PACKAGE_PIN T6     [get_ports FE_SFP_RX_P[1]]
set_property PACKAGE_PIN T5     [get_ports FE_SFP_RX_N[1]]
set_property PACKAGE_PIN R4     [get_ports FE_SFP_RX_P[2]]
set_property PACKAGE_PIN R3     [get_ports FE_SFP_RX_N[2]]
set_property PACKAGE_PIN P6     [get_ports FE_SFP_RX_P[3]]
set_property PACKAGE_PIN P5     [get_ports FE_SFP_RX_N[3]]
set_property PACKAGE_PIN E4     [get_ports FE_SFP_RX_P[4]]
set_property PACKAGE_PIN E3     [get_ports FE_SFP_RX_N[4]]
set_property PACKAGE_PIN B6     [get_ports FE_SFP_RX_P[5]]
set_property PACKAGE_PIN B5     [get_ports FE_SFP_RX_N[5]]
set_property PACKAGE_PIN D6     [get_ports FE_SFP_RX_P[6]]
set_property PACKAGE_PIN D5     [get_ports FE_SFP_RX_N[6]]
set_property PACKAGE_PIN A8     [get_ports FE_SFP_RX_P[7]]
set_property PACKAGE_PIN A7     [get_ports FE_SFP_RX_N[7]]


set_property PACKAGE_PIN Y2    [get_ports BE_SFP_TX_P]
set_property PACKAGE_PIN Y1    [get_ports BE_SFP_TX_N]

set_property PACKAGE_PIN AA4    [get_ports BE_SFP_RX_P]
set_property PACKAGE_PIN AA3    [get_ports BE_SFP_RX_N]

set_property PACKAGE_PIN R29 [get_ports SFP_TX_DISABLE]
set_property IOSTANDARD LVCMOS33 [get_ports SFP_TX_DISABLE]


set_property IOSTANDARD LVCMOS33 [get_ports cs_ad9528]
set_property PACKAGE_PIN R30 [get_ports cs_ad9528]
set_property IOSTANDARD LVCMOS33 [get_ports sclk_ad9528]
set_property PACKAGE_PIN P26 [get_ports sclk_ad9528]
set_property IOSTANDARD LVCMOS33 [get_ports sdio_ad9528]
set_property PACKAGE_PIN T30 [get_ports sdio_ad9528]
set_property IOSTANDARD LVCMOS33 [get_ports ad9528_rst_n]
set_property PACKAGE_PIN U20 [get_ports ad9528_rst_n]
set_property IOSTANDARD LVCMOS33 [get_ports ad9528_sysref_req]
set_property PACKAGE_PIN R26 [get_ports ad9528_sysref_req]

set_property IOSTANDARD LVCMOS33 [get_ports FAN_PWM]
set_property PACKAGE_PIN V24 [get_ports FAN_PWM]

set_property IOSTANDARD LVCMOS33 [get_ports gt_link_up_led1]
set_property PACKAGE_PIN U22 [get_ports gt_link_up_led1]

set_property IOSTANDARD LVCMOS33 [get_ports sitcp_led2]
set_property PACKAGE_PIN U23 [get_ports sitcp_led2]
