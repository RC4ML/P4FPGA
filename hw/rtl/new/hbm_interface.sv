`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2020/03/06 00:47:07
// Design Name: 
// Module Name: hbm_interface
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

module hbm_interface(
    input wire                  user_clk,
    input wire                  user_aresetn,

    input wire                  hbm_clk,
    input wire                  hbm_rstn,

    input wire                  dma_clk,
    input wire                  dma_aresetn,    

    //mlweaving parameter
    input wire [63:0]           addr_a,
    input wire [63:0]           addr_b,
    input wire [63:0]           addr_model,
    input wire [31:0]           mini_batch_size,
    input wire [31:0]           step_size,
    input wire [31:0]           number_of_epochs,
    input wire [31:0]           dimension,
    input wire [31:0]           number_of_samples,
    input wire [31:0]           number_of_bits,
    input wire [31:0]           data_a_length,
    input wire [31:0]           array_length,
    input wire [31:0]           channel_choice,
    input wire                      start,

    output wire [63:0][31:0]    hbm_status,
    /* DMA INTERFACE */
    //Commands
    axis_mem_cmd.master         m_axis_dma_read_cmd,
    // axis_mem_cmd.master         m_axis_dma_write_cmd,

    //Data streams
    // axi_stream.master           m_axis_dma_write_data,
    axi_stream.slave            s_axis_dma_read_data,
    
    /* HBM INTERFACE */
    axi_mm.master                hbm_axi[31:0],

    //-------------------------------------------------//
    output   reg                                   start_um,
    // input   wire [511:0]                           um_params,


    output reg[`ENGINE_NUM-1:0][`NUM_BITS_PER_BANK*`NUM_OF_BANKS-1:0]   dispatch_axb_a_data_o,
    output reg[`ENGINE_NUM-1:0]                                         dispatch_axb_a_wr_en_o,
    input wire [`ENGINE_NUM-1:0]                                   dispatch_axb_a_almost_full,

    output reg                 [32*`NUM_OF_BANKS-1:0]  dispatch_axb_b_data_o,
    output reg                                         dispatch_axb_b_wr_en_o,
    input  wire                                    dispatch_axb_b_almost_full

    );
    
    

 /*
  * Clock Conversion Command
  */

    axis_mem_cmd                m_axis_dma_to_hbm_read_cmd();
    axis_mem_cmd                m_axis_dma_to_hbm_write_cmd();

    axi_stream                  s_axis_dma_to_hbm_read_data();
    axi_stream                  m_axis_dma_to_hbm_write_data();

    axi_stream                  s_axis_reg_read_data();
    axi_stream                  m_axis_reg_write_data();    
    
    axis_clock_converter_96 hbm_bench_read_cmd_cc_inst (
    .s_axis_aresetn(hbm_rstn),
    .s_axis_aclk(hbm_clk),
    .s_axis_tvalid(m_axis_dma_to_hbm_read_cmd.valid),   // input wire s_axis_tvalid
    .s_axis_tready(m_axis_dma_to_hbm_read_cmd.ready),   // output wire s_axis_tready
    .s_axis_tdata({m_axis_dma_to_hbm_read_cmd.length,m_axis_dma_to_hbm_read_cmd.address}),
    
    .m_axis_aresetn(dma_aresetn),
    .m_axis_aclk(dma_clk),
    .m_axis_tvalid(m_axis_dma_read_cmd.valid),  // output wire m_axis_tvalid
    .m_axis_tready(m_axis_dma_read_cmd.ready),  // input wire m_axis_tready
    .m_axis_tdata({m_axis_dma_read_cmd.length,m_axis_dma_read_cmd.address})
    );

    //  axis_clock_converter_96 hbm_bench_write_cmd_cc_inst (
    //  .s_axis_aresetn(hbm_rstn),
    //  .s_axis_aclk(hbm_clk),
    //  .s_axis_tvalid(m_axis_dma_to_hbm_write_cmd.valid),
    //  .s_axis_tready(m_axis_dma_to_hbm_write_cmd.ready),
    //  .s_axis_tdata({m_axis_dma_to_hbm_write_cmd.length,m_axis_dma_to_hbm_write_cmd.address}),
    
    //  .m_axis_aresetn(user_aresetn),
    //  .m_axis_aclk(user_clk),
    //  .m_axis_tvalid(m_axis_dma_write_cmd.valid),
    //  .m_axis_tready(m_axis_dma_write_cmd.ready),
    //  .m_axis_tdata({m_axis_dma_write_cmd.length,m_axis_dma_write_cmd.address})
    //  );




    //axis_clock_converter_512 dma_bench_read_data_cc_inst (
    axis_register_slice_512 inst_axis_register_slice_read (
    .aclk(dma_clk),                    // input wire aclk
    .aresetn(dma_aresetn),              // input wire aresetn
    .s_axis_tvalid(s_axis_dma_read_data.valid),  // input wire s_axis_tvalid
    .s_axis_tready(s_axis_dma_read_data.ready),  // output wire s_axis_tready
    .s_axis_tdata(s_axis_dma_read_data.data),    // input wire [511 : 0] s_axis_tdata
    .s_axis_tkeep(s_axis_dma_read_data.keep),    // input wire [63 : 0] s_axis_tkeep
    .s_axis_tlast(s_axis_dma_read_data.last),    // input wire s_axis_tlast
    .m_axis_tvalid(s_axis_reg_read_data.valid),  // output wire m_axis_tvalid
    .m_axis_tready(s_axis_reg_read_data.ready),  // input wire m_axis_tready
    .m_axis_tdata(s_axis_reg_read_data.data),    // output wire [511 : 0] m_axis_tdata
    .m_axis_tkeep(s_axis_reg_read_data.keep),    // output wire [63 : 0] m_axis_tkeep
    .m_axis_tlast(s_axis_reg_read_data.last)    // output wire m_axis_tlast
    );

    axis_data_fifo_512_cc hbm_bench_read_data_cc_inst (
    .s_axis_aresetn(dma_aresetn),
    .s_axis_aclk(dma_clk),
    .s_axis_tvalid(s_axis_reg_read_data.valid),
    .s_axis_tready(s_axis_reg_read_data.ready),
    .s_axis_tdata(s_axis_reg_read_data.data),
    .s_axis_tkeep(s_axis_reg_read_data.keep),
    .s_axis_tlast(s_axis_reg_read_data.last),

    .m_axis_aclk(hbm_clk),
    .m_axis_tvalid(s_axis_dma_to_hbm_read_data.valid),
    .m_axis_tready(s_axis_dma_to_hbm_read_data.ready),
    .m_axis_tdata(s_axis_dma_to_hbm_read_data.data),
    .m_axis_tkeep(s_axis_dma_to_hbm_read_data.keep),
    .m_axis_tlast(s_axis_dma_to_hbm_read_data.last)
    
    );


     //axis_clock_converter_512 dma_bench_write_data_cc_inst (
//      axis_register_slice512 inst_axis_register_slice_write (
//      .aclk(dma_clk),                    // input wire aclk
//      .aresetn(dma_aresetn),              // input wire aresetn
//      .s_axis_tvalid(m_axis_reg_write_data.valid),  // input wire s_axis_tvalid
//      .s_axis_tready(m_axis_reg_write_data.ready),  // output wire s_axis_tready
//      .s_axis_tdata(m_axis_reg_write_data.data),    // input wire [511 : 0] s_axis_tdata
//      .s_axis_tkeep(m_axis_reg_write_data.keep),    // input wire [63 : 0] s_axis_tkeep
//      .s_axis_tlast(m_axis_reg_write_data.last),    // input wire s_axis_tlast
//      .m_axis_tvalid(m_axis_dma_write_data.valid),  // output wire m_axis_tvalid
//      .m_axis_tready(m_axis_dma_write_data.ready),  // input wire m_axis_tready
//      .m_axis_tdata(m_axis_dma_write_data.data),    // output wire [511 : 0] m_axis_tdata
//      .m_axis_tkeep(m_axis_dma_write_data.keep),    // output wire [63 : 0] m_axis_tkeep
//      .m_axis_tlast(m_axis_dma_write_data.last)    // output wire m_axis_tlast
//      );

    //  axis_data_fifo_512_cc hbm_bench_write_data_cc_inst (
    //  .s_axis_aresetn(hbm_rstn),
    //  .s_axis_aclk(hbm_clk),
    //  .s_axis_tvalid(m_axis_dma_to_hbm_write_data.valid),
    //  .s_axis_tready(m_axis_dma_to_hbm_write_data.ready),
    //  .s_axis_tdata(m_axis_dma_to_hbm_write_data.data),
    //  .s_axis_tkeep(m_axis_dma_to_hbm_write_data.keep),
    //  .s_axis_tlast(m_axis_dma_to_hbm_write_data.last),
    
    //  .m_axis_aclk(user_clk),
    //  .m_axis_tvalid(m_axis_reg_write_data.valid),
    //  .m_axis_tready(m_axis_reg_write_data.ready),
    //  .m_axis_tdata(m_axis_reg_write_data.data),
    //  .m_axis_tkeep(m_axis_reg_write_data.keep),
    //  .m_axis_tlast(m_axis_reg_write_data.last)
    //  );

    reg                         start_d1,start_d2;

    always @(posedge hbm_clk) begin
        start_d1    <= start;
        start_d2    <= start_d1;
    end 



    //MLWEAVING PARAMETER REG
    reg [31:0]                  data_b_length;
    wire                        hbm_write_done;
    reg [4:0]                   b_data_channel;


    always @(posedge hbm_clk) begin
        if(~hbm_rstn) begin
            data_b_length       <= 32'b0;
        end
        else begin
            data_b_length       <= number_of_samples << 2;    
        end  
    end          

    always @(posedge hbm_clk) begin
        b_data_channel          <= `B_DATA_CHANNEL;
    end


    hbm_write#(
        .ADDR_WIDTH          (33 ),  // 8G-->33 bits
        .DATA_WIDTH          (256),  // 512-bit for DDR4
        .PARAMS_BITS         (256),  // parameter bits from PCIe
        .ID_WIDTH            (6  )   //fixme,
    )hbm_write_inst(
    .hbm_clk                (hbm_clk),
    .hbm_aresetn            (hbm_rstn),

    /* DMA INTERFACE */
    //Commands
    .m_axis_dma_read_cmd    (m_axis_dma_to_hbm_read_cmd),
    // .m_axis_dma_write_cmd   (m_axis_dma_to_hbm_write_cmd),

    //Data streams
    // .m_axis_dma_write_data  (m_axis_dma_to_hbm_write_data),
    .s_axis_dma_read_data   (s_axis_dma_to_hbm_read_data),

    //signal

    .start                  (start_d1 & ~start_d2),
    .data_a_length          (data_a_length),  //need to multiple of 512
    .data_b_length          (data_b_length),  //need to multiple of 512
    .dma_addr_a             (addr_a),
    .dma_addr_b             (addr_b),
    .hbm_addr_b             ({b_data_channel,28'h8000000}),  
    .number_of_samples      (number_of_samples),  
    .dimension              (dimension),
    .number_of_bits         (number_of_bits),  
    .araddr_stride          (array_length),    
    .hbm_write_done         (hbm_write_done),              

    .hbm_waddr_state        (hbm_status[0]),
    .hbm_wdata_state        (hbm_status[1]),
    .hbm_write_cycle_cnt    (hbm_status[2]),
    .hbm_write_addr_cnt     (hbm_status[3]),
    .hbm_write_data_cnt     (hbm_status[4]),    
    /* HBM INTERFACE */
    //Write addr (output)
    .m_axi_AWADDR     (hbm_axi[`B_DATA_CHANNEL].awaddr  ), //wr byte address
    .m_axi_AWBURST    (hbm_axi[`B_DATA_CHANNEL].awburst ), //wr burst type: 01 (INC), 00 (FIXED)
    .m_axi_AWID       (hbm_axi[`B_DATA_CHANNEL].awid    ), //wr address id
    .m_axi_AWLEN      (hbm_axi[`B_DATA_CHANNEL].awlen   ), //wr burst=awlen+1,
    .m_axi_AWSIZE     (hbm_axi[`B_DATA_CHANNEL].awsize  ), //wr 3'b101, 32B
    .m_axi_AWVALID    (hbm_axi[`B_DATA_CHANNEL].awvalid ), //wr address valid
    .m_axi_AWREADY    (hbm_axi[`B_DATA_CHANNEL].awready ), //wr ready to accept address.
    .m_axi_AWLOCK     (), //wr no
    .m_axi_AWCACHE    (), //wr no
    .m_axi_AWPROT     (), //wr no
    .m_axi_AWQOS      (), //wr no
    .m_axi_AWREGION   (), //wr no

    //Write data (output)  
    .m_axi_WDATA      (hbm_axi[`B_DATA_CHANNEL].wdata  ), //wr data
    .m_axi_WLAST      (hbm_axi[`B_DATA_CHANNEL].wlast  ), //wr last beat in a burst
    .m_axi_WSTRB      (hbm_axi[`B_DATA_CHANNEL].wstrb  ), //wr data strob
    .m_axi_WVALID     (hbm_axi[`B_DATA_CHANNEL].wvalid ), //wr data valid
    .m_axi_WREADY     (hbm_axi[`B_DATA_CHANNEL].wready ), //wr ready to accept data
    .m_axi_WID        (), //wr data id

    //Write response (input)  
    .m_axi_BID        (hbm_axi[`B_DATA_CHANNEL].bid    ),
    .m_axi_BRESP      (hbm_axi[`B_DATA_CHANNEL].bresp  ),
    .m_axi_BVALID     (hbm_axi[`B_DATA_CHANNEL].bvalid ), 
    .m_axi_BREADY     (hbm_axi[`B_DATA_CHANNEL].bready )
    );  


    wire [`ENGINE_NUM*2-1:0][255:0]   hbm_read_a_data_in;
    reg  [`ENGINE_NUM*2-1:0][255:0]   hbm_read_a_data_in_r;
    wire [`ENGINE_NUM*2-1:0][255:0]   hbm_read_a_data_out;
    reg  [`ENGINE_NUM*2-1:0][255:0]   hbm_read_a_data_o;
    wire [`ENGINE_NUM*2-1:0]          hbm_read_a_wr_en;
    (* max_fanout = 64 *)reg  [`ENGINE_NUM*2-1:0]          hbm_read_a_wr_en_r;
    (* max_fanout = 64 *)reg  [`ENGINE_NUM*2-1:0]          hbm_read_a_rd_en;
    wire [`ENGINE_NUM*2-1:0]          hbm_read_a_almost_full;
    wire [`ENGINE_NUM*2-1:0]          hbm_read_a_empty;
    reg  [`ENGINE_NUM*2-1:0]          hbm_read_a_valid_o;
    wire [`ENGINE_NUM*2-1:0]          hbm_read_a_valid;


    reg  [`ENGINE_NUM-1:0][511:0]     dispatch_axb_a_data;
    reg  [`ENGINE_NUM-1:0][511:0]     dispatch_axb_a_data_r1,dispatch_axb_a_data_r2,dispatch_axb_a_data_r3,dispatch_axb_a_data_r4;
    wire [`ENGINE_NUM*2-1:0][255:0]   dispatch_axb_b_data;
    reg  [255:0]                      dispatch_axb_b_data_r1,dispatch_axb_b_data_r2,dispatch_axb_b_data_r3,dispatch_axb_b_data_r4;  
    reg  [`ENGINE_NUM-1:0]            dispatch_axb_a_wr_en;
    reg  [`ENGINE_NUM-1:0]            dispatch_axb_a_wr_en_r1,dispatch_axb_a_wr_en_r2,dispatch_axb_a_wr_en_r3,dispatch_axb_a_wr_en_r4;
    wire [`ENGINE_NUM*2-1:0]          dispatch_axb_b_wr_en;
    reg                               dispatch_axb_b_wr_en_r1,dispatch_axb_b_wr_en_r2,dispatch_axb_b_wr_en_r3,dispatch_axb_b_wr_en_r4;
//    wire [`ENGINE_NUM-1:0]            dispatch_axb_a_almost_full;
    reg  [`ENGINE_NUM-1:0]            dispatch_axb_a_almost_full_r1,dispatch_axb_a_almost_full_r2,dispatch_axb_a_almost_full_r3,dispatch_axb_a_almost_full_r4;
    wire                              almost_full;


    reg [31:0]                        data_length;
    reg [`ENGINE_NUM*2-1:0][31:0]     rd_sum_cnt;
    reg [`ENGINE_NUM*2-1:0][31:0]     rd_addr_cnt;
    reg [`ENGINE_NUM*2-1:0][31:0]     wr_a_counter;
    reg [`ENGINE_NUM*2-1:0][31:0]     wr_b_counter;
    reg [`ENGINE_NUM*2-1:0][31:0]     rd_addr_sum_cnt;

    //generate end generate
    genvar i;
    // Instantiate engines
    generate
    for(i = 0; i < `ENGINE_NUM; i++) begin

    hbm_read#(
        .ADDR_WIDTH       (33) ,  // 8G-->33 bits
        .DATA_WIDTH       (256),  // 512-bit for DDR4
        .PARAMS_BITS      (256),  // parameter bits from PCIe
        .ID_WIDTH         (6)     //fixme,
    )hbm_read0_inst(
        .hbm_clk(hbm_clk),
        .hbm_aresetn(hbm_rstn),

        //--------------------------Begin/Stop-----------------------------//
        .start(hbm_write_done),
        .mem_op_done(),

        //---------Input: Parameters (where, how many) from the root module-------//
        .addr_a(0),
        .addr_b(33'h8000000),
        .number_of_epochs(number_of_epochs),
        .number_of_samples(number_of_samples),
        .dimension(dimension),
        .number_of_bits(number_of_bits), 
        .engine_id(i*2),
        .araddr_stride(array_length),
        //---------------------Memory Inferface----------------------------//

        //Read Address (Output)  
        .m_axi_ARVALID(hbm_axi[i*2].arvalid) , //rd address valid
        .m_axi_ARADDR(hbm_axi[i*2].araddr)  , //rd byte address
        .m_axi_ARID(hbm_axi[i*2].arid)    , //rd address id
        .m_axi_ARLEN(hbm_axi[i*2].arlen)  , //rd burst=awlen+1,
        .m_axi_ARSIZE(hbm_axi[i*2].arsize)  , //rd 3'b101, 32B
        .m_axi_ARBURST(hbm_axi[i*2].arburst) , //rd burst type: 01 (INC), 00 (FIXED)
        .m_axi_ARLOCK(hbm_axi[i*2].arlock)  , //rd no
        .m_axi_ARCACHE(hbm_axi[i*2].arcache) , //rd no
        .m_axi_ARPROT(hbm_axi[i*2].arprot)  , //rd no
        .m_axi_ARQOS(hbm_axi[i*2].arqos)   , //rd no
        .m_axi_ARREGION(hbm_axi[i*2].arregion), //rd no
        .m_axi_ARUSER()  ,
        .m_axi_ARREADY(hbm_axi[i*2].arready),  //rd ready to accept address.
        .rd_sum_cnt(hbm_status[i*2+5]),
        .rd_addr_cnt(hbm_status[i*2+21])

        );

    hbm_read#(
        .ADDR_WIDTH       (33) ,  // 8G-->33 bits
        .DATA_WIDTH       (256),  // 512-bit for DDR4
        .PARAMS_BITS      (256),  // parameter bits from PCIe
        .ID_WIDTH         (6)     //fixme,
    )hbm_read1_inst(
        .hbm_clk(hbm_clk),
        .hbm_aresetn(hbm_rstn),

        //--------------------------Begin/Stop-----------------------------//
        .start(hbm_write_done),
        .mem_op_done(),

        //---------Input: Parameters (where, how many) from the root module-------//
        .addr_a(0),
        .addr_b(33'h8000000),
        .number_of_epochs(number_of_epochs),
        .number_of_samples(number_of_samples),
        .dimension(dimension),
        .number_of_bits(number_of_bits), 
        .engine_id(i*2+1),
        .araddr_stride(array_length),
        //---------------------Memory Inferface----------------------------//

        //Read Address (Output)  
        .m_axi_ARVALID(hbm_axi[i*2+1].arvalid) , //rd address valid
        .m_axi_ARADDR(hbm_axi[i*2+1].araddr)  , //rd byte address
        .m_axi_ARID(hbm_axi[i*2+1].arid)    , //rd address id
        .m_axi_ARLEN(hbm_axi[i*2+1].arlen)  , //rd burst=awlen+1,
        .m_axi_ARSIZE(hbm_axi[i*2+1].arsize)  , //rd 3'b101, 32B
        .m_axi_ARBURST(hbm_axi[i*2+1].arburst) , //rd burst type: 01 (INC), 00 (FIXED)
        .m_axi_ARLOCK(hbm_axi[i*2+1].arlock)  , //rd no
        .m_axi_ARCACHE(hbm_axi[i*2+1].arcache) , //rd no
        .m_axi_ARPROT(hbm_axi[i*2+1].arprot)  , //rd no
        .m_axi_ARQOS(hbm_axi[i*2+1].arqos)   , //rd no
        .m_axi_ARREGION(hbm_axi[i*2+1].arregion), //rd no
        .m_axi_ARUSER()  ,
        .m_axi_ARREADY(hbm_axi[i*2+1].arready),  //rd ready to accept address.
        .rd_sum_cnt(hbm_status[i*2+6]),
        .rd_addr_cnt(hbm_status[i*2+22])

        );



    hbm_dispatch 
    #(
        .DATA_WIDTH       (256),  // 512-bit for DDR4
        .ID_WIDTH         (6)     //fixme,
    )hbm_dispatch0_inst(
        .clk(hbm_clk),
        .rst_n(hbm_rstn),
        //--------------------------Begin/Stop-----------------------------//
        .start(hbm_write_done),
        .data_length(data_length),
        
        .state_counters_dispatch(),

        //---------------------Input: External Memory rd response-----------------//
        //Read Data (input)
        .m_axi_RVALID(hbm_axi[i*2].rvalid)  , //rd data valid
        .m_axi_RDATA(hbm_axi[i*2].rdata)   , //rd data 
        .m_axi_RLAST(hbm_axi[i*2].rlast)   , //rd data last
        .m_axi_RID(hbm_axi[i*2].rid)     , //rd data id
        .m_axi_RRESP(hbm_axi[i*2].rresp)   , //rd data status. 
        .m_axi_RREADY(hbm_axi[i*2].rready)  ,

        //banks = 8, bits_per_bank=64...
        //------------------Output: disptach resp data to a ofeach bank---------------//
        . dispatch_axb_a_data(hbm_read_a_data_in[i*2]), 
        . dispatch_axb_a_wr_en(hbm_read_a_wr_en[i*2]), 
        . dispatch_axb_a_almost_full(hbm_read_a_almost_full[i*2]), //only one of them is used to control...

        //------------------Output: disptach resp data to b of each bank---------------//
        .dispatch_axb_b_data(dispatch_axb_b_data[i*2]), 
        .dispatch_axb_b_wr_en(dispatch_axb_b_wr_en[i*2]),
        //input   wire                                     dispatch_axb_b_almost_full[`NUM_OF_BANKS-1:0],
        .wr_a_counter(hbm_status[i*2+37]),
 	    .wr_b_counter(hbm_status[i*2+53]), 
 	    .rd_sum_cnt(hbm_status[i*2+69])
    );
    
    
    hbm_dispatch 
    #(
        .DATA_WIDTH       (256),  // 512-bit for DDR4
        .ID_WIDTH         (6)     //fixme,
    )hbm_dispatch1_inst(
        .clk(hbm_clk),
        .rst_n(hbm_rstn),
        //--------------------------Begin/Stop-----------------------------//
        .start(hbm_write_done),
        .data_length(data_length),
        
        .state_counters_dispatch(),

        //---------------------Input: External Memory rd response-----------------//
        //Read Data (input)
        .m_axi_RVALID(hbm_axi[i*2+1].rvalid)  , //rd data valid
        .m_axi_RDATA(hbm_axi[i*2+1].rdata)   , //rd data 
        .m_axi_RLAST(hbm_axi[i*2+1].rlast)   , //rd data last
        .m_axi_RID(hbm_axi[i*2+1].rid)     , //rd data id
        .m_axi_RRESP(hbm_axi[i*2+1].rresp)   , //rd data status. 
        .m_axi_RREADY(hbm_axi[i*2+1].rready)  ,

        //banks = 8, bits_per_bank=64...
        //------------------Output: disptach resp data to a ofeach bank---------------//
        . dispatch_axb_a_data(hbm_read_a_data_in[i*2+1]), 
        . dispatch_axb_a_wr_en(hbm_read_a_wr_en[i*2+1]), 
        . dispatch_axb_a_almost_full(hbm_read_a_almost_full[i*2+1]), //only one of them is used to control...

        //------------------Output: disptach resp data to b of each bank---------------//
        .dispatch_axb_b_data(dispatch_axb_b_data[i*2+1]), 
        .dispatch_axb_b_wr_en(dispatch_axb_b_wr_en[i*2+1]),
        //input   wire                                     dispatch_axb_b_almost_full[`NUM_OF_BANKS-1:0],
        .wr_a_counter(hbm_status[i*2+38]),
 	    .wr_b_counter(hbm_status[i*2+54]), 
 	    .rd_sum_cnt(hbm_status[i*2+70])
    );  




    always @(posedge hbm_clk) begin
        hbm_read_a_wr_en_r[i*2]         <= hbm_read_a_wr_en[i*2];
        hbm_read_a_wr_en_r[i*2+1]       <= hbm_read_a_wr_en[i*2+1];
        hbm_read_a_data_in_r[i*2]          <= hbm_read_a_data_in[i*2];
        hbm_read_a_data_in_r[i*2+1]        <= hbm_read_a_data_in[i*2+1];
    end 

    inde_fifo_256w_128d inst_a0_fifo (
    .rst(~hbm_rstn),              // input wire rst
    .wr_clk(hbm_clk),        // input wire wr_clk
    .rd_clk(user_clk),        // input wire rd_clk
    .din(hbm_read_a_data_in_r[i*2]),              // input wire [255 : 0] din
    .wr_en(hbm_read_a_wr_en_r[i*2]),          // input wire wr_en
    .rd_en(hbm_read_a_rd_en[i*2]),          // input wire rd_en
    .dout(hbm_read_a_data_out[i*2]),            // output wire [255 : 0] dout
    .full(),            // output wire full
    .empty(hbm_read_a_empty[i*2]),          // output wire empty
    .valid(hbm_read_a_valid[i*2]),          // output wire valid
    .prog_full(hbm_read_a_almost_full[i*2])  // output wire prog_full
    ); 

    inde_fifo_256w_128d inst_a1_fifo (
    .rst(~hbm_rstn),              // input wire rst
    .wr_clk(hbm_clk),        // input wire wr_clk
    .rd_clk(user_clk),        // input wire rd_clk
    .din(hbm_read_a_data_in_r[i*2+1]),              // input wire [255 : 0] din
    .wr_en(hbm_read_a_wr_en_r[i*2+1]),          // input wire wr_en
    .rd_en(hbm_read_a_rd_en[i*2+1]),          // input wire rd_en
    .dout(hbm_read_a_data_out[i*2+1]),            // output wire [255 : 0] dout
    .full(),            // output wire full
    .empty(hbm_read_a_empty[i*2+1]),          // output wire empty
    .valid(hbm_read_a_valid[i*2+1]),          // output wire valid
    .prog_full(hbm_read_a_almost_full[i*2+1])  // output wire prog_full
    );

    always @(posedge user_clk) begin       
        hbm_read_a_valid_o[i*2]         <= hbm_read_a_valid[i*2];
        hbm_read_a_valid_o[i*2+1]       <= hbm_read_a_valid[i*2+1];
        hbm_read_a_data_o[i*2]          <= hbm_read_a_data_out[i*2];
        hbm_read_a_data_o[i*2+1]        <= hbm_read_a_data_out[i*2+1];
    end     
    
    always @(posedge user_clk) begin
        dispatch_axb_a_data[i]          <= {hbm_read_a_data_o[i*2+1],hbm_read_a_data_o[i*2]};
        dispatch_axb_a_wr_en[i]         <= hbm_read_a_valid_o[i*2];
    end       

    // always @(posedge user_clk) begin
    //     if((~hbm_read_a_empty[i*2+1]) && (~hbm_read_a_empty[i*2]) && (~dispatch_axb_a_almost_full_r1[i])) begin
    //         hbm_read_a_rd_en[i*2]       <= 1'b1;
    //         hbm_read_a_rd_en[i*2+1]     <= 1'b1;
    //     end
    //     else begin
    //         hbm_read_a_rd_en[i*2]       <= 1'b0;
    //         hbm_read_a_rd_en[i*2+1]     <= 1'b0;
    //     end            
    // end
    assign hbm_read_a_rd_en[i*2]        = (~hbm_read_a_empty[i*2+1]) && (~hbm_read_a_empty[i*2]) && (~dispatch_axb_a_almost_full_r1[i]);
    assign hbm_read_a_rd_en[i*2+1]      = (~hbm_read_a_empty[i*2+1]) && (~hbm_read_a_empty[i*2]) && (~dispatch_axb_a_almost_full_r1[i]);
    

