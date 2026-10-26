// Single-byte AiP5916 register transactions, address 0x56 (ADS high).
// Read: START AC reg RESTART AD data NACK STOP.
module i2c_register_master #(
    parameter integer CLK_HZ = 50000000,
    parameter integer I2C_HZ = 100000,
    parameter integer TIMEOUT_CYCLES = CLK_HZ / 100
) (
    input wire clk, reset_n, start, read_not_write,
    input wire [7:0] register_addr, write_data,
    output reg [7:0] read_data,
    output reg busy, done, error,
    inout wire sda, scl
);
    localparam integer DIV = CLK_HZ / (4 * I2C_HZ);
    localparam IDLE=0, START_A=1, START_B=2, START_C=3,
        TX_SET=4, TX_HIGH=5, TX_WAIT=6, TX_LOW=7,
        ACK_SET=8, ACK_HIGH=9, ACK_SAMPLE=10, ACK_LOW=11,
        REP_A=12, REP_B=13, REP_C=14, REP_D=15,
        RX_SET=16, RX_HIGH=17, RX_SAMPLE=18, RX_LOW=19,
        NACK_SET=20, NACK_HIGH=21, NACK_WAIT=22, NACK_LOW=23,
        STOP_A=24, STOP_B=25, STOP_C=26, STOP_D=27, STOP_E=28,
        START_HOLD=29, REP_WAIT=30, REP_HOLD=31;
    reg [4:0] state;
    reg [31:0] divider, timeout_count;
    reg sda_low, scl_low;
    reg [1:0] sda_sync, scl_sync;
    reg is_read;
    reg [7:0] reg_addr, wr_data, tx, rx;
    reg [2:0] bit_index;
    reg [1:0] phase;
    assign sda = sda_low ? 1'b0 : 1'bz;
    assign scl = scl_low ? 1'b0 : 1'bz;

    always @(posedge clk) begin
        if (!reset_n) begin
            sda_sync <= 2'b11;
            scl_sync <= 2'b11;
        end else begin
            sda_sync <= {sda_sync[0], sda};
            scl_sync <= {scl_sync[0], scl};
        end
    end

    always @(posedge clk) begin
        if (!reset_n) begin
            state <= IDLE;
            divider <= 0;
            timeout_count <= 0;
            sda_low <= 0;
            scl_low <= 0;
            busy <= 0;
            done <= 0;
            error <= 0;
            read_data <= 0;
            is_read <= 0;
            reg_addr <= 0;
            wr_data <= 0;
            tx <= 0;
            rx <= 0;
            bit_index <= 7;
            phase <= 0;
        end else begin
            done <= 0;
            if (!busy) begin
                divider <= 0;
                timeout_count <= 0;
                sda_low <= 0;
                scl_low <= 0;
                if (start) begin
                    busy <= 1;
                    error <= 0;
                    is_read <= read_not_write;
                    reg_addr <= register_addr;
                    wr_data <= write_data;
                    rx <= 0;
                    state <= START_A;
                end
            end else if (timeout_count == TIMEOUT_CYCLES-1) begin
                sda_low <= 0;
                scl_low <= 0;
                busy <= 0;
                done <= 1;
                error <= 1;
                state <= IDLE;
            end else begin
                timeout_count <= timeout_count + 1'b1;
                if (divider == DIV-1) begin
                    divider <= 0;
                    case (state)
                        START_A: if (scl_sync[1] && sda_sync[1]) state <= START_B;
                        START_B: begin sda_low <= 1; state <= START_HOLD; end
                        START_HOLD: state <= START_C; // >= 5 us START hold at 100 kHz
                        START_C: begin
                            scl_low <= 1;
                            tx <= 8'hAC;
                            bit_index <= 7;
                            phase <= 0;
                            state <= TX_SET;
                        end
                        TX_SET: begin sda_low <= !tx[bit_index]; state <= TX_HIGH; end
                        TX_HIGH: begin scl_low <= 0; state <= TX_WAIT; end
                        TX_WAIT: if (scl_sync[1]) state <= TX_LOW;
                        TX_LOW: begin
                            scl_low <= 1;
                            if (bit_index == 0) state <= ACK_SET;
                            else begin bit_index <= bit_index - 1'b1; state <= TX_SET; end
                        end
                        ACK_SET: begin sda_low <= 0; state <= ACK_HIGH; end
                        ACK_HIGH: begin scl_low <= 0; state <= ACK_SAMPLE; end
                        ACK_SAMPLE: if (scl_sync[1]) begin
                            if (sda_sync[1]) error <= 1;
                            state <= ACK_LOW;
                        end
                        ACK_LOW: begin
                            scl_low <= 1;
                            bit_index <= 7;
                            if (error) state <= STOP_A;
                            else case (phase)
                                0: begin tx <= reg_addr; phase <= 1; state <= TX_SET; end
                                1: if (is_read) state <= REP_A;
                                   else begin tx <= wr_data; phase <= 2; state <= TX_SET; end
                                2: state <= STOP_A;
                                3: state <= RX_SET;
                            endcase
                        end
                        REP_A: begin sda_low <= 0; state <= REP_B; end
                        REP_B: begin scl_low <= 0; state <= REP_WAIT; end
                        REP_WAIT: if (scl_sync[1]) state <= REP_C;
                        REP_C: begin sda_low <= 1; state <= REP_HOLD; end
                        REP_HOLD: state <= REP_D;
                        REP_D: begin
                            scl_low <= 1;
                            tx <= 8'hAD;
                            phase <= 3;
                            state <= TX_SET;
                        end
                        RX_SET: begin sda_low <= 0; state <= RX_HIGH; end
                        RX_HIGH: begin scl_low <= 0; state <= RX_SAMPLE; end
                        RX_SAMPLE: if (scl_sync[1]) begin
                            rx[bit_index] <= sda_sync[1];
                            state <= RX_LOW;
                        end
                        RX_LOW: begin
                            scl_low <= 1;
                            if (bit_index == 0) state <= NACK_SET;
                            else begin bit_index <= bit_index - 1'b1; state <= RX_SET; end
                        end
                        NACK_SET: begin sda_low <= 0; state <= NACK_HIGH; end
                        NACK_HIGH: begin scl_low <= 0; state <= NACK_WAIT; end
                        NACK_WAIT: if (scl_sync[1]) state <= NACK_LOW;
                        NACK_LOW: begin scl_low <= 1; state <= STOP_A; end
                        STOP_A: begin sda_low <= 1; state <= STOP_B; end
                        STOP_B: begin scl_low <= 0; state <= STOP_C; end
                        STOP_C: if (scl_sync[1]) state <= STOP_D;
                        STOP_D: begin sda_low <= 0; state <= STOP_E; end
                        STOP_E: begin
                            read_data <= rx;
                            busy <= 0;
                            done <= 1;
                            state <= IDLE;
                        end
                        default: begin
                            sda_low <= 0;
                            scl_low <= 0;
                            error <= 1;
                            busy <= 0;
                            done <= 1;
                            state <= IDLE;
                        end
                    endcase
                end else divider <= divider + 1'b1;
            end
        end
    end
endmodule
