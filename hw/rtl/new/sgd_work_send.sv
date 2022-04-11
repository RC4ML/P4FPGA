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
module sgd_work_send (
    input   wire                                   clk,
    input   wire                                   rst_n,
    //------------------------Configuration-----------------------------//


    //------------------Input: dot products for all the banks. ---------------//
    input wire signed [`ENGINE_NUM-1:0][`NUM_OF_BANKS-1:0][31:0] dot_product_signed,       //
    input wire        [`ENGINE_NUM-1:0][`NUM_OF_BANKS-1:0]        dot_product_signed_valid,  //
    axi_stream.master      m_axis_tx_data
);



////////////////////////////////////////fifo for a////////////////////////////////////////
//Warning: Make sure the buffer_b has the enough space for the 

reg     [`ENGINE_NUM-1:0]                       buffer_a_wr_en;     //rd
reg     [`ENGINE_NUM-1:0][32*`NUM_OF_BANKS-1:0] buffer_a_wr_data;   //rd_data

reg     [`ENGINE_NUM-1:0]                       buffer_a_rd_en,buffer_a_rd_en_r1,buffer_a_rd_en_r2;     //rd
wire    [`ENGINE_NUM-1:0][32*`NUM_OF_BANKS-1:0] buffer_a_rd_data;   //rd_data
wire    [`ENGINE_NUM-1:0]                       buffer_a_data_valid;
wire    [`ENGINE_NUM-1:0]                       buffer_a_data_empty;
reg     [`ENGINE_NUM-1:0]                       buffer_a_data_empty_r1,buffer_a_data_empty_r2;  
reg     [`ENGINE_NUM-1:0][3:0]                  buffer_a_rd_cnt;

//////////////////////add engine signal/
reg signed[31:0]          add_tree_in[`NUM_OF_BANKS-1:0][`ENGINE_NUM-1:0];
reg     [`NUM_OF_BANKS-1:0]                                 add_tree_in_valid;
reg signed[31:0]          add_tree_in_r[`NUM_OF_BANKS-1:0][`ENGINE_NUM-1:0];
reg     [`NUM_OF_BANKS-1:0]                                 add_tree_in_valid_r;
wire    [`NUM_OF_BANKS-1:0][31:0]                           add_tree_out;
wire    [`NUM_OF_BANKS-1:0]                                 add_tree_out_valid;


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


    //assign buffer_a_rd_en[m]          = buffer_a_data_empty ? 1'b0 : 1'b1;

    always @(posedge clk) begin
        buffer_a_data_empty_r1[m]   <= buffer_a_data_empty[m];
        buffer_a_data_empty_r2[m]   <= buffer_a_data_empty_r1[m];
        buffer_a_rd_en_r1[m]        <= buffer_a_rd_en[m]; 
        buffer_a_rd_en_r2[m]        <= buffer_a_rd_en_r1[m];     
    end     

    always @(posedge clk) begin
        if(~rst_n)
            buffer_a_rd_cnt[m]         <= 4'b0;
        else if(buffer_a_rd_cnt[m][3] & (buffer_a_data_empty_r2 == 0) )
            buffer_a_rd_cnt[m]         <= 4'b0;
        else if(buffer_a_rd_cnt[m][3])
            buffer_a_rd_cnt[m]         <= buffer_a_rd_cnt[m];
        else 
            buffer_a_rd_cnt[m]         <= buffer_a_rd_cnt[m] + 1'b1;
    end

    always @(posedge clk) begin
        if(buffer_a_rd_cnt[m][3] & (buffer_a_data_empty_r2 == 0))
            buffer_a_rd_en[m]       <= 1'b1;
        else
            buffer_a_rd_en[m]       <= 1'b0;
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
        .re         (buffer_a_rd_en_r2[m]  ),
        .dout       (buffer_a_rd_data[m]   ),
        .valid      (buffer_a_data_valid[m]),
        .empty      (buffer_a_data_empty[m]),
        .count      (                   )
    );

    for(n = 0;n < `NUM_OF_BANKS; n++)begin
        always @(posedge clk) begin
            add_tree_in[n][m]           <= buffer_a_rd_data[m][n*32+31:n*32];
            add_tree_in_r[n][m]         <= add_tree_in[n][m];
        end
    end

end 
endgenerate


//generate end generate
genvar k;
// Instantiate engines
generate 
for(k = 0; k < `NUM_OF_BANKS; k++) begin
    always @(posedge clk) begin
        add_tree_in_valid[k]        <= buffer_a_data_valid[0];
        add_tree_in_valid_r[k]      <= add_tree_in_valid[k];
    end
