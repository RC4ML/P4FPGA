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

module sgd_top_bw #(
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

    //-----------------------------------

    input [`ENGINE_NUM-1:0][`NUM_BITS_PER_BANK*`NUM_OF_BANKS-1:0]   dispatch_axb_a_data,
    input [`ENGINE_NUM-1:0]                                         dispatch_axb_a_wr_en,
    output reg [`ENGINE_NUM-1:0]                                    dispatch_axb_a_almost_full,

    input                  [32*`NUM_OF_BANKS-1:0]  dispatch_axb_b_data,
    input                                          dispatch_axb_b_wr_en,
    output  wire                                    dispatch_axb_b_almost_full,
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


    reg  [`ENGINE_NUM-1:0][511:0]     dispatch_axb_a_data_r1,dispatch_axb_a_data_r2,dispatch_axb_a_data_r3,dispatch_axb_a_data_r4;
    reg  [255:0]                      dispatch_axb_b_data_r1,dispatch_axb_b_data_r2,dispatch_axb_b_data_r3,dispatch_axb_b_data_r4;  
    reg  [`ENGINE_NUM-1:0]            dispatch_axb_a_wr_en_r1,dispatch_axb_a_wr_en_r2,dispatch_axb_a_wr_en_r3,dispatch_axb_a_wr_en_r4;
    reg                               dispatch_axb_b_wr_en_r1,dispatch_axb_b_wr_en_r2,dispatch_axb_b_wr_en_r3,dispatch_axb_b_wr_en_r4;
    reg  [`ENGINE_NUM-1:0]            dispatch_axb_a_almost_full_r1,dispatch_axb_a_almost_full_r2,dispatch_axb_a_almost_full_r3,dispatch_axb_a_almost_full_r4;



     always @(posedge clk) begin
        // if(~rst_n)begin
        //     dispatch_axb_a_almost_full_r2   <= 0;
        //     dispatch_axb_a_almost_full_r3   <= 0;
        //     dispatch_axb_a_almost_full_r4   <= 0;
        //     dispatch_axb_a_almost_full      <= 0;
                                               
        //     dispatch_axb_a_data_r1          <= 0;
        //     dispatch_axb_a_data_r2          <= 0;
        //     dispatch_axb_a_data_r3          <= 0;
        //     dispatch_axb_a_data_r4          <= 0;
                                               
        //     dispatch_axb_a_wr_en_r1         <= 0;
        //     dispatch_axb_a_wr_en_r2         <= 0;
        //     dispatch_axb_a_wr_en_r3         <= 0;
        //     dispatch_axb_a_wr_en_r4         <= 0;
        // end
        // else begin        

            dispatch_axb_a_almost_full_r2   <= dispatch_axb_a_almost_full_r1;
            dispatch_axb_a_almost_full_r3   <= dispatch_axb_a_almost_full_r2;
            dispatch_axb_a_almost_full_r4   <= dispatch_axb_a_almost_full_r3;
            dispatch_axb_a_almost_full      <= dispatch_axb_a_almost_full_r4;
    
            dispatch_axb_a_data_r1          <= dispatch_axb_a_data;
            dispatch_axb_a_data_r2          <= dispatch_axb_a_data_r1;
            dispatch_axb_a_data_r3          <= dispatch_axb_a_data_r2;
            dispatch_axb_a_data_r4          <= dispatch_axb_a_data_r3;
    
            dispatch_axb_a_wr_en_r1         <= dispatch_axb_a_wr_en;
            dispatch_axb_a_wr_en_r2         <= dispatch_axb_a_wr_en_r1;
            dispatch_axb_a_wr_en_r3         <= dispatch_axb_a_wr_en_r2;
            dispatch_axb_a_wr_en_r4         <= dispatch_axb_a_wr_en_r3;
        // end
    end  

    always @(posedge hbm_clk)begin
        // if(~rst_n)begin
        //     dispatch_axb_b_data_r1                  <= 0;
        //     dispatch_axb_b_data_r2                  <= 0;
        //     dispatch_axb_b_wr_en_r1                 <= 0;
        //     dispatch_axb_b_wr_en_r2                 <= 0;
        // end
        // else begin
            dispatch_axb_b_data_r1                  <= dispatch_axb_b_data;
            dispatch_axb_b_data_r2                  <= dispatch_axb_b_data_r1;
            dispatch_axb_b_wr_en_r1                 <= dispatch_axb_b_wr_en;
            dispatch_axb_b_wr_en_r2                 <= dispatch_axb_b_wr_en_r1;
        // end        
    end


    //---------------------Memory Inferface:write----------------------------//
    //cmd
    wire                                            x_data_send_back_start_r1;
    wire[63:0]                                      x_data_send_back_addr_r1;
    wire[31:0]                                      x_data_send_back_length_r1;    
    reg                                             x_data_send_back_start_r2;
    reg[63:0]                                       x_data_send_back_addr_r2;
    reg[31:0]                                       x_data_send_back_length_r2;

    //data
    wire[511:0]                                     x_data_out_r1;
    wire                                            x_data_out_valid_r1;    
    reg[511:0]                                      x_data_out_r2;
    reg                                             x_data_out_valid_r2;
    reg                                             x_data_out_almost_full_r1,x_data_out_almost_full_r2;


    always @(posedge dma_clk)begin
        // if(~rst_n)begin
        //     x_data_send_back_start_r2                   <= 0;
        //     x_data_send_back_start                      <= 0;
        //     x_data_send_back_addr_r2                    <= 0;
        //     x_data_send_back_addr                       <= 0;
        //     x_data_send_back_length_r2                  <= 0;
        //     x_data_send_back_length                     <= 0;
        //     x_data_out_r2                               <= 0;
        //     x_data_out                                  <= 0;
        //     x_data_out_valid_r2                         <= 0;
        //     x_data_out_valid                            <= 0;
        //     x_data_out_almost_full_r1                   <= 0;
        //     x_data_out_almost_full_r2                   <= 0;
        // end
        // else begin
            x_data_send_back_start_r2                   <= x_data_send_back_start_r1;
            x_data_send_back_start                      <= x_data_send_back_start_r2;
            x_data_send_back_addr_r2                    <= x_data_send_back_addr_r1;
            x_data_send_back_addr                       <= x_data_send_back_addr_r2;
            x_data_send_back_length_r2                  <= x_data_send_back_length_r1;
            x_data_send_back_length                     <= x_data_send_back_length_r2;
            x_data_out_r2                               <= x_data_out_r1;
            x_data_out                                  <= x_data_out_r2;
            x_data_out_valid_r2                         <= x_data_out_valid_r1;
            x_data_out_valid                            <= x_data_out_valid_r2;
            x_data_out_almost_full_r1                   <= x_data_out_almost_full;
            x_data_out_almost_full_r2                   <= x_data_out_almost_full_r1;            
        // end
    end    


`ifdef SLR0
    /*slr0 signal*/
    ///////////////dot_product output    
    wire signed [SLR0_ENGINE_NUM-1:0][`NUM_OF_BANKS-1:0][31:0]    dot_product_signed_slr0;       //
    wire        [SLR0_ENGINE_NUM-1:0][`NUM_OF_BANKS-1:0]          dot_product_signed_valid_slr0;  //

    ///////////////grandient input
    wire signed                       [31:0]                      ax_minus_b_sign_shifted_result_slr0[`NUM_OF_BANKS-1:0];         //
    wire                                                          ax_minus_b_sign_shifted_result_valid_slr0[`NUM_OF_BANKS-1:0];    

    ///////////////////rd part of x_updated//////////////////////
    wire                                                          writing_x_to_host_memory_done_slr0;
    wire      [`DIS_X_BIT_DEPTH-1:0]                              x_mem_rd_addr_slr0;
    wire     [SLR0_ENGINE_NUM-1:0][`NUM_BITS_PER_BANK*32-1:0]     x_mem_rd_data_slr0;


sgd_top_bw_slr0 #(
    .ENGINE_NUM                                     (SLR0_ENGINE_NUM)
) inst_sgd_top_bw_slr0(
    .clk                                            (clk),
    .rst_n                                          (rst_n),
    //-------------------------------------------------//
    .start_um                                       (start_um),

    .addr_model                                     (addr_model),
    .mini_batch_size                                (mini_batch_size),
    .step_size                                      (step_size),
    .number_of_epochs                               (number_of_epochs),
    .dimension                                      (dimension),
    .number_of_samples                              (number_of_samples),
    .number_of_bits                                 (number_of_bits),


    .um_done                                        (),
    .um_state_counters                              (),

    ///////////////////////a input
    .dispatch_axb_a_data                            (dispatch_axb_a_data_r4[SLR0_ENGINE_NUM-1:0]),
    .dispatch_axb_a_wr_en                           (dispatch_axb_a_wr_en_r4[SLR0_ENGINE_NUM-1:0]),
    .dispatch_axb_a_almost_full                     (dispatch_axb_a_almost_full_r1[SLR0_ENGINE_NUM-1:0]),

    ///////////////dot_product output
    .dot_product_signed                             (dot_product_signed_slr0),       //
    .dot_product_signed_valid                       (dot_product_signed_valid_slr0),  //

    ///////////////grandient input
    .ax_minus_b_sign_shifted_result                 (ax_minus_b_sign_shifted_result_slr0),         //
    .ax_minus_b_sign_shifted_result_valid           (ax_minus_b_sign_shifted_result_valid_slr0),    

    ///////////////////rd part of x_updated//////////////////////
    .writing_x_to_host_memory_done                  (writing_x_to_host_memory_done_slr0),                                                          
    .x_mem_rd_addr                                  (x_mem_rd_addr_slr0),
    .x_mem_rd_data                                  (x_mem_rd_data_slr0)
);
`endif


`ifdef SLR2
    /*slr0 signal*/
    ///////////////dot_product output    
    wire signed [SLR2_ENGINE_NUM-1:0][`NUM_OF_BANKS-1:0][31:0]    dot_product_signed_slr2;       //
    wire        [SLR2_ENGINE_NUM-1:0][`NUM_OF_BANKS-1:0]          dot_product_signed_valid_slr2;  //

    ///////////////grandient input
    wire signed                       [31:0]                      ax_minus_b_sign_shifted_result_slr2[`NUM_OF_BANKS-1:0];         //
    wire                                                          ax_minus_b_sign_shifted_result_valid_slr2[`NUM_OF_BANKS-1:0];    

    ///////////////////rd part of x_updated//////////////////////
    wire                                                          writing_x_to_host_memory_done_slr2;
    wire      [`DIS_X_BIT_DEPTH-1:0]                              x_mem_rd_addr_slr2;
    wire     [SLR2_ENGINE_NUM-1:0][`NUM_BITS_PER_BANK*32-1:0]     x_mem_rd_data_slr2;


