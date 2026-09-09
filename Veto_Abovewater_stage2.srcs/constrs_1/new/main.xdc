set_property PACKAGE_PIN AG10 [get_ports SYSCLK_200MP_IN]
set_property PACKAGE_PIN AH10 [get_ports SYSCLK_200MN_IN]
set_property IOSTANDARD DIFF_SSTL15 [get_ports SYSCLK_200MP_IN]
set_property IOSTANDARD DIFF_SSTL15 [get_ports SYSCLK_200MN_IN]
create_clock -period 5.000 -name SYSCLK_200MP_IN -waveform {0.000 2.500} [get_ports SYSCLK_200MP_IN]

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

# uw_addr per-channel byte crosses rxoutclk(125M) -> CLK_200M; 2-FF sync in main.v
set_false_path -from [get_cells uw_addr_reg_reg[*]] -to [get_cells uw_addr_sync1_reg[*]]