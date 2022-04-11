//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2020/02/20 19:18:58
// Design Name: 
// Module Name: sgd_top
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
`timescale 1ps / 1ps
//`default_nettype none

`include "sgd_defines.vh"

module sgd_top(
    output wire[15 : 0] pcie_tx_p,
    output wire[15 : 0] pcie_tx_n,
    input wire[15 : 0]  pcie_rx_p,
    input wire[15 : 0]  pcie_rx_n,

    input wire				sys_clk_p,
    input wire				sys_clk_n,
    input wire				sys_rst_n,

////////////////network//////////////

    input  wire [0:0][3:0] gt_rxp_in,
    input  wire [0:0][3:0] gt_rxn_in,
    output wire [0:0][3:0] gt_txp_out,
    output wire [0:0][3:0] gt_txn_out,

    input wire [0:0]  gt_refclk_p,
    input wire [0:0]  gt_refclk_n,  

///////////////////////////////////////////


	output wire				led,

     input wire           	hbm_100M_p,
     input wire           	hbm_100M_n,

     input wire     		sys_100M_p,
	 input wire				sys_100M_n     
    );
    
	assign led = 1'b0;

/*
 * Clock & Reset Signals
 */
wire sys_reset;
wire sys_100M;
wire sys_clk_100M;
// User logic clock & reset
wire user_clk;
wire user_aresetn;

   // Network user clock & reset
wire [1:0] net_clk;
wire [1:0] net_aresetn;

/*
 * Clock Generation
 */
wire dclk;


  user_clk inst_user_clk
   (
    // Clock out ports
    .clk_out1(user_clk),     // output clk_out1
    .clk_out2(dclk),     // output clk_out2
    // Status and control signals
    .reset(0), // input reset
    .locked(user_aresetn),       // output locked
   // Clock in ports
    .clk_in1_p(sys_100M_p),    // input clk_in1_p
    .clk_in1_n(sys_100M_n));    // input clk_in1_n

// HBM logic clock
wire hbm_100M;
wire hbm_clk_100M;

     IBUFDS #(
       .IBUF_LOW_PWR("TRUE")     // Low power="TRUE", Highest performance="FALSE" 
    ) IBUFDS0_inst (
       .O(hbm_100M),  // Buffer output
       .I(hbm_100M_p),  // Diff_p buffer input (connect directly to top-level port)
       .IB(hbm_100M_n) // Diff_n buffer input (connect directly to top-level port)
    );
 
   
      BUFG BUFG0_inst (
       .O(hbm_clk_100M), // 1-bit output: Clock output
       .I(hbm_100M)  // 1-bit input: Clock input
    );
//user clk
wire            pcie_clk;
wire            pcie_aresetn;

// DMA Signals
axis_mem_cmd    axis_dma_read_cmd();
axis_mem_cmd    axis_dma_write_cmd();
axi_stream      axis_dma_read_data();
axi_stream      axis_dma_write_data();



wire[511:0][31:0]     fpga_control_reg;
wire[511:0][31:0]     fpga_status_reg; 

wire[31:0][511:0]     bypass_control_reg;
wire[31:0][511:0]     bypass_status_reg;

/*
 * DMA Interface
 */

dma_inf dma_interface (
	/*HPY INTERFACE */
	.pcie_tx_p						(pcie_tx_p),    // output wire [15 : 0] pci_exp_txp
	.pcie_tx_n						(pcie_tx_n),    // output wire [15 : 0] pci_exp_txn
	.pcie_rx_p						(pcie_rx_p),    // input wire [15 : 0] pci_exp_rxp
	.pcie_rx_n						(pcie_rx_n),    // input wire [15 : 0] pci_exp_rxn

    .sys_clk_p						(sys_clk_p),
    .sys_clk_n						(sys_clk_n),
    .sys_rst_n						(sys_rst_n), 

    /* USER INTERFACE */
    //pcie clock output
    .pcie_clk						(pcie_clk),
    .pcie_aresetn					(pcie_aresetn),
	 
	//user clock input
    .user_clk						(pcie_clk),
    .user_aresetn					(pcie_aresetn),

    //DMA Commands 
    .s_axis_dma_read_cmd            (axis_dma_read_cmd),
    .s_axis_dma_write_cmd           (axis_dma_write_cmd),
	//DMA Data streams
    .m_axis_dma_read_data           (axis_dma_read_data),
    .s_axis_dma_write_data          (axis_dma_write_data),
 

    // CONTROL INTERFACE 
    // Control interface
    .fpga_control_reg               (fpga_control_reg),
	.fpga_status_reg                (fpga_status_reg)

`ifdef XDMA_BYPASS		
    // bypass register
	,.bypass_control_reg 			(bypass_control_reg),
	.bypass_status_reg  			(bypass_status_reg)
