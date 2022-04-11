`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2020/03/06 13:15:24
// Design Name: 
// Module Name: hbm_write
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

module hbm_write#(
    parameter ADDR_WIDTH      = 33 ,  // 8G-->33 bits
    parameter DATA_WIDTH      = 256,  // 512-bit for DDR4
    parameter PARAMS_BITS     = 256,  // parameter bits from PCIe
    parameter ID_WIDTH        = 6     //fixme,
)(
    input wire                  hbm_clk,
    input wire                  hbm_aresetn,

    /* DMA INTERFACE */
    //Commands
    axis_mem_cmd.master         m_axis_dma_read_cmd,
    // axis_mem_cmd.master         m_axis_dma_write_cmd,

    //Data streams
    // axi_stream.master           m_axis_dma_write_data,
    axi_stream.slave            s_axis_dma_read_data,

    //signal

    input wire                  start,
    input wire [31:0]           data_a_length,  //need to multiple of 512
    input wire [31:0]           data_b_length,  //need to multiple of 512
    input wire [63:0]           dma_addr_a,
    input wire [63:0]           dma_addr_b,
    input wire [32:0]           hbm_addr_b,  
    input wire [31:0]           number_of_samples,  
    input wire [31:0]           dimension,
    input wire [31:0]           number_of_bits,  
    input wire [31:0]           araddr_stride,   

    output reg                  hbm_write_done,               
    output reg [31:0]           hbm_waddr_state,
    output reg [31:0]           hbm_wdata_state,
    output reg [31:0]           hbm_write_cycle_cnt,
    output reg [31:0]           hbm_write_addr_cnt,
    output reg [31:0]           hbm_write_data_cnt, 
    /* HBM INTERFACE */
    //Write addr (output)
    output                        m_axi_AWVALID , //wr address valid
    output reg [ADDR_WIDTH - 1:0] m_axi_AWADDR  , //wr byte address
    output reg [  ID_WIDTH - 1:0] m_axi_AWID    , //wr address id
    output reg              [3:0] m_axi_AWLEN   , //wr burst=awlen+1,
    output reg              [2:0] m_axi_AWSIZE  , //wr 3'b101, 32B
    output reg              [1:0] m_axi_AWBURST , //wr burst type: 01 (INC), 00 (FIXED)
    output reg              [1:0] m_axi_AWLOCK  , //wr no
    output reg              [3:0] m_axi_AWCACHE , //wr no
    output reg              [2:0] m_axi_AWPROT  , //wr no
    output reg              [3:0] m_axi_AWQOS   , //wr no
    output reg              [3:0] m_axi_AWREGION, //wr no
    input                         m_axi_AWREADY , //wr ready to accept address.

    //Write data (output)  
    output                        m_axi_WVALID  , //wr data valid
    output wire [DATA_WIDTH - 1:0] m_axi_WDATA   , //wr data
    output reg [DATA_WIDTH/8-1:0] m_axi_WSTRB   , //wr data strob
    output                        m_axi_WLAST   , //wr last beat in a burst
    output reg   [ID_WIDTH - 1:0] m_axi_WID     , //wr data id
    input                         m_axi_WREADY  , //wr ready to accept data

    //Write response (input)  
    input                      m_axi_BVALID  , 
    input                [1:0] m_axi_BRESP   ,
    input     [ID_WIDTH - 1:0] m_axi_BID     ,
    output                     m_axi_BREADY  

    );           
    //
    reg                                     start_d0,start_d1;

    reg[7:0]                                cstate;
    reg[7:0]                                nstate;

    reg[7:0]                                wcstate;
    reg[7:0]                                wnstate;

    
    always @(posedge hbm_clk) begin
        start_d0                            <= start;
        start_d1                            <= start_d0;
    end


    /*dma read cmd logic*/

    reg [64:0]                              dma_read_cmd_address;
    reg [31:0]                              dma_read_cmd_length;

    assign m_axis_dma_read_cmd.valid        = cstate[1] | cstate[4];
    assign m_axis_dma_read_cmd.address      = dma_read_cmd_address;
    assign m_axis_dma_read_cmd.length       = dma_read_cmd_length;


    /*dma to hbm fifo*/
    //dam to hbm signal
    reg                                     dma2hbm_fifo_wr_en;
    reg  [511:0]                            dma2hbm_fifo_data_in;
    wire                                    dma2hbm_fifo_rd_en;
    reg                                     dma2hbm_fifo_rd_en_d;
    wire                                    dma2hbm_fifo_full;
    wire                                    dma2hbm_fifo_empty;
    wire                                    dma2hbm_fifo_valid;
    wire [7:0]                              dma2hbm_fifo_count;
    wire [256:0]                            dma2hbm_fifo_data;
    // reg [511:0]                             dma2hbm_fifo_data_out;
    reg                                     dma2hbm_fifo_rd_en_reg;
    reg                                     wdata_valid_reg;
    // reg                                     axi_data_flag,axi_data_flag_r;



    assign s_axis_dma_read_data.ready       = ~dma2hbm_fifo_full;
    assign dma2hbm_fifo_rd_en               = m_axi_WREADY & m_axi_WVALID;
    
    always @(posedge hbm_clk)begin
        dma2hbm_fifo_wr_en                  <= s_axis_dma_read_data.ready & s_axis_dma_read_data.valid;
        dma2hbm_fifo_data_in                <= s_axis_dma_read_data.data;
    end

//    always @(posedge hbm_clk) begin
//        if(s_axis_dma_read_data.ready & s_axis_dma_read_data.valid)
//            dma2hbm_fifo_wr_en              <= 1'b1;
//        else
//            dma2hbm_fifo_wr_en              <= 1'b0;
//    end

//    always @(posedge hbm_clk) begin
//        dma2hbm_fifo_data_in                <= s_axis_dma_read_data.data;
//    end


    // fifo_512wr_256rd_1024d inst_dma2hbm_fifo (
    // .clk(hbm_clk),                      // input wire clk
    // .srst(~hbm_aresetn),                    // input wire srst
    // .din(dma2hbm_fifo_data_in),                      // input wire [511 : 0] din
    // .wr_en(dma2hbm_fifo_wr_en),                  // input wire wr_en
    // .rd_en(dma2hbm_fifo_rd_en),                  // input wire rd_en
    // .dout(dma2hbm_fifo_data),                    // output wire [255 : 0] dout
    // .full(dma2hbm_fifo_full),                    // output wire full
    // .empty(dma2hbm_fifo_empty),                  // output wire empty
    // .valid(dma2hbm_fifo_valid),                  // output wire valid
    // .rd_data_count(dma2hbm_fifo_count),  // output wire [9 : 0] rd_data_count
    // .wr_rst_busy(),      // output wire wr_rst_busy
    // .rd_rst_busy()      // output wire rd_rst_busy
    // );

    fifo_512wr_256rd_1024d inst_dma2hbm_fifo (
    .clk(hbm_clk),                  // input wire clk
    .srst(~hbm_aresetn),                // input wire srst
    .din(dma2hbm_fifo_data_in),                  // input wire [511 : 0] din
    .wr_en(dma2hbm_fifo_wr_en),              // input wire wr_en
    .rd_en(dma2hbm_fifo_rd_en),              // input wire rd_en
    .dout(dma2hbm_fifo_data),                // output wire [511 : 0] dout
    .full(),                // output wire full
    .empty(dma2hbm_fifo_empty),              // output wire empty
    .valid(dma2hbm_fifo_valid),              // output wire valid
    .prog_full(dma2hbm_fifo_full),      // output wire prog_full
    .wr_rst_busy(),  // output wire wr_rst_busy
    .rd_rst_busy()  // output wire rd_rst_busy
    );


    //
    reg [32:0]                              hbm_awaddr;
    reg [31:0]                              b_sample_cnt;
    reg [31:0]                              a_feature_cnt;
    reg [31:0]                              a_sample_cnt;
    reg [7:0]                               a_bits_cnt;
    reg                                     a_bits_change;
    reg [4:0]                               channel_num;
    reg [31:0]                              dimension_align;
    reg [31:0]                              dimension_minus;
    reg [31:0]                              samples_minus;
    reg [31:0]                              bits_minus;
    reg [31:0]                              base_addr;


    reg [7:0]                               burst_inc;
    reg [31:0]                              wr_ops;
    reg [31:0]                              num_mem_ops_minus_1;
    reg                                     wr_data_done;
    reg [3:0]                               end_cnt;
    
    always @(posedge hbm_clk) begin
        dimension_align                 <= (dimension[`BIT_WIDTH_OF_BANK + `ENGINE_NUM_WIDTH:0] == 0)? dimension : (dimension[31:`BIT_WIDTH_OF_BANK + `ENGINE_NUM_WIDTH+1] + 1) << (`BIT_WIDTH_OF_BANK + `ENGINE_NUM_WIDTH+1);
        dimension_minus                 <= dimension_align - `NUM_BITS_PER_BANK * `ENGINE_NUM;
    end

    always @(posedge hbm_clk) begin
        samples_minus                   <= number_of_samples - `NUM_OF_BANKS;
    end

    always @(posedge hbm_clk) begin
        bits_minus                      <= number_of_bits - 2;
    end    


    /////////////////Parameters with fixed values////////////////
    always @(posedge hbm_clk) begin
        m_axi_AWID        <= {ID_WIDTH{1'b0}};
        m_axi_AWLEN       <= 4'h1;    
        m_axi_AWSIZE      <= (DATA_WIDTH==256)? 3'b101:3'b110; //just for 256-bit or 512-bit.
        m_axi_AWBURST     <= 2'b01;   // INC, not FIXED (00)
        m_axi_AWLOCK      <= 2'b00;   // Normal memory operation
        m_axi_AWCACHE     <= 4'b0000; //4'b0011; // Normal, non-cacheable, modifiable, bufferable (Xilinx recommends)
        m_axi_AWPROT      <= 3'b010; //3'b000;  // Normal, secure, data
        m_axi_AWQOS       <= 4'b0000; // Not participating in any Qos schem, a higher value indicates a higher priority transaction
        m_axi_AWREGION    <= 4'b0000; // Region indicator, default to 0
    
        //m_axi_WDATA       <= dma2hbm_fifo_data;        //data port
        
        m_axi_WSTRB       <= {(DATA_WIDTH/8){1'b1}};    
        m_axi_WID         <= {ID_WIDTH{1'b0}};          //maybe play with it. 
        // dma2hbm_fifo_rd_en_d <= dma2hbm_fifo_rd_en;
    end

    // always @(posedge hbm_clk) begin
    //     dma2hbm_fifo_data_out <= dma2hbm_fifo_data;
    // end

    assign m_axi_AWVALID                    = cstate[3] | cstate[6];
    assign m_axi_AWADDR                     = hbm_awaddr;
    assign m_axi_BREADY                     = 1'b1;    //always ready to accept data...
    assign m_axi_WVALID                     = (wcstate[2] | wcstate[4]) & ~dma2hbm_fifo_empty;// || axi_data_flag_r;
    assign m_axi_WLAST                      = (burst_inc==m_axi_AWLEN)& m_axi_WVALID &m_axi_WREADY;

    assign m_axi_WDATA                      = dma2hbm_fifo_data;







    localparam [7:0]                IDLE                = 8'b00000001,
                                    SEND_READ_B_CMD     = 8'b00000010,
                                    LOAD_B_ADDR         = 8'b00000100,
                                    WRITE_B_ADDR        = 8'b00001000,
                                    SEND_READ_A_CMD     = 8'b00010000,
                                    LOAD_A_ADDR         = 8'b00100000,
                                    WRITE_A_ADDR        = 8'b01000000,
                                    WRITE_END           = 8'b10000000;

    localparam [7:0]                WIDLE               = 8'b00000001,
                                    W_B_DATA_JUDGE      = 8'b00000010,
                                    W_B_DATA            = 8'b00000100,
                                    W_A_DATA_JUDGE      = 8'b00001000,
                                    W_A_DATA            = 8'b00010000,
                                    W_DATA_END          = 8'b00100000,
                                    W_WAIT              = 8'b01000000;
    // localparam [3:0]                WIDLE               = 4'h1,
    //                                 W_B_DATA_JUDGE      = 4'h2,
    //                                 W_B_DATA            = 4'h3,
    //                                 W_A_DATA_JUDGE      = 4'h4,
    //                                 W_A_DATA            = 4'h5,
    //                                 W_DATA_END          = 4'h6,
    //                                 W_WAIT              = 4'h7;                                   

    

    always @(posedge hbm_clk)begin
        if(~hbm_aresetn)
            cstate                          <= IDLE;
        else
            cstate                          <= nstate;
    end

    always @(*)begin
        case(cstate)
            IDLE:begin
                if(start_d0 & ~start_d1)begin
                    nstate                  <= SEND_READ_A_CMD;
                end
                else begin
                    nstate                  <= IDLE;
                end
            end
            // SEND_READ_B_CMD:begin
            //     if(m_axis_dma_read_cmd.valid && m_axis_dma_read_cmd.ready) begin
            //         nstate                  <= LOAD_B_ADDR;                    
            //     end
            //     else begin
            //         nstate                  <= SEND_READ_B_CMD;
            //     end
            // end
            // LOAD_B_ADDR:begin
            //     // if(dma2hbm_fifo_count > m_axi_AWLEN)begin
            //         nstate                  <= WRITE_B_ADDR;
            //     // end
            //     // else begin
            //         // nstate                  = LOAD_B_ADDR;
            //     // end
            // end
            // WRITE_B_ADDR:begin
            //     if(m_axi_AWVALID & m_axi_AWREADY)begin
            //         nstate                  <= WRITE_B_ADDR;
            //         if(b_sample_cnt >= (number_of_samples - 16)) begin
            //             nstate              <= SEND_READ_A_CMD;
            //         end
            //     end
            //     else begin
            //         nstate                  <= WRITE_B_ADDR;
            //     end
            // end
            SEND_READ_A_CMD:begin
                if(m_axis_dma_read_cmd.valid && m_axis_dma_read_cmd.ready) begin
                    nstate                  <= LOAD_A_ADDR;                    
                end
                else begin
                    nstate                  <= SEND_READ_A_CMD;
                end
            end
            LOAD_A_ADDR:begin
                // if(dma2hbm_fifo_count > m_axi_AWLEN)begin
                    nstate                  <= WRITE_A_ADDR;
                // end
                // else begin
                //     nstate                  = LOAD_A_ADDR;
                // end
            end                    
            WRITE_A_ADDR:begin
                if(m_axi_AWVALID & m_axi_AWREADY)begin
                    nstate                  <= WRITE_A_ADDR;
                    if(a_feature_cnt >= dimension_minus) begin
                        nstate              <= WRITE_A_ADDR;
                        if(a_sample_cnt >= samples_minus) begin
                            nstate          <= LOAD_A_ADDR;
                            if(channel_num >= (2 * `ENGINE_NUM-1))begin
                                nstate          <= LOAD_A_ADDR;
                                if(a_bits_cnt >= bits_minus) begin
                                    nstate      <= WRITE_END;
                                end
                            end
                        end
                    end
                end
                else begin
                    nstate                  <= WRITE_A_ADDR;
                end
            end      
            WRITE_END:begin
                nstate                      <=  IDLE;
            end
        endcase
    end

    always @(posedge hbm_clk)begin
        case(cstate)
            IDLE:begin
                if(start_d0 & ~start_d1)begin
                    dma_read_cmd_address    <= dma_addr_a;
                    dma_read_cmd_length     <= data_a_length;
                    b_sample_cnt            <= 0;
                    a_feature_cnt           <= 0;
                    a_sample_cnt            <= 0;
                    a_bits_cnt              <= 0;
                    a_bits_change           <= 0;
                    channel_num             <= 0;
                    base_addr               <= 0;
                end
            end
            // SEND_READ_B_CMD:begin
            // end
            // LOAD_B_ADDR:begin
            //     hbm_awaddr                  <= hbm_addr_b;
            // end
            // WRITE_B_ADDR:begin
            //     if(m_axi_AWVALID & m_axi_AWREADY)begin
            //         hbm_awaddr              <= hbm_awaddr + 32'h40;
            //         b_sample_cnt            <= b_sample_cnt + 16;
            //     end
            //     dma_read_cmd_address    <= dma_addr_a;
            //     dma_read_cmd_length     <= data_a_length;
            // end
            SEND_READ_A_CMD:begin
                hbm_awaddr                      <= 0;
            end
            LOAD_A_ADDR:begin
                if(channel_num == (2 * `ENGINE_NUM - 1))begin
                    hbm_awaddr                  <= {channel_num,base_addr[27:0]};  
                    base_addr                   <= base_addr + araddr_stride;
                end
                else begin
                    hbm_awaddr                  <= {channel_num,base_addr[27:0]};          
                end    
            end                    
            WRITE_A_ADDR:begin
                if(m_axi_AWVALID & m_axi_AWREADY)begin
                    hbm_awaddr              <= hbm_awaddr + 32'h40;
                    a_feature_cnt           <= a_feature_cnt + `NUM_BITS_PER_BANK * `ENGINE_NUM;
                    if(a_feature_cnt >= dimension_minus) begin
                        a_feature_cnt       <= 0;
                        a_sample_cnt        <= a_sample_cnt + 8;
                        if(a_sample_cnt >= samples_minus) begin
                            a_sample_cnt    <= 0;
                            channel_num     <= channel_num + 1;
                            if(channel_num >= (2 * `ENGINE_NUM-1))begin
                                channel_num     <= 0;
                                a_bits_cnt      <= a_bits_cnt + 2;
                                if(a_bits_cnt >= bits_minus) begin
                                    a_bits_cnt  <= 0;
                                end
                            end
                        end
                    end
                end
            end      
            WRITE_END:begin
            end
        endcase
    end








    // always @(posedge hbm_clk) begin
    //     if(~hbm_aresetn) begin
    //         wdata_valid_reg     <= 1'b0;
    //     end
    //     else if(m_axi_WREADY) begin
    //         wdata_valid_reg     <= dma2hbm_fifo_rd_en;                 
    //     end
    //     else begin
    //         wdata_valid_reg     <= wdata_valid_reg;
    //     end
    // end


    always @(posedge hbm_clk) begin
        if (~hbm_aresetn) begin
            burst_inc                 <=  8'b0;
            wr_ops                    <= 32'b0;
            // wr_data_done              <=  1'b0;
        end
        // else if (wr_data_done & m_axi_WVALID & m_axi_WREADY)begin
        //     burst_inc                 <=  burst_inc + 8'b1;
        //     wr_data_done              <=  1'b0;
        //     wr_ops                    <= 32'b0;
        // end
        // else if(wr_data_done) begin
        //     burst_inc                 <=  1'b0;
        //     wr_data_done              <=  1'b0;
        //     wr_ops                    <= 32'b0;            
        // end
        else if (m_axi_WVALID & m_axi_WREADY) begin
            burst_inc             <= burst_inc + 8'b1;
            if (burst_inc == m_axi_AWLEN)begin
                burst_inc         <= 8'b0;
                wr_ops            <= wr_ops + 1'b1;
                if (wr_ops == num_mem_ops_minus_1)begin
                    wr_ops  <=  32'b0;
                end
            end    
        end        
    end

    always @(posedge hbm_clk)begin
        if(~hbm_aresetn) begin
            num_mem_ops_minus_1             <= 32'b0;
        end
        // else if(wcstate == W_B_DATA_JUDGE) begin
        //     num_mem_ops_minus_1             <= (data_b_length >> 6) - 1;
        // end
        else if(wcstate == W_A_DATA_JUDGE) begin
            num_mem_ops_minus_1             <= (data_a_length >> 6) - 1;
        end
        else 
            num_mem_ops_minus_1             <= num_mem_ops_minus_1;
    end

    // always @(posedge hbm_clk)begin
    //     if(~hbm_aresetn)
    //         axi_data_flag                   <= 1'b0;
    //     else if(dma2hbm_fifo_rd_en & m_axi_WREADY)
    //         axi_data_flag                   <= 1'b1;   
    //     else if(axi_data_flag & m_axi_WREADY)
    //         axi_data_flag                   <= 1'b0;
    //     else
    //         axi_data_flag                   <= axi_data_flag;
    // end

    // always @(posedge hbm_clk)begin
    //     axi_data_flag_r                     <= axi_data_flag;

    // end


    always @(posedge hbm_clk)begin
        if(~hbm_aresetn)
            wcstate                         <= WIDLE;
        else
            wcstate                         <= wnstate;
    end
        
    always @(*)begin
        case(wcstate)
            WIDLE:begin
                // hbm_write_done              <= 1'b0;
                if(start_d0 & ~start_d1)begin
                    wnstate                 <= W_A_DATA_JUDGE;
                end
                else begin
                    wnstate                 <= WIDLE;
                end
            end
            // W_B_DATA_JUDGE:begin
            //     if(~dma2hbm_fifo_empty) begin
            //         wnstate                 <= W_B_DATA;
            //     end
            //     else begin
            //         wnstate                 <= W_B_DATA_JUDGE;
            //     end
            // end
            // W_B_DATA:begin
            //     if(m_axi_WVALID & m_axi_WREADY) begin                    
            //         if(m_axi_WLAST) begin
            //             if(wr_ops == num_mem_ops_minus_1)begin
            //                 wnstate         <= W_WAIT;
            //             end
            //             else begin
            //                 wnstate         <= W_B_DATA;
            //             end
            //         end
            //         else begin
            //             wnstate             <= W_B_DATA;
            //         end
            //     end
            //     else begin
            //         wnstate                 <= W_B_DATA;
            //     end
            // end
            // W_WAIT:begin
            //     wnstate                     <= W_A_DATA_JUDGE;
            // end
            W_A_DATA_JUDGE:begin
                if(~dma2hbm_fifo_empty) begin
                    wnstate                 <= W_A_DATA;
                end
                else begin
                    wnstate                 <= W_A_DATA_JUDGE;
                end
            end
            W_A_DATA:begin
                if(m_axi_WVALID & m_axi_WREADY) begin
                    if(m_axi_WLAST) begin
                        if(wr_ops == num_mem_ops_minus_1)begin
                            wnstate         <= W_DATA_END;
                        end
                        else begin
                            wnstate         <= W_A_DATA;
                        end
                    end
                    else begin
                        wnstate             <= W_A_DATA;
                    end
                end
                else begin
                    wnstate                 <= W_A_DATA;
                end
            end   
            W_DATA_END:begin
                // if(end_cnt[3])
                    wnstate                 <= WIDLE;
                // else
                    // wnstate                 <= W_DATA_END;
                // hbm_write_done              <= 1'b1;
            end
        endcase
    end 

     always @(posedge hbm_clk)begin
        if(~hbm_aresetn)
            hbm_write_done                       <= 1'b0;
        else if(wcstate == W_DATA_END)
            hbm_write_done                       <= 1'b1;
        else
            hbm_write_done                       <= 0;
    end    

    //  always @(posedge hbm_clk)begin
    //     if(~hbm_aresetn)
    //         end_cnt                       <= 1'b0;
    //     else if(wcstate == W_DATA_END)
    //         end_cnt                       <= end_cnt + 1'b1;
    //     else
    //         end_cnt                       <= 0;
    // end
 
                

//////////////////////////////debug TH CNT//////////////////////////////////
    reg [31:0]          wr_sum_cnt,wr_addr_cnt,wr_data_cnt;
    reg                 wr_sum_cnt_en;

    always @(posedge hbm_clk)begin
        if(~hbm_aresetn)
            wr_sum_cnt_en                       <= 1'b0;
        else if(start_d0 & ~start_d1)
            wr_sum_cnt_en                       <= 1'b1;
        else if(hbm_write_done)
            wr_sum_cnt_en                       <= 1'b0;
        else
            wr_sum_cnt_en                       <= wr_sum_cnt_en;
    end


    always @(posedge hbm_clk)begin
        if(~hbm_aresetn)
            wr_sum_cnt                       <= 1'b0;
        else if(start_d0 & ~start_d1)
            wr_sum_cnt                       <= 1'b0;
        else if(wr_sum_cnt_en)
            wr_sum_cnt                       <= wr_sum_cnt + 1'b1;
        else
            wr_sum_cnt                       <= wr_sum_cnt;
    end

    always @(posedge hbm_clk)begin
        if(~hbm_aresetn)
            wr_addr_cnt                       <= 1'b0;
        else if(start_d0 & ~start_d1)
            wr_addr_cnt                       <= 1'b0;
        else if(m_axi_AWVALID & m_axi_AWREADY)
            wr_addr_cnt                       <= wr_addr_cnt + 1'b1;
        else
            wr_addr_cnt                       <= wr_addr_cnt;
    end

    always @(posedge hbm_clk)begin
        if(~hbm_aresetn)
            wr_data_cnt                       <= 1'b0;
        else if(start_d0 & ~start_d1)
            wr_data_cnt                       <= 1'b0;
        else if(m_axi_WVALID & m_axi_WREADY)
            wr_data_cnt                       <= wr_data_cnt + 1'b1;
        else
            wr_data_cnt                       <= wr_data_cnt;
    end

    always @(posedge hbm_clk)begin
        hbm_waddr_state                         <= cstate;
        hbm_wdata_state                         <= wcstate;
        hbm_write_cycle_cnt                     <= wr_sum_cnt;
        hbm_write_addr_cnt                      <= wr_addr_cnt;
        hbm_write_data_cnt                      <= wr_data_cnt;   
    end     

/////////////debug ila////////////////////


// ila_hbm_write ila_hbm_write_inst (
// 	.clk(hbm_clk), // input wire clk


// 	.probe0(m_axi_AWVALID), // input wire [0:0]  probe0  
// 	.probe1(m_axi_AWREADY), // input wire [0:0]  probe1 
// 	.probe2(m_axi_AWADDR), // input wire [32:0]  probe2 
// 	.probe3(m_axi_WVALID), // input wire [0:0]  probe3 
// 	.probe4(m_axi_WREADY), // input wire [0:0]  probe4 
// 	.probe5(m_axi_WLAST), // input wire [0:0]  probe5 
// 	.probe6(m_axi_WDATA), // input wire [255:0]  probe6 
// 	.probe7(dma2hbm_fifo_wr_en), // input wire [0:0]  probe7 
//    .probe8(dma2hbm_fifo_rd_en), // input wire [0:0]  probe8 
// 	.probe9(wr_addr_cnt), // input wire [31:0]  probe9 
// 	.probe10(wr_data_cnt), // input wire [31:0]  probe10     
// 	.probe11(b_sample_cnt), // input wire [31:0]  probe11 
// 	.probe12(a_feature_cnt), // input wire [31:0]  probe12 
// 	.probe13(a_sample_cnt), // input wire [31:0]  probe13 
// 	.probe14(a_bits_cnt), // input wire [7:0]  probe14 
// 	.probe15(channel_num), // input wire [4:0]  probe15 
// 	.probe16(cstate), // input wire [7:0]  probe16 
// 	.probe17({dma2hbm_fifo_empty,wcstate[6:0]}) // input wire [7:0]  probe17 
// //	.probe18(wr_sum_cnt) // input wire [31:0]  probe18
// );   


//ila_hbm_write ila_hbm_write_inst (
//	.clk(hbm_clk), // input wire clk


//	.probe0(m_axi_AWVALID), // input wire [0:0]  probe0  
//	.probe1(m_axi_AWREADY), // input wire [0:0]  probe1 
//	.probe2(m_axi_AWADDR), // input wire [32:0]  probe2 
//	.probe3(m_axi_WVALID), // input wire [0:0]  probe3 
//	.probe4(m_axi_WREADY), // input wire [0:0]  probe4 
//	.probe5(m_axi_WLAST), // input wire [0:0]  probe5 
//	.probe6(m_axi_WDATA), // input wire [255:0]  probe6 
//	.probe7(dma2hbm_fifo_wr_en), // input wire [0:0]  probe7 
//   .probe8(dma2hbm_fifo_rd_en) // input wire [0:0]  probe8 
////	.probe9(dma2hbm_fifo_data_in) // input wire [511:0]  probe9 
//);  

// ila_hbm_write ila_hbm_write_inst (
// 	.clk(hbm_clk), // input wire clk


// 	.probe0(wr_sum_cnt), // input wire [31:0]  probe0  
// 	.probe1(wr_data_cnt), // input wire [31:0]  probe1 
// 	.probe2(wr_addr_cnt) // input wire [31:0]  probe2
// );

endmodule
