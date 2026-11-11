# Implementation-only CDC clock groups. GT output clocks do not exist during
# synthesis, so this file must not be used by the synthesis run.
set_clock_groups -asynchronous \
    -group [get_clocks {SYSCLK_200MP_IN clk_out1_clk_wiz_aurora}] \
    -group [get_clocks -regexp {.*(RXOUTCLK|TXOUTCLK).*}]
