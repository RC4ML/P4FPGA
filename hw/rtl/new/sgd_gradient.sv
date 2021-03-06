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
//The objective of the module is to compute the accumulated gradient from all the banks. 
//
//Fixme: ....

`include "sgd_defines.vh"

module sgd_gradient (
    input   wire                                   clk,
    input   wire                                   rst_n,
    //--------------------------Begin/Stop-----------------------------//
    input   wire                                   started,

    //------------------------Configuration-----------------------------//
    input   wire [31:0]                            number_of_epochs,
    input   wire [31:0]                            number_of_samples,
    input   wire [31:0]                            dimension,
    input   wire [31:0]                            number_of_bits, 

    output  reg                                    fifo_a_rd_en,     //rd 
    input wire [`NUM_BITS_PER_BANK*`NUM_OF_BANKS-1:0] fifo_a_rd_data,

    //------------------Input: dot product---------------//
    input wire signed                       [31:0] ax_minus_b_sign_shifted_result[`NUM_OF_BANKS-1:0],         //
    input wire                                     ax_minus_b_sign_shifted_result_valid[`NUM_OF_BANKS-1:0],

    //------------------Output: dot products for all the banks. ---------------//
    output reg signed                      [31:0] acc_gradient[`NUM_BITS_PER_BANK-1:0], //
    output reg                                    acc_gradient_valid[`NUM_BITS_PER_BANK-1:0],   //

    //////////////////debug//////////////
    output reg[31:0]                           grad_counter
);

reg               [11:0] main_counter, main_counter_wire;
reg               [ 4:0] numBits_minus_1;
always @(posedge clk) begin
    begin
        main_counter_wire        <= dimension[31 :(`BIT_WIDTH_OF_BANK+`ENGINE_NUM_WIDTH)] + (dimension[`BIT_WIDTH_OF_BANK+`ENGINE_NUM_WIDTH-1:0] != 0);
        main_counter             <= main_counter_wire;        //dimension[9+MAX_BURST_BITS-1:9];        

        numBits_minus_1          <= number_of_bits[5:0] - 6'h1;
    end 
end

reg signed [31:0] staged_axy[`NUM_OF_BANKS-1:0]; //only upated when ax_minus_b_sign_shifted_result_valid is valid...

reg   [4:0] g_bit_index;   //[`NUM_OF_BANKS-1:0]
reg  [11:0] g_main_index;  //[`NUM_OF_BANKS-1:0]

////////////////////////

reg [255:0]                         ax_minus_b_sign_shifted_dout;
wire                                ax_minus_b_sign_shifted_valid;
wire                                ax_minus_b_sign_shifted_empty;
wire                                ax_minus_b_sign_shifted_rd_en;
wire                                overflow,underflow;
reg                                 overflow_r,underflow_r;

fifo_256w_64d inst_fifo_256w_64d (
  .clk(clk),              // input wire clk
  .rst(~rst_n),              // input wire rst
  .din({ax_minus_b_sign_shifted_result[7],ax_minus_b_sign_shifted_result[6],ax_minus_b_sign_shifted_result[5],ax_minus_b_sign_shifted_result[4],ax_minus_b_sign_shifted_result[3],ax_minus_b_sign_shifted_result[2],ax_minus_b_sign_shifted_result[1],ax_minus_b_sign_shifted_result[0]}),              // input wire [255 : 0] din
  .wr_en(ax_minus_b_sign_shifted_result_valid[0]),          // input wire wr_en
  .rd_en(ax_minus_b_sign_shifted_rd_en),          // input wire rd_en
  .dout(ax_minus_b_sign_shifted_dout),            // output wire [255 : 0] dout
  .full(),            // output wire full
  .overflow(overflow),    // output wire overflow
  .empty(ax_minus_b_sign_shifted_empty),          // output wire empty
  .valid(ax_minus_b_sign_shifted_valid),          // output wire valid
  .underflow(underflow)  // output wire underflow
);

always @(posedge clk) begin
    if(~rst_n) begin
        overflow_r                   <= 1'b0;
    end
    else if(overflow)begin
        overflow_r                   <= 1'b1;
    end
    else begin
        overflow_r                   <= overflow_r;
    end
end


always @(posedge clk) begin
    if(~rst_n) begin
        underflow_r                   <= 1'b0;
    end
    else if(underflow)begin
        underflow_r                   <= 1'b1;
    end
    else begin
        underflow_r                   <= underflow_r;
    end