`endif

);

//reset

reg 					reset,reset_r;
reg[7:0]				reset_cnt;
reg 					user_rstn_i;
reg 					user_rstn;			

always @(posedge pcie_clk)begin
	reset				<= fpga_control_reg[0][0];
	reset_r				<= reset;
	user_rstn         <= pcie_aresetn & reset_cnt[7];
end

always @(posedge pcie_clk)begin
	if(reset & ~reset_r)begin
		reset_cnt		<= 1'b0;
	end
	else if(reset_cnt[7] == 1'b1)begin
		reset_cnt		<= reset_cnt;
	end
	else begin
		reset_cnt		<= reset_cnt + 1'b1;
	end
end


/*
* 100G Network Module
*/

// axis_meta #(.WIDTH(16))     axis_tcp_listen_port();
// axis_meta #(.WIDTH(8))      axis_tcp_port_status();
// axis_meta #(.WIDTH(48))     axis_tcp_open_connection();
// axis_meta #(.WIDTH(24))     axis_tcp_open_status();
// axis_meta #(.WIDTH(16))     axis_tcp_close_connection();
// axis_meta #(.WIDTH(88))     axis_tcp_notification();
// axis_meta #(.WIDTH(32))     axis_tcp_read_pkg();

// axis_meta #(.WIDTH(16))     axis_tcp_rx_meta();
// axi_stream #(.WIDTH(512))   axis_tcp_rx_data();
// axis_meta #(.WIDTH(48))     axis_tcp_tx_meta();
// axi_stream #(.WIDTH(512))   axis_tcp_tx_data();
// axis_meta #(.WIDTH(64))     axis_tcp_tx_status();

// axis_meta #(.WIDTH(88))     app_axis_tcp_rx_meta();
// axi_stream #(.WIDTH(512))   app_axis_tcp_rx_data();
// axis_meta #(.WIDTH(48))     app_axis_tcp_tx_meta();
// axi_stream #(.WIDTH(512))   app_axis_tcp_tx_data();
// axis_meta #(.WIDTH(64))     app_axis_tcp_tx_status();

// tcp_wrapper #(
//     .TIME_OUT_CYCLE 			(32'd250000000)
//     )inst_tcp_wrapper(
//         .clk						(pcie_clk),
//         .user_clk                   (pcie_clk),
//         .rstn						(user_rstn),
        
        
//        //netword interface streams
//         .m_axis_listen_port			(axis_tcp_listen_port),
//         .s_axis_listen_port_status	(axis_tcp_port_status),
       
//         .m_axis_open_connection		(axis_tcp_open_connection),
//         .s_axis_open_status			(axis_tcp_open_status),
//         .m_axis_close_connection	(axis_tcp_close_connection), 
    
//         .s_axis_notifications       (axis_tcp_notification),
//         .m_axis_read_package        (axis_tcp_read_pkg),
        
//         .s_axis_rx_metadata         (axis_tcp_rx_meta),
//         .s_axis_rx_data             (axis_tcp_rx_data),
        
//        .m_axis_tx_metadata         (axis_tcp_tx_meta),
//        .m_axis_tx_data             (axis_tcp_tx_data),
//        .s_axis_tx_status           (axis_tcp_tx_status),

//     //    //director set conn interface
//     //    .m_axis_conn_send           (axis_conn_send),
//     //    .m_axis_ack_to_send         (axis_ack_to_send),     //ack to tcp send
//     //    .m_axis_ack_to_recv         (axis_ack_to_recv),     //ack to rcv to set buffer id
//     //    .s_axis_conn_recv           (axis_conn_recv),

//        //app interface streams
//        .s_axis_tx_metadata          (app_axis_tcp_tx_meta),
//        .s_axis_tx_data              (app_axis_tcp_tx_data),
//        .m_axis_tx_status            (app_axis_tcp_tx_status),    
   
//        .m_axis_rx_metadata          (app_axis_tcp_rx_meta), 
//        .m_axis_rx_data              (app_axis_tcp_rx_data),
   
//        ///
//        .control_reg				    (fpga_control_reg[143:130]),
//        .status_reg			        (fpga_status_reg[407:392])
   
//      );



////////mac module/////////////////////////

wire                            network_init;
wire                            user_rx_reset,user_tx_reset;  
axi_stream #(.WIDTH(512))       axis_net_rx_data();
axi_stream #(.WIDTH(512))       axis_net_tx_data();
assign net_aresetn              = network_init;


network_module_100g network_module_inst
(
    .dclk (dclk),
    .user_clk(pcie_clk),
    .net_clk(net_clk),
    .sys_reset (~pcie_aresetn),
    .aresetn(net_aresetn),
    .network_init_done(network_init),
    
    .gt_refclk_p(gt_refclk_p[0]),
    .gt_refclk_n(gt_refclk_n[0]),
    
    .gt_rxp_in(gt_rxp_in[0]),
    .gt_rxn_in(gt_rxn_in[0]),
    .gt_txp_out(gt_txp_out[0]),
    .gt_txn_out(gt_txn_out[0]),
    
    .user_rx_reset(user_rx_reset),
    .user_tx_reset(user_tx_reset),
    .rx_aligned(),
    
    //master 0
    .m_axis_net_rx(axis_net_rx_data),
    .s_axis_net_tx(axis_net_tx_data)

);



// network_stack #(
// .WIDTH(512),
// .MAC_ADDRESS (48'hE59D02350A00) // LSB first, 00:0A:35:02:9D:E5
// ) network_stack_inst (
// /*          gt ports        */
// // .gt_rxp_in(gt_rxp_in[0]),
// // .gt_rxn_in(gt_rxn_in[0]),
// // .gt_txp_out(gt_txp_out[0]),
// // .gt_txn_out(gt_txn_out[0]),

// // //    input wire          sys_reset_n,
// // .gt_refclk_p(gt_refclk_p[0]),
// // .gt_refclk_n(gt_refclk_n[0]),
//     .axis_net_rx_data(axis_net_rx_data),
//     .axis_net_tx_data(axis_net_tx_data),
// /*          clock           */
// // .dclk(dclk),
// .user_clk(pcie_clk),
// .user_aresetn(user_rstn),
// .net_clk(net_clk),
// .net_aresetn(net_aresetn),
// .mem_clk(pcie_clk),
// // //Control interface
// .set_ip_addr_data(fpga_control_reg[129]),//32'h0b01d401
// .set_board_number_data(fpga_control_reg[128]),

// //Role interface
// .s_axis_listen_port(axis_tcp_listen_port),
// .m_axis_listen_port_status(axis_tcp_port_status),
// .s_axis_open_connection(axis_tcp_open_connection),
// .m_axis_open_status(axis_tcp_open_status),
// .s_axis_close_connection(axis_tcp_close_connection),
// .m_axis_notifications(axis_tcp_notification),
// .s_axis_read_package(axis_tcp_read_pkg),
// .m_axis_rx_metadata(axis_tcp_rx_meta),
// .m_axis_rx_data(axis_tcp_rx_data),
// .s_axis_tx_metadata(axis_tcp_tx_meta),
// .s_axis_tx_data(axis_tcp_tx_data),
// .m_axis_tx_status(axis_tcp_tx_status),
// .status_reg(fpga_status_reg[423:408])
// );


 



////////////////////hbm driver/////////////////

axi_mm          hbm_axi[32]();
wire            hbm_clk;
wire            hbm_rstn;

hbm_driver inst_hbm_driver(

    .sys_clk_100M(hbm_clk_100M),
    .hbm_axi(hbm_axi),
    .hbm_clk(hbm_clk),
    .hbm_rstn(hbm_rstn)
    );

wire								start_um;
reg  [63:0]                  		addr_model;
reg  [31:0]                  		mini_batch_size;
reg  [31:0]                  		step_size;
reg  [31:0]                  		number_of_epochs;
reg  [31:0]                  		dimension;
reg  [31:0]                  		number_of_samples;
reg  [31:0]                  		number_of_bits; 
reg  [15:0]                         session_id;


wire  [`ENGINE_NUM-1:0][511:0]     	dispatch_axb_a_data;
wire [255:0]                      	dispatch_axb_b_data; 
wire  [`ENGINE_NUM-1:0]            	dispatch_axb_a_wr_en;
wire                            	dispatch_axb_b_wr_en;
wire [`ENGINE_NUM-1:0]            	dispatch_axb_a_almost_full;

