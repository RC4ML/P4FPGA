`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2020/04/01 00:39:24
// Design Name: 
// Module Name: hbm_dispatch
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


`include "sgd_defines.vh"

module hbm_dispatch 
#(
    parameter DATA_WIDTH      = 256,  // 256-bit for AXI3
    parameter ID_WIDTH        = 6     //fixme,
)(
    input   wire                                   clk,
    input   wire                                   rst_n,
    //--------------------------Begin/Stop-----------------------------//
    input   wire                                   start,
    input   wire [31:0]                             data_length,

    output  reg  [31:0]                            state_counters_dispatch,

    //---------------------Input: External Memory rd response-----------------//
    //Read Data (input)
    input                      m_axi_RVALID  , //rd data valid
    input   [DATA_WIDTH - 1:0] m_axi_RDATA   , //rd data 
    input                      m_axi_RLAST   , //rd data last
    input     [ID_WIDTH - 1:0] m_axi_RID     , //rd data id
    input                [1:0] m_axi_RRESP   , //rd data status. 
    output                     m_axi_RREADY  ,



    //banks = 8, bits_per_bank=64...
    //------------------Output: disptach resp data to a ofeach bank---------------//
    output  reg [(`NUM_BITS_PER_BANK*`NUM_OF_BANKS/2)-1:0]  dispatch_axb_a_data, 
    output  reg                                             dispatch_axb_a_wr_en, 
    input   wire                                            dispatch_axb_a_almost_full, //only one of them is used to control...

    //------------------Output: disptach resp data to b of each bank---------------//
    output  reg                 [32*`NUM_OF_BANKS-1:0] dispatch_axb_b_data, 
    output  reg                                        dispatch_axb_b_wr_en,
    //input   wire                                     dispatch_axb_b_almost_full[`NUM_OF_BANKS-1:0],

    output reg [31:0]                                   wr_a_counter,
 	output reg [31:0]                                   wr_b_counter, 
 	output reg [31:0]                                   rd_sum_cnt
);

    // RX RD response
    wire [5:0]                             um_rx_rd_tag;
    wire [255:0]                           um_rx_data;
    wire                                   um_rx_rd_valid;
    wire                                   um_rx_rd_ready;

    reg [(`NUM_BITS_PER_BANK*`NUM_OF_BANKS/2)-1:0]  dispatch_axb_a_data_pre1,dispatch_axb_a_data_pre2; 
    reg                                             dispatch_axb_a_wr_en_pre1,dispatch_axb_a_wr_en_pre2;    

assign um_rx_rd_tag         = m_axi_RID;
assign um_rx_data           = m_axi_RDATA;
assign um_rx_rd_valid       = m_axi_RVALID;
assign m_axi_RREADY         = um_rx_rd_ready;


reg         started_r;
always @(posedge clk) begin
    if(~rst_n) 
    begin
        started_r <= 1'b0;
    end 
    else if (start) 
    begin
        started_r <= 1'b1;
    end
end

//reg [31:0] wr_a_counter, wr_b_counter;
always @(posedge clk) begin
    if(~rst_n) 
    begin
        wr_a_counter <= 32'b0;
    end 
    else if(start)
        wr_a_counter <= 32'b0;
    else if (um_rx_rd_valid & tmp_ready) 
    begin
        wr_a_counter <= wr_a_counter + 32'b1;
    end
end

always @(posedge clk) begin
    if(~rst_n) 
    begin
        wr_b_counter <= 32'b0;
    end 
    else if(start)
        wr_b_counter <=32'b0;
    else if (dispatch_axb_b_wr_en) 
    begin
        wr_b_counter <= wr_b_counter + 32'b1;
    end
end



reg tmp_ready, compute_unit_full;

