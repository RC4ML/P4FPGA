/*
 * Copyright 2017 - 2018, Zeke Wang, Systems Group, ETH Zurich
 *
 * This hardware operator is free software: you can redistribute it and/or
 * modify it under the terms of the GNU General Public License as published
 * by the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */
//The objective of the module is to compute the dot products for eight banks.
//
//Fixme: we can tune the precision of computation in this part....

`include "sgd_defines.vh"
module sgd_work_recv (
    input   wire                                   clk,
    input   wire                                   rst_n,
    //------------------------Configuration-----------------------------//

    //------------------Input: dot products for all the banks. ---------------//
    output reg signed                      [31:0] ax_minus_b_sign_shifted_result[`NUM_OF_BANKS-1:0],         //
    output reg                                    ax_minus_b_sign_shifted_result_valid[`NUM_OF_BANKS-1:0],    
    axis_meta.slave             s_axis_rx_metadata,
    axi_stream.slave            s_axis_rx_data
);



reg[255:0]                              receive_data;


localparam [3:0]    IDLE                = 9'h0,  
                    RECV_DATA           = 9'h1; 

reg [3:0]                               state;




assign s_axis_rx_metadata.ready         = 1;
assign s_axis_rx_data.ready             = state == IDLE;


always@(posedge clk)begin
    if(~rst_n)begin
        state                           <= IDLE;
    end
    else begin
        case(state)
            IDLE:begin
                if(s_axis_rx_data.ready & s_axis_rx_data.valid)begin
                    receive_data        <= s_axis_rx_data.data[255:0];
                    state               <= RECV_DATA;
                end
                else begin
                    state               <= IDLE;
                end
            end
            RECV_DATA:begin
                state           <= IDLE;
            end
        endcase
    end
end

genvar i;
generate
    for(i = 0; i < `NUM_OF_BANKS; i = i + 1) begin
        always@(posedge clk)begin
            if(~rst_n)begin
                ax_minus_b_sign_shifted_result_valid[i]     <= 0;
            end
            else if(state==RECV_DATA)begin
                ax_minus_b_sign_shifted_result_valid[i]     <= 1;
            end
            else begin
                ax_minus_b_sign_shifted_result_valid[i]     <= 0;
            end
        end

        always@(posedge clk)begin
            if(~rst_n)begin
                ax_minus_b_sign_shifted_result[i]     <= 0;
            end
            else if(state==RECV_DATA)begin
                ax_minus_b_sign_shifted_result[i]     <= receive_data[i*32+31:i*32];
            end
            else begin
                ax_minus_b_sign_shifted_result[i]     <= ax_minus_b_sign_shifted_result[i];
            end
        end

    end
endgenerate


// ila_work_recv probe_ila_work_recv(
// .clk(clk),

// .probe0(state), // input wire [4:0]
// .probe1(s_axis_rx_metadata.valid), // input wire [1:0]
// .probe2(s_axis_rx_metadata.ready), // input wire [1:0]
// .probe3(s_axis_rx_metadata.data), // input wire [88:0]
// .probe4(s_axis_rx_data.valid), // input wire [1:0]
// .probe5(s_axis_rx_data.ready), // input wire [1:0]
// .probe6(s_axis_rx_data.last), // input wire [1:0]
// .probe7(s_axis_rx_data.data) // input wire [64:0]
// );

    
endmodule
 