`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: rbcp_read_slave
// Description: RBCP read slave for slow-control UDP return.
//   Host first sends all command words as RBCP writes (existing write slave),
//   then, while waiting for the result, sends one "collect" read packet:
//     RBCP_ADDR[7:0]   (1~8) : GT channel select (stage1 board)
//   On RBCP_RE, this module pops one byte from fifo_sc_tx[ch] and answers
//   with a delayed ACK (RBCP_RD = byte, RBCP_ACK = 2 clocks).  SiTCP turns
//   that into a UDP reply to the host.  If the response word has not arrived
//   yet, the module simply stalls (delayed ACK) until fifo_sc_tx has data.
//
//   Each slow-control response word is 16-bit and occupies TWO bytes in the
//   16-in/8-out fifo_sc_tx (low byte first), so the host must send 2 collects
//   per word to keep the FIFO aligned.
//
//   RBCP timing: delayed ACK, RBCP_RD held with RBCP_ACK for 2 clocks.
//   All logic in CLK_200M domain (same as fifo_sc_tx read side).
//////////////////////////////////////////////////////////////////////////////////

module rbcp_read_slave (
    input  wire         CLK_200M,
    input  wire         rst_n,

    // RBCP bus (200MHz)
    input  wire         RBCP_RE,
    input  wire [31:0]  RBCP_ADDR,
    output reg  [7:0]   RBCP_RD,
    output reg          RBCP_ACK,

    // fifo_sc_tx read interface (CLK_200M)
    input  wire [127:0] sc_dout,       // packed [ch*8 +: 8]
    input  wire [7:0]   sc_valid,
    input  wire [7:0]   sc_rd_rst_busy,
    output reg  [7:0]   sc_rd_en
);

    localparam RD_IDLE = 2'd0;
    localparam RD_WAIT = 2'd1;
    localparam RD_ACK  = 2'd2;

    reg  [1:0] state;
    reg  [2:0] ch;
    reg  [7:0] data_reg;
    reg  [1:0] ack_cnt;
    reg        re_ff;

    wire [7:0] ch_addr  = RBCP_ADDR[7:0];
    wire       ch_valid = (ch_addr >= 8'd1) && (ch_addr <= 8'd8);
    wire [7:0] ch_sel   = ch_addr - 8'd1;
    wire       re_pedge = RBCP_RE && !re_ff;

    always @(posedge CLK_200M or negedge rst_n) begin
        if (!rst_n) begin
            re_ff     <= 1'b0;
            state     <= RD_IDLE;
            ch        <= 3'd0;
            data_reg  <= 8'h0;
            ack_cnt   <= 2'd0;
            RBCP_RD   <= 8'h0;
            RBCP_ACK  <= 1'b0;
            sc_rd_en  <= 8'h0;
        end else begin
            re_ff     <= RBCP_RE;
            sc_rd_en  <= 8'h0;
            RBCP_ACK  <= 1'b0;
            case (state)
                RD_IDLE: begin
                    if (re_pedge) begin
                        if (ch_valid) begin
                            ch    <= ch_sel[2:0];
                            state <= RD_WAIT;
                        end else begin
                            data_reg <= 8'h00;   // invalid channel: reply 0, no stall
                            state    <= RD_ACK;
                        end
                    end
                end
                RD_WAIT: begin
                    // data arrived => capture head byte and pop it this cycle
                    if (sc_valid[ch] && !sc_rd_rst_busy[ch]) begin
                        data_reg <= sc_dout[ch*8 +: 8];
                        sc_rd_en  <= (8'd1 << ch);
                        state    <= RD_ACK;
                    end
                end
                RD_ACK: begin
                    // delayed ACK: hold RBCP_RD with RBCP_ACK for 2 clocks
                    RBCP_RD  <= data_reg;
                    RBCP_ACK <= 1'b1;
                    if (ack_cnt == 2'd1) begin
                        ack_cnt <= 2'd0;
                        state   <= RD_IDLE;
                    end else begin
                        ack_cnt <= ack_cnt + 2'd1;
                    end
                end
                default: state <= RD_IDLE;
            endcase
        end
    end

endmodule