///////add reg
     always @(posedge user_clk) begin
        dispatch_axb_a_almost_full_r1[i]<= dispatch_axb_a_almost_full[i];
        dispatch_axb_a_data_o[i]       <= dispatch_axb_a_data[i];
        dispatch_axb_a_wr_en_o[i]      <= dispatch_axb_a_wr_en[i];
    end  


    // ila_read_fifo probe_ila_read_fifo(
    // .clk(user_clk),

    // .probe0(hbm_read_a_rd_counter[i*2]), // input wire [8:0]
    // .probe1(hbm_read_a_rd_counter[i*2+1]), // input wire [8:0]
    // .probe2(hbm_read_a_rd_en[i*2]), // input wire [1:0]
    // .probe3(hbm_read_a_rd_en[i*2+1]), // input wire [1:0]
    // .probe4(hbm_status[i*2+37]), // input wire [32:0]
    // .probe5(hbm_status[i*2+38]) // input wire [32:0]
    // );

    end
    endgenerate


//ila_4 ila_hbm (
//	.clk(hbm_clk), // input wire clk


//	.probe0({hbm_read_a_data_in_r[1],hbm_read_a_data_in_r[0]}), // input wire [511:0]  probe0  
//	.probe1(hbm_read_a_wr_en_r[0]), // input wire [0:0]  probe1 
//	.probe2(hbm_read_a_almost_full[0]), // input wire [0:0]  probe2 
//	.probe3(hbm_read_a_wr_en_r[1]) // input wire [0:0]  probe3
//);

