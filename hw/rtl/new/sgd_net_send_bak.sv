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
module sgd_net_send_bak (
    input   wire                                   clk,
    input   wire                                   rst_n,
    //------------------------Configuration-----------------------------//
    input   wire [31:0]                            session_id_i,

    //------------------Input: dot products for all the banks. ---------------//
    input wire signed [`ENGINE_NUM-1:0][`NUM_OF_BANKS-1:0][31:0] dot_product_signed,       //
    input wire        [`ENGINE_NUM-1:0][`NUM_OF_BANKS-1:0]        dot_product_signed_valid,  //
    axis_meta.master       s_axis_tx_metadata,
    axi_stream.master      s_axis_tx_data,
    axis_meta.slave        m_axis_tx_status
);



////////////////////////////////////////fifo for a////////////////////////////////////////
//Warning: Make sure the buffer_b has the enough space for the 

reg     [`ENGINE_NUM-1:0]                       buffer_a_wr_en;     //rd
reg     [`ENGINE_NUM-1:0][32*`NUM_OF_BANKS-1:0] buffer_a_wr_data;   //rd_data

reg     [`ENGINE_NUM-1:0]                       buffer_a_rd_en;     //rd
wire    [`ENGINE_NUM-1:0][32*`NUM_OF_BANKS-1:0] buffer_a_rd_data;   //rd_data
reg     [`ENGINE_NUM-1:0][32*`NUM_OF_BANKS-1:0] buffer_a_rd_data_r;
wire    [`ENGINE_NUM-1:0]                       buffer_a_data_valid;
reg     [`ENGINE_NUM-1:0]                       buffer_a_data_valid_r,buffer_a_data_valid_r1;
wire    [`ENGINE_NUM-1:0]                       buffer_a_data_empty; 
reg     [`ENGINE_NUM-1:0][2:0]                  buffer_a_rd_cnt;



//generate end generate
genvar m,n;
// Instantiate engines
generate 
for(m = 0; m < `ENGINE_NUM; m++) begin
    always @(posedge clk) begin
        buffer_a_wr_en[m]      <= dot_product_signed_valid[m]; 
    end
    for(n = 0;n < `NUM_OF_BANKS; n++)begin
        always @(posedge clk) begin
            buffer_a_wr_data[m][n*32+31:n*32]    <= dot_product_signed[m][n];
        end
    end
   

   //  always @(posedge clk) begin
   //      if(~rst_n)
   //          buffer_a_rd_cnt[m]         <= 4'b0;
   //      else if(buffer_a_rd_cnt[m][2] & (buffer_a_data_empty == 0) )
   //          buffer_a_rd_cnt[m]         <= 4'b0;
   //      else if(buffer_a_rd_cnt[m][2])
   //          buffer_a_rd_cnt[m]         <= buffer_a_rd_cnt[m];
   //      else 
   //          buffer_a_rd_cnt[m]         <= buffer_a_rd_cnt[m] + 1'b1;
   //  end

   //  always @(posedge clk) begin
   //      if(buffer_a_rd_cnt[m][2] & (buffer_a_data_empty == 0))
   //          buffer_a_rd_en[m]       <= 1'b1;
   //      else
   //          buffer_a_rd_en[m]       <= 1'b0;
   //  end



    distram_fifo  #( .FIFO_WIDTH      (32*`NUM_OF_BANKS), 
                    .FIFO_DEPTH_BITS (       6        ) 
    ) inst_a_fifo (
        .clk        (clk),
        .reset_n    (rst_n),

        //Writing side. from sgd_dispatch...
        .we         ( buffer_a_wr_en[m]    ),
        .din        ( buffer_a_wr_data[m]  ),
        .almostfull (                   ), 

        //reading side.....
        .re         (buffer_a_rd_en[m]  ),
        .dout       (buffer_a_rd_data[m]   ),
        .valid      (buffer_a_data_valid[m]),
        .empty      (buffer_a_data_empty[m]),
        .count      (                   )
    );

    always@(posedge clk)begin
        if(~rst_n)begin
            buffer_a_rd_data_r[m]       <= 0;
        end
        else if(buffer_a_data_valid[m])begin
            buffer_a_rd_data_r[m]       <= buffer_a_rd_data[m];
        end
        else begin
            buffer_a_rd_data_r[m]       <= buffer_a_rd_data_r[m];
        end
    end

    always@(posedge clk)begin
        buffer_a_data_valid_r[m]        <= buffer_a_data_valid[m];
        buffer_a_data_valid_r1[m]       <= buffer_a_data_valid_r[m];
    end