sgd_top_bw_slr2 #(
    .ENGINE_NUM                                     (SLR2_ENGINE_NUM)
) inst_sgd_top_bw_slr2(
    .clk                                            (clk),
    .rst_n                                          (rst_n),
    //-------------------------------------------------//
    .start_um                                       (start_um),

    .addr_model                                     (addr_model),
    .mini_batch_size                                (mini_batch_size),
    .step_size                                      (step_size),
    .number_of_epochs                               (number_of_epochs),
    .dimension                                      (dimension),
    .number_of_samples                              (number_of_samples),
    .number_of_bits                                 (number_of_bits),


    .um_done                                        (),
    .um_state_counters                              (),

    ///////////////////////a input
    .dispatch_axb_a_data                            (dispatch_axb_a_data_r4[SLR0_ENGINE_NUM + SLR1_ENGINE_NUM + SLR2_ENGINE_NUM-1 : SLR0_ENGINE_NUM + SLR1_ENGINE_NUM]),
    .dispatch_axb_a_wr_en                           (dispatch_axb_a_wr_en_r4[SLR0_ENGINE_NUM + SLR1_ENGINE_NUM + SLR2_ENGINE_NUM-1 : SLR0_ENGINE_NUM + SLR1_ENGINE_NUM]),
    .dispatch_axb_a_almost_full                     (dispatch_axb_a_almost_full_r1[SLR0_ENGINE_NUM + SLR1_ENGINE_NUM + SLR2_ENGINE_NUM-1 : SLR0_ENGINE_NUM + SLR1_ENGINE_NUM]),

    ///////////////dot_product output
    .dot_product_signed                             (dot_product_signed_slr2),       //
    .dot_product_signed_valid                       (dot_product_signed_valid_slr2),  //

    ///////////////grandient input
    .ax_minus_b_sign_shifted_result                 (ax_minus_b_sign_shifted_result_slr2),         //
    .ax_minus_b_sign_shifted_result_valid           (ax_minus_b_sign_shifted_result_valid_slr2),    

    ///////////////////rd part of x_updated//////////////////////
    .writing_x_to_host_memory_done                  (writing_x_to_host_memory_done_slr2),                                                          
    .x_mem_rd_addr                                  (x_mem_rd_addr_slr2),
    .x_mem_rd_data                                  (x_mem_rd_data_slr2)
);
`endif


sgd_top_bw_slr1 #(
    .SLR0_ENGINE_NUM                                (SLR0_ENGINE_NUM),
    .SLR1_ENGINE_NUM                                (SLR1_ENGINE_NUM),
    .SLR2_ENGINE_NUM                                (SLR2_ENGINE_NUM)
) inst_sgd_top_bw_slr1(
    .clk                                            (clk),
    .rst_n                                          (rst_n),
    .dma_clk                                        (dma_clk),
    .hbm_clk                                        (hbm_clk),
    //-------------------------------------------------//
    .start_um                                       (start_um),
                                                    
    .addr_model                                     (addr_model),
    .mini_batch_size                                (mini_batch_size),
    .step_size                                      (step_size),
    .number_of_epochs                               (number_of_epochs),
    .dimension                                      (dimension),
    .number_of_samples                              (number_of_samples),
    .number_of_bits                                 (number_of_bits),


    .um_done                                        (),
    .um_state_counters                              (um_state_counters),

       //app interface streams
    .m_axis_tx_data                                 (m_axis_tx_data),     
    .s_axis_rx_data                                 (s_axis_rx_data),    
                                                    
    .dispatch_axb_a_data                            (dispatch_axb_a_data_r4[SLR0_ENGINE_NUM + SLR1_ENGINE_NUM-1:SLR0_ENGINE_NUM]),
    .dispatch_axb_a_wr_en                           (dispatch_axb_a_wr_en_r4[SLR0_ENGINE_NUM + SLR1_ENGINE_NUM-1:SLR0_ENGINE_NUM]),
    .dispatch_axb_a_almost_full                     (dispatch_axb_a_almost_full_r1[SLR0_ENGINE_NUM + SLR1_ENGINE_NUM-1:SLR0_ENGINE_NUM]),
                                                    
    .dispatch_axb_b_data                            (dispatch_axb_b_data_r2),
    .dispatch_axb_b_wr_en                           (dispatch_axb_b_wr_en_r2),
    .dispatch_axb_b_almost_full                     (dispatch_axb_b_almost_full),

`ifdef SLR0
    /*slr0 signal*/
    ///////////////dot_product output
    .dot_product_signed_slr0                        (dot_product_signed_slr0),       //
    .dot_product_signed_valid_slr0                  (dot_product_signed_valid_slr0),  //

    ///////////////grandient input
    .ax_minus_b_sign_shifted_result_slr0            (ax_minus_b_sign_shifted_result_slr0),         //
    .ax_minus_b_sign_shifted_result_valid_slr0      (ax_minus_b_sign_shifted_result_valid_slr0),    

    ///////////////////rd part of x_updated//////////////////////
    .writing_x_to_host_memory_done_slr0             (writing_x_to_host_memory_done_slr0),
    .x_mem_rd_addr_slr0                             (x_mem_rd_addr_slr0),
    .x_mem_rd_data_slr0                             (x_mem_rd_data_slr0),