// ila_4 ila_user (
// 	.clk(user_clk), // input wire clk


// 	.probe0(dispatch_axb_a_data[0]), // input wire [511:0]  probe0  
// 	.probe1(dispatch_axb_a_wr_en[0]), // input wire [0:0]  probe1 
// 	.probe2(hbm_read_a_rd_en[0]), // input wire [0:0]  probe2 
// 	.probe3(dispatch_axb_a_almost_full_r1[0]) // input wire [0:0]  probe3
// );



    always @(posedge hbm_clk)begin
        dispatch_axb_b_data_r1                  <= dispatch_axb_b_data[`ENGINE_NUM];
        dispatch_axb_b_data_o                  <= dispatch_axb_b_data_r1;
        dispatch_axb_b_wr_en_r1                 <= dispatch_axb_b_wr_en[`ENGINE_NUM];
        dispatch_axb_b_wr_en_o                 <= dispatch_axb_b_wr_en_r1;
    end

    always @(posedge hbm_clk) begin
        start_um                        <= hbm_write_done;
    end 

    //  always @(posedge user_clk) begin
    //     dispatch_axb_a_almost_full_r    <= {dispatch_axb_a_almost_full_r[3:0],dispatch_axb_a_almost_full};
    //     dispatch_axb_a_data_r           <= {dispatch_axb_a_data_r[3:0],dispatch_axb_a_data};
    //     dispatch_axb_a_wr_en_r          <= {dispatch_axb_a_wr_en_r[3:0],dispatch_axb_a_wr_en};
    // end    


    // wire [511:0]                     back_data;
    // wire                             back_valid;
    // reg [7:0]                       channel_choice_r;

    // always @(posedge hbm_clk)begin
    //     channel_choice_r            <= channel_choice[7:0];
    // end

    // always @(posedge hbm_clk)begin
    //     if(channel_choice == 8'd32)
    //         data_length             <= data_b_length;
    //     else
    //         data_length             <= data_a_length >> `ENGINE_NUM_WIDTH;
    // end

