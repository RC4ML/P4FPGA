`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2020/03/30 20:49:55
// Design Name: 
// Module Name: hbm_read
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

module hbm_read#(
    parameter ADDR_WIDTH      = 33 ,  // 8G-->33 bits
    parameter DATA_WIDTH      = 256,  // 512-bit for DDR4
    parameter PARAMS_BITS     = 256,  // parameter bits from PCIe
    parameter ID_WIDTH        = 6     //fixme,
)(
    input wire                  hbm_clk,
    input wire                  hbm_aresetn,

    //--------------------------Begin/Stop-----------------------------//
    input   wire                                   start,
    output  reg                                    mem_op_done,

    //---------Input: Parameters (where, how many) from the root module-------//
    input   wire [32:0]                            addr_a,
    input   wire [32:0]                            addr_b,
    //input   wire [63:0]                            addr_model,
    input   wire [31:0]                            number_of_epochs,
    input   wire [31:0]                            number_of_samples,
    input   wire [31:0]                            dimension,
    input   wire [31:0]                            number_of_bits, 
    input   wire [7 :0]                            engine_id,
    input   wire [31:0]                            araddr_stride,
    output  reg                                     hbm_read_done,
    //---------------------Memory Inferface----------------------------//

    //Read Address (Output)  
    output                      m_axi_ARVALID , //rd address valid
    output reg [ADDR_WIDTH - 1:0]  m_axi_ARADDR  , //rd byte address
    output reg   [ID_WIDTH - 1:0]  m_axi_ARID    , //rd address id
    output reg              [3:0]  m_axi_ARLEN   , //rd burst=awlen+1,
    output reg              [2:0]  m_axi_ARSIZE  , //rd 3'b101, 32B
    output reg              [1:0]  m_axi_ARBURST , //rd burst type: 01 (INC), 00 (FIXED)
    output reg              [1:0]  m_axi_ARLOCK  , //rd no
    output reg              [3:0]  m_axi_ARCACHE , //rd no
    output reg              [2:0]  m_axi_ARPROT  , //rd no
    output reg              [3:0]  m_axi_ARQOS   , //rd no
    output reg              [3:0]  m_axi_ARREGION, //rd no
    output reg              [5:0]  m_axi_ARUSER  ,
    input                       m_axi_ARREADY,  //rd ready to accept address.

    ///
    output reg [31:0]               rd_sum_cnt,
    output reg [31:0]               rd_addr_cnt
    );

    reg                                     start_d0,start_d1;
    
    always @(posedge hbm_clk) begin
        start_d0                            <= start;
        start_d1                            <= start_d0;
    end



    reg [ID_WIDTH - 1:0]                        hbm_arid;
    reg [32:0]                                  channel_base_addr;
    reg [32:0]                                  hbm_araddr;
    reg [32:0]                                  hbm_base_addr;      
    reg [31:0]                                  offset_addr_of_sample;
    reg [31:0]                                  num_CLs_per_bank;
    reg [31:0]                                  main_counter;
    reg [31:0]                                  epoch_index;
    reg [31:0]                                  numEpochs;
    reg [31:0]                                  addr_b_index;
    reg [31:0]                                  addr_a_index;
    reg [ 7:0]                                  a_bits_cnt;  
    reg [31:0]                                  dimension_minus;
    reg [31:0]                                  samples_minus;
    reg [ 7:0]                                  bits_minus;
    reg [31:0]                                  a_sample_cnt;
    reg [31:0]                                  a_feature_cnt;
    reg                                         need_to_entry_B,need_to_entry_B_reg;
    reg [31:0]                                  number_of_samples_r;  
    reg [31:0]                                  dimension_r;   
    
    localparam [7:0]                AR_IDLE             = 8'b00000001,
                                    AR_START            = 8'b00000010,
                                    AR_EPOCH            = 8'b00000100,
                                    AR_LOAD_B_ADDR      = 8'b00001000,
                                    AR_B_ADDR           = 8'b00010000,
                                    AR_LOAD_A_ADDR      = 8'b00100000,
                                    AR_A_ADDR           = 8'b01000000,
                                    AR_END              = 8'b10000000;

    reg[7:0]                                    cstate;
    reg[7:0]                                    nstate;    




    always @(posedge hbm_clk) begin
        dimension_r                         <= dimension;
        if(dimension_r <= (`NUM_BITS_PER_BANK * `ENGINE_NUM * 2))
            dimension_minus                 <= 32'b0;
        else 
            dimension_minus                 <= dimension_r - (`NUM_BITS_PER_BANK * `ENGINE_NUM * 2);
    end

    always @(posedge hbm_clk) begin
        number_of_samples_r             <= number_of_samples;
        samples_minus                   <= number_of_samples_r - `NUM_OF_BANKS;
    end

    always @(posedge hbm_clk) begin
        bits_minus                      <= number_of_bits - 2;
    end    


    always @(posedge hbm_clk) begin
        m_axi_ARLEN             <= 4'h3;
        m_axi_ARSIZE            <= (DATA_WIDTH==256)? 3'b101:3'b110; //just for 256-bit or 512-bit.
        m_axi_ARBURST           <= 2'b01;   // INC, not FIXED (00)
        m_axi_ARLOCK            <= 2'b00;   // Normal memory operation
        m_axi_ARCACHE           <= 4'b0000; // 4'b0011: Normal, non-cacheable, modifiable, bufferable (Xilinx recommends)
        m_axi_ARPROT            <= 3'b010;  // 3'b000: Normal, secure, data
        m_axi_ARQOS             <= 4'b0000; // Not participating in any Qos schem, a higher value indicates a higher priority transaction
        m_axi_ARREGION          <= 4'b0000; // Region indicator, default to 0
        channel_base_addr       <= engine_id << 28;
        main_counter            <= dimension_r[31 :(`BIT_WIDTH_OF_BANK+`ENGINE_NUM_WIDTH+1)] + (dimension_r[`BIT_WIDTH_OF_BANK+`ENGINE_NUM_WIDTH:0] != 0);
        num_CLs_per_bank        <= main_counter << 7;
        need_to_entry_B_reg     <= ( (addr_a_index[4:0] == 4'h0) & (addr_a_index[31:5] != 28'h0)  );
        numEpochs               <= number_of_epochs;        
    end
    
    assign  m_axi_ARVALID                   = cstate[4] | cstate[6];
    assign m_axi_ARADDR                     = hbm_araddr;
    assign m_axi_ARID                       = hbm_arid;




    always @(posedge hbm_clk)begin
        if(~hbm_aresetn)
            cstate                          <= AR_IDLE;
        else
            cstate                          <= nstate;
    end

    always @(*) begin
        case(cstate)
            AR_IDLE:begin
                if(start_d0 & ~start_d1)
                    nstate                  = AR_START;
                else
                    nstate                  = AR_IDLE;
            end
            AR_START:begin
                nstate                      = AR_EPOCH;
            end
            AR_EPOCH:begin
                nstate                      = AR_LOAD_B_ADDR;
                if(epoch_index == numEpochs)
                    nstate                  = AR_END;
                else
                    nstate                  = AR_LOAD_B_ADDR;
            end
            AR_LOAD_B_ADDR:begin
                nstate                      = AR_B_ADDR;
            end
            AR_B_ADDR:begin
                if(m_axi_ARVALID & m_axi_ARREADY) begin      
                    nstate                  = AR_LOAD_A_ADDR;
                end
                else begin
                    nstate                  = AR_B_ADDR;
                end
            end
            AR_LOAD_A_ADDR:begin
                if(a_sample_cnt >= number_of_samples_r) begin
                    nstate                  = AR_EPOCH;
                end
                else if(need_to_entry_B_reg & need_to_entry_B) begin
                    nstate                  = AR_LOAD_B_ADDR;
                end
                else begin
                    nstate                  = AR_A_ADDR;                    
                end
            end            
            AR_A_ADDR:begin
                if(m_axi_ARVALID & m_axi_ARREADY)begin 
                    nstate                  = AR_A_ADDR;
                    if(a_bits_cnt >= bits_minus) begin
                        nstate              = AR_A_ADDR;
                        if(a_feature_cnt >= dimension_minus) begin
                            nstate          = AR_LOAD_A_ADDR;
                        end
                    end 
                    else begin
                        nstate              = AR_A_ADDR;
                    end
                end
                else begin
                    nstate                  = AR_A_ADDR;
                end
            end
            AR_END:begin
                nstate                      = AR_IDLE;
            end
        endcase
    end


    always @(posedge hbm_clk) begin
        case(cstate)
            AR_IDLE:begin
                hbm_read_done               <= 0;
            end
            AR_START:begin
                epoch_index                 <= 0;
            end
            AR_EPOCH:begin
                a_sample_cnt                <= 0;
                a_feature_cnt               <= 0;
                hbm_base_addr               <= 0;
                hbm_araddr                  <= 0;
                addr_b_index                <= 0;
                addr_a_index                <= 0;                                
                a_bits_cnt                  <= 0;
                offset_addr_of_sample       <= 0;
                epoch_index                 <= epoch_index + 1'b1;
            end
            AR_LOAD_B_ADDR:begin
                hbm_arid                    <= `MEM_RD_B_TAG;
                hbm_araddr                  <= channel_base_addr + addr_b + (addr_b_index << 2);  
            end
            AR_B_ADDR:begin
                need_to_entry_B             <= 0;
                if(m_axi_ARVALID & m_axi_ARREADY) begin
                    addr_b_index            <= addr_b_index + 32;        
                end
            end
            AR_LOAD_A_ADDR:begin               
                if(a_sample_cnt >= number_of_samples_r) begin
                end
                else if(need_to_entry_B_reg & need_to_entry_B) begin
                end
                else begin
                    hbm_arid                    <= `MEM_RD_A_TAG;
                    addr_a_index                <= addr_a_index + `NUM_OF_BANKS;
                    offset_addr_of_sample       <= offset_addr_of_sample + num_CLs_per_bank;
                    hbm_araddr                  <= channel_base_addr + addr_a + offset_addr_of_sample; 
                    hbm_base_addr               <= channel_base_addr + addr_a + offset_addr_of_sample;  
                    need_to_entry_B             <= 1;                
                end
            end            
            AR_A_ADDR:begin
                if(m_axi_ARVALID & m_axi_ARREADY)begin
                    a_bits_cnt                  <= a_bits_cnt + 2;
                    if(a_bits_cnt >= bits_minus) begin
                        a_bits_cnt              <= 0;
                        hbm_base_addr           <= hbm_base_addr + 32'h80;
                        hbm_araddr              <= hbm_base_addr + 32'h80;
                        a_feature_cnt           <= a_feature_cnt + `NUM_BITS_PER_BANK * `ENGINE_NUM * 2;
                        if(a_feature_cnt >= dimension_minus) begin
                            a_feature_cnt       <= 0;
                            a_sample_cnt        <= a_sample_cnt + `NUM_OF_BANKS;
                        end
                    end 
                    else begin
                        hbm_araddr              <= hbm_araddr + araddr_stride;
                    end
                end
            end
            AR_END:begin
                hbm_read_done                   <= 1;
            end
        endcase
    end