`endif
`ifdef SLR2
    /*slr2 signal*/
    ///////////////dot_product output
    .dot_product_signed_slr2                        (dot_product_signed_slr2),       //
    .dot_product_signed_valid_slr2                  (dot_product_signed_valid_slr2),  //

    ///////////////grandient input
    .ax_minus_b_sign_shifted_result_slr2            (ax_minus_b_sign_shifted_result_slr2),         //
    .ax_minus_b_sign_shifted_result_valid_slr2      (ax_minus_b_sign_shifted_result_valid_slr2),    

    ///////////////////rd part of x_updated//////////////////////
    .writing_x_to_host_memory_done_slr2             (writing_x_to_host_memory_done_slr2),
    .x_mem_rd_addr_slr2                             (x_mem_rd_addr_slr2),
    .x_mem_rd_data_slr2                             (x_mem_rd_data_slr2),
`endif

    //---------------------Memory Inferface:write----------------------------//
    //cmd
    .x_data_send_back_start                         (x_data_send_back_start_r1),
    .x_data_send_back_addr                          (x_data_send_back_addr_r1), 
    .x_data_send_back_length                        (x_data_send_back_length_r1),

    //data
    .x_data_out                                     (x_data_out_r1),
    .x_data_out_valid                               (x_data_out_valid_r1),
    .x_data_out_almost_full                         (x_data_out_almost_full_r2)

);



endmodule