//     ila_hbm_read your_instance_name (
// 	.clk(hbm_clk), // input wire clk


// 	.probe0(rd_addr_cnt[channel_choice_r]), // input wire [31:0]  probe0  
// 	.probe1(rd_addr_sum_cnt[channel_choice_r]), // input wire [31:0]  probe1 
// 	.probe2(rd_sum_cnt[channel_choice_r]), // input wire [31:0]  probe2 
// 	.probe3(wr_b_counter[channel_choice_r]), // input wire [31:0]  probe3 
// 	.probe4(wr_a_counter[channel_choice_r]) // input wire [31:0]  probe4
// );

    // always @(posedge hbm_clk)begin
    //     if(channel_choice == 8'd32)begin
    //         back_data               <= dispatch_axb_b_data[`ENGINE_NUM/2];
    //         back_valid              <= dispatch_axb_b_wr_en[`ENGINE_NUM/2];
    //     end
    //     else begin
    //         back_data               <= dispatch_axb_a_data[channel_choice_r[6:0]];
    //         back_valid              <= dispatch_axb_a_wr_en[channel_choice_r[6:0]];
    //     end
    // end

// always @(posedge hbm_clk)begin
//     dispatch_axb_b_data_r[0]                <= dispatch_axb_b_data[`ENGINE_NUM];
//     dispatch_axb_b_data_r[4:1]              <= dispatch_axb_b_data_r[3:0];
//     dispatch_axb_b_wr_en_r[0]               <= dispatch_axb_b_wr_en[`ENGINE_NUM];
//     dispatch_axb_b_wr_en_r[4:1]             <= dispatch_axb_b_wr_en_r[3:0];
// end