//---------------------Memory Inferface:write----------------------------//
//cmd
wire                                     x_data_send_back_start;
wire[63:0]                               x_data_send_back_addr;
wire[31:0]                               x_data_send_back_length;

    //data
wire[511:0]                              x_data_out;
wire                                     x_data_out_valid;
wire                                     x_data_out_almost_full;

/////////////////////start

reg         start_d;
reg         start_send_back;   
reg[7:0]    start_cnt;

always @(posedge hbm_clk)begin
    if(~user_rstn)
        start_d            <= 1'b0;
    else if(start_um)
        start_d            <= 1'b1;
    else if(start_cnt > 8'hf0)
        start_d             <= 1'b0;
    else begin
        start_d             <= start_d;
    end
end

always @(posedge hbm_clk)begin
    if(~user_rstn)
        start_cnt            <= 1'b0;    
    else if(start_d)
        start_cnt            <= 1'b1 + start_cnt;
    else begin
        start_cnt             <= 1'b0;
    end
end

////////////////////////////////////////////////////////////


hbm_interface inst_hbm_interface(
     .user_clk(pcie_clk),
     .user_aresetn(user_rstn),
//    .user_clk(pcie_clk),
//    .user_aresetn(user_rstn),

    .hbm_clk(hbm_clk),
    .hbm_rstn(user_rstn),

    .dma_clk(pcie_clk),
    .dma_aresetn(user_rstn), 
	//mlweaving parameter
    .addr_a								({fpga_control_reg[21],fpga_control_reg[20]}),
    .addr_b								({fpga_control_reg[23],fpga_control_reg[22]}),	
    .addr_model                         ({fpga_control_reg[25],fpga_control_reg[24]}),
    .mini_batch_size                    (fpga_control_reg[26]),
    .step_size                          (fpga_control_reg[27]),
    .number_of_epochs                   (fpga_control_reg[28]),
    .dimension                          (fpga_control_reg[29]),
    .number_of_samples                  (fpga_control_reg[30]),
    .number_of_bits                     (fpga_control_reg[31]), 
    .data_a_length						(fpga_control_reg[32]),
    .array_length						(fpga_control_reg[33]),
    .channel_choice						(fpga_control_reg[34]),
    .start                              (fpga_control_reg[36]),
    .hbm_status                         (fpga_status_reg[191:64]),


    /* DMA INTERFACE */
    //Commands
    .m_axis_dma_read_cmd(axis_dma_read_cmd),
    // .m_axis_dma_write_cmd(axis_dma_write_cmd),

    //Data streams
    // .m_axis_dma_write_data(axis_dma_write_data),
    .s_axis_dma_read_data(axis_dma_read_data),
    
    /* HBM INTERFACE */
    .hbm_axi(hbm_axi),

    /* sgd calculate*/
	//parameter
    .start_um                           (start_um),


    .dispatch_axb_a_data_o              (dispatch_axb_a_data),
    .dispatch_axb_a_wr_en_o             (dispatch_axb_a_wr_en),
    .dispatch_axb_a_almost_full         (dispatch_axb_a_almost_full),

    .dispatch_axb_b_data_o              (dispatch_axb_b_data),
    .dispatch_axb_b_wr_en_o             (dispatch_axb_b_wr_en),
    .dispatch_axb_b_almost_full         ()

    );



    always@(posedge pcie_clk)begin
        // addr_model              <= {fpga_control_reg[25],fpga_control_reg[24]};
        mini_batch_size         <= fpga_control_reg[26];
        step_size               <= fpga_control_reg[27];
        number_of_epochs        <= fpga_control_reg[28];
        dimension               <= fpga_control_reg[29];
        number_of_samples       <= fpga_control_reg[30];
        number_of_bits          <= fpga_control_reg[31];
    end

    // always @(posedge pcie_clk)begin
    //     if(~user_rstn)
    //         session_id            <= 1'b0;    
    //     else if(axis_tcp_open_status.valid & axis_tcp_open_status.ready)
    //         session_id            <= axis_tcp_open_status.data[15:0];
    //     else begin
    //         session_id             <= session_id;
    //     end
    // end


//SGD 
sgd_top_bw #( 
    .DATA_WIDTH_IN               (4),
    .MAX_DIMENSION_BITS          (18),
    .SLR0_ENGINE_NUM                                (2),
    .SLR1_ENGINE_NUM                                (4),
    .SLR2_ENGINE_NUM                                (2)

)sgd_top_bw_inst (    
    .clk                                (pcie_clk),
    .rst_n                              (user_rstn),
    .dma_clk                            (pcie_clk),
    .hbm_clk                            (hbm_clk),
    //-------------------------------------------------//
    .start_um                           (start_d),
    // .um_params                          (m_axis_mlweaving_data),

    .addr_model                         ({fpga_control_reg[25],fpga_control_reg[24]}),
    .mini_batch_size                    (mini_batch_size),
    .step_size                          (step_size),
    .number_of_epochs                   (number_of_epochs),
    .dimension                          (dimension),
    .number_of_samples                  (number_of_samples),
    .number_of_bits                     (number_of_bits),

    .um_done                            (),
    .um_state_counters                  (fpga_status_reg[383:256]),

       //app interface streams
    .m_axis_tx_data                     (axis_net_tx_data),  
    .s_axis_rx_data                     (axis_net_rx_data),

    //

    .dispatch_axb_a_data                (dispatch_axb_a_data),
    .dispatch_axb_a_wr_en               (dispatch_axb_a_wr_en),
    .dispatch_axb_a_almost_full         (dispatch_axb_a_almost_full),

    .dispatch_axb_b_data                (dispatch_axb_b_data),
    .dispatch_axb_b_wr_en               (dispatch_axb_b_wr_en),
    .dispatch_axb_b_almost_full         (),
    //---------------------Memory Inferface:write----------------------------//
    //cmd
    .x_data_send_back_start             (x_data_send_back_start),
    .x_data_send_back_addr              (x_data_send_back_addr),
    .x_data_send_back_length            (x_data_send_back_length),

    //data
    .x_data_out                         (x_data_out),
    .x_data_out_valid                   (x_data_out_valid),
    .x_data_out_almost_full             (x_data_out_almost_full)

);


   hbm_send_back  u_hbm_send_back (
       .hbm_clk                                            ( pcie_clk                                            ),
       .hbm_aresetn                                        ( user_rstn                                           ),
       .m_axis_dma_write_cmd                               ( axis_dma_write_cmd                                ),
       .m_axis_dma_write_data                              ( axis_dma_write_data                               ),
       .start                                              ( x_data_send_back_start                              ),
       .addr_x                                             ( x_data_send_back_addr                               ),
       .data_length                                        ( x_data_send_back_length                             ),
       .back_data                                          ( x_data_out                                           ),
       .back_valid                                         ( x_data_out_valid                                          ),

       .almost_full                                        ( x_data_out_almost_full                                         ),
       .status_reg                                          (fpga_status_reg[391:384])
   );