//////////////////////////////debug TH CNT//////////////////////////////////
    //reg [31:0]          rd_sum_cnt,rd_addr_cnt;
    reg                 rd_sum_cnt_en;

    always @(posedge hbm_clk)begin
        if(~hbm_aresetn)
            rd_sum_cnt_en                       <= 1'b0;
        else if(start_d0 & ~start_d1)
            rd_sum_cnt_en                       <= 1'b1;
        else if(hbm_read_done)
            rd_sum_cnt_en                       <= 1'b0;
        else
            rd_sum_cnt_en                       <= rd_sum_cnt_en;
    end


    always @(posedge hbm_clk)begin
        if(~hbm_aresetn)
            rd_sum_cnt                       <= 1'b0;
        else if(start_d0 & ~start_d1)
            rd_sum_cnt                       <= 1'b0;
        else if(rd_sum_cnt_en)
            rd_sum_cnt                       <= rd_sum_cnt + 1'b1;
        else
            rd_sum_cnt                       <= rd_sum_cnt;
    end

    always @(posedge hbm_clk)begin
        if(~hbm_aresetn)
            rd_addr_cnt                       <= 1'b0;
        else if(start_d0 & ~start_d1)
            rd_addr_cnt                       <= 1'b0;
        else if(m_axi_ARVALID & m_axi_ARREADY)
            rd_addr_cnt                       <= rd_addr_cnt + 1'b1;
        else
            rd_addr_cnt                       <= rd_addr_cnt;
    end    