end

assign ax_minus_b_sign_shifted_rd_en = (~ax_minus_b_sign_shifted_empty & (g_main_index==0)) ? 1 : 0;

// always @(posedge clk) begin
//     if(~rst_n) begin
//         ax_minus_b_sign_shifted_rd_en                   <= 1'b0;
//     end
//     else if(~ax_minus_b_sign_shifted_empty & (g_main_index==0))begin
//         ax_minus_b_sign_shifted_rd_en                   <= 1'b1;
//     end
//     else begin
//         ax_minus_b_sign_shifted_rd_en                   <= 1'b0;
//     end
// end


always @(posedge clk) begin
    if(~rst_n) 
    begin
        g_bit_index                    <= 5'b0;
        g_main_index                   <= 12'h0;
        fifo_a_rd_en                   <= 1'b0;
    end
    else
    begin
        fifo_a_rd_en                   <= 1'b0;
        //It is for the case of consective arrival of memory transactions. 
        if (ax_minus_b_sign_shifted_rd_en & (g_main_index > 0)) 
        begin
            g_main_index               <= main_counter;  //Trigger the execution condition...
            g_bit_index                <= 5'b0;
            fifo_a_rd_en               <= 1'b1;
        end 
        else if (ax_minus_b_sign_shifted_rd_en) //set the quotation: one-cycle delay here...
            g_main_index  <= main_counter;  //Trigger the execution condition...
        else
        begin
            if (g_main_index > 0)
            begin
                fifo_a_rd_en           <= 1'b1;
                g_bit_index            <= g_bit_index + 5'b1;
                if (g_bit_index == numBits_minus_1)
                begin
                    g_bit_index        <= 5'b0;
                    g_main_index       <= g_main_index - 32'h1; //when g_main_index is zero, it ends. 
                end
            end
        end
    end
end


reg         loss_pre_valid[`NUM_OF_BANKS-1:0],loss_pre1_valid[`NUM_OF_BANKS-1:0],loss_pre2_valid[`NUM_OF_BANKS-1:0];
reg signed  [31:0] loss_pre[`NUM_OF_BANKS-1:0],loss_pre1[`NUM_OF_BANKS-1:0]; 

reg [`NUM_BITS_PER_BANK*`NUM_OF_BANKS-1:0] fifo_a_rd_data_r1,fifo_a_rd_data_r2;

reg signed  [31:0] loss[`NUM_OF_BANKS-1:0]; //for each sample , loss is fixed.
reg         loss_valid[`NUM_OF_BANKS-1:0];  //for each sample, the valid signal is valid for main_counter cycles. 

    always @(posedge clk) begin  
        fifo_a_rd_data_r1            <= fifo_a_rd_data;  
        // fifo_a_rd_data_r2            <= fifo_a_rd_data_r1;
    end


genvar i, j;
generate for( i = 0; i < `NUM_OF_BANKS; i = i + 1) begin: inst_bank
    //staged_axy will keep the same value during the gradient computation. 
    always @(posedge clk) begin    
        if (ax_minus_b_sign_shifted_valid)
            staged_axy[i]          <= ax_minus_b_sign_shifted_dout[32*i+31:32*i];
    end

    //data will be valid after two cycles..
    always @(posedge clk) begin    
        loss_pre_valid[i]          <= fifo_a_rd_en;
        // loss_pre1_valid[i]         <= loss_pre_valid[i];
        // loss_pre2_valid[i]         <= loss_pre1_valid[i];
        loss_valid[i]              <= loss_pre_valid[i];
    end
    //Fixme, the latency may not be enough...
    always @(posedge clk) begin  
        loss[i]                    <= staged_axy[i]; 
        // loss_pre1[i]               <= loss_pre[i]; 
        // loss[i]                    <= loss_pre1[i];
    end


