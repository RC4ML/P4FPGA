`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2020/04/26 18:41:52
// Design Name: 
// Module Name: sgd_x_to_memory_read_data
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

module sgd_x_to_memory_read_data(
    input   wire                                   clk,
    input   wire                                   rst_n,
    //--------------------------Begin/Stop-----------------------------//
    input   wire                                   started,

    //---------Input: Parameters (where, how many) from the root module-------//
    input   wire [63:0]                            addr_model,

    input   wire [31:0]                            dimension,
    input   wire [31:0]                            numEpochs,

    ///////////////////rd part of x_updated_fifo//////////////////////
    input   wire [`ENGINE_NUM-1:0][511:0]          x_to_mem_rd_data,
    (* max_fanout = 64 *)output  reg  [`ENGINE_NUM-1:0]                 x_to_mem_rd_en,
    input   wire [`ENGINE_NUM-1:0]                 x_to_mem_empty,


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


//to make sure that the parameters has been assigned...
reg       started_r, started_r2, started_r3;   //one cycle delay from started...
reg [2:0] state; 
reg [3:0] error_state; //0000: ok; 0001: dimension is zero; 


    reg [1:0]                               inner_index;
    reg [8:0][1:0]                          inner_index_r;
    reg [3:0]                               engine_index;
    reg [8:0][3:0]                          engine_index_r;
    reg [31:0]                              dimension_index,dimension_index_r,dimension_minus;  
    reg [31:0]                              epoch_index;
    reg [8:0]                               rd_en_r;
    wire                                    rd_en;

    reg[511:0]                              x_data_out_pre1,x_data_out_pre2,x_data_out_pre3;
    reg                                     x_data_out_valid_pre1,x_data_out_valid_pre2,x_data_out_valid_pre3;
    reg                                     x_data_out_almost_full_r1,x_data_out_almost_full_r2,x_data_out_almost_full_r3;


    always @(posedge clk) begin
        if(~rst_n)begin
            started_r  <= 1'b0;
            started_r2 <= 1'b0;
            started_r3 <= 1'b0; //1'b0;
        end 
        else begin
            started_r  <= started;   //1'b0;
            started_r2 <= started_r; //1'b0;
            started_r3 <= started_r2; //1'b0;
        end 
    end

    always @(posedge clk) begin
        inner_index_r                       <= {inner_index_r[7:0],inner_index};
        engine_index_r                      <= {engine_index_r[7:0],engine_index};
        dimension_index_r                   <= dimension_index;
        rd_en_r                             <= {rd_en_r[7:0],rd_en};
    end

    always @(posedge clk) begin
        if(dimension < `ENGINE_NUM * `NUM_BITS_PER_BANK)
            dimension_minus                 <= 0;
        else
            dimension_minus                 <= dimension - `ENGINE_NUM * `NUM_BITS_PER_BANK;
    end

    always @(posedge clk) begin
        x_data_send_back_length             <= dimension << 2;
    end