// ila_hbm_read ila_hbm_read_inst (
// 	.clk(hbm_clk), // input wire clk


// 	.probe0(m_axi_ARVALID), // input wire [0:0]  probe0  
// 	.probe1(m_axi_ARREADY), // input wire [0:0]  probe1 
// 	.probe2(m_axi_ARID), // input wire [5:0]  probe2 
// 	.probe3(m_axi_ARADDR), // input wire [32:0]  probe3 
// 	.probe4(epoch_index), // input wire [31:0]  probe4 
// 	.probe5(addr_b_index), // input wire [31:0]  probe5 
// 	.probe6(addr_a_index), // input wire [31:0]  probe6 
// 	.probe7(a_bits_cnt), // input wire [7:0]  probe7 
// 	.probe8(a_sample_cnt), // input wire [31:0]  probe8 
// 	.probe9(a_feature_cnt), // input wire [31:0]  probe9 
// 	.probe10(cstate), // input wire [7:0]  probe10 
// 	.probe11(rd_sum_cnt), // input wire [31:0]  probe11
//    .probe12(rd_addr_cnt) // input wire [31:0]  probe12
// );
//  ila_hbm_read ila_hbm_read_inst (
//  	.clk(hbm_clk), // input wire clk


//  	.probe0(rd_sum_cnt), // input wire [31:0]  probe0  
//  	.probe1(rd_addr_cnt) // input wire [31:0]  probe1
//  );

endmodule
