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
module sgd_server_send (
    input   wire                                   clk,
    input   wire                                   rst_n,
    //------------------------Configuration-----------------------------//
    input   wire [`WORKER_NUM-1:0][15:0]           session_id,

    //------------------Input: dot products for all the banks. ---------------//
    input wire signed                      [31:0] ax_minus_b_sign_shifted_result[`NUM_OF_BANKS-1:0],         //
    input wire                                    ax_minus_b_sign_shifted_result_valid[`NUM_OF_BANKS-1:0],
    axis_meta.master       s_axis_tx_metadata,
    axi_stream.master      s_axis_tx_data,
    axis_meta.slave        m_axis_tx_status
);



////////////////////////////////////////fifo for a////////////////////////////////////////
//Warning: Make sure the buffer_b has the enough space for the 

reg                                                 buffer_a_wr_en;     //rd
reg     [32*`NUM_OF_BANKS-1:0]                      buffer_a_wr_data;   //rd_data
reg                                                 buffer_a_rd_en;     //rd
wire    [32*`NUM_OF_BANKS-1:0]                      buffer_a_rd_data;   //rd_data
reg     [32*`NUM_OF_BANKS-1:0]                      buffer_a_rd_data_r;
wire                                                buffer_a_data_valid;
reg                                                 buffer_a_data_valid_r,buffer_a_data_valid_r1;
wire                                                buffer_a_data_empty; 
reg     [2:0]                                       buffer_a_rd_cnt;



    always @(posedge clk) begin
        buffer_a_wr_en                              <= ax_minus_b_sign_shifted_result_valid[0]; 
    end

genvar n;
generate
    for(n = 0;n < `NUM_OF_BANKS; n++)begin
        always @(posedge clk) begin
            buffer_a_wr_data[n*32+31:n*32]          <= ax_minus_b_sign_shifted_result[n];
        end
    end
endgenerate




    distram_fifo  #( .FIFO_WIDTH      (32*`NUM_OF_BANKS), 
                    .FIFO_DEPTH_BITS (       6        ) 
    ) inst_a_fifo (
        .clk        (clk),
        .reset_n    (rst_n),

        //Writing side. from sgd_dispatch...
        .we         ( buffer_a_wr_en    ),
        .din        ( buffer_a_wr_data  ),
        .almostfull (                   ), 

        //reading side.....
        .re         (buffer_a_rd_en  ),
        .dout       (buffer_a_rd_data   ),
        .valid      (buffer_a_data_valid),
        .empty      (buffer_a_data_empty),
        .count      (                   )
    );


    localparam [3:0]    IDLE            = 9'h0,  
                        READ_DATA       = 4'h1,
                        SEND_META       = 9'h2, 
                        SEND_DATA       = 9'h3,
                        SEND_END        = 9'h4; 
 
    reg [15:0]                          current_session;
    reg [3:0]                           send_cnt;
    reg [3:0]                           state;

    reg [32*`NUM_OF_BANKS-1:0]          tx_send_data;

    always@(posedge clk)begin
        current_session                 <= session_id[send_cnt];
    end

 
    assign m_axis_tx_status.ready = 1;

    assign s_axis_tx_metadata.data = {64,current_session};
    assign s_axis_tx_metadata.valid = state == SEND_META;

    assign s_axis_tx_data.valid = state == SEND_DATA;
    assign s_axis_tx_data.data = {256'b0,tx_send_data};
    assign s_axis_tx_data.keep = 64'hffff_ffff_ffff_ffff;
    assign s_axis_tx_data.last = s_axis_tx_data.valid & s_axis_tx_data.ready;




    always@(posedge clk)begin
        if(~rst_n)begin
            state                       <= IDLE;
            send_cnt                    <= 0;
            buffer_a_rd_en              <= 0;
            tx_send_data                <= 0;
        end
        else begin
            buffer_a_rd_en              <= 0;
            case(state)
                IDLE:begin
                    if(~buffer_a_data_empty)begin
                        state           <= READ_DATA;
                        buffer_a_rd_en  <= 1;
                    end
                    else begin
                        state           <= IDLE;
                    end
                end
                READ_DATA:begin
                    if(buffer_a_data_valid)begin
                        tx_send_data    <= buffer_a_rd_data;
                        state           <= SEND_META;
                    end
                    else begin
                        state           <= READ_DATA;
                    end
                end
                SEND_META:begin
                    if(s_axis_tx_metadata.valid & s_axis_tx_metadata.ready)begin
                        send_cnt        <= send_cnt +1'b1;
                        state           <= SEND_DATA;
                    end
                    else begin
                        state           <= SEND_META;
                    end
                end
                SEND_DATA:begin
                    if(s_axis_tx_data.last)begin 
                        if(send_cnt == `WORKER_NUM)begin
                            send_cnt                <= 0;
                            state                   <= SEND_END;
                        end
                        else begin
                            state                   <= SEND_META;
                        end
                    end
                    else begin
                        state                   <= SEND_DATA;
                    end                                            
                end
                SEND_END:begin
                    state               <= IDLE;
                end
            endcase
        end
    end   
    
endmodule
 