end // inst_bank
endgenerate
////Output: loss, loss_valid for each bank///
reg                  v_loss_valid[`NUM_BITS_PER_BANK-1:0];
reg  signed   [31:0] v_loss[`NUM_BITS_PER_BANK-1:0][`NUM_OF_BANKS-1:0];
reg                  v_a[`NUM_BITS_PER_BANK-1:0][`NUM_OF_BANKS-1:0];
////one_cycle delay loss, loss_valid for each bank///
reg                  v_loss_valid_r[`NUM_BITS_PER_BANK-1:0];
reg  signed   [31:0] v_loss_r[`NUM_BITS_PER_BANK-1:0][`NUM_OF_BANKS-1:0];
reg                  v_a_r[`NUM_BITS_PER_BANK-1:0][`NUM_OF_BANKS-1:0]; 
//////////Add tree/////////////
reg signed    [31:0] v_gradient_b[`NUM_BITS_PER_BANK-1:0][`NUM_OF_BANKS-1:0];
reg                  v_gradient_b_valid[`NUM_BITS_PER_BANK-1:0];
reg signed    [31:0] v_gradient_b_r[`NUM_BITS_PER_BANK-1:0][`NUM_OF_BANKS-1:0];
reg                  v_gradient_b_valid_r[`NUM_BITS_PER_BANK-1:0];
wire signed   [31:0] acc_gradient_b[`NUM_BITS_PER_BANK-1:0];
wire                 acc_gradient_b_valid[`NUM_BITS_PER_BANK-1:0];

//////////Accumulate the gradient. /////////////
reg                  acc_gradient_shift_valid_pre[`NUM_BITS_PER_BANK-1:0],acc_gradient_shift_valid_pre1[`NUM_BITS_PER_BANK-1:0];
reg                  acc_gradient_first_bit_en[`NUM_BITS_PER_BANK-1:0],acc_gradient_first_bit_en_r[`NUM_BITS_PER_BANK-1:0];


wire signed   [35:0] acc_gradient_b_shift_wire[`NUM_BITS_PER_BANK-1:0];
reg  signed   [35:0] acc_gradient_b_shift[`NUM_BITS_PER_BANK-1:0],acc_gradient_b_shift_r[`NUM_BITS_PER_BANK-1:0];
reg                  acc_gradient_b_shift_valid[`NUM_BITS_PER_BANK-1:0],acc_gradient_b_shift_valid_r[`NUM_BITS_PER_BANK-1:0];
reg                  acc_gradient_b_shift_zero_flag[`NUM_BITS_PER_BANK-1:0];
reg signed    [35:0] acc_gradient_shift[`NUM_BITS_PER_BANK-1:0];
reg                  acc_gradient_shift_valid[`NUM_BITS_PER_BANK-1:0];

reg           [ 4:0] d_numBits_index[`NUM_BITS_PER_BANK-1:0];
reg           [ 4:0] numBits_minus_1_g[`NUM_BITS_PER_BANK-1:0];


generate 
for( i = 0; i < `NUM_BITS_PER_BANK; i = i + 1) begin: inst_adder_tree_bank

    //set the parameter: 
    always @(posedge clk) begin
        numBits_minus_1_g[i]           <= numBits_minus_1;    
    end


    //2-cycle latency.... from (loss, loss_valid) --> (v_gradient_b, v_gradient_b_valid)
    for (j = 0; j < `NUM_OF_BANKS; j = j+1) 
    begin: inst_1_c
        always @(posedge clk) begin    
            v_loss[i][j]          <= loss[j];
            v_a[i][j]             <= fifo_a_rd_data[i+j*`NUM_BITS_PER_BANK];
        end
    end
    always @(posedge clk) begin
        v_loss_valid[i]           <= loss_valid[0];    
    end




// //     2-cycle latency.... from (loss, loss_valid) --> (v_gradient_b, v_gradient_b_valid)
//    for (j = 0; j < `NUM_OF_BANKS; j = j+1) 
//    begin: inst_2_cycle
//        always @(posedge clk) begin    
//            v_gradient_b[i][j]    <= (v_a[i][j] == 1'b1)? v_loss[i][j]:32'b0;
//            // v_gradient_b_r[i][j]  <= v_gradient_b[i][j];
//        end
//    end
//    always @(posedge clk) begin
//        v_gradient_b_valid[i]     <= v_loss_valid[i];
//        // v_gradient_b_valid_r[i]   <= v_gradient_b_valid[i];
//    end

