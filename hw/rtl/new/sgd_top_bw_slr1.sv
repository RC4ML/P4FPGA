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

/////////////////////////////////////////////////////////// 
//This file is provided to implement to BitWeaving-based SGD...
// Each cache line contains the bit information from 8 samples.  
///////////////////////////////////////////////////////////
////Timing issues.
////1, the configuration signal "dimension" violates the timing constraint. --> insert the registers...
////
//Configuration of the SGD 
`include "sgd_defines.vh"

module sgd_top_bw_slr1 #(
	parameter DATA_WIDTH_IN                         = 4,
	parameter MAX_DIMENSION_BITS                    = 18,
	parameter SLR0_ENGINE_NUM                       = 4,
	parameter SLR1_ENGINE_NUM                       = 4,
	parameter SLR2_ENGINE_NUM                       = 4
				 ) (
	input   wire                                   clk,
	input   wire                                   rst_n,
	input   wire                                   dma_clk,
	input   wire                                   hbm_clk,
	//-------------------------------------------------//
	input   wire                                   start_um,
	// input   wire [511:0]                           um_params,

	input   wire [63:0]                            addr_model,
	input   wire [31:0]                            mini_batch_size,
	input   wire [31:0]                            step_size,
	input   wire [31:0]                            number_of_epochs,
	input   wire [31:0]                            dimension,
	input   wire [31:0]                            number_of_samples,
	input   wire [31:0]                            number_of_bits,


	output  wire                                   um_done,
	output  wire  [127:0][31:0]                    um_state_counters,

		//-----------------------//net app interface streams       
    axi_stream.master                               m_axis_tx_data,                    
	axi_stream.slave                                s_axis_rx_data,
	

	input [SLR1_ENGINE_NUM-1:0][`NUM_BITS_PER_BANK*`NUM_OF_BANKS-1:0]   dispatch_axb_a_data,
	input [SLR1_ENGINE_NUM-1:0]                                         dispatch_axb_a_wr_en,
	output wire [SLR1_ENGINE_NUM-1:0]                                   dispatch_axb_a_almost_full,

	input                  [32*`NUM_OF_BANKS-1:0]                       dispatch_axb_b_data,
	input                                                               dispatch_axb_b_wr_en,
	output  wire                                                        dispatch_axb_b_almost_full,

`ifdef SLR0
	/*slr0 signal*/
	///////////////dot_product output
	input wire signed [SLR0_ENGINE_NUM-1:0][`NUM_OF_BANKS-1:0][31:0]    dot_product_signed_slr0,       //
	input wire        [SLR0_ENGINE_NUM-1:0][`NUM_OF_BANKS-1:0]          dot_product_signed_valid_slr0,  //

	///////////////grandient input
	output reg signed                       [31:0]                      ax_minus_b_sign_shifted_result_slr0[`NUM_OF_BANKS-1:0],         //
	output reg                                                          ax_minus_b_sign_shifted_result_valid_slr0[`NUM_OF_BANKS-1:0],    

	///////////////////rd part of x_updated//////////////////////
	output reg                                                          writing_x_to_host_memory_done_slr0,
	output reg      [`DIS_X_BIT_DEPTH-1:0]                              x_mem_rd_addr_slr0,
	input  wire     [SLR0_ENGINE_NUM-1:0][`NUM_BITS_PER_BANK*32-1:0]    x_mem_rd_data_slr0,
`endif
`ifdef SLR2
	/*slr2 signal*/
	///////////////dot_product output
	input wire signed [SLR2_ENGINE_NUM-1:0][`NUM_OF_BANKS-1:0][31:0]    dot_product_signed_slr2,       //
	input wire        [SLR2_ENGINE_NUM-1:0][`NUM_OF_BANKS-1:0]          dot_product_signed_valid_slr2,  //

	///////////////grandient input
	output reg signed                       [31:0]                      ax_minus_b_sign_shifted_result_slr2[`NUM_OF_BANKS-1:0],         //
	output reg                                                          ax_minus_b_sign_shifted_result_valid_slr2[`NUM_OF_BANKS-1:0],    

	///////////////////rd part of x_updated//////////////////////
	output reg                                                          writing_x_to_host_memory_done_slr2,
	output reg      [`DIS_X_BIT_DEPTH-1:0]                              x_mem_rd_addr_slr2,
	input  wire     [SLR2_ENGINE_NUM-1:0][`NUM_BITS_PER_BANK*32-1:0]    x_mem_rd_data_slr2,
`endif

	//---------------------Memory Inferface:write----------------------------//
	//cmd
	output  reg                                     x_data_send_back_start,
	output  reg[63:0]                               x_data_send_back_addr,
	output  reg[31:0]                               x_data_send_back_length,

	//data
	output  reg[511:0]                              x_data_out,
	output  reg                                     x_data_out_valid,
	input   wire                                    x_data_out_almost_full

);
/////debuginggggggggggggggggggggggggggg
wire [`ENGINE_NUM-1:0][31:0] state_counters_mem_rd;
wire [`ENGINE_NUM-1:0][31:0] state_counters_x_wr;
wire [31:0] state_counters_bank_0, state_counters_wr_x_to_memory, state_counters_dispatch;

reg [5:0] counter_for_rst;
reg rst_n_reg;

always @(posedge clk) 
begin
	rst_n_reg             <= rst_n;
end