/////////////////////add engine///////
    sgd_adder_tree #(
        .TREE_DEPTH (`ENGINE_NUM_WIDTH), //2**8 = 64 
        .TREE_TRI_DEPTH(`ENGINE_NUM_TRI_WIDTH)
    ) inst_ax (
        .clk              ( clk                   ),
        .rst_n            ( rst_n                 ), 
        .v_input          ( add_tree_in_r[k]      ),
        .v_input_valid    ( add_tree_in_valid_r[k]),
        .v_output         ( add_tree_out[k]       ),   //output...
        .v_output_valid   ( add_tree_out_valid[k] ) 
    ); 
end 
endgenerate

    reg signed           [31:0] ax_dot_product_reg[`NUM_OF_BANKS-1:0];         //cycle synchronization. 
    reg [`NUM_OF_BANKS-1:0]     ax_dot_product_valid_reg;
    reg [31:0]                  index;
    reg [511:0]                 net_data;
    reg                         net_data_valid;
    always @(posedge clk) begin
        if(~rst_n) begin
            index               <=  32'b0;
        end
        else if(index >= 32'h7f)begin
            index               <= 32'b0;
        end     
        else if(m_axis_tx_data.valid)begin
            index               <= index + 1;
        end
        else begin
            index               <= index;
        end 
    end

    always @(posedge clk) begin
        net_data                <= {index,224'h0,ax_dot_product_reg[7],ax_dot_product_reg[6],ax_dot_product_reg[5],ax_dot_product_reg[4],ax_dot_product_reg[3],ax_dot_product_reg[2],ax_dot_product_reg[1],ax_dot_product_reg[0]};
        net_data_valid          <= ax_dot_product_valid_reg[0];
    end



    assign m_axis_tx_data.valid = net_data_valid;
    // assign m_axis_tx_data.data = {index,224'h0,ax_dot_product_reg[7],ax_dot_product_reg[6],ax_dot_product_reg[5],ax_dot_product_reg[4],ax_dot_product_reg[3],ax_dot_product_reg[2],ax_dot_product_reg[1],ax_dot_product_reg[0]};
    assign m_axis_tx_data.keep = 64'hffff_ffff_ffff_ffff;
    assign m_axis_tx_data.last = 1;


    genvar i;
    generate
        for(i = 0; i < 64; i = i + 1) begin
            assign m_axis_tx_data.data[i*8+7:i*8] = net_data[511-(i*8):511-(i*8)-7];	
        end
    endgenerate

    
    
    // genvar i;
    generate for( i = 0; i < `NUM_OF_BANKS; i = i + 1) begin: inst_bank
    
        
        always @(posedge clk) begin
            if(~rst_n) 
            begin
                ax_dot_product_valid_reg[i]             <=  1'b0;
                ax_dot_product_reg[i]                   <=  1'b0;
            end
            else
            begin
                //one-cycle delay
                ax_dot_product_valid_reg[i]             <= add_tree_out_valid[i];
                ax_dot_product_reg[i]                   <= add_tree_out[i];
    
            end 
        end
    
    
    
    end 
    endgenerate


    // ila_work_send probe_ila_work_send (
    //     .clk(clk), // input wire clk
    
    
    //     .probe0(m_axis_tx_data.valid), // input wire [0:0]  probe0  
    //     .probe1(m_axis_tx_data.ready) // input wire [31:0]  probe1 
    //     // .probe2(ax_dot_product_reg[0]), // input wire [31:0]  probe2 
    //     // .probe3(ax_dot_product_reg[1]), // input wire [31:0]  probe3 
    //     // .probe4(ax_dot_product_reg[2]), // input wire [31:0]  probe4 
    //     // .probe5(ax_dot_product_reg[3]), // input wire [31:0]  probe5 
    //     // .probe6(ax_dot_product_reg[4]), // input wire [31:0]  probe6 
    //     // .probe7(ax_dot_product_reg[5]), // input wire [31:0]  probe7 
    //     // .probe8(ax_dot_product_reg[6]), // input wire [31:0]  probe8 
    //     // .probe9(ax_dot_product_reg[7]) // input wire [31:0]  probe9
    // );


    // ila_work_send probe_ila_work_send(
    //     .clk(clk),
        
    //     .probe0(state), // input wire [4:0]
    //     .probe1(fifo_rd_cnt), // input wire [1:0]
    //     .probe2(buffer_a_rd_en), // input wire [1:0]
    //     .probe3(buffer_a_data_valid), // input wire [48:0]
    //     .probe4(buffer_a_data_empty), // input wire [1:0]
    //     .probe5(buffer_a_wr_en) // input wire [1:0]
    //     // .probe6(m_axis_tx_data.last), // input wire [1:0]
    //     // .probe7(m_axis_tx_data.data) // input wire [64:0]
    //     );

endmodule
 