`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 05/19/2020 02:16:44 PM
// Design Name: 
// Module Name: sgd_dsp_add_tree
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
//NUM_OF_BANKS_WIDTH

module sgd_dsp_add_tree #(
    parameter TREE_DEPTH          = 3,
    parameter TREE_WIDTH          = 2**TREE_DEPTH,//8//TREE_DEPTH**2 //
    parameter TREE_TRI_DEPTH      = 2,
    parameter TREE_TRI_WIDTH      = 3**TREE_TRI_DEPTH
)(
    input   wire                                   clk,
    input   wire                                   rst_n,
    //--------------------------Begin/Stop-----------------------------//

    //---------------------Input: External Memory rd response-----------------//
    input   wire  signed                    [31:0] v_input[TREE_WIDTH-1:0],       //
    input   wire                                   v_input_valid,  //
    input   wire                                   v_input_enable[TREE_WIDTH-1:0],

    //------------------Output: disptach resp data to b of each bank---------------//
    output  wire signed                     [31:0] v_output, 
    output  wire                                    v_output_valid 
);



wire signed [47:0]  dsp_intermdiate_result[TREE_WIDTH/4-1:0]; 
reg  signed [31:0]  v_intermdiate_result[TREE_DEPTH-2:0][TREE_WIDTH/8-1:0];
reg [TREE_DEPTH-1:0] v_intermdiate_result_valid;





genvar d,w; 

generate 
    for( d = 0; d < TREE_WIDTH/4; d = d + 1) begin: inst_adder_tree_depth_first 
        wire [47:0] PCOUT;
        dsp48_add_first dsp48_add_first_inst (
            .CLK(clk),                // input wire CLK
            .C(v_input[4*d]),                    // input wire [31 : 0] C
            .CONCAT(v_input[4*d+1]),          // input wire [31 : 0] CONCAT
            .PCOUT(PCOUT),            // output wire [47 : 0] PCOUT
            .P(),                    // output wire [32 : 0] P
            .SCLRCONCAT(~v_input_enable[4*d+1]),  // input wire SCLRCONCAT
            .SCLRC(~v_input_enable[4*d])            // input wire SCLRC
          );    

          dsp48_add dsp48_add_inst (
            .CLK(clk),                // input wire CLK
            .PCIN(PCOUT),              // input wire [47 : 0] PCIN
            .C(v_input[4*d+2]),                    // input wire [31 : 0] C
            .CONCAT(v_input[4*d+3]),          // input wire [31 : 0] CONCAT
            .P(dsp_intermdiate_result[d]),                    // output wire [47 : 0] P
            .SCLRCONCAT(~v_input_enable[4*d+3]),  // input wire SCLRCONCAT
            .SCLRC(~v_input_enable[4*d+2])            // input wire SCLRC
          );
    end 
endgenerate

generate 
    for( d = 0; d < TREE_DEPTH-2; d = d + 1) begin: inst_adder_tree_depth 
        for( w = 0; w < ( TREE_WIDTH/(2**(d+3)) ); w = w + 1) begin: inst_adder_tree_width
            always @(posedge clk) begin
                if(d == 0) begin
                    v_intermdiate_result[d][w]     <= dsp_intermdiate_result[2*w] + dsp_intermdiate_result[2*w+1];
                end 
                else begin
                    v_intermdiate_result[d][w]     <= v_intermdiate_result[d-1][2*w] + v_intermdiate_result[d-1][2*w+1];
                end
            end 
        end
    end 
endgenerate



generate 
    for( d = 0; d < TREE_DEPTH; d = d + 1) begin: inst_adder_tree_valid 

    always @(posedge clk) 
    begin 
            if(d == 0) begin
                v_intermdiate_result_valid[d]     <= v_input_valid;
            end 
            else begin
                v_intermdiate_result_valid[d]     <= v_intermdiate_result_valid[d-1];
            end             
    end
end 
endgenerate  
   

/*
always @(posedge clk or negedge rst_n) 
begin 
    if(~rst_n) 
        v_intermdiate_result_valid[TREE_DEPTH-1:0]  <= { TREE_DEPTH{1'b0} };
    else
     begin
        generate 
            for( d = 0; d < TREE_DEPTH; d = d + 1) begin: inst_adder_tree_valid 
                if(d == 0) begin
                    v_intermdiate_result_valid[d]     <= v_input_valid[0];
                end 
                else begin
                    v_intermdiate_result_valid[d]     <= v_intermdiate_result_valid[d-1];
                end             
            end 
        endgenerate        
     end
end
*/
assign v_output       = v_intermdiate_result[TREE_DEPTH-3][0]; 
assign v_output_valid = v_intermdiate_result_valid[TREE_DEPTH-1]; 

endmodule