//generate end generate
genvar i;
// Instantiate engines
generate
for(i = 0; i < `ENGINE_NUM; i++) begin    

    always @(posedge clk) begin
        if(engine_index_r[0] == i)
            x_to_mem_rd_en[i]   <= rd_en_r[0];
        else
            x_to_mem_rd_en[i]   <= 1'b0;
    end

end
endgenerate




    always @(posedge clk) begin
        if(~rst_n) begin
            x_data_out_pre1                 <= 0;  
            x_data_out_valid_pre1           <= 1'b0;                  
        end
        else if(rd_en_r[2])begin
            x_data_out_valid_pre1           <= 1'b1;
            case(inner_index_r[2])
                2'b00:begin
                    x_data_out_pre1         <= x_to_mem_rd_data[engine_index_r[2]];
                end
                2'b01:begin
                    x_data_out_pre1         <= x_to_mem_rd_data[engine_index_r[2]];
                end
                2'b10:begin
                    x_data_out_pre1         <= x_to_mem_rd_data[engine_index_r[2]];
                end
                2'b11:begin
                    x_data_out_pre1         <= x_to_mem_rd_data[engine_index_r[2]];
                end
            endcase
        end
        else begin
            x_data_out_valid_pre1           <= 1'b0;
        end
    end




    always @(posedge clk) begin
        x_data_out_pre2                     <= x_data_out_pre1;
        // x_data_out_pre3                     <= x_data_out_pre2;
        x_data_out                          <= x_data_out_pre2;
        x_data_out_valid_pre2               <= x_data_out_valid_pre1;
        // x_data_out_valid_pre3               <= x_data_out_valid_pre2;
        x_data_out_valid                    <= x_data_out_valid_pre2;
        x_data_out_almost_full_r1           <= x_data_out_almost_full;
        // x_data_out_almost_full_r2           <= x_data_out_almost_full_r1;
        // x_data_out_almost_full_r3           <= x_data_out_almost_full_r2;
    end

    

    localparam [3:0]    IDLE            = 4'b0001,
                        WRITE_MEM_EPOCH = 4'b0010,
                        WRITE_MEM_DATA  = 4'b0100,
                        WRITE_MEM_WAIT  = 4'b0101,
                        WRITE_MEM_END   = 4'b1000;

    reg [3:0]                           cstate,nstate;   
    
    reg [3:0]                           wait_counter;

    always@(posedge clk)begin
        if(cstate == WRITE_MEM_WAIT)begin
            wait_counter                <= wait_counter + 1'b1;
        end
        else begin
            wait_counter                <= 0;
        end
    end

    assign rd_en                        = ~x_data_out_almost_full_r1 & (cstate == WRITE_MEM_DATA);


    always @(posedge clk) begin
        if(~rst_n)
            cstate                      <= IDLE;
        else
            cstate                      <= nstate;
    end

    always @(*) begin
        case(cstate)
            IDLE:begin
                if(started_r3)
                    nstate              = WRITE_MEM_EPOCH;
                else
                    nstate              = IDLE;
            end
            WRITE_MEM_EPOCH:begin
                if(epoch_index == numEpochs)begin
                    nstate              = WRITE_MEM_END;
                end
                if(~x_to_mem_empty[0])begin
                    nstate              = WRITE_MEM_DATA;
                end
                else begin
                    nstate              = WRITE_MEM_EPOCH;
                end
            end
            WRITE_MEM_DATA:begin
                if(rd_en) begin
                    nstate                      = WRITE_MEM_DATA;
                    if(inner_index == 2'b11) begin
                        nstate                  = WRITE_MEM_DATA;
                        if(engine_index >= `ENGINE_NUM-1)begin
                            nstate              = WRITE_MEM_DATA;
                            if(dimension_index >= dimension_minus)begin
                                nstate          = WRITE_MEM_WAIT;
                            end
                        end
                    end
                end
            end
            WRITE_MEM_WAIT:begin
                if(wait_counter == 4'd4)begin
                    nstate          = WRITE_MEM_EPOCH;
                end
                else begin
                    nstate          = WRITE_MEM_WAIT;
                end
            end            
            WRITE_MEM_END:begin
                nstate                          = IDLE;
            end
        endcase
    end

    always @(posedge clk) begin
        case(cstate)
            IDLE:begin
                inner_index                     <= 1'b0;
                engine_index                    <= 8'b0;
                dimension_index                 <= 32'b0;
                epoch_index                     <= 32'b0;

                x_data_send_back_start          <= 1'b0;
                x_data_send_back_addr           <= addr_model;

            end
            WRITE_MEM_EPOCH:begin
                x_data_send_back_start          <= 1'b0;
                if(epoch_index == numEpochs)begin
                end
                if(~x_to_mem_empty[0])begin
                    epoch_index                 <= epoch_index + 1'b1;
                    x_data_send_back_start      <= 1'b1;
                    x_data_send_back_addr       <= x_data_send_back_addr + x_data_send_back_length;
                end
                else begin
                end
            end
            WRITE_MEM_DATA:begin
                if(rd_en) begin
                    inner_index         <= inner_index + 1 ;
                    if(inner_index == 2'b11) begin
                        engine_index    <= engine_index + 1;
                        if(engine_index >= `ENGINE_NUM-1)begin
                            engine_index        <= 0;
                            dimension_index     <= dimension_index + `ENGINE_NUM * `NUM_BITS_PER_BANK;
                            if(dimension_index >= dimension_minus)begin
                                dimension_index <= 0;
                            end
                        end
                    end
                end
            end
            WRITE_MEM_END:begin
            end
        endcase
    end



endmodule