/////////////////////////////////////////////send hbm data//////////////////


//     reg [511:0]                     back_data;
//     reg                             back_valid;
//     reg [7:0]                       channel_choice_r;



// assign dispatch_axb_a_almost_full = {`ENGINE_NUM{x_data_out_almost_full}};




// always @(posedge pcie_clk)begin
//     if(~user_rstn)
//         start_send_back            <= 1'b0;
//     else if(start_d)
//         start_send_back             <= 1'b1;
//     else 
//         start_send_back             <= 1'b0;
// end

//     always @(posedge pcie_clk)begin
//         channel_choice_r            <= fpga_control_reg[34][7:0];
//     end

//     always @(posedge pcie_clk)begin
//         if(channel_choice_r == 32)begin
//             back_data               <= dispatch_axb_b_data;
//             back_valid              <= dispatch_axb_b_wr_en;            
//         end
//         else begin
//             back_data               <= dispatch_axb_a_data[channel_choice_r[6:0]];
//             back_valid              <= dispatch_axb_a_wr_en[channel_choice_r[6:0]];            
//         end

//     end


//    hbm_send_back  u_hbm_send_back (
//        .hbm_clk                                            ( pcie_clk                                            ),
//        .hbm_aresetn                                        ( user_rstn                                           ),
//        .m_axis_dma_write_cmd                               ( axis_dma_write_cmd                                ),
//        .m_axis_dma_write_data                              ( axis_dma_write_data                               ),
//        .start                                              ( start_send_back                              ),
//        .addr_x                                             ( {fpga_control_reg[25],fpga_control_reg[24]}                               ),
//        .data_length                                        ( fpga_control_reg[35]                             ),
//        .back_data                                          ( back_data                                           ),
//        .back_valid                                         ( back_valid                                          ),