reg        started,started_r, done;
wire       mem_op_done;
wire [`ENGINE_NUM-1:0] sgd_execution_done;
wire [31:0] num_issued_mem_rd_reqs;


always @(posedge clk) 
begin  
	started <= start_um;
	started_r <= started;
end





//Completion of operations...
//wire       mem_op_done;
//reg [63:0] num_issued_mem_rd_reqs;
reg [31:0] num_received_rds;
reg [63:0] num_cycles;




assign um_done = done;



wire [SLR1_ENGINE_NUM-1:0]                                   dot_product_axb_a_almost_full;


//dot product -->serial loss
reg signed [`ENGINE_NUM-1:0][`NUM_OF_BANKS-1:0][31:0]       dot_product_signed;      
reg        [`ENGINE_NUM-1:0][`NUM_OF_BANKS-1:0]             dot_product_signed_valid;
reg  signed [`ENGINE_NUM-1:0][`NUM_OF_BANKS-1:0][31:0]      dot_product_signed_r1;      
reg         [`ENGINE_NUM-1:0][`NUM_OF_BANKS-1:0]            dot_product_signed_valid_r1; 
`ifdef SLR0
reg signed  [SLR0_ENGINE_NUM-1:0][`NUM_OF_BANKS-1:0][31:0]  dot_product_signed_slr0_r1,dot_product_signed_slr0_r2;       //
reg         [SLR0_ENGINE_NUM-1:0][`NUM_OF_BANKS-1:0]        dot_product_signed_valid_slr0_r1,dot_product_signed_valid_slr0_r2;  //
`endif
wire signed [SLR1_ENGINE_NUM-1:0][`NUM_OF_BANKS-1:0][31:0]  dot_product_signed_slr1;      
wire        [SLR1_ENGINE_NUM-1:0][`NUM_OF_BANKS-1:0]        dot_product_signed_valid_slr1;
reg signed  [SLR1_ENGINE_NUM-1:0][`NUM_OF_BANKS-1:0][31:0]  dot_product_signed_slr1_r1,dot_product_signed_slr1_r2,dot_product_signed_slr1_r3;       //
reg         [SLR1_ENGINE_NUM-1:0][`NUM_OF_BANKS-1:0]        dot_product_signed_valid_slr1_r1,dot_product_signed_valid_slr1_r2,dot_product_signed_valid_slr1_r3;  //
`ifdef SLR2
reg signed  [SLR2_ENGINE_NUM-1:0][`NUM_OF_BANKS-1:0][31:0]  dot_product_signed_slr2_r1,dot_product_signed_slr2_r2;       //
reg         [SLR2_ENGINE_NUM-1:0][`NUM_OF_BANKS-1:0]        dot_product_signed_valid_slr2_r1,dot_product_signed_valid_slr2_r2;  //
`endif

`ifdef SLR0
	always @(posedge clk)begin
		// if(~rst_n_reg) begin
		//     dot_product_signed_slr0_r1                      <= 0;
		//     dot_product_signed_slr0_r2                      <= 0;
		//     dot_product_signed_valid_slr0_r1                <= 0;     
		//     dot_product_signed_valid_slr0_r2                <= 0;
		//     dot_product_signed[SLR0_ENGINE_NUM-1:0]         <= 0;
		//     dot_product_signed_valid[SLR0_ENGINE_NUM-1:0]   <= 0;
		// end
		// else begin
			dot_product_signed_slr0_r1                      <= dot_product_signed_slr0;
			dot_product_signed_slr0_r2                      <= dot_product_signed_slr0_r1;
			dot_product_signed_valid_slr0_r1                <= dot_product_signed_valid_slr0;        
			dot_product_signed_valid_slr0_r2                <= dot_product_signed_valid_slr0_r1;
			dot_product_signed[SLR0_ENGINE_NUM-1:0]         <= dot_product_signed_slr0_r2;
			dot_product_signed_valid[SLR0_ENGINE_NUM-1:0]   <= dot_product_signed_valid_slr0_r2;        
		// end
	end
`endif

	always @(posedge clk)begin
		// if(~rst_n_reg)begin
		//     dot_product_signed_slr1_r1                      <= 0;
		//     dot_product_signed_slr1_r2                      <= 0;
		//     dot_product_signed_slr1_r3                      <= 0;
		//     dot_product_signed_valid_slr1_r1                <= 0;     
		//     dot_product_signed_valid_slr1_r2                <= 0;
		//     dot_product_signed_valid_slr1_r3                <= 0;
		//     dot_product_signed[SLR0_ENGINE_NUM + SLR1_ENGINE_NUM-1:SLR0_ENGINE_NUM]         <= 0;
		//     dot_product_signed_valid[SLR0_ENGINE_NUM + SLR1_ENGINE_NUM-1:SLR0_ENGINE_NUM]   <= 0;
		// end
		// else begin
			dot_product_signed_slr1_r1                      <= dot_product_signed_slr1;
			dot_product_signed_slr1_r2                      <= dot_product_signed_slr1_r1;
			dot_product_signed_slr1_r3                      <= dot_product_signed_slr1_r2;
			dot_product_signed_valid_slr1_r1                <= dot_product_signed_valid_slr1;        
			dot_product_signed_valid_slr1_r2                <= dot_product_signed_valid_slr1_r1;
			dot_product_signed_valid_slr1_r3                <= dot_product_signed_valid_slr1_r2;
			dot_product_signed[SLR0_ENGINE_NUM + SLR1_ENGINE_NUM-1:SLR0_ENGINE_NUM]         <= dot_product_signed_slr1_r3;
			dot_product_signed_valid[SLR0_ENGINE_NUM + SLR1_ENGINE_NUM-1:SLR0_ENGINE_NUM]   <= dot_product_signed_valid_slr1_r3;
		// end
	end

`ifdef SLR2
	always @(posedge clk)begin
		// if(~rst_n_reg)begin
		//     dot_product_signed_slr2_r1                      <= 0;
		//     dot_product_signed_slr2_r2                      <= 0;
		//     dot_product_signed_valid_slr2_r1                <= 0;     
		//     dot_product_signed_valid_slr2_r2                <= 0;
		//     dot_product_signed[SLR0_ENGINE_NUM + SLR1_ENGINE_NUM + SLR2_ENGINE_NUM-1 : SLR0_ENGINE_NUM + SLR1_ENGINE_NUM]       <= 0;
		//     dot_product_signed_valid[SLR0_ENGINE_NUM + SLR1_ENGINE_NUM + SLR2_ENGINE_NUM-1 : SLR0_ENGINE_NUM + SLR1_ENGINE_NUM] <= 0;
		// end
		// else begin
			dot_product_signed_slr2_r1                      <= dot_product_signed_slr2;
			dot_product_signed_slr2_r2                      <= dot_product_signed_slr2_r1;
			dot_product_signed_valid_slr2_r1                <= dot_product_signed_valid_slr2;        
			dot_product_signed_valid_slr2_r2                <= dot_product_signed_valid_slr2_r1;
			dot_product_signed[SLR0_ENGINE_NUM + SLR1_ENGINE_NUM + SLR2_ENGINE_NUM-1 : SLR0_ENGINE_NUM + SLR1_ENGINE_NUM]       <= dot_product_signed_slr2_r2;
			dot_product_signed_valid[SLR0_ENGINE_NUM + SLR1_ENGINE_NUM + SLR2_ENGINE_NUM-1 : SLR0_ENGINE_NUM + SLR1_ENGINE_NUM] <= dot_product_signed_valid_slr2_r2;        
		// end
	end
`endif

	always @(posedge clk)begin
		// if(~rst_n_reg)begin
		//     dot_product_signed_r1                           <= 0;
		//     dot_product_signed_valid_r1                     <= 0;
		// end
		// else begin
			dot_product_signed_r1                           <= dot_product_signed;
			dot_product_signed_valid_r1                     <= dot_product_signed_valid;        
		// end
	end




wire [`ENGINE_NUM-1:0]                      writing_x_to_host_memory_en;
reg                                         writing_x_to_host_memory_en_r1,writing_x_to_host_memory_en_r2,writing_x_to_host_memory_en_r3,writing_x_to_host_memory_en_r4;
wire                                        writing_x_to_host_memory_done;
reg  [SLR1_ENGINE_NUM-1:0]                  writing_x_to_host_memory_done_r1,writing_x_to_host_memory_done_r2,writing_x_to_host_memory_done_r3,writing_x_to_host_memory_done_r4;

`ifdef SLR0
reg                                     writing_x_to_host_memory_done_slr0_pre,writing_x_to_host_memory_done_slr0_pre1;
	always @(posedge clk)begin
		// if(~rst_n_reg)begin
		//     writing_x_to_host_memory_done_slr0_pre          <= 0;
		//     writing_x_to_host_memory_done_slr0              <= 0;
		// end
		// else begin
			writing_x_to_host_memory_done_slr0_pre          <= writing_x_to_host_memory_done;
			writing_x_to_host_memory_done_slr0_pre1			<= writing_x_to_host_memory_done_slr0_pre;
			writing_x_to_host_memory_done_slr0              <= writing_x_to_host_memory_done_slr0_pre1;
		// end        
	end
`endif