// sgd_top_bw #( 
//     .DATA_WIDTH_IN               (4),
//     .MAX_DIMENSION_BITS          (18)
// )sgd_top_bw_inst (    
//     .clk                                (user_clk),
//     .rst_n                              (hbm_rstn),
//     .dma_clk                            (dma_clk),
//     .hbm_clk                            (hbm_clk),
//     //-------------------------------------------------//
//     .start_um                           (hbm_write_done),
//     // .um_params                          (m_axis_mlweaving_data),

//     .addr_model                         (addr_model),
//     .mini_batch_size                    (mini_batch_size),
//     .step_size                          (step_size),
//     .number_of_epochs                   (number_of_epochs),
//     .dimension                          (dimension),
//     .number_of_samples                  (number_of_samples),
//     .number_of_bits                     (number_of_bits),

//     .um_done                            (),
//     .um_state_counters                  (),


//     .dispatch_axb_a_data                (dispatch_axb_a_data_r4),
//     .dispatch_axb_a_wr_en               (dispatch_axb_a_wr_en_r4),
//     .dispatch_axb_a_almost_full         (dispatch_axb_a_almost_full),

//     .dispatch_axb_b_data                (dispatch_axb_b_data_r4),
//     .dispatch_axb_b_wr_en               (dispatch_axb_b_wr_en_r4),
//     .dispatch_axb_b_almost_full         (),
//     //---------------------Memory Inferface:write----------------------------//
//     //cmd
//     .x_data_send_back_start             (x_data_send_back_start),
//     .x_data_send_back_addr              (x_data_send_back_addr),
//     .x_data_send_back_length            (x_data_send_back_length),