//        .almost_full                                        ( x_data_out_almost_full                              ),
//        .status_reg                                          (fpga_status_reg[199:192])
//    );



//////////////////hbm debug/////////////////


//ila_0 ila_write_inst (
//	.clk(pcie_clk), // input wire clk


//	.probe0(axis_dma_write_cmd.valid), // input wire [0:0]  probe0  
//	.probe1(axis_dma_write_cmd.ready), // input wire [0:0]  probe1 
//	.probe2(axis_dma_write_cmd.address), // input wire [63:0]  probe2 
//	.probe3(axis_dma_write_cmd.length), // input wire [31:0]  probe3 
//	.probe4(axis_dma_write_data.valid), // input wire [0:0]  probe4 
//	.probe5(axis_dma_write_data.ready), // input wire [0:0]  probe5 
//	.probe6(axis_dma_write_data.data) // input wire [511:0]  probe6
//); 

//ila_0 ila_read_inst (
//	.clk(pcie_clk), // input wire clk


//	.probe0(axis_dma_read_cmd.valid), // input wire [0:0]  probe0  
//	.probe1(axis_dma_read_cmd.ready), // input wire [0:0]  probe1 
//	.probe2(axis_dma_read_cmd.address), // input wire [63:0]  probe2 
//	.probe3(axis_dma_read_cmd.length), // input wire [31:0]  probe3 
//	.probe4(axis_dma_read_data.valid), // input wire [0:0]  probe4 
//	.probe5(axis_dma_read_data.ready), // input wire [0:0]  probe5 
//	.probe6(axis_dma_read_data.data) // input wire [511:0]  probe6
//);





//MLWEAVING PARAMETER REG
// reg [63:0] addr_a;
// reg [63:0] addr_b;
// reg [63:0] addr_model;
// reg [31:0] mini_batch_size;
// reg [31:0] step_size;
// reg [31:0] number_of_epochs;
// reg [31:0] dimension;
// reg [31:0] number_of_samples;
// reg [31:0] number_of_bits;   
// reg [31:0] data_a_length;
// reg [31:0] array_length;
// reg [31:0] channel_choice;

// reg [511:0] dma_read_data;

//   wire            	start;
//   reg				start_d;


// always @(posedge hbm_clk)begin
// 	start_d <= start;
// end

// always @(posedge hbm_clk)begin
//     if(~hbm_rstn)begin
//         m_axis_mlweaving_data           <= 512'b0;
//     end
//     else begin
//         m_axis_mlweaving_data[ 63:0  ]  <= addr_a;
//         m_axis_mlweaving_data[127:64 ]  <= addr_b;
//         m_axis_mlweaving_data[191:128]  <= addr_model;
//         m_axis_mlweaving_data[223:192]  <= mini_batch_size;
//         m_axis_mlweaving_data[255:224]  <= step_size;
//         m_axis_mlweaving_data[287:256]  <= number_of_epochs;
//         m_axis_mlweaving_data[319:288]  <= dimension;    
//         m_axis_mlweaving_data[351:320]  <= number_of_samples;
//         m_axis_mlweaving_data[383:352]  <= number_of_bits;  
//         m_axis_mlweaving_data[415:384]  <= data_a_length;   
//         m_axis_mlweaving_data[447:416]  <= array_length;
//         m_axis_mlweaving_data[479:448]  <= channel_choice;
//     end
// end

// vio_0 your_instance_name (
//   .clk(hbm_clk),                  // input wire clk
//   .probe_out0(addr_a),    // output wire [63 : 0] probe_out0
//   .probe_out1(addr_b),    // output wire [63 : 0] probe_out1
//   .probe_out2(addr_model),    // output wire [63 : 0] probe_out2
//   .probe_out3(mini_batch_size),    // output wire [31 : 0] probe_out3
//   .probe_out4(step_size),    // output wire [31 : 0] probe_out4
//   .probe_out5(number_of_epochs),    // output wire [31 : 0] probe_out5
//   .probe_out6(dimension),    // output wire [31 : 0] probe_out6
//   .probe_out7(number_of_samples),    // output wire [31 : 0] probe_out7
//   .probe_out8(number_of_bits),    // output wire [31 : 0] probe_out8
//   .probe_out9(data_a_length),    // output wire [31 : 0] probe_out9
//   .probe_out10(array_length),  // output wire [31 : 0] probe_out10
//   .probe_out11(channel_choice),  // output wire [31 : 0] probe_out11
//   .probe_out12(start)  // output wire [0 : 0] probe_out12
// );



// always @(posedge hbm_clk)begin	
// 	if(~hbm_rstn)
// 		m_axis_mlweaving_valid		<= 1'b0;
// 	else if(start & ~start_d)
// 		m_axis_mlweaving_valid		<= 1'b1;
// 	else
// 		m_axis_mlweaving_valid		<= 1'b0;
// end