always @(posedge clk)begin
//     if(~rst_n_reg)begin
//         writing_x_to_host_memory_done_r1                    <= 0;
//         writing_x_to_host_memory_done_r2                    <= 0;
//         writing_x_to_host_memory_done_r3                    <= 0;
// //        writing_x_to_host_memory_done_r4                    <= 0;
//         writing_x_to_host_memory_en_r1                      <= 0;
//         writing_x_to_host_memory_en_r2                      <= 0;
//         writing_x_to_host_memory_en_r3                      <= 0;
//         writing_x_to_host_memory_en_r4                      <= 0;
//     end
//     else begin
		writing_x_to_host_memory_done_r1                    <= {SLR1_ENGINE_NUM{writing_x_to_host_memory_done}};
		writing_x_to_host_memory_done_r2                    <= writing_x_to_host_memory_done_r1;
		writing_x_to_host_memory_done_r3                    <= writing_x_to_host_memory_done_r2;
		writing_x_to_host_memory_done_r4                    <= writing_x_to_host_memory_done_r3;
		writing_x_to_host_memory_en_r1                      <= writing_x_to_host_memory_en[0];
		writing_x_to_host_memory_en_r2                      <= writing_x_to_host_memory_en_r1;
		writing_x_to_host_memory_en_r3                      <= writing_x_to_host_memory_en_r2;
		writing_x_to_host_memory_en_r4                      <= writing_x_to_host_memory_en_r3;
	// end    
end

`ifdef SLR2
	reg                                     writing_x_to_host_memory_done_slr2_pre,writing_x_to_host_memory_done_slr2_pre1;
	always @(posedge clk)begin
		// if(~rst_n_reg)begin
		//     writing_x_to_host_memory_done_slr2_pre          <= 0;
		//     writing_x_to_host_memory_done_slr2              <= 0;
		// end
		// else begin
			writing_x_to_host_memory_done_slr2_pre          <= writing_x_to_host_memory_done;
			writing_x_to_host_memory_done_slr2_pre1			<= writing_x_to_host_memory_done_slr2_pre;
			writing_x_to_host_memory_done_slr2              <= writing_x_to_host_memory_done_slr2_pre1;
		// end        
	end
`endif

//serial loss -->gradient
wire signed                          [31:0] ax_minus_b_sign_shifted_result[`NUM_OF_BANKS-1:0]; 
wire                                        ax_minus_b_sign_shifted_result_valid[`NUM_OF_BANKS-1:0];
// reg signed                          [31:0] ax_minus_b_sign_shifted_result_r1[SLR1_ENGINE_NUM/2-1:0][`NUM_OF_BANKS-1:0];
// reg signed                          [31:0] ax_minus_b_sign_shifted_result_r1[SLR1_ENGINE_NUM-1:0][`NUM_OF_BANKS-1:0]; 
// reg signed                          [31:0] ax_minus_b_sign_shifted_result_r2[SLR1_ENGINE_NUM-1:0][`NUM_OF_BANKS-1:0]; 
reg signed                          [31:0] ax_minus_b_sign_shifted_result_r3[SLR1_ENGINE_NUM-1:0][`NUM_OF_BANKS-1:0]; 
reg signed                          [31:0] ax_minus_b_sign_shifted_result_r4[SLR1_ENGINE_NUM-1:0][`NUM_OF_BANKS-1:0];
reg signed                          [31:0] ax_minus_b_sign_shifted_result_r5[SLR1_ENGINE_NUM-1:0][`NUM_OF_BANKS-1:0];
//  reg                                        ax_minus_b_sign_shifted_result_valid_r1[SLR1_ENGINE_NUM/2-1:0][`NUM_OF_BANKS-1:0];
// reg                                        ax_minus_b_sign_shifted_result_valid_r1[SLR1_ENGINE_NUM-1:0][`NUM_OF_BANKS-1:0];
// reg                                        ax_minus_b_sign_shifted_result_valid_r2[SLR1_ENGINE_NUM-1:0][`NUM_OF_BANKS-1:0];
reg                                        ax_minus_b_sign_shifted_result_valid_r3[SLR1_ENGINE_NUM-1:0][`NUM_OF_BANKS-1:0];
reg                                        ax_minus_b_sign_shifted_result_valid_r4[SLR1_ENGINE_NUM-1:0][`NUM_OF_BANKS-1:0];
reg                                        ax_minus_b_sign_shifted_result_valid_r5[SLR1_ENGINE_NUM-1:0][`NUM_OF_BANKS-1:0];
reg [SLR1_ENGINE_NUM-1:0]					fifo_a_wr_almostfull_r;

reg signed                          [31:0] ax_minus_b_sign_shifted_result_r1[SLR1_ENGINE_NUM/4-1:0][`NUM_OF_BANKS-1:0];
reg signed                          [31:0] ax_minus_b_sign_shifted_result_r2[SLR1_ENGINE_NUM/2-1:0][`NUM_OF_BANKS-1:0]; 
reg                                        ax_minus_b_sign_shifted_result_valid_r1[SLR1_ENGINE_NUM/4-1:0][`NUM_OF_BANKS-1:0];
reg                                        ax_minus_b_sign_shifted_result_valid_r2[SLR1_ENGINE_NUM/2-1:0][`NUM_OF_BANKS-1:0];


// genvar m,n;
//  generate for( m = 0; m < SLR1_ENGINE_NUM/2; m = m + 1)begin
// // generate for( m = 0; m < SLR1_ENGINE_NUM; m = m + 1)begin
// 	for( n = 0; n < `NUM_OF_BANKS; n = n + 1)begin
// 		always @(posedge clk) begin
// 			// if(~rst_n_reg)begin
// 			//     ax_minus_b_sign_shifted_result_r1[m][n]            <= 0;
// 			//     ax_minus_b_sign_shifted_result_valid_r1[m][n]      <= 0;
// 			// end
// 			// else begin
// 				ax_minus_b_sign_shifted_result_r1[m][n]            <= ax_minus_b_sign_shifted_result[n]; 
// 				ax_minus_b_sign_shifted_result_valid_r1[m][n]      <= ax_minus_b_sign_shifted_result_valid[n];
// 			// end            
// 		end
// 	end
// end 
// endgenerate

genvar m,n;
 generate for( m = 0; m < SLR1_ENGINE_NUM/4; m = m + 1)begin
// generate for( m = 0; m < SLR1_ENGINE_NUM; m = m + 1)begin
	for( n = 0; n < `NUM_OF_BANKS; n = n + 1)begin
		always @(posedge clk) begin
			// if(~rst_n_reg)begin
			//     ax_minus_b_sign_shifted_result_r1[m][n]            <= 0;
			//     ax_minus_b_sign_shifted_result_valid_r1[m][n]      <= 0;
			// end
			// else begin
				ax_minus_b_sign_shifted_result_r1[m][n]            <= ax_minus_b_sign_shifted_result[n]; 
				ax_minus_b_sign_shifted_result_valid_r1[m][n]      <= ax_minus_b_sign_shifted_result_valid[n];
			// end            
		end
	end
end 
endgenerate

// genvar m,n;
 generate for( m = 0; m < SLR1_ENGINE_NUM/2; m = m + 1)begin
// generate for( m = 0; m < SLR1_ENGINE_NUM; m = m + 1)begin
	for( n = 0; n < `NUM_OF_BANKS; n = n + 1)begin
		always @(posedge clk) begin
			// if(~rst_n_reg)begin
			//     ax_minus_b_sign_shifted_result_r1[m][n]            <= 0;
			//     ax_minus_b_sign_shifted_result_valid_r1[m][n]      <= 0;
			// end
			// else begin
				ax_minus_b_sign_shifted_result_r2[m][n]            <= ax_minus_b_sign_shifted_result_r1[m/2][n]; 
				ax_minus_b_sign_shifted_result_valid_r2[m][n]      <= ax_minus_b_sign_shifted_result_valid_r1[m/2][n];
			// end            
		end
	end