//    sgd_adder_tree #(
//        .TREE_DEPTH (`NUM_OF_BANKS_WIDTH), //2**3 = 8 
//        .TREE_TRI_DEPTH(`NUM_OF_BANKS_TRI_WIDTH)
//    ) inst_acc_gradient_b (
//        .clk              ( clk                     ),
//        .rst_n            ( rst_n                   ),
//        .v_input          ( v_gradient_b[i]         ),
//        .v_input_valid    ( v_gradient_b_valid[i]   ),
//        .v_output         ( acc_gradient_b[i]       ),   //output...
//        .v_output_valid   ( acc_gradient_b_valid[i] ) 
//    );    


    // always @(posedge clk) begin
    //     v_loss_valid_r[i]           <= v_loss_valid[i];  
    //     v_loss_r[i]                 <= v_loss[i];
    //     v_a_r[i]                    <= v_a[i];
    // end

    sgd_dsp_add_tree #(
        .TREE_DEPTH (`NUM_OF_BANKS_WIDTH), //2**3 = 8 
        .TREE_TRI_DEPTH(`NUM_OF_BANKS_TRI_WIDTH)
    ) inst_acc_gradient_b (
        .clk              ( clk                     ),
        .rst_n            ( rst_n                   ),
        .v_input          ( v_loss[i]               ),
        .v_input_valid    ( v_loss_valid[i]         ),
        .v_input_enable   ( v_a[i]                  ),
        .v_output         ( acc_gradient_b[i]       ),   //output...
        .v_output_valid   ( acc_gradient_b_valid[i] ) 
    ); 


    assign acc_gradient_b_shift_wire[i]  = { acc_gradient_b[i], 4'b0 }; 
    //shift the 
    always @(posedge clk) 
    begin
        case (d_numBits_index[i])
            5'h00: acc_gradient_b_shift[i]          <= (acc_gradient_b_shift_wire[i]>>>1 );
            5'h01: acc_gradient_b_shift[i]          <= (acc_gradient_b_shift_wire[i]>>>2 );
            5'h02: acc_gradient_b_shift[i]          <= (acc_gradient_b_shift_wire[i]>>>3 );
            5'h03: acc_gradient_b_shift[i]          <= (acc_gradient_b_shift_wire[i]>>>4 );
            5'h04: acc_gradient_b_shift[i]          <= (acc_gradient_b_shift_wire[i]>>>5 );
            5'h05: acc_gradient_b_shift[i]          <= (acc_gradient_b_shift_wire[i]>>>6 );
            5'h06: acc_gradient_b_shift[i]          <= (acc_gradient_b_shift_wire[i]>>>7 );
            5'h07: acc_gradient_b_shift[i]          <= (acc_gradient_b_shift_wire[i]>>>8 );
            5'h08: acc_gradient_b_shift[i]          <= (acc_gradient_b_shift_wire[i]>>>9 );
            5'h09: acc_gradient_b_shift[i]          <= (acc_gradient_b_shift_wire[i]>>>10);
            5'h0a: acc_gradient_b_shift[i]          <= (acc_gradient_b_shift_wire[i]>>>11);
            5'h0b: acc_gradient_b_shift[i]          <= (acc_gradient_b_shift_wire[i]>>>12);
            5'h0c: acc_gradient_b_shift[i]          <= (acc_gradient_b_shift_wire[i]>>>13);
            5'h0d: acc_gradient_b_shift[i]          <= (acc_gradient_b_shift_wire[i]>>>14);
            5'h0e: acc_gradient_b_shift[i]          <= (acc_gradient_b_shift_wire[i]>>>15);
            5'h0f: acc_gradient_b_shift[i]          <= (acc_gradient_b_shift_wire[i]>>>16);
            // 5'h10: acc_gradient_b_shift[i]          <= (acc_gradient_b_shift_wire[i]>>>17);
            // 5'h11: acc_gradient_b_shift[i]          <= (acc_gradient_b_shift_wire[i]>>>18);
            // 5'h12: acc_gradient_b_shift[i]          <= (acc_gradient_b_shift_wire[i]>>>19);
            // 5'h13: acc_gradient_b_shift[i]          <= (acc_gradient_b_shift_wire[i]>>>20);
            // 5'h14: acc_gradient_b_shift[i]          <= (acc_gradient_b_shift_wire[i]>>>21);
            // 5'h15: acc_gradient_b_shift[i]          <= (acc_gradient_b_shift_wire[i]>>>22);
            // 5'h16: acc_gradient_b_shift[i]          <= (acc_gradient_b_shift_wire[i]>>>23);
            // 5'h17: acc_gradient_b_shift[i]          <= (acc_gradient_b_shift_wire[i]>>>24);
            // 5'h18: acc_gradient_b_shift[i]          <= (acc_gradient_b_shift_wire[i]>>>25);
            // 5'h19: acc_gradient_b_shift[i]          <= (acc_gradient_b_shift_wire[i]>>>26);
            // 5'h1a: acc_gradient_b_shift[i]          <= (acc_gradient_b_shift_wire[i]>>>27);
            // 5'h1b: acc_gradient_b_shift[i]          <= (acc_gradient_b_shift_wire[i]>>>28);
            // 5'h1c: acc_gradient_b_shift[i]          <= (acc_gradient_b_shift_wire[i]>>>29);
            // 5'h1d: acc_gradient_b_shift[i]          <= (acc_gradient_b_shift_wire[i]>>>30);
            // 5'h1e: acc_gradient_b_shift[i]          <= (acc_gradient_b_shift_wire[i]>>>31);
            // 5'h1f: acc_gradient_b_shift[i]          <= (acc_gradient_b_shift_wire[i]>>>32);
        endcase 
        //acc_gradient_b_shift[i]          <= ( ({acc_gradient_b[i], 4'b0})>>>(d_numBits_index+5'b1) );
        acc_gradient_b_shift_valid[i]               <= acc_gradient_b_valid[i];
    end 

    always @(posedge clk) begin
        if(~rst_n) 
        begin
            d_numBits_index[i]                      <=  5'b0;
        end
        else
        begin
            acc_gradient_first_bit_en[i]            <= 1'b0;
            acc_gradient_shift_valid_pre[i]         <= 1'b0;
            if ( acc_gradient_b_valid[i] )       //acc_gradient_b_shift_valid
            begin
                acc_gradient_first_bit_en[i]        <= (d_numBits_index[i] == 5'h0);
                //1, Outer loop: d_numBits_index
                d_numBits_index[i]                  <= d_numBits_index[i] + 5'h1;
                if (d_numBits_index[i] == numBits_minus_1_g[i] ) //numBits_minus_1 
                begin
                    d_numBits_index[i]              <= 5'h0;  
                    acc_gradient_shift_valid_pre[i] <= 1'b1;
                end
            end
        end 
    end
    
    always @(posedge clk)
        acc_gradient_b_shift_zero_flag[i]     <= (acc_gradient_b_shift[i][35:0] == 36'hfffffffff);
            
    always @(posedge clk) begin
        acc_gradient_shift_valid_pre1[i]        <= acc_gradient_shift_valid_pre[i];
        acc_gradient_b_shift_valid_r[i]       <= acc_gradient_b_shift_valid[i];
        acc_gradient_first_bit_en_r[i]        <= acc_gradient_first_bit_en[i];
        acc_gradient_b_shift_r[i]             <= acc_gradient_b_shift[i];
    end                
    
    
    always @(posedge clk)
    begin
        acc_gradient_shift_valid[i]             <= acc_gradient_shift_valid_pre1[i];
        if (acc_gradient_b_shift_valid_r[i])       //part of the result coming...
        begin
            //compute the dot product result...
            if ( acc_gradient_first_bit_en_r[i] ) //first of vector
                acc_gradient_shift[i]           <= acc_gradient_b_shift_r[i] + 36'hb;
            else                                        //add  
                acc_gradient_shift[i]           <= acc_gradient_shift[i] + ( (acc_gradient_b_shift_zero_flag[i])? 36'h0:acc_gradient_b_shift_r[i] );//acc_gradient_b_shift[i] ; // 
       end
    end
//reg                  acc_gradient_shift_valid_pre[`NUM_BITS_PER_BANK-1:0];
//reg                  acc_gradient_first_bit_en[`NUM_BITS_PER_BANK-1:0];
    //Real output of this model...    
    always @(posedge clk) begin
        acc_gradient[i]       <= acc_gradient_shift[i][35:4];
        acc_gradient_valid[i] <= acc_gradient_shift_valid[i];

    end

    // assign acc_gradient[i]       = acc_gradient_shift[i][35:4];
    // assign acc_gradient_valid[i] = acc_gradient_shift_valid[i];
end
endgenerate

////////////////////////////////debug/////////////////
reg [29:0]                      gradient_counter;

always@(posedge clk)begin
	if(~rst_n)begin
		gradient_counter          <= 1'b0;
	end
	else if(acc_gradient_valid[0])begin
		gradient_counter          <= gradient_counter + 1'b1;
	end
	else begin
		gradient_counter          <= gradient_counter;
	end
end	

always@(posedge clk)begin
    grad_counter                    <= {overflow_r,underflow_r,gradient_counter};
end	

endmodule