//     always @(posedge hbm_clk) begin 
//         if(~hbm_rstn)  
//             dma_read_data       <= 0;
//         else if(axis_dma_read_data.valid & axis_dma_read_data.ready)
//             dma_read_data       <= dma_read_data + 1;
//         else
//             dma_read_data       <= dma_read_data;
//     end

// always @(posedge hbm_clk)begin	
// 	if(~hbm_rstn)
// 		axis_dma_read_data.valid		<= 1'b0;
// 	else if(start & ~start_d)
// 		axis_dma_read_data.valid		<= 1'b1;
// 	else
// 		axis_dma_read_data.valid		<= axis_dma_read_data.valid;
// end


//     assign axis_dma_read_cmd.ready = 1;
//     assign axis_dma_write_cmd.ready = 1;
//     assign axis_dma_write_data.ready = 1;
//     //assign axis_dma_read_data.valid = 1;
//     assign axis_dma_read_data.keep = {64{1'b1}};
//     assign axis_dma_read_data.last = 0;
//     assign axis_dma_read_data.data = dma_read_data;


/////////////////////////dma debug///////////
/*
  reg            	read_start;
  reg				read_start_d;
  reg            	write_start;
  reg				write_start_d;
  reg [31:0]		axis_dma_write_data_cnt;
  reg [31:0]		axis_dma_write_data_length;
  reg [31:0]		axis_dma_read_data_cnt;
  reg [31:0]		axis_dma_read_data_length;
  reg [31:0]		ops;

  reg [31:0]		read_cnt;
  reg [31:0]		write_cnt;
  reg 				read_cnt_en;
  reg 				write_cnt_en;
  reg [31:0]		wr_op_cnt;
  reg [31:0]		rd_op_cnt;
  reg [31:0]		wr_op_data_cnt;
  reg [31:0]		rd_op_data_cnt;  

assign user_clk = pcie_clk;
assign user_aresetn = pcie_aresetn;

always @(posedge user_clk)begin
	read_start_d <= read_start;
	write_start_d <= write_start;
end

////dma throughput cnt
always @(posedge user_clk)begin
	if(~pcie_aresetn)
		read_cnt_en <= 1'b0;
	else if(read_start && ~read_start_d)
		read_cnt_en <= 1'b1;
	else if(rd_op_data_cnt == ops)
		read_cnt_en <=  1'b0;
	else 
		read_cnt_en <= read_cnt_en;
end

always @(posedge user_clk)begin
	if(~pcie_aresetn)
		read_cnt <= 0;
	else if(read_cnt_en)
		read_cnt <= read_cnt + 1'b1;
	else 
		read_cnt <= 0;
end

always @(posedge user_clk)begin
	if(~pcie_aresetn)
		rd_cnt <= 0;
	else if((rd_op_data_cnt == (ops-1))&&(axis_dma_read_data_cnt == axis_dma_read_data_length))
		rd_cnt <= read_cnt;
	else 
		rd_cnt <= rd_cnt;
end

always @(posedge user_clk)begin
	if(~pcie_aresetn)
		rd_op_cnt <= 0;
	else if(m_axis_mlweaving_ready && m_axis_mlweaving_valid)
		rd_op_cnt <= 0;
	else if(axis_dma_read_cmd.valid && axis_dma_read_cmd.ready)
		rd_op_cnt <= rd_op_cnt + 1'b1;
	else 
		rd_op_cnt <= rd_op_cnt;
end


always @(posedge user_clk)begin
	if(~pcie_aresetn)
		rd_op_data_cnt <= 0;
	else if(m_axis_mlweaving_ready && m_axis_mlweaving_valid)
		rd_op_data_cnt <= 0;
	else if(axis_dma_read_data_cnt == axis_dma_read_data_length)
		rd_op_data_cnt <= rd_op_data_cnt + 1'b1;
	else 
		rd_op_data_cnt <= rd_op_data_cnt;
end


always @(posedge user_clk)begin
	if(~pcie_aresetn)
		write_cnt_en <= 1'b0;
	else if(write_start && ~write_start_d)
		write_cnt_en <= 1'b1;
	else if(wr_op_data_cnt == ops)
		write_cnt_en <=  1'b0;
	else 
		write_cnt_en <= write_cnt_en;
end

always @(posedge user_clk)begin
	if(~pcie_aresetn)
		write_cnt <= 0;
	else if(write_cnt_en)
		write_cnt <= write_cnt + 1'b1;
	else 
		write_cnt <= 0;
end


always @(posedge user_clk)begin
	if(~pcie_aresetn)
		wr_cnt <= 0;
	else if((wr_op_data_cnt == (ops-1))&&(axis_dma_write_data_cnt == axis_dma_write_data_length))
		wr_cnt <= write_cnt;
	else 
		wr_cnt <= wr_cnt;
end

always @(posedge user_clk)begin
	if(~pcie_aresetn)
		wr_op_cnt <= 0;
	else if(m_axis_mlweaving_ready && m_axis_mlweaving_valid)
		wr_op_cnt <= 0;
	else if(axis_dma_write_cmd.valid && axis_dma_write_cmd.ready)
		wr_op_cnt <= wr_op_cnt + 1'b1;
	else 
		wr_op_cnt <= wr_op_cnt;
end

always @(posedge user_clk)begin
	if(~pcie_aresetn) 
		wr_op_data_cnt <= 0;
	else if(m_axis_mlweaving_ready && m_axis_mlweaving_valid)
		wr_op_data_cnt <= 0;
	else if(axis_dma_write_data_cnt == axis_dma_write_data_length)
		wr_op_data_cnt <= wr_op_data_cnt + 1'b1;
	else 
		wr_op_data_cnt <= wr_op_data_cnt;
end

/////////////////////







always @(posedge user_clk)begin
	if(~pcie_aresetn)
		axis_dma_read_cmd.valid <= 1'b0;
	else if(read_start && ~read_start_d)
		axis_dma_read_cmd.valid <= 1'b1;
	else if(axis_dma_read_cmd.valid && axis_dma_read_cmd.ready)
		axis_dma_read_cmd.valid <= 1'b0;
	else 
		axis_dma_read_cmd.valid <= axis_dma_read_cmd.valid;
end

always @(posedge user_clk)begin
	if(~pcie_aresetn)
		axis_dma_write_cmd.valid <= 1'b0;
	else if(write_start && ~write_start_d)
		axis_dma_write_cmd.valid <= 1'b1;
	else if(axis_dma_write_cmd.valid && axis_dma_write_cmd.ready)
		axis_dma_write_cmd.valid <= 1'b0;
	else 
		axis_dma_write_cmd.valid <= axis_dma_write_cmd.valid;
end

always @(posedge user_clk)begin
	if(~pcie_aresetn)
		axis_dma_write_data_cnt <= 1'b0;
	else if(axis_dma_write_data.last)
		axis_dma_write_data_cnt <= 1'b0;
	else if(axis_dma_write_data.valid && axis_dma_write_data.ready)
		axis_dma_write_data_cnt <= axis_dma_write_data_cnt + 1;    
	else
		axis_dma_write_data_cnt <= axis_dma_write_data_cnt;
end

always @(posedge user_clk)begin
	axis_dma_write_data_length <= (axis_dma_write_cmd.length>>6) - 1;
end


always @(posedge user_clk)begin
	if(~pcie_aresetn)
		axis_dma_read_data_cnt <= 1'b0;
	else if((axis_dma_read_data_cnt == axis_dma_read_data_length) && axis_dma_read_data.valid && axis_dma_read_data.ready)
		axis_dma_read_data_cnt <= 1'b0;
	else if(axis_dma_read_data.valid && axis_dma_read_data.ready)
		axis_dma_read_data_cnt <= axis_dma_read_data_cnt + 1;    
	else
		axis_dma_read_data_cnt <= axis_dma_read_data_cnt;
end

always @(posedge user_clk)begin
	axis_dma_read_data_length <= (axis_dma_read_cmd.length>>6) - 1;
end

assign axis_dma_read_data.ready = 1'b1;
assign axis_dma_write_data.valid = 1'b1;
assign axis_dma_write_data.keep = 64'hffff_ffff_ffff_ffff;
assign axis_dma_write_data.data = axis_dma_write_data_cnt;
assign axis_dma_write_data.last = axis_dma_write_data.valid && axis_dma_write_data.ready && (axis_dma_write_data_cnt == axis_dma_write_data_length);
assign m_axis_mlweaving_ready = 1'b1; 

always @(posedge user_clk)begin
	if(~pcie_aresetn)begin
		axis_dma_read_cmd.address		<= 0;
		axis_dma_read_cmd.length		<= 0;
		read_start						<= 0;
		ops								<= 0;
	end	
	else if(m_axis_mlweaving_ready && m_axis_mlweaving_valid)begin
		axis_dma_read_cmd.address		<= m_axis_mlweaving_data[ 63:0  ];
		axis_dma_read_cmd.length		<= m_axis_mlweaving_data[223:192];
		read_start						<= m_axis_mlweaving_data[256];
		ops								<= m_axis_mlweaving_data[319:288];
	end
	else if(axis_dma_read_cmd.valid && axis_dma_read_cmd.ready)begin
		axis_dma_read_cmd.address		<= axis_dma_read_cmd.address;
		read_start						<= 0;
	end
	else if((axis_dma_read_data_cnt > 0) && (rd_op_cnt < ops))begin
		read_start						<= 1'b1;
	end
	else begin
		axis_dma_read_cmd.address		<= axis_dma_read_cmd.address;
		axis_dma_read_cmd.length		<= axis_dma_read_cmd.length;
		read_start						<= read_start;
		ops								<= ops;
	end
end


always @(posedge user_clk)begin
	if(~pcie_aresetn)begin
		axis_dma_write_cmd.address		<= 0;
		axis_dma_write_cmd.length		<= 0;
		write_start						<= 0;
	end	
	else if(m_axis_mlweaving_ready && m_axis_mlweaving_valid)begin
		axis_dma_write_cmd.address		<= m_axis_mlweaving_data[127:64 ];
		axis_dma_write_cmd.length		<= m_axis_mlweaving_data[255:224];
		write_start						<= m_axis_mlweaving_data[257];
	end
	else if(axis_dma_write_cmd.valid && axis_dma_write_cmd.ready)begin
		axis_dma_write_cmd.address		<= axis_dma_write_cmd.address;
		write_start						<= 0;
	end
	else if((axis_dma_write_data_cnt > 0)&&(wr_op_cnt < ops))begin
		write_start						<= 1'b1;
	end
	else begin
		axis_dma_write_cmd.address		<= axis_dma_write_cmd.address;
		axis_dma_write_cmd.length		<= axis_dma_write_cmd.length;
		write_start						<= write_start;	
	end
end

*/