end 
endgenerate




`ifdef SLR0
	reg signed                       [31:0]                  ax_minus_b_sign_shifted_result_slr0_pre[`NUM_OF_BANKS-1:0];         //
	reg                                                      ax_minus_b_sign_shifted_result_valid_slr0_pre[`NUM_OF_BANKS-1:0];       
	always @(posedge clk)begin
		// if(~rst_n_reg)begin
		//     ax_minus_b_sign_shifted_result_slr0_pre                 <= 0;
		//     ax_minus_b_sign_shifted_result_slr0                     <= 0;
		//     ax_minus_b_sign_shifted_result_valid_slr0_pre           <= 0;
		//     ax_minus_b_sign_shifted_result_valid_slr0               <= 0;
		// end
		// else begin
			ax_minus_b_sign_shifted_result_slr0_pre                 <= ax_minus_b_sign_shifted_result;
			ax_minus_b_sign_shifted_result_slr0                     <= ax_minus_b_sign_shifted_result_slr0_pre;
			ax_minus_b_sign_shifted_result_valid_slr0_pre           <= ax_minus_b_sign_shifted_result_valid;
			ax_minus_b_sign_shifted_result_valid_slr0               <= ax_minus_b_sign_shifted_result_valid_slr0_pre;
		// end        
	end
`endif

`ifdef SLR2
	reg signed                       [31:0]                  ax_minus_b_sign_shifted_result_slr2_pre[`NUM_OF_BANKS-1:0];         //
	reg                                                      ax_minus_b_sign_shifted_result_valid_slr2_pre[`NUM_OF_BANKS-1:0];       
	always @(posedge clk)begin
//        if(~rst_n_reg) begin
//            ax_minus_b_sign_shifted_result_slr2_pre                 <= 0;
//            ax_minus_b_sign_shifted_result_slr2                     <= 0;
//            ax_minus_b_sign_shifted_result_valid_slr2_pre           <= 0;
//            ax_minus_b_sign_shifted_result_valid_slr2               <= 0;
//        end
//        else begin
			ax_minus_b_sign_shifted_result_slr2_pre                 <= ax_minus_b_sign_shifted_result;
			ax_minus_b_sign_shifted_result_slr2                     <= ax_minus_b_sign_shifted_result_slr2_pre;
			ax_minus_b_sign_shifted_result_valid_slr2_pre           <= ax_minus_b_sign_shifted_result_valid;
			ax_minus_b_sign_shifted_result_valid_slr2               <= ax_minus_b_sign_shifted_result_valid_slr2_pre;
//        end        
	end
`endif


///////////////////rd part of x//////////////////////
wire  [SLR1_ENGINE_NUM-1:0]         [`DIS_X_BIT_DEPTH-1:0] x_updated_rd_addr;
reg   [SLR1_ENGINE_NUM-1:0]         [`DIS_X_BIT_DEPTH-1:0] x_updated_rd_addr_r1,x_updated_rd_addr_r2;
wire  [SLR1_ENGINE_NUM-1:0][`NUM_BITS_PER_BANK*32-1:0] x_updated_rd_data;
reg   [SLR1_ENGINE_NUM-1:0][`NUM_BITS_PER_BANK*32-1:0] x_updated_rd_data_r1,x_updated_rd_data_r2,x_updated_rd_data_r3,x_updated_rd_data_r4;

wire  [SLR1_ENGINE_NUM-1:0]         [`DIS_X_BIT_DEPTH-1:0] x_batch_rd_addr;
wire  [`DIS_X_BIT_DEPTH-1:0]                                x_mem_rd_addr;
reg   [`ENGINE_NUM-1:0][`NUM_BITS_PER_BANK*32-1:0]              x_mem_rd_data;

`ifdef SLR0
	reg      [`DIS_X_BIT_DEPTH-1:0]                                     x_mem_rd_addr_slr0,x_mem_rd_addr_slr0_pre;
	reg      [SLR0_ENGINE_NUM-1:0][`NUM_BITS_PER_BANK*32-1:0]           x_mem_rd_data_slr0_r1,x_mem_rd_data_slr0_r2;   
	always @(posedge clk)begin
		// if(~rst_n_reg)begin
		//     x_mem_rd_addr_slr0_pre                                  <= 0;
		//     x_mem_rd_addr_slr0                                      <= 0;
		// end
		// else begin
			x_mem_rd_addr_slr0_pre                                  <= x_mem_rd_addr;
			x_mem_rd_addr_slr0                                      <= x_mem_rd_addr_slr0_pre;
		// end        
	end
	always @(posedge clk)begin
		// if(~rst_n_reg)begin
		//     x_mem_rd_data_slr0_r1                                   <= 0;
		//     x_mem_rd_data_slr0_r2                                   <= 0;
		//     x_mem_rd_data[SLR0_ENGINE_NUM-1:0]                      <= 0;
		// end
		// else begin
			x_mem_rd_data_slr0_r1                                   <= x_mem_rd_data_slr0;
			x_mem_rd_data_slr0_r2                                   <= x_mem_rd_data_slr0_r1;
			x_mem_rd_data[SLR0_ENGINE_NUM-1:0]                      <= x_mem_rd_data_slr0_r2;
		// end        
	end    
`endif

	always @(posedge clk)begin
		// if(~rst_n_reg)begin
		//     x_mem_rd_data[SLR0_ENGINE_NUM + SLR1_ENGINE_NUM-1:SLR0_ENGINE_NUM]  <= 0;
		// end
		// else begin
			x_mem_rd_data[SLR0_ENGINE_NUM + SLR1_ENGINE_NUM-1:SLR0_ENGINE_NUM]  <= x_updated_rd_data_r4;
		// end        
	end  


`ifdef SLR2
	reg      [`DIS_X_BIT_DEPTH-1:0]                                     x_mem_rd_addr_slr2_pre;
	reg      [SLR2_ENGINE_NUM-1:0][`NUM_BITS_PER_BANK*32-1:0]           x_mem_rd_data_slr2_r1,x_mem_rd_data_slr2_r2;   
	always @(posedge clk)begin
		// if(~rst_n_reg)begin
		//     x_mem_rd_addr_slr2_pre                                  <= 0;
		//     x_mem_rd_addr_slr2                                      <= 0;
		// end
		// else begin
			x_mem_rd_addr_slr2_pre                                  <= x_mem_rd_addr;
			x_mem_rd_addr_slr2                                      <= x_mem_rd_addr_slr2_pre;
		// end        
	end
	always @(posedge clk)begin
		// if(~rst_n_reg)begin
		//     x_mem_rd_data_slr2_r1                                   <= 0;
		//     x_mem_rd_data_slr2_r2                                   <= 0;
		//     x_mem_rd_data[SLR0_ENGINE_NUM + SLR1_ENGINE_NUM + SLR2_ENGINE_NUM-1 : SLR0_ENGINE_NUM + SLR1_ENGINE_NUM] <= 0;
		// end
		// else begin
			x_mem_rd_data_slr2_r1                                   <= x_mem_rd_data_slr2;
			x_mem_rd_data_slr2_r2                                   <= x_mem_rd_data_slr2_r1;
			x_mem_rd_data[SLR0_ENGINE_NUM + SLR1_ENGINE_NUM + SLR2_ENGINE_NUM-1 : SLR0_ENGINE_NUM + SLR1_ENGINE_NUM] <= x_mem_rd_data_slr2_r2;
		// end        
	end    
`endif



//generate end generate
genvar i;
// Instantiate engines
generate
for(i = 0; i < SLR1_ENGINE_NUM; i++) 
begin




////////////////////////////////////////////////////////////////////
//////////////////////......model x......//////////////////////////
////////////////////////////////////////////////////////////////////
///////////////////wr part of x//////////////////////
wire                               x_wr_en;     
wire   [`DIS_X_BIT_DEPTH-1:0]      x_wr_addr;
wire   [`NUM_BITS_PER_BANK*32-1:0] x_wr_data;
///////////////////rd part of x//////////////////////
//wire          [`NUM_OF_BANKS-1:0]  x_rd_en;     
wire  [`DIS_X_BIT_DEPTH-1:0]       x_rd_addr;
wire  [`NUM_BITS_PER_BANK*32-1:0]  x_rd_data;



//Compute the wr_counter to make sure ...
blockram_2port #(.DATA_WIDTH      (`NUM_BITS_PER_BANK*32),    
				 .DEPTH_BIT_WIDTH (`DIS_X_BIT_DEPTH)
) inst_x (
	.clock     ( clk             ),
	.data      ( x_wr_data    ),
	.wraddress ( x_wr_addr    ),
	.wren      ( x_wr_en      ),
	.rdaddress ( x_rd_addr    ), //can be any one of the address.
	.q         ( x_rd_data    )
);


////////////////////counter to avoid RAW hazard.////////////////////
wire [7:0]  x_wr_credit_counter; //x_rd_credit_counter: generate in each bank.







//dot product -->gradient
wire                                        buffer_a_rd_data_valid;
wire [`NUM_BITS_PER_BANK*`NUM_OF_BANKS-1:0] buffer_a_rd_data;
//gradient to x-updated 
wire signed                         [31:0] acc_gradient[`NUM_BITS_PER_BANK-1:0]; //
wire                                       acc_gradient_valid[`NUM_BITS_PER_BANK-1:0];   //


////////////////////wr part of fifo a///////////////////
reg                                         fifo_a_wr_en_pre,   fifo_a_wr_en;     
reg  [`NUM_BITS_PER_BANK*`NUM_OF_BANKS-1:0] fifo_a_wr_data_pre, fifo_a_wr_data; 
wire                                        fifo_a_wr_almostfull;

////////////////////rd part of fifo a///////////////////
wire                                        fifo_a_rd_en;     //rd 
wire [`NUM_BITS_PER_BANK*`NUM_OF_BANKS-1:0] fifo_a_rd_data;
wire                                        fifo_a_empty;
wire               [`A_FIFO_DEPTH_BITS-1:0] fifo_a_counter; 
wire                                        fifo_a_data_valid;

always @(posedge clk) 
begin
	fifo_a_wr_en_pre     <= buffer_a_rd_data_valid; //wr
	fifo_a_wr_data_pre   <= buffer_a_rd_data;    

	fifo_a_wr_en         <= fifo_a_wr_en_pre  ;     //wr
	fifo_a_wr_data       <= fifo_a_wr_data_pre;    
end

ultraram_fifo #( .FIFO_WIDTH      (`NUM_BITS_PER_BANK*`NUM_OF_BANKS ), //64 
				 .FIFO_DEPTH_BITS (`A_FIFO_DEPTH_BITS )  //determine the size of 16  13
) inst_a_fifo (
	.clk        (clk),
	.reset_n    (rst_n),

	//Writing side....
	.we         (fifo_a_wr_en     ), //or one cycle later...
	.din        (fifo_a_wr_data   ),
	.almostfull (fifo_a_wr_almostfull), //back pressure to  

	//reading side.....
	.re         (fifo_a_rd_en     ),
	.dout       (fifo_a_rd_data   ),
	.valid      (fifo_a_data_valid),
	.empty      (fifo_a_empty     ),
	.count      (fifo_a_counter   )
);

always @(posedge clk) begin
    if(~rst_n) begin
        fifo_a_wr_almostfull_r[i]                   <= 1'b0;
    end
    else if(fifo_a_wr_almostfull)begin
        fifo_a_wr_almostfull_r[i]                   <= 1'b1;
    end
    else begin
        fifo_a_wr_almostfull_r[i]                   <= fifo_a_wr_almostfull_r[i];
    end
end
// ila_a_counter inst_ila_a_counter (
// 	.clk(clk), // input wire clk


// 	.probe0(fifo_a_wr_almostfull), // input wire [0:0]  probe0  
// 	.probe1(fifo_a_counter) // input wire [10:0]  probe1
// );

// ila_x ila_x_inst (
// 	.clk(clk), // input wire clk


// 	.probe0(fifo_a_counter) // input wire [10:0] probe0
// );


////////////////////////////////////////////////////////////////////
////////////////////////model x_updated/////////////////////////////
////////////////////////////////////////////////////////////////////
///////////////////wr part of x//////////////////////
wire                              x_updated_wr_en;     
wire           [`DIS_X_BIT_DEPTH-1:0] x_updated_wr_addr;
wire  [`NUM_BITS_PER_BANK*32-1:0] x_updated_wr_data;







reg writing_x_to_host_memory_en_r;
always @(posedge clk) 
begin
	//if(~rst_n) 
	//    writing_x_to_host_memory_en_r <= 1'b0;
	//else
		writing_x_to_host_memory_en_r <= writing_x_to_host_memory_en[i];
end


	assign dispatch_axb_a_almost_full[i] = fifo_a_wr_almostfull | dot_product_axb_a_almost_full[i];
	sgd_dot_product inst_sgd_dot_product (
	.clk                        (clk        ),
	.rst_n                      (rst_n      ), //rst_n
	.started                    (started    ),
	.state_counters_dot_product (           ),    

	.mini_batch_size            (mini_batch_size  ),
	.number_of_epochs           (number_of_epochs ),
	.number_of_samples          (number_of_samples),
	.dimension                  (dimension        ),
	.number_of_bits             (number_of_bits   ),
	.step_size                  (step_size        ),

	.dispatch_axb_a_data        (dispatch_axb_a_data[i]        ),
	.dispatch_axb_a_wr_en       (dispatch_axb_a_wr_en[i]       ),
	.dispatch_axb_a_almost_full (dot_product_axb_a_almost_full[i] ),

	//.x_rd_en                    (x_rd_en                    ), 
	.x_rd_addr                  (x_rd_addr                  ),
	.x_rd_data                  (x_rd_data                  ),  
	//.x_rd_data_valid            (x_rd_data_valid          ),
	.x_wr_credit_counter        (x_wr_credit_counter        ),
	.writing_x_to_host_memory_done(writing_x_to_host_memory_done_r4[i]),

	//to 
	.buffer_a_rd_data_valid     (buffer_a_rd_data_valid     ),
	.buffer_a_rd_data           (buffer_a_rd_data           ), 

	.dot_product_signed_valid   (dot_product_signed_valid_slr1[i]   ),
	.dot_product_signed         (dot_product_signed_slr1[i]         ),
	
	//debug
	.dot_state					(um_state_counters[i])
  );


always @(posedge clk)begin
	//  ax_minus_b_sign_shifted_result_valid_r2[i]          <= ax_minus_b_sign_shifted_result_valid_r1[i/2];
	// ax_minus_b_sign_shifted_result_valid_r2[i]          <= ax_minus_b_sign_shifted_result_valid_r1[i];
	ax_minus_b_sign_shifted_result_valid_r3[i]          <= ax_minus_b_sign_shifted_result_valid_r2[i/2];
	ax_minus_b_sign_shifted_result_valid_r4[i]          <= ax_minus_b_sign_shifted_result_valid_r3[i];
	// ax_minus_b_sign_shifted_result_r2[i]          <= ax_minus_b_sign_shifted_result_r1[i/2];
	// ax_minus_b_sign_shifted_result_r2[i]          <= ax_minus_b_sign_shifted_result_r1[i];
	ax_minus_b_sign_shifted_result_r3[i]          <= ax_minus_b_sign_shifted_result_r2[i/2];
	ax_minus_b_sign_shifted_result_r4[i]          <= ax_minus_b_sign_shifted_result_r3[i];    
end


  sgd_gradient inst_sgd_gradient (
	.clk                        (clk        ),
	.rst_n                      (rst_n      ), //rst_n
	.started                    (started    ),

	.number_of_epochs           (number_of_epochs ),
	.number_of_samples          (number_of_samples),
	.dimension                  (dimension        ),
	.number_of_bits             (number_of_bits   ),

	.fifo_a_rd_en               (fifo_a_rd_en     ),
	.fifo_a_rd_data             (fifo_a_rd_data   ),

	.ax_minus_b_sign_shifted_result_valid (ax_minus_b_sign_shifted_result_valid_r3[i] ),
	.ax_minus_b_sign_shifted_result       (ax_minus_b_sign_shifted_result_r3[i]      ), 

	.acc_gradient_valid         (acc_gradient_valid),
	.acc_gradient               (acc_gradient      ),

	.grad_counter				(um_state_counters[i+8])
  );



//Maybe add registers after x_updated_rd_addr...

reg           [`DIS_X_BIT_DEPTH-1:0] x_mem_rd_addr_r1,x_mem_rd_addr_r2,x_mem_rd_addr_r3,x_mem_rd_addr_r4;

always @(posedge clk)begin
	x_mem_rd_addr_r1            <= x_mem_rd_addr;
	x_mem_rd_addr_r2            <= x_mem_rd_addr_r1;
	x_mem_rd_addr_r3            <= x_mem_rd_addr_r2;
	x_mem_rd_addr_r4            <= x_mem_rd_addr_r3;
	x_updated_rd_data_r1[i]     <= x_updated_rd_data[i];
	x_updated_rd_data_r2[i]     <= x_updated_rd_data_r1[i];
	x_updated_rd_data_r3[i]     <= x_updated_rd_data_r2[i];
	x_updated_rd_data_r4[i]     <= x_updated_rd_data_r3[i];
	// x_updated_rd_addr_r1[i]     <= x_updated_rd_addr[i];
	// x_updated_rd_addr_r2[i]     <= x_updated_rd_addr_r1[i];
end

assign x_updated_rd_addr[i] = writing_x_to_host_memory_en_r? x_mem_rd_addr_r4 : x_batch_rd_addr[i];

//Compute the wr_counter to make sure ...add reigster to any rd/wr ports. 
ultraram_2port #(.DATA_WIDTH      (`NUM_BITS_PER_BANK*32),    
				 .DEPTH_BIT_WIDTH (`DIS_X_BIT_DEPTH         )
) inst_x_updated (
	.clock     ( clk                ),
	.data      ( x_updated_wr_data  ),
	.wraddress ( x_updated_wr_addr  ),
	.wren      ( x_updated_wr_en    ),
	.rdaddress ( x_updated_rd_addr[i]), 
	.q         ( x_updated_rd_data[i]  )
);

//reg x_updated_rd_en_pre;
//always @(posedge clk) 
//begin
//    x_updated_rd_en_pre <= v_input_valid[0][0];
//end


////////////////Read/write ports of x_updated////////////////////////
sgd_x_updated_rd_wr inst_x_updated_rd_wr(
	.clk                        (clk    ),
	.rst_n                      (rst_n ),

	.started                    (started            ), 
	.dimension                  (dimension          ),

	.acc_gradient               (acc_gradient       ),//[`NUM_BITS_PER_BANK-1:0] 
	.acc_gradient_valid         (acc_gradient_valid ),//[`NUM_BITS_PER_BANK-1:0]

	.x_updated_rd_addr          ( x_batch_rd_addr[i]   ), //x_updated_rd_addr
	.x_updated_rd_data          (x_updated_rd_data[i]  ),

	.x_updated_wr_addr          (x_updated_wr_addr  ),
	.x_updated_wr_data          (x_updated_wr_data  ),
	.x_updated_wr_en            (x_updated_wr_en    ),

	.x_update_wr_counter		(um_state_counters[i+16])
);