end 
endgenerate


    localparam [3:0]    IDLE            = 9'h0,  
                        SEND_META       = 9'h1, 
                        SEND_DATA       = 9'h2,
                        SEND_END        = 9'h3; 
 
    reg [31:0]                          tx_length;
    reg [15:0]                          session_id;
    reg [3:0]                           fifo_rd_cnt;
    reg [4:0][3:0]                      fifo_rd_cnt_r;
    reg [1:0]                           inner_cnt;
    reg [4:0][1:0]                      inner_cnt_r;
    reg [3:0]                           state,tstate;
    reg [31:0]                          tx_data_cnt,tx_length_minus;

    reg [32*`NUM_OF_BANKS-1:0]          tx_send_data;
    reg [3:0]                           fifo_valid_cnt;

    always@(posedge clk)begin
        tx_length                       <= `ENGINE_NUM * `NUM_OF_BANKS * 4;
        session_id                      <= session_id_i;
        tx_length_minus                 <= tx_length - 8;
    end

    always@(posedge clk)begin
        if(~rst_n)begin
            tx_data_cnt                 <= 0;
        end
        else if(s_axis_tx_data.last)begin
            tx_data_cnt                 <= 0;
        end
        else if(s_axis_tx_data.valid & s_axis_tx_data.ready)begin
            tx_data_cnt                 <= tx_data_cnt + 1;
        end
        else begin
            tx_data_cnt                 <= tx_data_cnt;
        end
    end

 
    assign m_axis_tx_status.ready = 1;

    assign s_axis_tx_metadata.data = {tx_length,session_id};
    assign s_axis_tx_metadata.valid = state == SEND_META;

    assign s_axis_tx_data.valid = (buffer_a_data_valid_r1 != 0) || (inner_cnt_r[4]!=0);
    assign s_axis_tx_data.data = tx_send_data;
    assign s_axis_tx_data.keep = 8'hff;
    assign s_axis_tx_data.last = (tx_data_cnt == tx_length_minus) & s_axis_tx_data.valid & s_axis_tx_data.ready;




    always@(posedge clk)begin
        if(~rst_n)begin
            state                       <= IDLE;
            buffer_a_rd_en              <= 0;
            fifo_rd_cnt                 <= 0;
            inner_cnt                   <= 0;
        end
        else begin
            buffer_a_rd_en              <= 0;
            case(state)
                IDLE:begin
                    if(~buffer_a_data_empty[0])begin
                        state           <= SEND_META;
                    end
                    else begin
                        state           <= IDLE;
                    end
                end
                SEND_META:begin
                    if(s_axis_tx_metadata.valid & s_axis_tx_metadata.ready)begin
                        state           <= SEND_DATA;
                    end
                    else begin
                        state           <= SEND_META;
                    end
                end
                SEND_DATA:begin
                    inner_cnt                   <= inner_cnt + 1'b1;
                    if(inner_cnt == 2'b0)begin
                        buffer_a_rd_en[fifo_rd_cnt] <= 1'b1;
                        state                       <= SEND_DATA;
                    end
                    else if(inner_cnt == 2'b11)begin    
                        fifo_rd_cnt                 <= fifo_rd_cnt + 1'b1;
                        if(fifo_rd_cnt == (`ENGINE_NUM-1))begin
                            fifo_rd_cnt             <= 0;
                            state                   <= SEND_END;
                        end
                        else begin
                            state                   <= SEND_DATA;
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

    
    always@(posedge clk)begin
        inner_cnt_r                         <= {inner_cnt_r[3:0],inner_cnt};
        fifo_rd_cnt_r                       <= {fifo_rd_cnt_r[3:0],fifo_rd_cnt};
    end

    always @(posedge clk) begin
        if(~rst_n) begin 
            tx_send_data                    <= 0;                  
        end
        else begin
            case(inner_cnt_r[3])
                2'b00:begin
                    tx_send_data            <= buffer_a_rd_data_r[fifo_rd_cnt_r[3]][63:0];
                end
                2'b01:begin
                    tx_send_data            <= buffer_a_rd_data_r[fifo_rd_cnt_r[3]][127:64];
                end
                2'b10:begin
                    tx_send_data            <= buffer_a_rd_data_r[fifo_rd_cnt_r[3]][191:128];
                end
                2'b11:begin
                    tx_send_data            <= buffer_a_rd_data_r[fifo_rd_cnt_r[3]][255:192];
                end
            endcase
        end
    end    
    
endmodule
 