// ila_0 inst_ila_0 (
// 	.clk(user_clk), // input wire clk


// 	.probe0(axis_dma_read_cmd.valid), // input wire [0:0]  probe0  
// 	.probe1(axis_dma_read_cmd.ready), // input wire [0:0]  probe1 
// 	.probe2(axis_dma_write_cmd.valid), // input wire [0:0]  probe2 
// 	.probe3(axis_dma_write_cmd.ready), // input wire [0:0]  probe3 
// 	.probe4(axis_dma_read_data.data), // input wire [511:0]  probe4 
// 	.probe5({32'b0,read_cnt}), // input wire [63:0]  probe5 
// 	.probe6(axis_dma_read_data_cnt), // input wire [31:0]  probe6 
// 	.probe7(axis_dma_read_data.valid), // input wire [0:0]  probe7 
// 	.probe8(axis_dma_write_data.ready), // input wire [0:0]  probe8 
// 	.probe9(axis_dma_write_data.data), // input wire [511:0]  probe9 
// 	.probe10({32'b0,write_cnt}), // input wire [63:0]  probe10 
// 	.probe11(axis_dma_write_data_cnt), // input wire [31:0]  probe11
// 	.probe12(rd_cnt), // input wire [31:0]  probe12 
// 	.probe13(wr_cnt) // input wire [31:0]  probe13
// );