////////////////Write ports of x////////////////////////
sgd_x_wr inst_x_wr (
	.clk                        (clk    ),
	.rst_n                      (rst_n         ),

	.state_counters_x_wr        (um_state_counters[i+24]),
	.x_wr_counter				(um_state_counters[i+32]),
	.started                    (started            ), 
	.mini_batch_size            (mini_batch_size    ),
	.number_of_epochs           (number_of_epochs   ),
	.number_of_samples          (number_of_samples  ),
	.dimension                  (dimension          ),

	.sgd_execution_done         (sgd_execution_done[i] ),
	.x_wr_credit_counter        (x_wr_credit_counter),//[`NUM_BITS_PER_BANK-1:0]

	.writing_x_to_host_memory_en   (writing_x_to_host_memory_en[i]),
	.writing_x_to_host_memory_done (writing_x_to_host_memory_done_r4[i]),

	.x_updated_wr_addr          (x_updated_wr_addr  ),
	.x_updated_wr_data          (x_updated_wr_data  ),
	.x_updated_wr_en            (x_updated_wr_en    ),

	.x_wr_addr                  (x_wr_addr          ),
	.x_wr_data                  (x_wr_data          ),
	.x_wr_en                    (x_wr_en            )
);


  `ifdef SIM

  integer testfile,bfile,dotfile,serialfile,gradientfile,xupdatefile,xfile;
  
  initial begin
	//   testfile      = $fopen( "/home/amax/hhj/distributed_sgd/distributed_input_a.txt" , "w");
		bfile	       = $fopen( "/home/amax/hhj/distributed_sgd/distributed_b.txt" , "w");
	  dotfile       = $fopen( "/home/amax/hhj/distributed_sgd/distributed_dot_product.txt" , "w");
	  serialfile    = $fopen( "/home/amax/hhj/distributed_sgd/distributed_serial.txt" , "w"); 
	  gradientfile  = $fopen( "/home/amax/hhj/distributed_sgd/distributed_gradient.txt" , "w"); 
	  xupdatefile   = $fopen( "/home/amax/hhj/distributed_sgd/distributed_xupdate.txt" , "w"); 
	  xfile         = $fopen( "/home/amax/hhj/distributed_sgd/distributed_x.txt" , "w");  
	  
  end
  
	// always @(posedge clk)begin
	//     if(dispatch_axb_a_wr_en[0])
	//         $fwrite(testfile, "%h\n",dispatch_axb_a_data[0]);
	// end

  always @(posedge clk)begin
	if(dispatch_axb_b_wr_en)
		$fwrite(bfile, "%h\n",dispatch_axb_b_data);
	end  

	always @(posedge clk)begin
		if(dot_product_signed_valid[0])
			$fwrite(dotfile, "%h\n",dot_product_signed[0]);
	end
	
	always @(posedge clk)begin
		if(ax_minus_b_sign_shifted_result_valid[0])
			$fwrite(serialfile, "%h %h %h %h %h %h %h %h \n",ax_minus_b_sign_shifted_result[0],ax_minus_b_sign_shifted_result[1],ax_minus_b_sign_shifted_result[2],ax_minus_b_sign_shifted_result[3],
															ax_minus_b_sign_shifted_result[4],ax_minus_b_sign_shifted_result[5],ax_minus_b_sign_shifted_result[6],ax_minus_b_sign_shifted_result[7]);
	end
	
	always @(posedge clk)begin
		if(acc_gradient_valid[0])
			$fwrite(gradientfile, "%h\n",{acc_gradient[ 0],acc_gradient[ 11],acc_gradient[ 2],acc_gradient[ 3],acc_gradient[ 4],acc_gradient[ 5],acc_gradient[ 6],acc_gradient[ 7],acc_gradient[ 8],acc_gradient[ 9],
										  acc_gradient[10],acc_gradient[111],acc_gradient[12],acc_gradient[13],acc_gradient[14],acc_gradient[15],acc_gradient[16],acc_gradient[17],acc_gradient[18],acc_gradient[19],
										  acc_gradient[20],acc_gradient[211],acc_gradient[22],acc_gradient[23],acc_gradient[24],acc_gradient[25],acc_gradient[26],acc_gradient[27],acc_gradient[28],acc_gradient[29],
										  acc_gradient[30],acc_gradient[311],acc_gradient[32],acc_gradient[33],acc_gradient[34],acc_gradient[35],acc_gradient[36],acc_gradient[37],acc_gradient[38],acc_gradient[39],
										  acc_gradient[40],acc_gradient[411],acc_gradient[42],acc_gradient[43],acc_gradient[44],acc_gradient[45],acc_gradient[46],acc_gradient[47],acc_gradient[48],acc_gradient[49],
										  acc_gradient[50],acc_gradient[511],acc_gradient[52],acc_gradient[53],acc_gradient[54],acc_gradient[55],acc_gradient[56],acc_gradient[57],acc_gradient[58],acc_gradient[59],
										  acc_gradient[60],acc_gradient[611],acc_gradient[62],acc_gradient[63]});
	end

	always @(posedge clk)begin
		if(x_updated_wr_en)
			$fwrite(xupdatefile, "%h %h\n",x_updated_wr_addr,x_updated_wr_data);
	end
	
	always @(posedge clk)begin
		if(x_wr_en)
			$fwrite(xfile, "%h %h\n",x_wr_addr,x_wr_data);
	end

  always @(posedge clk)begin
	  if(writing_x_to_host_memory_done) begin
		//   $fclose(testfile);
		$fclose(bfile);
		  $fclose(dotfile);
		  $fclose(serialfile);
		  $fclose(gradientfile);
		  $fclose(xupdatefile);
		  $fclose(xfile);
	  end
  end
  
  
  `endif



