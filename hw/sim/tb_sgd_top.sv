`timescale 1ns / 1ns
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2020/02/11 13:32:27
// Design Name: 
// Module Name: tb_sgd_bw_top
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

module tb_sgd_bw_top(

    );

    reg                                 clk,rst_n;
    reg                                   start_um;
    reg [511:0]                           um_params;

    reg [63:0] addr_a;
    reg [63:0] addr_b;
    reg [63:0] addr_model;
    reg [31:0] mini_batch_size;
    reg [31:0] step_size;
    reg [31:0] number_of_epochs;
    reg [31:0] dimension;
    reg [31:0] number_of_samples;
    reg [31:0] number_of_bits;    

    reg[511:0] a[`ENGINE_NUM-1:0][29056:0];
    reg[31:0] b[7291:0];


    // TX RD
    //wire  [57:0]                           hbm_axi.araddr; //reg
    wire  [7:0]                            um_tx_rd_tag;  //reg
    wire                                   um_tx_rd_valid;//reg
    wire                                   um_tx_rd_ready; //connected to almost full signal. Send one more request after full signal.
    // RX RD
    
    
    wire                                   um_rx_rd_valid;
    wire                                   um_rx_rd_ready;

    reg [`ENGINE_NUM-1:0][`NUM_BITS_PER_BANK*`NUM_OF_BANKS-1:0]   dispatch_axb_a_data;
    reg [`ENGINE_NUM-1:0]                                         dispatch_axb_a_wr_en;
    wire [`ENGINE_NUM-1:0]                                   dispatch_axb_a_almost_full;

    reg                  [32*`NUM_OF_BANKS-1:0]  dispatch_axb_b_data;
    reg                                          dispatch_axb_b_wr_en;
    wire                                        dispatch_axb_b_almost_full;

    axi_stream #(.WIDTH(512))       m_axis_tx_data();
    axi_stream #(.WIDTH(512))       s_axis_rx_data();

    assign um_params = {128'b0,number_of_bits,number_of_samples,dimension,number_of_epochs,step_size,mini_batch_size,addr_model,addr_b,addr_a};

    always @(posedge clk) 
    begin 
            addr_a           <= 0; //no need of [5:0], cache line aligned... Mohsen
            addr_b           <= 32'h20000000;
            addr_model       <= 32'h40000000;
            mini_batch_size  <= 16;
            step_size        <= 16;
            number_of_epochs <= 3;
            dimension        <= 48128;//21504;    
            number_of_samples<= 72320;
            number_of_bits   <= 4;    
    end


    initial begin
        // $readmemh("/home/amax/hhj/distributed_sgd/a_ups.txt",a,0,1866496);
        $readmemh("/home/amax/hhj/distributed_sgd/dis_sim_data/engine2/ups0.txt",a[0],0,28800);
        $readmemh("/home/amax/hhj/distributed_sgd/dis_sim_data/engine2/ups1.txt",a[1],0,28800);
        $readmemh("/home/amax/hhj/distributed_sgd/b_ups.txt",b,0,7291);
        clk = 1'b1;
        rst_n = 1'b0;
        start_um = 1'b0;
        #1000
        rst_n = 1'b1;
        #1000
        start_um = 1'b1;
    end

    always #5 clk = ~clk;



//generate end generate
genvar i;
// Instantiate engines
generate
for(i = 0; i < `ENGINE_NUM; i++) 
begin  

    reg [31:0]              bits_cnt;
    reg                     bits_flag;
    reg                     dimension_flag;
    reg [31:0]              dimension_cnt;
    reg [31:0]              a_sample_cnt;
    reg [31:0]              a_addr;

    // always @(posedge clk)begin
    //     if(~rst_n) begin
    //         bits_cnt                        <= 0;
    //         bits_flag                       <= 0;
    //         dimension_flag                  <= 0;
    //         dimension_cnt                   <= 0;
    //         a_sample_cnt                    <= 0;
    //     end
    //     else if(dispatch_axb_a_wr_en[i]) begin
    //         bits_flag <= bits_flag + 1;
    //         if(bits_flag) begin
    //             dimension_flag <= dimension_flag +1;
    //             if(dimension_flag) begin
    //                 bits_cnt <= bits_cnt + 2;
    //                 if(bits_cnt >= number_of_bits - 2) begin 
    //                     bits_cnt <= 0;
    //                     dimension_cnt <= dimension_cnt + `NUM_BITS_PER_BANK * `ENGINE_NUM * 2;
    //                     if(dimension_cnt >= (dimension-`NUM_BITS_PER_BANK * `ENGINE_NUM * 2)) begin
    //                         dimension_cnt <= 0;
    //                         a_sample_cnt <= a_sample_cnt + `NUM_OF_BANKS;
    //                         if(a_sample_cnt >= number_of_samples - `NUM_OF_BANKS) begin

    //                         end
    //                     end
    //                 end
    //             end
    //         end
    //     end
    //     else begin
    //         bits_cnt                        <= bits_cnt;
    //         bits_flag                       <= bits_flag;
    //         dimension_flag                  <= dimension_flag;
    //         dimension_cnt                   <= dimension_cnt;
    //         a_sample_cnt                    <= a_sample_cnt;        
    //     end
    // end

    always @(posedge clk)begin
        if(~rst_n)
            dispatch_axb_a_wr_en[i]     <= 0;
        else if(a_sample_cnt >= number_of_samples)
            dispatch_axb_a_wr_en[i]     <= 0;
        else if(~dispatch_axb_a_almost_full[i])
            dispatch_axb_a_wr_en[i]     <= 1;
        else
            dispatch_axb_a_wr_en[i]     <= 0;
    end

    // assign a_addr = (a_sample_cnt * dimension * 32)/(`NUM_OF_BANKS * `NUM_BITS_PER_BANK) +  (((dimension_cnt + dimension_flag * `NUM_BITS_PER_BANK * `ENGINE_NUM + i * `NUM_BITS_PER_BANK)/2)) + (bits_cnt + bits_flag);

    always @(posedge clk)begin
        if(~rst_n)
            a_addr                      <= 0;
        else if(a_addr == ((number_of_samples<<1) - 1))
            a_addr                      <= 0;
        else if(dispatch_axb_a_wr_en[i])
            a_addr                      <= a_addr + 1'b1;
        else begin
            a_addr                      <= a_addr;
        end        
    end

    // assign dispatch_axb_a_data[i]     = {a[a_addr*16+15],a[a_addr*16+14],a[a_addr*16+13],a[a_addr*16+12],a[a_addr*16+11],a[a_addr*16+10],a[a_addr*16+9],a[a_addr*16+8],
    //                                     a[a_addr*16+7],a[a_addr*16+6],a[a_addr*16+5],a[a_addr*16+4],a[a_addr*16+3],a[a_addr*16+2],a[a_addr*16+1],a[a_addr*16]};
    assign dispatch_axb_a_data[i]     = a[i][a_addr];

end
endgenerate

    reg [31:0]              b_cnt;

    always @(posedge clk)begin
        if(~rst_n)
            b_cnt     <= 0;
        else if(b_cnt == ((number_of_samples>>3) - 1))
            b_cnt     <= 0;            
        else if(~dispatch_axb_b_almost_full)
            b_cnt     <= b_cnt + 1;
        else
            b_cnt     <= b_cnt;
    end

    // always @(posedge clk)begin
    //     if(~rst_n)
    //         dispatch_axb_b_wr_en     <= 0;
    //     else if(b_cnt >= (number_of_samples>>3))
    //         dispatch_axb_b_wr_en     <= 0;
    //     else if(~dispatch_axb_b_almost_full)
    //         dispatch_axb_b_wr_en     <= 1;
    //     else
    //         dispatch_axb_b_wr_en     <= 0;
    // end


    assign     dispatch_axb_b_wr_en = rst_n ? ~dispatch_axb_b_almost_full : 0;

    // always @(posedge clk)begin
    //     if(~dispatch_axb_b_almost_full)
    //         dispatch_axb_b_data     <= {b[b_cnt*8+7],b[b_cnt*8+6],b[b_cnt*8+5],b[b_cnt*8+4],b[b_cnt*8+3],b[b_cnt*8+2],b[b_cnt*8+1],b[b_cnt*8]};
    //     else
    //         dispatch_axb_b_data     <= dispatch_axb_b_data;
    // end

    assign dispatch_axb_b_data = {b[b_cnt*8+7],b[b_cnt*8+6],b[b_cnt*8+5],b[b_cnt*8+4],b[b_cnt*8+3],b[b_cnt*8+2],b[b_cnt*8+1],b[b_cnt*8]};

    reg [5000:0][511:0]     delay_data;
    reg [5000:0][63:0]      delay_keep;
    reg [5000:0]            delay_last;
    reg [5000:0]            delay_valid;

    always @(posedge clk)begin
        if(~rst_n)begin
      
            delay_data     <= 0;
            delay_keep     <= 0;
            delay_last     <= 0;
            delay_valid    <= 0;             
        end
        else begin
            delay_data[0]       <= m_axis_tx_data.data;
            delay_keep[0]       <= m_axis_tx_data.keep;
            delay_last[0]       <= m_axis_tx_data.last;
            delay_valid[0]      <= m_axis_tx_data.valid;       
            delay_data[5000:1]     <= delay_data[4999:0];
            delay_keep[5000:1]     <= delay_keep[4999:0];
            delay_last[5000:1]     <= delay_last[4999:0];
            delay_valid[5000:1]     <= delay_valid[4999:0]; 
        end
    end

    assign s_axis_rx_data.data = delay_data[0];
    assign s_axis_rx_data.keep = delay_keep[0];
    assign s_axis_rx_data.last = delay_last[0];
    assign s_axis_rx_data.valid = delay_valid[0];


sgd_top_bw #( 
    .DATA_WIDTH_IN               (4),
    .MAX_DIMENSION_BITS          (18),
    .SLR0_ENGINE_NUM                                (0),
    .SLR1_ENGINE_NUM                                (8),
    .SLR2_ENGINE_NUM                                (0)
)sgd_top_bw_inst (
    .clk                                (clk),
    .rst_n                              (rst_n),
    .dma_clk                            (clk),
    .hbm_clk                            (clk),
    //-------------------------------------------------//
    .start_um                           (start_um),
    .addr_model                         (addr_model),
    .mini_batch_size                    (mini_batch_size),
    .step_size                          (step_size),
    .number_of_epochs                   (number_of_epochs),
    .dimension                          (dimension),
    .number_of_samples                  (number_of_samples),
    .number_of_bits                     (number_of_bits),
    .um_done                            (),
    .um_state_counters                  (),

    .m_axis_tx_data                     (m_axis_tx_data),  
    .s_axis_rx_data                     (s_axis_rx_data),


    .dispatch_axb_a_data                (dispatch_axb_a_data),
    .dispatch_axb_a_wr_en               (dispatch_axb_a_wr_en),
    .dispatch_axb_a_almost_full         (dispatch_axb_a_almost_full),

    .dispatch_axb_b_data                (dispatch_axb_b_data),
    .dispatch_axb_b_wr_en               (dispatch_axb_b_wr_en),
    .dispatch_axb_b_almost_full         (dispatch_axb_b_almost_full),
    //---------------------Memory Inferface:write----------------------------//
    //cmd
    .x_data_send_back_start             (),
    .x_data_send_back_addr              (),
    .x_data_send_back_length            (),

    //data
    .x_data_out                         (),
    .x_data_out_valid                   (),
    .x_data_out_almost_full             (0)

);











endmodule