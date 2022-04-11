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
module sgd_server_recv (
    input   wire                                   clk,
    input   wire                                   rst_n,
    //------------------------Configuration-----------------------------//
    input   wire [15:0][31:0]                      control_reg,

    //------------------Input: dot products for all the banks. ---------------//
    output reg signed [`ENGINE_NUM*`WORKER_NUM-1:0][`NUM_OF_BANKS-1:0][31:0]  dot_product_signed,       //
    output reg        [`ENGINE_NUM*`WORKER_NUM-1:0][`NUM_OF_BANKS-1:0]        dot_product_signed_valid,  //
    
    axis_meta.slave             s_axis_rx_metadata,
    axi_stream.slave            s_axis_rx_data
);



reg [`WORKER_NUM-1:0][31:0]                                 ipaddr;
reg [`WORKER_NUM-1:0][15:0]                                 session_id;


localparam [3:0]    IDLE                = 4'h0,  
                    JUDGE               = 4'h1, 
                    RECV_DATA           = 4'h2,
                    RD_DATA             = 4'h3,
                    WAIT                = 4'h4; 

reg [3:0]                               state,rstate;
reg [15:0]                              current_session_id;
reg [15:0]                              current_length;
reg [31:0]                              des_ip_addr;
reg [15:0]                              des_port;
reg [7:0]                               session_close_flag;
reg [15:0]                              data_cnt;
reg [3:0]                               wait_cnt;



genvar i;
generate
    for(i = 0; i < `WORKER_NUM; i = i + 1) begin
        always@(posedge clk)begin
            ipaddr[i]                   <= control_reg[i];
        end

        always@(posedge clk)begin
            if(~rst_n)begin
                session_id[i]           <= 0;
            end
            else if(des_ip_addr == ipaddr[i])begin
                session_id[i]           <= current_session_id;
            end
            else begin
                session_id[i]           <= session_id[i];
            end
        end
    end
endgenerate


assign s_axis_rx_metadata.ready         = state == IDLE;
assign s_axis_rx_data.ready             = state == RECV_DATA;


always@(posedge clk)begin
    if(~rst_n)begin
        state                           <= IDLE;
        data_cnt                        <= 0;
    end
    else begin
        case(state)
            IDLE:begin
                if(s_axis_rx_metadata.ready & s_axis_rx_metadata.valid & (s_axis_rx_metadata.data[31:16] == 0))begin
                    state               <= IDLE;
                end
                else if(s_axis_rx_metadata.ready & s_axis_rx_metadata.valid)begin
                    state               <= JUDGE;
                    current_length		<= s_axis_rx_metadata.data[31:16];
                    current_session_id	<= s_axis_rx_metadata.data[15:0];
                    des_ip_addr			<= s_axis_rx_metadata.data[63:32];
                    des_port			<= s_axis_rx_metadata.data[79:64];
                    session_close_flag	<= s_axis_rx_metadata.data[87:80];
                end
                else begin
                    state               <= IDLE;
                end
            end
            JUDGE:begin
                if(current_length == 0)begin
                    state               <= IDLE;
                end
                else begin
                    state               <= RECV_DATA;
                end
            end
            RECV_DATA:begin
                if(s_axis_rx_data.valid & s_axis_rx_data.ready)begin
                    data_cnt            <= data_cnt + 1'b1;
                    if(s_axis_rx_data.last)begin
                        data_cnt        <= 0;
                        state           <= IDLE;
                    end
                    else begin
                        state           <= RECV_DATA;
                    end
                end
                else begin
                    state               <= RECV_DATA;
                end
            end
        endcase
    end
end




////////////////////////////////////////fifo for a////////////////////////////////////////
//Warning: Make sure the buffer_b has the enough space for the 

reg     [`ENGINE_NUM*`WORKER_NUM-1:0]                       buffer_a_wr_en;     //rd
reg     [`ENGINE_NUM*`WORKER_NUM-1:0][32*`NUM_OF_BANKS-1:0] buffer_a_wr_data;   //rd_data

reg     [`ENGINE_NUM*`WORKER_NUM-1:0]                       buffer_a_rd_en;     //rd
wire    [`ENGINE_NUM*`WORKER_NUM-1:0][32*`NUM_OF_BANKS-1:0] buffer_a_rd_data;   //rd_data
reg     [`ENGINE_NUM*`WORKER_NUM-1:0][32*`NUM_OF_BANKS-1:0] buffer_a_rd_data_r;
wire    [`ENGINE_NUM*`WORKER_NUM-1:0]                       buffer_a_data_valid;
reg     [`ENGINE_NUM*`WORKER_NUM-1:0]                       buffer_a_data_valid_r,buffer_a_data_valid_r1;
wire    [`ENGINE_NUM*`WORKER_NUM-1:0]                       buffer_a_data_empty; 
reg     [`ENGINE_NUM*`WORKER_NUM-1:0][2:0]                  buffer_a_rd_cnt;






//generate end generate
genvar m,n;
// Instantiate engines
generate 
for(m = 0; m < `ENGINE_NUM*`WORKER_NUM; m++) begin
    always @(posedge clk) begin
        if((des_ip_addr == ipaddr[m/`ENGINE_NUM]) && (data_cnt == m%`ENGINE_NUM))begin
            buffer_a_wr_en[m]       <= s_axis_rx_data.valid & s_axis_rx_data.ready; 
        end
        else begin
            buffer_a_wr_en[m]       <= 0;
        end
    end


    always @(posedge clk) begin
        buffer_a_wr_data[m]         <= s_axis_rx_data.data[255:0];
    end



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

    for(n = 0;n < `NUM_OF_BANKS; n++)begin
        always @(posedge clk) begin
            if(~rst_n)begin
                dot_product_signed[m][n]        <= 0;
            end
            else if(buffer_a_data_valid[m])begin            
                dot_product_signed[m][n]        <= buffer_a_rd_data[m][n*32+31:n*32];
            end
            else begin
                dot_product_signed[m][n]        <= dot_product_signed[m][n];
            end            
        end

        always@(posedge clk)begin
            dot_product_signed_valid[m][n]      <= buffer_a_data_valid[m];
        end        

    end

end 
endgenerate


always@(posedge clk)begin
    if(~rst_n)begin
        rstate                          <= IDLE;
        buffer_a_rd_en                  <= 0;
        wait_cnt                        <= 0;
    end
    else begin
        buffer_a_rd_en                  <= 0;
        case(rstate)
            IDLE:begin
                if(buffer_a_data_empty == 0)begin
                    rstate              <= RD_DATA;
                end
                else begin
                    rstate              <= IDLE;
                end
            end
            RD_DATA:begin
                buffer_a_rd_en          <= {`ENGINE_NUM*`WORKER_NUM{1'b1}};
                rstate                  <= WAIT;
            end
            WAIT:begin
                wait_cnt                <= wait_cnt + 1'b1;
                if(wait_cnt[2])begin
                    wait_cnt            <= 0;
                    rstate              <= IDLE;
                end
                else begin
                    rstate              <= WAIT;
                end
            end
        endcase
    end
end


    
endmodule
 