end
endgenerate


sgd_work_send inst_sgd_work_send (
	.clk(clk),
	.rst_n(rst_n),
	//------------------------Configuration-----------------------------//

	//------------------Input: dot products for all the banks. ---------------//
	.dot_product_signed(dot_product_signed_r1),       //
	.dot_product_signed_valid(dot_product_signed_valid_r1),  //
	.m_axis_tx_data(m_axis_tx_data)
);




  sgd_serial_loss inst_sgd_serial_loss (
	.clk                        (clk                      ),
	.rst_n                      (rst_n                ), 
	.hbm_clk                    (hbm_clk                  ),

	.step_size                  (step_size                ),

	.dispatch_axb_b_data        (dispatch_axb_b_data      ),
	.dispatch_axb_b_wr_en       (dispatch_axb_b_wr_en     ),
	.dispatch_axb_b_almost_full (dispatch_axb_b_almost_full),  

	.s_axis_rx_data   			(s_axis_rx_data ),

	.ax_minus_b_sign_shifted_result_valid (ax_minus_b_sign_shifted_result_valid),
	.ax_minus_b_sign_shifted_result       (ax_minus_b_sign_shifted_result      )
  );







////////////Writing back to the host memory////////////
sgd_wr_x_to_memory inst_wr_x_to_memory (
	.clk                        (clk    ),
	.rst_n                      (rst_n ),
	.dma_clk                    (dma_clk),

	.state_counters_wr_x_to_memory (state_counters_wr_x_to_memory),
	.started                    (started            ),
	.dimension                  (dimension          ),
	.numEpochs                  (number_of_epochs   ),
	.addr_model                 (addr_model         ),

	.writing_x_to_host_memory_en   (writing_x_to_host_memory_en_r2  ),
	.writing_x_to_host_memory_done (writing_x_to_host_memory_done),

	.x_mem_rd_addr              (x_mem_rd_addr      ),
	.x_mem_rd_data              (x_mem_rd_data      ),

	//---------------------Memory Inferface:write----------------------------//
	//cmd
	.x_data_send_back_start(x_data_send_back_start),
	.x_data_send_back_addr(x_data_send_back_addr),
	.x_data_send_back_length(x_data_send_back_length),

	//data
	.x_data_out(x_data_out),
	.x_data_out_valid(x_data_out_valid),
	.x_data_out_almost_full(x_data_out_almost_full)

);