//     //data
//     .x_data_out                         (back_data),
//     .x_data_out_valid                   (back_valid),
//     .x_data_out_almost_full             (almost_full)

// );
//    hbm_send_back  u_hbm_send_back (
//        .hbm_clk                                            ( dma_clk                                            ),
//        .hbm_aresetn                                        ( dma_aresetn                                        ),
//        .m_axis_dma_write_cmd                               ( m_axis_dma_write_cmd                                ),
//        .m_axis_dma_write_data                              ( m_axis_reg_write_data                               ),
//        .start                                              ( x_data_send_back_start                              ),
//        .addr_x                                             ( x_data_send_back_addr                               ),
//        .data_length                                        ( x_data_send_back_length                             ),
//        .back_data                                          ( back_data                                           ),
//        .back_valid                                         ( back_valid                                          ),

//        .almost_full                                        ( almost_full                                         )
//    );
   

// ila_hbm_inf ila_hbm_inf_inst (
// 	.clk(hbm_clk), // input wire clk


// 	.probe0(addr_a), // input wire [63:0]  probe0  
// 	.probe1(addr_b), // input wire [63:0]  probe1 
// 	.probe2(addr_model), // input wire [63:0]  probe2 
// 	.probe3(mini_batch_size), // input wire [31:0]  probe3 
// 	.probe4(step_size), // input wire [31:0]  probe4 
// 	.probe5(number_of_epochs), // input wire [31:0]  probe5 
// 	.probe6(dimension), // input wire [31:0]  probe6 
// 	.probe7(number_of_samples), // input wire [31:0]  probe7 
// 	.probe8(number_of_bits), // input wire [31:0]  probe8 
// 	.probe9(data_a_length), // input wire [31:0]  probe9 
// 	.probe10(array_length) // input wire [31:0]  probe10
// );


endmodule