//ila_0 inst_ila_0 (
//	.clk(pcie_clk), // input wire clk


//	.probe0(axis_dma_write_cmd.valid), // input wire [0:0]  probe0  
//	.probe1(axis_dma_write_cmd.ready), // input wire [0:0]  probe1 
//	.probe2(axis_dma_write_cmd.address), // input wire [63:0]  probe2 
//	.probe3(axis_dma_write_cmd.length), // input wire [31:0]  probe3 
//	.probe4(axis_dma_write_data.ready), // input wire [0:0]  probe4 
//	.probe5(axis_dma_write_data.valid), // input wire [0:0]  probe5 
//	.probe6(axis_dma_write_data.data) // input wire [511:0]  probe6
//);

//ila_0 inst_ila_read (
//	.clk(pcie_clk), // input wire clk


//	.probe0(axis_dma_read_cmd.valid), // input wire [0:0]  probe0  
//	.probe1(axis_dma_read_cmd.ready), // input wire [0:0]  probe1 
//	.probe2(axis_dma_read_cmd.address), // input wire [63:0]  probe2 
//	.probe3(axis_dma_read_cmd.length), // input wire [31:0]  probe3 
//	.probe4(axis_dma_read_data.ready), // input wire [0:0]  probe4 
//	.probe5(axis_dma_read_data.valid), // input wire [0:0]  probe5 
//	.probe6(axis_dma_read_data.data) // input wire [511:0]  probe6
//);



//


/*

sgd_top_bw inst_sgd_top_bw(
    .clk(hbm_clk),
    .rst_n(hbm_rstn),
    //-------------------------------------------------//
    .start_um(1'b1),
    .um_params(512'b0),
    .um_done(),
    .um_state_counters(),

    .um_axi(hbm_axi[0])

);

//generate end generate
genvar i;
// Instantiate engines
generate
for(i = 1; i < 32; i++) 
begin
    
    assign hbm_axi[i].araddr    = 0;
    assign hbm_axi[i].arburst   = 2'b01;
    assign hbm_axi[i].arcache   = 4'b0;
    assign hbm_axi[i].arid      = 0;
    assign hbm_axi[i].arlen     = 8'b0;   
    assign hbm_axi[i].arlock    = 1'b0;   
    assign hbm_axi[i].arprot    = 3'b0;   
    assign hbm_axi[i].arqos     = 4'b0;   
    assign hbm_axi[i].arregion  = 4'b0;   
    assign hbm_axi[i].arsize    = 3'b0;   
    assign hbm_axi[i].arvalid   = 1'b0;   
    assign hbm_axi[i].aruser    = 0;
    assign hbm_axi[i].awaddr    = 0;  
    assign hbm_axi[i].awburst   = 2'b01;
    assign hbm_axi[i].awcache   = 4'b0;   
    assign hbm_axi[i].awid      = 0;
    assign hbm_axi[i].awlen     = 8'b0;   
    assign hbm_axi[i].awlock    = 1'b0;   
    assign hbm_axi[i].awprot    = 3'b0;   
    assign hbm_axi[i].awqos     = 4'b0;   
    assign hbm_axi[i].awregion  = 4'b0;   
    assign hbm_axi[i].awsize    = 3'b0;   
    assign hbm_axi[i].awvalid   = 1'b0;
    assign hbm_axi[i].awuser    = 0;
    assign hbm_axi[i].bready    = 1'b0;    
    assign hbm_axi[i].rready    = 1'b0;   
    assign hbm_axi[i].wdata     = 0;  
    assign hbm_axi[i].wlast     = 1'b0;
    assign hbm_axi[i].wstrb     = 0;  
    assign hbm_axi[i].wvalid    = 1'b0;   
    assign hbm_axi[i].wuser     = 0;



end
endgenerate

*/
    
endmodule
//`default_nettype wire