////////////Debug output....////////////
// reg[31:0][31:0]                     netdelay_counter;
// reg[4:0]							net_cnt;
// reg									netdelay_start,netdelay_end,netdelay_start_r;
					

// always@(posedge clk)begin
// 	if(~rst_n)begin
// 		netdelay_start          <= 1'b0;
// 	end
// 	else if(m_axis_tx_data.valid & m_axis_tx_data.ready)begin
// 		netdelay_start          <= 1'b1;
// 	end
// 	else if(ax_minus_b_sign_shifted_result_valid[0])begin
// 		netdelay_start			<= 1'b0;
// 	end
// 	else begin
// 		netdelay_start          <= netdelay_start;
// 	end
// end


// always@(posedge clk)begin
// 	netdelay_start_r			<= netdelay_start;
// end

// always@(posedge clk)begin
// 	if(~rst_n)begin
// 		net_cnt          <= 1'b0;
// 	end
// 	else if(net_cnt == 5'b11111)begin
// 		net_cnt			<= net_cnt;
// 	end
// 	else if(~netdelay_start & netdelay_start_r)begin
// 		net_cnt          <= net_cnt + 1'b1;
// 	end
// 	else begin
// 		net_cnt          <= net_cnt;
// 	end
// end
    
// always@(posedge clk)begin
// 	if(~rst_n)begin
// 		netdelay_counter          <= 1'b0;
// 	end
// 	else if(netdelay_start)begin
// 		netdelay_counter[net_cnt]          <= netdelay_counter[net_cnt] + 1'b1;
// 	end
// 	else begin
// 		netdelay_counter          <= netdelay_counter;
// 	end
// end