//output: accumulating the gradient, output to the gradient tree...
//assign state_counters_dispatch = {wr_b_counter[15:0], wr_a_counter[15:0]};
always @(posedge clk) begin
    if(~rst_n) 
        state_counters_dispatch <= 32'b0;
    else 
        state_counters_dispatch <= state_counters_dispatch + {31'b0, compute_unit_full};
end

always @(posedge clk) 
begin
    compute_unit_full <=  dispatch_axb_a_almost_full;
    tmp_ready         <= ~dispatch_axb_a_almost_full;
end

assign um_rx_rd_ready = tmp_ready; //~dispatch_axb_a_almost_full[0]; //Can insert one register between them. 


///////////////////////////////////////////////////////////////////////////////////////////////////
//------------------Output: disptach resp data to b ofeach bank---------------//
//We donot check the avaiability of the buffer for b, since we assume it has.
///////////////////////////////////////////////////////////////////////////////////////////////////
// reg   [1:0] state_b; 
// reg [511:0] mem_b_buffer;
// reg         mem_b_received_en;
// reg   [2:0] mem_b_index, mem_b_addr;
// /////////FSM: generate  m_b_index, mem_b_received_en and mem_b_buffer.
// parameter MEM_B_WRITING_COUNTER = 512/(32*`NUM_OF_BANKS);
// localparam [1:0]
//         RE_B_IDLE_STATE       = 2'b00,
//         RE_B_POOLING_STATE    = 2'b01,
//         RE_B_WRITING_STATE    = 2'b10,
//         RE_B_END_STATE        = 2'b11;
// //////////////////////////////   Finite State Machine: for b    ///////////////////////////////////
// always@(posedge clk) begin
//     if(~rst_n) 
//     begin
//         state_b                  <= RE_B_IDLE_STATE;
//         //mem_b_buffer             <= 512'b0;
//         mem_b_received_en        <= 1'b0;
//         //mem_b_index              <= 3'b0;
//         //mem_b_addr               <= 3'b0;
//     end 
//     else 
//     begin
//         mem_b_received_en        <= 1'b0;
//         case (state_b)
//             //This state is the beginning of  
//             RE_B_IDLE_STATE: 
//             begin 
//                 if(started_r)  // started with one cycle later...
//                     state_b        <= RE_B_POOLING_STATE;  
//             end

//             /* This state is just polling the arriving of data for b.*/
//             RE_B_POOLING_STATE: 
//             begin
//                 mem_b_index       <= 3'b0;
//                 mem_b_addr        <= 3'b0;
//                 /* It also registers the parameters for the FSM*/
//                 if (um_rx_rd_valid & tmp_ready & (um_rx_rd_tag == `MEM_RD_B_TAG) )
//                 begin
//                     mem_b_buffer  <= um_rx_data;
//                     state_b         <= RE_B_WRITING_STATE;  
//                 end
//             end

//             RE_B_WRITING_STATE:
//             begin
//                 mem_b_received_en <= 1'b1;
//                 mem_b_addr        <= mem_b_addr  + {2'b0, mem_b_received_en};
//                 mem_b_index       <= mem_b_index + 3'b1;

//                 if (mem_b_index == (MEM_B_WRITING_COUNTER-1))
//                     state_b         <= RE_B_POOLING_STATE;  
//             end
//         endcase 
//     end 
// end

///////////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////Output///////////////////////////////////////////////////////
//------------------aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa---------------//
always @(posedge clk) 
begin 
    if(~rst_n) 
    begin
        dispatch_axb_a_wr_en_pre1      <= 1'b0 ;        
    end 
    else 
    begin  //I do not know whether this implementation works or not...
        dispatch_axb_a_wr_en_pre1      <= um_rx_rd_valid & tmp_ready & (um_rx_rd_tag == `MEM_RD_A_TAG);
        dispatch_axb_a_data_pre1       <= um_rx_data;
    end
end

always @(posedge clk) begin 
    dispatch_axb_a_wr_en_pre2           <= dispatch_axb_a_wr_en_pre1;
    dispatch_axb_a_wr_en                <= dispatch_axb_a_wr_en_pre2;
    dispatch_axb_a_data_pre2            <= dispatch_axb_a_data_pre1;
    dispatch_axb_a_data                 <= dispatch_axb_a_data_pre2;
end

//------------------bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb---------------//
always @(posedge clk) 
begin 
    if(~rst_n) 
    begin
        //dispatch_axb_b_data[i]       <= 32'h0;
        dispatch_axb_b_wr_en      <= 1'b0 ;        
    end 
    else 
    begin  
        dispatch_axb_b_wr_en      <= um_rx_rd_valid & tmp_ready & (um_rx_rd_tag == `MEM_RD_B_TAG);
        dispatch_axb_b_data       <= um_rx_data; //255:0
    end
end





/////////////////////////////debug//////////
    //reg [31:0]          rd_sum_cnt;
    reg                 rd_sum_cnt_en;

    always @(posedge clk)begin
        if(~rst_n)
            rd_sum_cnt_en                       <= 1'b0;
        else if(start)
            rd_sum_cnt_en                       <= 1'b1;
        else if(wr_a_counter >= (data_length>>5))
            rd_sum_cnt_en                       <= 1'b0;
        else
            rd_sum_cnt_en                       <= rd_sum_cnt_en;
    end


    always @(posedge clk)begin
        if(~rst_n)
            rd_sum_cnt                       <= 1'b0;
        else if(start)
            rd_sum_cnt                       <= 1'b0;
        else if(rd_sum_cnt_en)
            rd_sum_cnt                       <= rd_sum_cnt + 1'b1;
        else
            rd_sum_cnt                       <= rd_sum_cnt;
    end

//ila_dispatch ila_dispatch_inst (
//	.clk(clk), // input wire clk


//	.probe0(m_axi_RVALID), // input wire [0:0]  probe0  
//	.probe1(m_axi_RREADY), // input wire [0:0]  probe1 
//	.probe2(m_axi_RLAST), // input wire [0:0]  probe2 
//	.probe3(m_axi_RDATA), // input wire [255:0]  probe3
//    .probe4(m_axi_RID) // input wire [5:0]  probe4
////    .probe5(wr_a_counter), // input wire [31:0]  probe5 
////	.probe6(wr_b_counter) // input wire [31:0]  probe6
//);

//   ila_dispatch ila_dispatch_inst (
//   	.clk(clk), // input wire clk


//   	.probe0(wr_a_counter), // input wire [31:0]  probe0  
//   	.probe1(wr_b_counter), // input wire [31:0]  probe1 
//   	.probe2(rd_sum_cnt) // input wire [31:0]  probe2
//   );

endmodule
