// AiP5916: configure once, then indicate any pressed touch key using INT.
// All logic runs on clk; SCL is an open-drain GPIO, never an internal clock.
module touch_led_top #(
    parameter integer CLK_HZ = 50000000,
    parameter integer I2C_HZ = 100000,
    parameter integer POWERUP_CYCLES = CLK_HZ / 50,
    parameter integer FILTER_CYCLES = CLK_HZ / 1000
) (
    input  wire clk,
    input  wire rst_n,          // Dock USER_BUTTON0, active low
    inout  wire touch_sda,
    inout  wire touch_scl,
    input  wire touch_int_n,
    output wire led_n           // Dock LED1 at R26: 0 = on
);
    reg [15:0] por_count = 16'd0;
    always @(posedge clk)
        if (!rst_n) por_count <= 16'd0;
        else if (!(&por_count)) por_count <= por_count + 1'b1;
    wire reset_n = rst_n && (&por_count);

    localparam WAIT_POWER=0, WRITE_START=1, WRITE_WAIT=2,
               READ_START=3, READ_WAIT=4, MONITOR=5, FAILED=6;
    reg [2:0] state;
    reg [31:0] wait_count;
    reg [4:0] config_index;
    reg init_ok;
    reg init_error;
    reg start;
    reg read_not_write;
    wire busy, done, error;
    wire [7:0] read_data;

    // {register address, value}, matching the supplied PCB user guide.
    function [15:0] config_word;
        input [4:0] index;
        begin
            case (index)
                0: config_word = 16'h3A5A;  // enter configuration
                1: config_word = 16'h2104;  // 1 MHz, multi-key, level INT
                2: config_word = 16'h2300;  // enable K00..K07
                3: config_word = 16'h2400;  // enable K10..K17
                4: config_word = 16'h2002;  // default global sensitivity
                21: config_word = 16'h2220;
                22: config_word = 16'h2D00;
                23: config_word = 16'h2A10;
                24: config_word = 16'h3A00; // return to normal operation
                default: config_word = {3'b000, (index - 5'd5), 8'h04};
            endcase
        end
    endfunction
    wire [15:0] config_entry = config_word(config_index);

    i2c_register_master #(.CLK_HZ(CLK_HZ), .I2C_HZ(I2C_HZ)) i2c (
        .clk(clk), .reset_n(reset_n), .start(start),
        .read_not_write(read_not_write), .register_addr(config_entry[15:8]),
        .write_data(config_entry[7:0]), .read_data(read_data),
        .busy(busy), .done(done), .error(error),
        .sda(touch_sda), .scl(touch_scl)
    );

    always @(posedge clk) begin
        if (!reset_n) begin
            state <= WAIT_POWER;
            wait_count <= 0;
            config_index <= 0;
            init_ok <= 0;
            init_error <= 0;
            start <= 0;
            read_not_write <= 0;
        end else begin
            start <= 0;
            case (state)
                WAIT_POWER:
                    if (wait_count == POWERUP_CYCLES-1) begin
                        wait_count <= 0;
                        state <= WRITE_START;
                    end else wait_count <= wait_count + 1'b1;
                WRITE_START: if (!busy) begin
                    read_not_write <= 0;
                    start <= 1;
                    state <= WRITE_WAIT;
                end
                WRITE_WAIT: if (done) begin
                    if (error) state <= FAILED;
                    else state <= READ_START;
                end
                READ_START: if (!busy) begin
                    read_not_write <= 1;
                    start <= 1;
                    state <= READ_WAIT;
                end
                READ_WAIT: if (done) begin
                    if (error || read_data != config_entry[7:0]) state <= FAILED;
                    else if (config_index == 24) begin
                        init_ok <= 1;
                        state <= MONITOR;
                    end else begin
                        config_index <= config_index + 1'b1;
                        state <= WRITE_START;
                    end
                end
                MONITOR: begin end
                FAILED: begin
                    init_ok <= 0;
                    init_error <= 1;
                end
                default: state <= FAILED;
            endcase
        end
    end

    // Synchronize INT and require 1 ms of stable level for either transition.
    reg [1:0] int_sync;
    reg pressed;
    reg [31:0] filter_count;
    always @(posedge clk) begin
        if (!reset_n) begin
            int_sync <= 2'b11;
            pressed <= 0;
            filter_count <= 0;
        end else begin
            int_sync <= {int_sync[0], touch_int_n};
            if (!init_ok || pressed == !int_sync[1]) filter_count <= 0;
            else if (filter_count == FILTER_CYCLES-1) begin
                pressed <= !int_sync[1];
                filter_count <= 0;
            end else filter_count <= filter_count + 1'b1;
        end
    end
    assign led_n = !(init_ok && pressed);
endmodule