reg[31:0]                           a_data_counter;
    
always@(posedge clk)begin
	if(~rst_n)begin
		a_data_counter          <= 1'b0;
	end
	else if(dispatch_axb_a_wr_en[0])begin
		a_data_counter          <= a_data_counter + 1'b1;
	end
	else begin
		a_data_counter          <= a_data_counter;
	end
end

reg[31:0]                           dot_counter;
    
always@(posedge clk)begin
	if(~rst_n)begin
		dot_counter          <= 1'b0;
	end
	else if(dot_product_signed_valid[0])begin
		dot_counter          <= dot_counter + 1'b1;
	end
	else begin
		dot_counter          <= dot_counter;
	end
end

reg[31:0]                           serial_counter;
    
always@(posedge clk)begin
	if(~rst_n)begin
		serial_counter          <= 1'b0;
	end
	else if(ax_minus_b_sign_shifted_result_valid[0])begin
		serial_counter          <= serial_counter + 1'b1;
	end
	else begin
		serial_counter          <= serial_counter;
	end
end

// reg[31:0]                           grad_counter;
    
// always@(posedge clk)begin
// 	if(~rst_n)begin
// 		grad_counter          <= 1'b0;
// 	end
// 	else if(acc_gradient_valid[0])begin
// 		grad_counter          <= grad_counter + 1'b1;
// 	end
// 	else begin
// 		grad_counter          <= grad_counter;
// 	end
// end	

// reg[31:0]                           x_update_counter;
    
// always@(posedge clk)begin
// 	if(~rst_n)begin
// 		x_update_counter          <= 1'b0;
// 	end
// 	else if(x_updated_wr_en)begin
// 		x_update_counter          <= grad_counter + 1'b1;
// 	end
// 	else begin
// 		x_update_counter          <= x_update_counter;
// 	end
// end	

reg[31:0]                           x_wr_counter;
    
always@(posedge dma_clk)begin
	if(~rst_n)begin
		x_wr_counter          <= 1'b0;
	end
	else if(x_data_out_valid)begin
		x_wr_counter          <= x_wr_counter + 1'b1;
	end
	else begin
		x_wr_counter          <= x_wr_counter;
	end
end	
	
reg[31:0]                           done_counter;
    
always@(posedge clk)begin
	if(~rst_n)begin
		done_counter          <= 1'b0;
	end
	else if(writing_x_to_host_memory_done)begin
		done_counter          <= done_counter + 1'b1;
	end
	else begin
		done_counter          <= done_counter;
	end
end	

reg                           		counter_en;
reg[31:0]                           counter;
reg[5:0]							done_epoch;
reg[49:0][31:0]						epoch_counter;

always@(posedge clk)begin
	if(~rst_n)begin
		done_epoch          <= 1'b0;
	end
	else if(writing_x_to_host_memory_done & ~writing_x_to_host_memory_done_r1[0])begin
		done_epoch          <= done_epoch + 1'b1;
	end
	else begin
		done_epoch          <=  done_epoch;
	end
end

always@(posedge clk)begin
	if(~rst_n)begin
		epoch_counter          <= 1'b0;
	end
	else if(writing_x_to_host_memory_done & ~writing_x_to_host_memory_done_r1[0])begin
		epoch_counter[done_epoch]          <= counter;
	end
	else begin
		epoch_counter          <=  epoch_counter;
	end
end

always@(posedge clk)begin
	if(~rst_n)begin
		counter_en          <= 1'b0;
	end
	else if(started & ~started_r)begin
		counter_en          <= 1'b1;
	end
	else if(sgd_execution_done[0])begin
		counter_en          <= 1'b0;
	end	
	else begin
		counter_en          <= counter_en;
	end
end

always@(posedge clk)begin
	if(~rst_n)begin
		counter          <= 1'b0;
	end
	else if(counter_en)begin
		counter          <= counter + 1'b1;
	end
	else begin
		counter          <= counter;
	end
end



generate for( m = 0; m < 49; m = m + 1)begin
	// generate for( m = 0; m < SLR1_ENGINE_NUM; m = m + 1)begin
		assign um_state_counters[50+m]		= epoch_counter[m];
	end 
	endgenerate
	
	
	
//um_state_counters[255:0]
// always @(posedge clk) 
// begin 
	// um_state_counters[0]		<= b_counter;
	assign um_state_counters[40]		= dot_counter;
	assign um_state_counters[41]		= serial_counter;
	// um_state_counters[3]		<= grad_counter;
	// um_state_counters[4]		<= x_update_counter;
	assign um_state_counters[43]		= x_wr_counter;
	assign um_state_counters[42]		= done_counter;
	// assign um_state_counters[44]		= netdelay_counter;
	assign um_state_counters[45]		= counter;
	assign um_state_counters[46]		= fifo_a_wr_almostfull_r;
	assign um_state_counters[47]		= a_data_counter;
	// assign um_state_counters[95:64] 	= netdelay_counter;
// end

	// ila_product ila_product_inst (
	// 	.clk(clk), // input wire clk
	
	
	// 	.probe0(dot_counter), // input wire [31:0]  probe0  
	// 	.probe1(dot_product_signed_valid), // input wire [15:0]  probe1 
	// 	.probe2(dot_product_signed[0]), // input wire [255:0]  probe2 
	// 	.probe3(dot_product_signed[1]) // input wire [255:0]  probe3
	// );

	// ila_x ila_x_inst (
	// 	.clk(clk), // input wire clk
	
	
	// 	.probe0(serial_counter), // input wire [31:0]  probe0  
	// 	.probe1({ax_minus_b_sign_shifted_result_valid[7],ax_minus_b_sign_shifted_result_valid[6],ax_minus_b_sign_shifted_result_valid[5],ax_minus_b_sign_shifted_result_valid[4],ax_minus_b_sign_shifted_result_valid[3],ax_minus_b_sign_shifted_result_valid[2],ax_minus_b_sign_shifted_result_valid[1],ax_minus_b_sign_shifted_result_valid[0]}), // input wire [7:0]  probe1 
	// 	.probe2(ax_minus_b_sign_shifted_result[0]), // input wire [31:0]  probe2 
	// 	.probe3(ax_minus_b_sign_shifted_result[1]), // input wire [31:0]  probe3 
	// 	.probe4(ax_minus_b_sign_shifted_result[2]), // input wire [31:0]  probe4 
	// 	.probe5(ax_minus_b_sign_shifted_result[3]), // input wire [31:0]  probe5 
	// 	.probe6(ax_minus_b_sign_shifted_result[4]), // input wire [31:0]  probe6 
	// 	.probe7(ax_minus_b_sign_shifted_result[5]), // input wire [31:0]  probe7 
	// 	.probe8(ax_minus_b_sign_shifted_result[6]), // input wire [31:0]  probe8 
	// 	.probe9(ax_minus_b_sign_shifted_result[7]) // input wire [31:0]  probe9
	// );

//num_received_rds == num_issued_mem_rd_reqs)
endmodule