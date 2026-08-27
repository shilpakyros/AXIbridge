/*
typedef enum logic[1:0]{
	IDLE,
	SETUP,
	WAIT_S,
	TRAN
	} states;


typedef enum logic [1:0]{
//	NO_TRANSFER,
	OKAY,
	EXOKAY,
	SLVERR,
	DECERR
//	DEFER,
//	TRASFAULT,
//	UNSUPPORTED
}bresp_t;

typedef enum logic [1:0]{
		FIXED,
		INCR ,
		WRAP  ,
		RESERVED 
}bust_t;
*/

import axi_typedef_pkg::*;
module axi_slave #(parameter MEM_DEPTH = 256,
					parameter ADDR_WIDTH = 32,
					parameter DATA_WIDTH = 32,
					parameter STRB_WIDTH = 4,
					parameter FIFO_WIDTH = ADDR_WIDTH + DATA_WIDTH,
					parameter MEM_WIDTH = 8,
                    parameter PTR_WIDTH = 4,
					parameter COUNTER_WIDTH = 10)

				( input logic aclk,
				  input logic aresetn,
				  //write address channel
				  input logic awvalid,
				  input logic [ADDR_WIDTH-1:0]awaddr,
				  input logic [MEM_WIDTH-1:0]awlen,
				  input [2:0]awsize,
				  input bust_t awburst,
				  output logic awready, 
					
				  //write data channel
				  input logic wvalid,
				  input logic [DATA_WIDTH-1:0]wdata,
				  input logic [STRB_WIDTH-1:0]wstrb,
				  input logic wlast,
				  output logic wready,

				  //write response channel
				  input logic bready,
				  output bresp_t bresp,
				  output logic bvalid,

				  //read address channel
				  input logic arvalid,
				  input logic [ADDR_WIDTH-1:0]araddr,
				  input logic [MEM_WIDTH-1:0]arlen,
				  input logic [2:0]arsize,
				  input bust_t arburst,
				  output logic arready,

				  //read data and response channel
				  input logic rready,
				  output logic rvalid,
				  output logic [DATA_WIDTH-1:0]rdata,
				  output bresp_t rresp,
				  output logic rlast,
				  
				  output logic [FIFO_WIDTH-1:0]fifo_write,
				  output logic [ADDR_WIDTH-1:0]fifo_raddr_out,
				  input logic [DATA_WIDTH-1:0]fifo_rdata_in,
				  input logic full_flag,
				  input logic full_flag_rdata,
				  input logic apb_error,
				  output logic wr_en_waddr,
				  output logic wr_en_raddr,
				  input logic rdata_req,

                  output logic rdata_rd_en,     // newly added signal to read data from the async read fifo

                  // newly added signals that will say each beat is completed or not

                  input logic apb_wr_done,
                  input logic apb_rd_done,

                  output logic apb_rd_error_seen

);





//	reg	[MEM_WIDTH-1:0] mem [MEM_DEPTH -1:0];  //slave memory


//	integer count;
//	integer i;
	
	

	states aw_present_state;
	states aw_next_state;
	states w_present_state;
	states w_next_state;
	states b_present_state;
	states b_next_state;
//	states ar_present_state;
//	states ar_next_state;
//	states r_present_state;
//	states r_next_state;


	bust_t wburst;
	logic [2:0]wsize; // = 3'b0;
	logic [ADDR_WIDTH-1:0]awaddr_temp; // = 'b0;
    logic [ADDR_WIDTH-1:0] boundary; // = 'b0;
	logic [ADDR_WIDTH-1:0]upper_boundary; // = 'b0;
	logic [ADDR_WIDTH-1:0]lower_boundary; // = 'b0;
	logic [MEM_WIDTH-1:0]length; // = 8'b0;
//	logic [7:0]length_check = 8'b0;     // unused signal
	logic [MEM_WIDTH-1:0] write_length; // = 'b0;
	logic [ADDR_WIDTH-1:0]write_addr; // = 'b0;
//	logic wr_en_waddr;
    

// internal control signals    
    logic aw_hs_done;
    logic ar_hs_done;

// internals signals for write transaction compelte and slverr
    logic [MEM_WIDTH:0] apb_wr_done_count;
    logic apb_wr_error_seen;
    logic apb_wr_burst_done;
    logic [MEM_WIDTH:0] total_required_apb_awaddrs;

logic apb_wr_done_r;
logic apb_wr_done_p;


    // READ CHANNEL INTERNAL SIGNALS

typedef enum logic [1:0] {
    RD_AR_IDLE,
    RD_AR_CAPTURE
} rd_ar_fsm_t;

typedef enum logic [1:0] {
    RD_ADDR_IDLE,
    RD_ADDR_PUSH
} rd_addr_fsm_t;

// RD_R_POP inserted between WAIT_FIFO and SEND:
//   RD_R_POP  ? rdata_rd_en=1, rvalid=0  (FIFO pops, data settles next cycle)
//   RD_R_SEND ? rdata_rd_en=0, rvalid=1  (data stable; stall here until rready)
typedef enum logic [1:0] {
    RD_R_IDLE       = 2'b00,
    RD_R_WAIT_BURST = 2'b01,
    RD_R_POP        = 2'b10
//    RD_R_PRELOAD    = 2'b01,
//    RD_R_SEND       = 2'b11
} rd_rsp_fsm_t;


// PRESENT STATE REGISTERS

rd_ar_fsm_t   rd_ar_state,   rd_ar_next;
rd_addr_fsm_t rd_addr_state, rd_addr_next;
rd_rsp_fsm_t  rd_rsp_state,  rd_rsp_next;


// READ BURST STORAGE

logic [ADDR_WIDTH-1:0]          rd_base_addr;
logic [2:0]                     rd_transfer_size;
logic [MEM_WIDTH:0]             rd_total_beats;
logic [MEM_WIDTH:0]             rd_addr_push_count;
logic [MEM_WIDTH-1:0]           rd_return_count;

logic [2:0] rd_addr_incr_r;
//logic [2:0] rd_arsize_align_mask_r;

bust_t                          rd_burst_type;


// WRAP CALCULATIONS
logic [ADDR_WIDTH-1:0] rd_wrap_low_addr;
logic [ADDR_WIDTH-1:0] rd_wrap_high_addr;


// CURRENT ADDRESS TRACKING

logic [ADDR_WIDTH-1:0] rd_curr_addr;

logic [ADDR_WIDTH-1:0] rd_addr_unaligned;
logic [ADDR_WIDTH-1:0] rd_araddr_un;
logic [DATA_WIDTH-1:0] axi_rdata_unaligned;

// CONTROL FLAGS

logic rd_addr_phase_start;
logic rd_addr_phase_done;

// SLVERR control signals
//logic apb_rd_error_seen;
// logic [MEM_WIDTH:0] total_generated_apb_raddrs;
    logic ar_burst_ctrl;


logic apb_rd_done_r;
logic apb_rd_done_p;
logic [MEM_WIDTH:0] apb_rd_done_count;
logic apb_rd_burst_done;

//logic apb_error_q;
//logic apb_error_q0;
//logic apb_error_q1;
//logic apb_error_r;
logic apb_error_p;

// --------------APB ERROR PULSE------------------------
// cdc clearance
    always@(posedge aclk or negedge aresetn) begin
        if(!aresetn) begin
            apb_error_p <= 1'b0;
//            apb_error_r <= 1'b0;
//            apb_error_q0 <= 1'b0;
//            apb_error_q1 <= 1'b0;
        end else if(apb_error)begin
//            apb_error_q0 <= apb_error;
//            apb_error_q1 <= apb_error_q0;
//            apb_error_r <= apb_error_q1;
            apb_error_p <= 1'b1; //~apb_error_r && apb_error_q1;
        end else if(apb_wr_done_p || apb_rd_done_p) begin // only if single burst of write or read operations need to done
            apb_error_p <= 1'b0;
        end
    end
    
/*    always@(posedge aclk or negedge aresetn) begin
      if(!aresetn) begin
//          apb_error_p <= 1'b0;
          apb_error_q <= 1'b0;
          apb_error_r <= 1'b0;
      end else begin
          apb_error_q <= apb_error;
          apb_error_r <= apb_error_q;
      end 
//      else if(apb_error) begin
//          apb_error_p <= 1'b1;
//      end
   end

   always@(posedge aclk or negedge aresetn) begin
    if(!aresetn) begin
        apb_error_p <= 1'b0;
    end else if(apb_wr_done_p || apb_rd_done_p) begin
        apb_error_p <= 1'b0;
    end else if(apb_error_r) begin
        apb_error_p <= 1'b1;
    end
  end
*/


// ----------------full_flag_rdata register--------------------------
// cdc clearance
logic full_flag_rdata_q;

always_ff @(posedge aclk or negedge aresetn)
begin
    if(!aresetn)
        full_flag_rdata_q <= 1'b0;
    else
        full_flag_rdata_q <= full_flag_rdata;
end
    

//------------WRITE ADDRESS CHANNEL---------------------

	always@(posedge aclk or negedge aresetn) begin
		if(!aresetn) begin
			aw_present_state <= SETUP;
		end
		else begin
			aw_present_state <= aw_next_state;
		end
	end

	always_comb begin
		aw_next_state = aw_present_state; // aw_next_state is assigned to the  w_present_state which corrupts the WA channel, 
      									  // so modification is done
		case(aw_present_state)
          // IDLE state is not required here, also this state is depends on the aresetn which is not acceptable, because this is a combinational part of the FSM
/*			IDLE:begin
					if(aresetn) begin
						aw_next_state = SETUP;
				  	end
				  	else begin
						aw_next_state = IDLE;
				  	end
			end
            */
			SETUP:begin
					if(awvalid) begin
						aw_next_state = TRAN;
				  	end
				  	else begin
				  		aw_next_state = SETUP;
				  	end
			end
			TRAN:begin
				if(awvalid)begin
                  if(awready)begin // transition in this channel should depend on the current channel awready but not the W channel wready
						aw_next_state = SETUP;
					end
					else begin
						aw_next_state = TRAN;
					end
				end
				else begin
					aw_next_state = SETUP;
				end
			end 
		endcase
	end


    logic aw_burst_ctrl;
    always_ff@(posedge aclk or negedge aresetn) begin
        if(!aresetn) begin
            aw_burst_ctrl <= 1'b1;
        end else if(bvalid && bready) begin
            aw_burst_ctrl <= 1'b1;
        end else if(awvalid && awready) begin
            aw_burst_ctrl <= 1'b0;
        end
    end
 	
	always@(posedge aclk or negedge aresetn)begin
		if(!aresetn)begin
			awready <= 1'b0;
			wburst <= FIXED;
			length <= {MEM_WIDTH{1'b0}};
//			length_check <= 'b0;	// unused signal
			write_addr <= 'b0;
			wsize <= 3'b0;
			lower_boundary <= 'b0;
			boundary <= {ADDR_WIDTH{1'b0}};
            
            aw_hs_done <= 1'b0;
		end
		else begin
            if(!awvalid)
                aw_hs_done <= 1'b0;
            else if(awvalid && awready)
                aw_hs_done <= 1'b1;
//          			awready <= 1'b0;
//					lower_boundary <= lower_boundary;
//					boundary <= boundary;
		case(aw_present_state)
//			IDLE:begin 
//					awready <= 1'b0;
//					lower_boundary <= lower_boundary;
//					boundary <= boundary;
//			end
			SETUP:begin 
//					lower_boundary <= lower_boundary;
//                    boundary <= (({ADDR_WIDTH})'(awlen) +{{ADDR_WIDTH-1{1'b0}},1'b1})*({{ADDR_WIDTH-1{1'b0}},1'b1}<<({ADDR_WIDTH})'(awsize));		
                      boundary <= ({ADDR_WIDTH})'(awlen + {{MEM_WIDTH-1{1'b0}},1'b1}) << awsize;

//					if(awvalid)begin
						awready <= (~|apb_wr_done_count) && awvalid && !aw_hs_done && aw_burst_ctrl; 
                      						
//					end
//					else begin
//						awready <= 1'b0;
//					end
			end
			TRAN:begin
              			awready <= 1'b0;
//					if(awvalid && awready)begin
						wburst <= awburst; 	
						length <= awlen + {{MEM_WIDTH-1{1'b0}},1'b1};
//						length_check <= awlen + 1;	// unused signal
						write_addr <= awaddr;
						wsize <= awsize;
                      // need to check this
//                      lower_boundary  <= (awaddr/boundary)*boundary; // awaddr & ~(boundary - 1); // (awaddr/boundary)*boundary;
                      lower_boundary  <=  awaddr & ~(boundary - 1); // (awaddr/boundary)*boundary;
                      
//					end	
			end
			default:begin
					awready <= 1'b0;
					wburst <= FIXED;
					length <= {MEM_WIDTH{1'b0}};
//					length_check <= 'b0;    // unused signal
					write_addr <= 'b0;
					wsize <= 3'b0;
					lower_boundary <= 'b0;
					boundary <= 'b0;
			end
		endcase
	end
	end

//---------------------WRITE DATA CHANNEL------------------------

	always@(posedge aclk or negedge aresetn) begin
		if(!aresetn)begin
			w_present_state <= IDLE;
		end 
		else begin
			w_present_state <= w_next_state;
		end
	end

//logic [15:0] aw_count;
	always_comb begin
		w_next_state = w_present_state;
		case(w_present_state)
          // in the IDLE state the synchronization is doing with the AW FSM of slave
          // but the actuall synchronization need to be done with the W channel of Master
			IDLE:begin
//              if(aw_present_state == TRAN)begin // this condition need to depend on the adress handshake done 
//                				aw_count<=0;				// then only needed to start this FSM not based on the AW FSM state
              if(awvalid && awready)
						w_next_state = SETUP;
//					end
					else begin
						w_next_state = IDLE;
					end
			     end
			SETUP:begin
					if(wvalid && !full_flag)begin
						case(wburst)
							FIXED:w_next_state = TRAN;
							INCR:w_next_state = TRAN;
							WRAP:begin

//                                if(((awaddr_temp % {{ADDR_WIDTH-2{1'b0}},2'd2}*({ADDR_WIDTH})'(wsize)) == {ADDR_WIDTH{1'b0}}) && length inside {2 , 4 , 8 , 16})

//                                if((({{ADDR_WIDTH-1{1'b0}},awaddr_temp[0]}*({ADDR_WIDTH})'(wsize)) == {ADDR_WIDTH{1'b0}}) && length inside {2 , 4 , 8 , 16})
                                if(((awaddr_temp & ({ADDR_WIDTH})'((length << wsize)-{{MEM_WIDTH-1{1'b0}},1'b1})) == {ADDR_WIDTH{1'b0}}) && length inside {2 , 4 , 8 , 16})
//                                    (awaddr_temp & ((length << wsize)-1)) == 0
//                                      if((awaddr_temp % ((1 << wsize) * length)) == 0 &&
//   length inside {2,4,8,16})
                                      w_next_state = TRAN;
									else w_next_state = IDLE; // 
							    end
                            default: begin
                                        w_next_state = IDLE;
                                    end
						endcase
				  	end
				  	else begin
						w_next_state = SETUP;
				  	end
			end
			TRAN:begin
				if(wvalid && wready)begin
					//if(write_length == 8'b0 || wlast)begin
                  if(write_length == {{MEM_WIDTH-1{1'b0}},1'b0} && wlast)
                    begin
						w_next_state = IDLE;
					end
					else begin
						w_next_state = TRAN;
					end
				end
				else begin
					w_next_state = TRAN; //IDLE;
				end
			end
			default:w_next_state = IDLE;
		endcase
	end


logic [ADDR_WIDTH-1:0] addrw_incr_r;
logic [ADDR_WIDTH-1:0] addrw_mask_r;
logic [ADDR_WIDTH-1:0] awaddr_next_w;

always_comb
    awaddr_next_w = awaddr_temp + addrw_incr_r;

always@(posedge aclk or negedge aresetn) begin
 	if(!aresetn) begin
		wready <= 1'b0;
		write_length <= {MEM_WIDTH{1'b0}};
		awaddr_temp <= 'b0;
		upper_boundary <= 'b0;
        total_required_apb_awaddrs <= {MEM_WIDTH+1{1'b0}};

        addrw_incr_r <= 'b0;
        addrw_mask_r <= 'b0;
//        awaddr_next_w <= 'b0;
	end
	else begin

		case(w_present_state)
			IDLE:begin
				wready<=1'b0;
				write_length <= {MEM_WIDTH{1'b0}};
				awaddr_temp <= 'b0;
				upper_boundary <= 'b0;
                if(awvalid && awready) begin
                    total_required_apb_awaddrs <= {MEM_WIDTH+1{1'b0}};
					write_length <= awlen + {{MEM_WIDTH-1{1'b0}},1'b1};    
                    addrw_incr_r <= {{ADDR_WIDTH-1{1'b0}},1'b1} << awsize;
//                    addrw_mask_r <= (addrw_incr_r - {{ADDR_WIDTH-1{1'b0}},1'b1});
                    
                end
			end
			SETUP:begin
		//		if(wvalid)wready <= 1'b1; // wready should not only depend on the wvalid,
                                          // it should also need to check the FIFO depth, it has place or not 
                wready <= wvalid && !full_flag;
				if(write_length !={MEM_WIDTH{1'b0}}) write_length <= length - {{(MEM_WIDTH-1){1'b0}},1'b1}; // length -2;
				awaddr_temp <= write_addr;
				upper_boundary <= lower_boundary + boundary; 
                    addrw_mask_r <= ~(addrw_incr_r - {{ADDR_WIDTH-1{1'b0}},1'b1});
                
					
			end
			TRAN:begin
				upper_boundary <= lower_boundary + boundary; 
                wready <= wvalid && !full_flag;
				
//				if(wvalid && wready && !full_flag)begin
					if(write_length !={MEM_WIDTH{1'b0}}) write_length <= write_length - {{(MEM_WIDTH-1){1'b0}},1'b1};
                        
                    
                case(wburst)
                    FIXED: begin
                                awaddr_temp <= awaddr_temp;
                                total_required_apb_awaddrs <= ({MEM_WIDTH+1})'(awlen + {{(MEM_WIDTH-1){1'b0}},1'b1});                             
                           end
                    INCR: begin
                                total_required_apb_awaddrs <= ({MEM_WIDTH+1})'(awlen + {{(MEM_WIDTH-1){1'b0}},1'b1});
                    
                                //rd_curr_addr <= rd_curr_addr + (1 << rd_transfer_size);
//                                if (|(awaddr_temp % ({{ADDR_WIDTH-1{1'b0}},1'b1}<<(ADDR_WIDTH)'(wsize)))) begin
//                                    if (| (awaddr_temp & (({{ADDR_WIDTH-1{1'b0}},1'b1} << (ADDR_WIDTH)'(wsize)) - {{ADDR_WIDTH-1{1'b0}},1'b1}))) begin
                                    if (| (awaddr_temp & (addrw_incr_r) - {{ADDR_WIDTH-1{1'b0}},1'b1})) begin
                                        
                                    // This is beat 0 being pushed; compute beat-1 address.
                                    // Align up: advance by size then mask off low bits.
//                                    awaddr_temp <= (awaddr_temp + ({{ADDR_WIDTH-1{1'b0}},1'b1} << wsize)) & ~((({ADDR_WIDTH})'(1) << wsize) - {{ADDR_WIDTH-1{1'b0}},1'b1});
//                                    awaddr_temp <= (awaddr_temp + addrw_incr_r) & ~(addrw_incr_r - {{ADDR_WIDTH-1{1'b0}},1'b1});
//                                    awaddr_temp <= (awaddr_temp + addrw_incr_r) & addrw_mask_r;//~(addrw_incr_r - {{ADDR_WIDTH-1{1'b0}},1'b1});
                                    awaddr_temp <= awaddr_next_w & addrw_mask_r;//~(addrw_incr_r - {{ADDR_WIDTH-1{1'b0}},1'b1});
                                    
                                end else begin
                                    // Beat 1 onwards: already aligned, just increment
//                                    awaddr_temp <= awaddr_temp + ({{ADDR_WIDTH-1{1'b0}},1'b1} << wsize);
//                                    awaddr_temp <= awaddr_temp + addrw_incr_r; //({{ADDR_WIDTH-1{1'b0}},1'b1} << wsize);
                                    awaddr_temp <= awaddr_next_w; //awaddr_temp + addrw_incr_r; //({{ADDR_WIDTH-1{1'b0}},1'b1} << wsize);
                                    
                                end
                          end
                    WRAP: begin
                                total_required_apb_awaddrs <= (MEM_WIDTH+1)'(awlen + {{(MEM_WIDTH-1){1'b0}},1'b1});
                    
//                            if (rd_addr_push_count == rd_total_beats) begin
//                                // Compute aligned beat-1 address
//                                rd_curr_addr <=
//                                    (rd_curr_addr + (1 << rd_transfer_size))
//                                    & ~((32'(1) << rd_transfer_size) - 1);
//                            end else begin
                                // Normal wrap increment
//                                if ((awaddr_temp + ({{ADDR_WIDTH-1{1'b0}},1'b1} << wsize)) >= upper_boundary)
//                                if ((awaddr_temp + (addrw_incr_r)) >= upper_boundary)
                                if (awaddr_next_w >= upper_boundary)
                                    
                                    awaddr_temp <= lower_boundary;
                                else
//                                    awaddr_temp <= awaddr_temp + ({{ADDR_WIDTH-1{1'b0}},1'b1} << wsize);
//                                    awaddr_temp <= awaddr_temp + addrw_incr_r; //({{ADDR_WIDTH-1{1'b0}},1'b1} << wsize);
                                    awaddr_temp <= awaddr_next_w; //awaddr_temp + addrw_incr_r; //({{ADDR_WIDTH-1{1'b0}},1'b1} << wsize);
                                    
//                            end   
                        end
                        
                    default: awaddr_temp <= awaddr_temp;
               endcase


//			end
			end
			default:begin
				write_length <= {MEM_WIDTH{1'b0}};
				awaddr_temp <= 'b0;
				upper_boundary <='b0;
                addrw_incr_r <= 'b0;
                addrw_mask_r <= 'b0;

			end
		endcase
	end
end

/*
logic [DATA_WIDTH-1:0] stage [STRB_WIDTH:0];

always_comb begin
    wr_en_waddr = 1'b0;
    fifo_write  = '0;
    stage[STRB_WIDTH] = '0;

    for (int i = STRB_WIDTH-1; i >= 0; i--)
        stage[i] = '0;

    if (wvalid && wready && !full_flag) begin
        wr_en_waddr = 1'b1;

        for (int i = STRB_WIDTH-1; i >= 0; i--) begin
            if (wstrb[i])
                stage[i] = {stage[i+1][DATA_WIDTH-MEM_WIDTH-1:0],
                            wdata[i*MEM_WIDTH +: MEM_WIDTH]};
            else
                stage[i] = stage[i+1];
        end

        if (wstrb != '0)
            fifo_write = {awaddr_temp, stage[0]};
        else
            fifo_write = '0;
    end
end
*/
logic [DATA_WIDTH-1:0] stage;

always_comb begin
    wr_en_waddr = 1'b0;
    fifo_write  = '0;
    stage       = '0;

    if (wvalid && wready && !full_flag) begin
        wr_en_waddr = 1'b1;

        for (int i = STRB_WIDTH-1; i >= 0; i--) begin
            if (wstrb[i]) begin
                stage = {stage[DATA_WIDTH-MEM_WIDTH-1:0],
                         wdata[i*MEM_WIDTH +: MEM_WIDTH]};
            end
        end

        if (|wstrb)
            fifo_write = {awaddr_temp, stage};
    end
end

/*
always_comb begin
	wr_en_waddr = 1'b0;
	fifo_write = {FIFO_WIDTH{1'b0}};
		if(wvalid && wready && (!full_flag))begin
			wr_en_waddr = 1'b1;
				case(wstrb)
							4'b0000:begin
										fifo_write = {FIFO_WIDTH{1'b0}};
							end
						    4'b0001:begin
										fifo_write = {awaddr_temp,24'b0,wdata[7:0]};
							end
							4'b0010:begin
										fifo_write = {awaddr_temp,24'b0,wdata[15:8]};
							end
							4'b0011:begin
										fifo_write = {awaddr_temp,16'b0,wdata[15:0]};
							end
							4'b0100:begin
										fifo_write = {awaddr_temp,24'b0,wdata[23:16]};
							end
							4'b0101:begin
										fifo_write = {awaddr_temp,16'b0,wdata[23:16],wdata[7:0]};
							end
							4'b0110:begin
										fifo_write = {awaddr_temp,16'b0,wdata[23:8]};
							end
							4'b0111:begin
										fifo_write = {awaddr_temp,8'b0,wdata[23:0]};
							end
							4'b1000:begin
										fifo_write = {awaddr_temp,24'b0,wdata[31:24]};
							end
							4'b1001:begin
										fifo_write = {awaddr_temp,16'b0,wdata[31:24],wdata[7:0]};
							end
							4'b1010:begin
										fifo_write = {awaddr_temp,16'b0,wdata[31:24],wdata[15:8]};
							end
							4'b1011:begin
										fifo_write = {awaddr_temp,8'b0,wdata[31:24],wdata[15:0]};
							end
							4'b1100:begin
										fifo_write = {awaddr_temp,16'b0,wdata[31:16]};
							end
							4'b1101:begin
										fifo_write = {awaddr_temp,8'b0,wdata[31:16],wdata[7:0]};
							end
							4'b1110:begin
										fifo_write = {awaddr_temp,8'b0,wdata[31:8]};
							end
							4'b1111:begin
										fifo_write = {awaddr_temp,wdata[31:0]};
							end
//							default: fifo_write = {FIFO_WIDTH{1'b0}};
						endcase
			end
			else begin
					fifo_write = {FIFO_WIDTH{1'b0}};
					wr_en_waddr = 1'b0;
			end						
end
*/


//----------------------write response channel-----------------------------


always_ff@(posedge aclk or negedge aresetn) begin
    if(!aresetn) begin
        apb_wr_done_r <= 1'b0;
        apb_wr_done_p <=1'b0;
    end else begin
        apb_wr_done_r <= apb_wr_done;
        apb_wr_done_p <= ~apb_wr_done_r && apb_wr_done;
    end
end

always @(posedge aclk or negedge aresetn) begin
    if(!aresetn) begin
        apb_wr_done_count <= '0;
        apb_wr_error_seen <= 1'b0;
    end
    else begin

        if(bvalid && bready) begin
            apb_wr_error_seen <= 1'b0;
        end

        // New write burst started
        else if(apb_wr_burst_done ) begin//|| (bvalid && bready)) begin
//        if(bvalid && bready ) begin //&& (apb_wr_done_count == total_required_apb_awaddrs)) begin
            apb_wr_done_count <= '0;
//            apb_wr_error_seen <= 1'b0;
        // APB completed one beat
        end else if(apb_wr_done_p) begin
            apb_wr_done_count <= apb_wr_done_count + {{MEM_WIDTH{1'b0}},1'b1};
            // Sticky error accumulation
            if(apb_error_p)
                apb_wr_error_seen <= 1'b1;
        end
    end

/*
	if(!aresetn)begin
		apb_wr_burst_done <= 1'b0;
	end
    else if(b_present_state == TRAN || (~|total_required_apb_awaddrs ))// && bready && bvalid)
         begin
            apb_wr_burst_done <= 1'b0;
    end	else if((apb_wr_done_count == total_required_apb_awaddrs)) begin//(total_generated_apb_cmds - 1))
            apb_wr_burst_done <= 1'b1;
	end

*/


end


// weather burst completed or not
always@(posedge aclk or negedge aresetn)begin
	if(!aresetn)begin
		apb_wr_burst_done <= 1'b0;
	end
    else if(b_present_state == TRAN || (~|total_required_apb_awaddrs ))// && bready && bvalid)
//      else if(awvalid && awready) 
         begin
            apb_wr_burst_done <= 1'b0;
//    end else if(apb_time_out_p) begin
//        apb_wr_burst_done <= 1'b0;
    end	else if((apb_wr_done_count == total_required_apb_awaddrs)) begin//(total_generated_apb_cmds - 1))
            apb_wr_burst_done <= 1'b1;
	end

end


always@(posedge aclk or negedge aresetn)begin
	if(!aresetn)begin
		b_present_state <= IDLE;
	end
	else begin
		b_present_state <= b_next_state;
	end
end

always_comb begin
  	b_next_state = b_present_state; 	// default is not written  for the FSM state's
	case(b_present_state)
		IDLE:begin
          //				if(wlast)begin // if master asserts wlast, slave might be ready or not
          // without knowing the response is sending out
          // if all this are then we are sure baout the W channel slave response
//          if(wvalid && wready && wlast)
                if(apb_wr_burst_done)
					b_next_state = TRAN;
//				end
				else begin
					b_next_state = IDLE;
				end
		end
		TRAN:begin
                if(bready)
                    b_next_state = IDLE;
//                else if(!bready)
//                    b_next_state = TRAN;
                else
                    b_next_state = TRAN;

		end
        default: begin
               b_next_state = IDLE;
               end
	endcase
end


always@(posedge aclk or negedge aresetn)begin
	if(!aresetn)begin
		bvalid <= 1'b0;
		bresp <= OKAY;
	end
	else begin
//		bvalid <= 0;
//		bresp <= NO_TRANSFER;
		case(b_present_state)
			IDLE:begin
				bvalid <= 1'b0;
				bresp <= OKAY;
			end

            // previously SETUP and TRAN states has exactly same logic which is like a duplicate state
            // not written properly for those states logic accordingly, deleted the SETUP state
			TRAN:begin
                    if(bready && bvalid)
                      begin
					    bvalid <= 1'b0;
                            bresp <= OKAY;
                      end
                    else
                      begin
                        bvalid <= 1'b1;
					    if(apb_wr_error_seen)begin
						    bresp <= SLVERR;
					    end
					    else begin
						    bresp <= OKAY;
					    end
                      end
			end
			default:begin
					bvalid <= 1'b0;
					bresp <= OKAY;
			end
		endcase
	end
end


//-----------read_address channel-------------------
// completely modified the AR and R channels

// READ ADDRESS CHANNEL FSM 1 (rd_ar_state)

// STATE REGISTER

always_ff @(posedge aclk or negedge aresetn) begin
    if(!aresetn) rd_ar_state <= RD_AR_IDLE;
    else         rd_ar_state <= rd_ar_next;
end


// NEXT STATE combinational

always_comb begin
    rd_ar_next = rd_ar_state;   // default: hold
    case(rd_ar_state)

        RD_AR_IDLE: begin
            if(arvalid && arready)
                rd_ar_next = RD_AR_CAPTURE;
            else
                rd_ar_next = RD_AR_IDLE;
        end

        RD_AR_CAPTURE: begin
            rd_ar_next = RD_AR_IDLE;    // single dead cycle, back immediately
        end

        default: rd_ar_next = RD_AR_IDLE;
    endcase
end

// OUTPUT LOGIC
/*
    always_ff@(posedge aclk or negedge aresetn) begin
        if(!aresetn) begin
            ar_burst_ctrl <= 1'b1;
        end else if(rvalid && rready) begin
            ar_burst_ctrl <= 1'b1;
        end else if(arvalid && arready) begin
            ar_burst_ctrl <= 1'b0;
        end
    end
 	
*/

  always_ff @(posedge aclk or negedge aresetn) begin
    if(!aresetn) begin
        arready               <= 1'b0;
        rd_base_addr          <= {ADDR_WIDTH{1'b0}};
        rd_transfer_size      <= '0;
        rd_total_beats        <= {MEM_WIDTH+1{1'b0}};
        rd_burst_type         <= FIXED;
        rd_wrap_low_addr      <= {ADDR_WIDTH{1'b0}};
        rd_wrap_high_addr     <= {ADDR_WIDTH{1'b0}};
        rd_addr_phase_start   <= 1'b0;
        
        rd_addr_incr_r  <= '0;
//        rd_arsize_align_mask_r <= '0;

        ar_hs_done            <= 1'b0;

        rd_araddr_un       <= {ADDR_WIDTH{1'b0}};   // for unaligned data
    end else begin
        rd_addr_phase_start <= 1'b0;    // default: pulse one cycle only

            if(!arvalid)
                ar_hs_done <= 1'b0;
            else if(arvalid && arready)
                ar_hs_done <= 1'b1;

        case(rd_ar_state)
           

            RD_AR_IDLE: begin
			      arready <= arvalid && !ar_hs_done && ar_burst_ctrl && !full_flag_rdata_q; 

                if(arvalid && arready) begin
                    rd_base_addr     <= araddr;
                    rd_transfer_size <= arsize;
                    rd_total_beats   <= ({MEM_WIDTH+1})'(arlen + {{MEM_WIDTH-1{1'b0}},1'b1});
                    rd_burst_type    <= arburst;

                    rd_addr_incr_r <= (3'b1 << arsize);
//                    rd_arsize_align_mask_r <= ~((1 << arsize) - {{ADDR_WIDTH-1{1'b0}},1'b1});

                    rd_araddr_un   <= araddr;        // unalign tracking from last bits of araddr


//                    rd_wrap_low_addr <= (araddr / (((ADDR_WIDTH)'(arlen) + {{ADDR_WIDTH-1{1'b0}},1'b1}) * ({{ADDR_WIDTH-1{1'b0}},1'b1} << ({ADDR_WIDTH})'(arsize)))) * (((ADDR_WIDTH)'(arlen) + {{ADDR_WIDTH-1{1'b0}},1'b1}) * ({{ADDR_WIDTH-1{1'b0}},1'b1} << ({ADDR_WIDTH})'(arsize)));
                    rd_wrap_low_addr  <= araddr & ~((ADDR_WIDTH)'(((arlen + {{MEM_WIDTH-1{1'b0}},1'b1}) << arsize) - {{MEM_WIDTH-1{1'b0}},1'b1}));
//                    rd_wrap_high_addr <= ((araddr / (((ADDR_WIDTH)'(arlen) + {{ADDR_WIDTH-1{1'b0}},1'b1}) * ({{ADDR_WIDTH-1{1'b0}},1'b1} << (ADDR_WIDTH)'(arsize)))) * (((ADDR_WIDTH)'(arlen) + {{ADDR_WIDTH-1{1'b0}},1'b1}) * ({{ADDR_WIDTH-1{1'b0}},1'b1} << ({ADDR_WIDTH})'(arsize)))) + (((ADDR_WIDTH)'(arlen) + {{ADDR_WIDTH-1{1'b0}},1'b1}) * ({{ADDR_WIDTH-1{1'b0}},1'b1} << (ADDR_WIDTH)'(arsize)));
                    rd_wrap_high_addr <= (araddr & ~((ADDR_WIDTH)'(((arlen + {{MEM_WIDTH-1{1'b0}},1'b1}) << arsize) - {{MEM_WIDTH-1{1'b0}},1'b1}))) + (ADDR_WIDTH)'((arlen + {{MEM_WIDTH-1{1'b0}},1'b1}) << arsize);
                    rd_addr_phase_start <= 1'b1;
                    arready             <= 1'b0;
                end
            end

            RD_AR_CAPTURE: begin
                arready <= 1'b0;
            end

            default: begin
                        arready               <= 1'b0;
                        rd_base_addr          <= {ADDR_WIDTH{1'b0}};
                        rd_transfer_size      <= '0;
                        rd_total_beats        <= {MEM_WIDTH+1{1'b0}};
                        rd_burst_type         <= FIXED;
                        rd_wrap_low_addr      <= {ADDR_WIDTH{1'b0}};
                        rd_wrap_high_addr     <= {ADDR_WIDTH{1'b0}};
                        rd_addr_phase_start   <= 1'b0;

//                        rd_arsize_align_mask_r <= '0;
                        rd_addr_incr_r <= '0;

                        ar_hs_done            <= 1'b0;

                        rd_araddr_un          <= {ADDR_WIDTH{1'b0}};  
                     end

        endcase
    end


  end


  always_ff @(posedge aclk or negedge aresetn) begin

        if(!aresetn) begin
            ar_burst_ctrl <= 1'b1;
        end else if(rvalid && rready) begin
            ar_burst_ctrl <= 1'b1;
        end else if(arvalid && arready) begin
            ar_burst_ctrl <= 1'b0;
        end
  end


// READ ADDRESS GENERATOR FSM 2 (rd_addr_state)

// NEXT STATE combinational

always_comb begin
    rd_addr_next = rd_addr_state;   // default: hold
    case(rd_addr_state)

        RD_ADDR_IDLE: begin
            if(rd_addr_phase_start)
                rd_addr_next = RD_ADDR_PUSH;
            else
                rd_addr_next = RD_ADDR_IDLE;
        end

        RD_ADDR_PUSH: begin
            if(rd_addr_push_count == {{MEM_WIDTH{1'b0}},1'b1})
                rd_addr_next = RD_ADDR_IDLE;    // last address pushed
            else
                rd_addr_next = RD_ADDR_PUSH;
        end

        default: rd_addr_next = RD_ADDR_IDLE;
    endcase
end

// STATE REGISTER

always_ff @(posedge aclk or negedge aresetn) begin
    if(!aresetn) 
        rd_addr_state <= RD_ADDR_IDLE;
    else         
        rd_addr_state <= rd_addr_next;
end

// OUTPUT LOGIC

always_ff @(posedge aclk or negedge aresetn) begin
    if(!aresetn) begin
        wr_en_raddr        <= 1'b0;
        fifo_raddr_out     <= {ADDR_WIDTH{1'b0}};
        rd_curr_addr       <= {ADDR_WIDTH{1'b0}};
        rd_addr_push_count <= {MEM_WIDTH+1{1'b0}};
        rd_addr_phase_done <= 1'b0;

//        total_generated_apb_raddrs <= 'b0;
    end else begin
        wr_en_raddr        <= 1'b0;     // default: no push
        rd_addr_phase_done <= 1'b0;     // default: pulse one cycle only


        case(rd_addr_state)

            RD_ADDR_IDLE: begin
                if(rd_addr_phase_start) begin
                    rd_curr_addr       <= rd_base_addr;
                    rd_addr_push_count <= rd_total_beats;
                end
            end

            RD_ADDR_PUSH: begin
                wr_en_raddr    <= 1'b1;
                fifo_raddr_out <= rd_curr_addr;
//                total_generated_apb_raddrs <= total_generated_apb_raddrs + 1'b1;

                if(rd_addr_push_count == {{MEM_WIDTH{1'b0}},1'b1})
                    rd_addr_phase_done <= 1'b1;

                rd_addr_push_count <= rd_addr_push_count - {{MEM_WIDTH{1'b0}},1'b1};

                case(rd_burst_type)
                    FIXED: begin
                                rd_curr_addr <= rd_curr_addr;
                           end
                    INCR: begin
                                //rd_curr_addr <= rd_curr_addr + (1 << rd_transfer_size);
                                if (rd_addr_push_count == rd_total_beats) begin
                                    // This is beat 0 being pushed; compute beat-1 address.
                                    // Align up: advance by size then mask off low bits.
//                                    rd_curr_addr <= (rd_curr_addr + (1<<rd_transfer_size)) & ~((({ADDR_WIDTH})'(1) << rd_transfer_size) - {{ADDR_WIDTH-1{1'b0}},1'b1});
                                    rd_curr_addr <= (rd_curr_addr + ({ADDR_WIDTH})'(rd_addr_incr_r)) & ~(({ADDR_WIDTH})'(rd_addr_incr_r) - {{ADDR_WIDTH-1{1'b0}},1'b1});//rd_arsize_align_mask_r;
//                                    rd_curr_addr <= (rd_curr_addr + rd_addr_incr_r) & rd_arsize_align_mask_r;

                                end else begin
                                    // Beat 1 onwards: already aligned, just increment
//                                    rd_curr_addr <= rd_curr_addr + (1 << rd_transfer_size);
                                    rd_curr_addr <= rd_curr_addr + ({ADDR_WIDTH})'(rd_addr_incr_r); //(1 << rd_transfer_size);
                                    
                                end
                          end
                    WRAP: begin
//                            if (rd_addr_push_count == rd_total_beats) begin
//                                // Compute aligned beat-1 address
//                                rd_curr_addr <=
//                                    (rd_curr_addr + (1 << rd_transfer_size))
//                                    & ~((32'(1) << rd_transfer_size) - 1);
//                            end else begin
                                // Normal wrap increment
//                                if ((rd_curr_addr + (1 << rd_transfer_size)) >= rd_wrap_high_addr)
                                if ((rd_curr_addr + ({ADDR_WIDTH})'(rd_addr_incr_r)) >= rd_wrap_high_addr)                                
                                    rd_curr_addr <= rd_wrap_low_addr;
                                else
//                                    rd_curr_addr <= rd_curr_addr + (1 << rd_transfer_size);
                                    rd_curr_addr <= rd_curr_addr + ({ADDR_WIDTH})'(rd_addr_incr_r); //(1 << rd_transfer_size);
                                    
//                            end   
                        end
                    default: rd_curr_addr <= rd_curr_addr;
               endcase
           end

           default: begin
                        wr_en_raddr        <= 1'b0;
                        fifo_raddr_out     <= {ADDR_WIDTH{1'b0}};
                        rd_curr_addr       <= {ADDR_WIDTH{1'b0}};
                        rd_addr_push_count <= {MEM_WIDTH+1{1'b0}};
                        rd_addr_phase_done <= 1'b0;

//                        total_generated_apb_raddrs <= 'b0;
                    end
        endcase
    end
end



//============================================================
// READ RESPONSE CHANNEL FSM 3 (rd_rsp_state)
//
// Per-beat flow:
//   RD_R_WAIT_FIFO ? (rdata_req) ?
//   RD_R_POP       : rdata_rd_en=1, rvalid=0  FIFO pops
//   RD_R_SEND      : rdata_rd_en=0, rvalid=1  data stable
//     rready=0     ? stall (stay RD_R_SEND, no pop, rdata frozen)
//     rready=1, not last ? RD_R_WAIT_FIFO
//     rready=1, last     ? RD_R_IDLE
//============================================================
//logic rdata_rd_en_reg;



always_ff@(posedge aclk, negedge aresetn) begin
    if(!aresetn) begin
        apb_rd_done_r <= 1'b0;
        apb_rd_done_p <= 1'b0;
    end else begin
        apb_rd_done_r <= apb_rd_done;
        apb_rd_done_p <= ~apb_rd_done_r && apb_rd_done;
    end
end

always_ff @(posedge aclk or negedge aresetn) begin
    if(!aresetn) begin
        apb_rd_done_count <= '0;
        apb_rd_error_seen <= 1'b0;
    end
    else begin

        if(arvalid && arready) begin
            apb_rd_error_seen <= 1'b0;
        end

        // New write burst started
        else if(apb_rd_burst_done ) begin//|| (bvalid && bready)) begin
//        if(bvalid && bready ) begin //&& (apb_wr_done_count == total_required_apb_awaddrs)) begin
            apb_rd_done_count <= '0;
//            apb_wr_error_seen <= 1'b0;
//        end else if(apb_time_out_p) begin
//            apb_wr_error_seen <= 1'b1;
        // APB completed one beat
        end else if(apb_rd_done_p) begin
            apb_rd_done_count <= apb_rd_done_count + (MEM_WIDTH+1)'(1);//{{MEM_WIDTH-1{1'b0}},1'b1};
            // Sticky error accumulation
            if(apb_error_p)
                apb_rd_error_seen <= 1'b1;
        end
    end
end

// weather burst completed or not
always@(posedge aclk or negedge aresetn)begin
	if(!aresetn)begin
		apb_rd_burst_done <= 1'b0;
	end
    else if(rd_rsp_state == RD_R_IDLE || (~|rd_total_beats ))// && bready && bvalid)
//      else if(awvalid && awready) 
         begin
            apb_rd_burst_done <= 1'b0;
    end	else if((apb_rd_done_count == rd_total_beats)) begin//(total_generated_apb_cmds - 1))
            apb_rd_burst_done <= 1'b1;
	end

end



/*
always_ff @(posedge aclk or negedge aresetn) begin
    if(!aresetn) begin
        apb_rd_error_seen <= 1'b0;
    end
    else begin


        // New write burst started
        if(rlast) begin
            apb_rd_error_seen <= 1'b0;
        end
        // APB completed one beat
        else if(apb_rd_done_p) begin
            if(apb_error)
                apb_rd_error_seen <= 1'b1;
        end
    end
end

*/



// STATE REGISTER
always_ff @(posedge aclk or negedge aresetn) begin
    if(!aresetn) 
        rd_rsp_state <= RD_R_IDLE;
    else         
        rd_rsp_state <= rd_rsp_next;
end

// NEXT STATE combinational

always_comb begin
    rd_rsp_next = rd_rsp_state;     // default: hold
    case(rd_rsp_state)

        RD_R_IDLE: begin
            if(rd_addr_phase_done)
                rd_rsp_next = RD_R_WAIT_BURST;
            else
                rd_rsp_next = RD_R_IDLE;
        end

        RD_R_WAIT_BURST: begin
            if(apb_rd_burst_done) begin
                rd_rsp_next = RD_R_POP;
            end
            else
                rd_rsp_next = RD_R_WAIT_BURST;
        end

        RD_R_POP: begin
            // Always one cycle; FIFO data settles during this cycle
            if(rvalid && rready) begin
                if(({1'b0,rd_return_count} == rd_total_beats-{{MEM_WIDTH{1'b0}},1'b1}))
                    rd_rsp_next = RD_R_IDLE;
                else
                    rd_rsp_next = RD_R_POP;
//            rd_rsp_next = RD_R_SEND;
            end
            else begin
                rd_rsp_next = RD_R_POP;
             end
        end

        default: rd_rsp_next = RD_R_IDLE;
    endcase
end


// OUTPUT LOGIC

always_ff @(posedge aclk or negedge aresetn) begin
    if(!aresetn) begin
        rvalid              <= 1'b0;
        rresp               <= OKAY;
        rd_return_count     <= '0;
        rdata_rd_en         <= 1'b0;
        rd_addr_unaligned   <= 'b0;
    end else begin

        case(rd_rsp_state)

            RD_R_IDLE: begin
                rvalid          <= 1'b0;
                rresp           <= OKAY;
                rd_return_count <= {MEM_WIDTH{1'b0}};
                rdata_rd_en     <= 1'b0;
            end

            RD_R_WAIT_BURST: begin
                rvalid <= 1'b0;
                rd_addr_unaligned <= rd_araddr_un;
            end

            // One-cycle pop strobe rvalid stays 0
            // rdata_rd_en is combinationally 1 (state == RD_R_POP)
            RD_R_POP: begin
                rdata_rd_en <= rdata_req;//(rd_return_count == rd_total_beats -2) ? 1'b0: 1'b1;

                if(rdata_rd_en) begin
//                    rvalid <= 1'b1;
                                    rvalid <= 1'b1;
                rresp  <= apb_rd_error_seen ? SLVERR : OKAY;

                if(rvalid && rready) begin
                    rd_return_count <= rd_return_count + {{MEM_WIDTH-1{1'b0}},1'b1};
                    
                case(rd_burst_type)
                    FIXED: begin
                                rd_addr_unaligned <= rd_addr_unaligned;
                           end
                    INCR: begin
                                //rd_curr_addr <= rd_curr_addr + (1 << rd_transfer_size);
                                if (rd_return_count == {MEM_WIDTH{1'b0}}) begin
                                    // This is beat 0 being pushed; compute beat-1 address.
                                    // Align up: advance by size then mask off low bits.
//                                    rd_addr_unaligned <= (rd_addr_unaligned + (1 << rd_transfer_size)) & ~((({ADDR_WIDTH})'(1) << rd_transfer_size) - {{ADDR_WIDTH-1{1'b0}},1'b1});
                                    rd_addr_unaligned <= (rd_addr_unaligned + ({ADDR_WIDTH})'(rd_addr_incr_r)) & ~(({ADDR_WIDTH})'(rd_addr_incr_r) - {{ADDR_WIDTH-1{1'b0}},1'b1});
                                    
                                end else begin
                                    // Beat 1 onwards: already aligned, just increment
//                                    rd_addr_unaligned <= rd_addr_unaligned + (1 << rd_transfer_size);
                                    rd_addr_unaligned <= rd_addr_unaligned + ({ADDR_WIDTH})'(rd_addr_incr_r); //(1 << rd_transfer_size);
                                    
                                end
                          end
                    WRAP: begin
                                // Normal wrap increment
//                                if ((rd_addr_unaligned + (1 << rd_transfer_size)) >= rd_wrap_high_addr)
                                if ((rd_addr_unaligned + ({ADDR_WIDTH})'(rd_addr_incr_r)) >= rd_wrap_high_addr)
                                    
                                    rd_addr_unaligned <= rd_wrap_low_addr;
                                else
//                                    rd_addr_unaligned <= rd_addr_unaligned + (1 << rd_transfer_size);
                                    rd_addr_unaligned <= rd_addr_unaligned + ({ADDR_WIDTH})'(rd_addr_incr_r); //(1 << rd_transfer_size);
                                    
//                            end   
                        end
                        
                    default: rd_addr_unaligned <= rd_addr_unaligned;
               endcase


                    if({1'b0,rd_return_count} == rd_total_beats - {{MEM_WIDTH{1'b0}},1'b1}) begin
                        // Last beat burst done
                        rvalid              <= 1'b0;
                        rresp               <= OKAY;
                    end else begin
                        // More beats drop rvalid while waiting for next pop
                        rvalid <= 1'b1;
                    end
                end
                // else: rready=0 ? rvalid stays 1, stall

//                    rdata
                end
                else
                    rvalid <= 1'b0; 
            end

            // Data is stable drive rvalid=1 and stall until rready
            // rdata_rd_en is combinationally 0 (state != RD_R_POP)
            // fifo_rdata_in is frozen during stall ? rdata (comb) stable
            default: begin
                rresp <= OKAY;
             end
        endcase
    end
end


// COMBINATIONAL OUTPUTS

//logic [DATA_WIDTH-1:0] axi_rdata_unaligned;
logic [$clog2(STRB_WIDTH):0] valid_bytes;
logic [$clog2(STRB_WIDTH)-1:0] addr_offset;

always_comb begin
    axi_rdata_unaligned = {DATA_WIDTH{1'b0}};
    addr_offset = rd_addr_unaligned[$clog2(STRB_WIDTH)-1:0];

    // Bytes before next naturally-aligned boundary
    valid_bytes = ({$clog2(STRB_WIDTH)+1})'(1 << rd_transfer_size) -
                  ({$clog2(STRB_WIDTH)+1})'(addr_offset & ({$clog2(STRB_WIDTH)})'((3'd1 << rd_transfer_size) - {{STRB_WIDTH-2{1'b0}},1'b1}));

    for (int i = 0; i < STRB_WIDTH; i++) begin
        if (i >= addr_offset && i < {1'b0,addr_offset} + valid_bytes) begin
            axi_rdata_unaligned[i*MEM_WIDTH +: MEM_WIDTH] =
                fifo_rdata_in[i*MEM_WIDTH +: MEM_WIDTH];
        end
    end
end

assign rdata = axi_rdata_unaligned;

/*
always_comb begin

    axi_rdata_unaligned = fifo_rdata_in;

    case(rd_transfer_size)
        3'b000: begin
                    case(rd_addr_unaligned[1:0])
                        2'd0: axi_rdata_unaligned = {24'd0,fifo_rdata_in[7:0]};
                        2'd1: axi_rdata_unaligned = {16'd0,fifo_rdata_in[15:8],8'd0};
                        2'd2: axi_rdata_unaligned = {8'd0,fifo_rdata_in[23:16],16'd0};
                        2'd3: axi_rdata_unaligned = {fifo_rdata_in[31:24],24'd0};
                    endcase
                end
        3'b001: begin
                    case(rd_addr_unaligned[1:0])

                        // aligned 0,1 positions
                        2'd0:
                            axi_rdata_unaligned = {16'b0, fifo_rdata_in[15:0]};

                        // unaligned 1 position
                        2'd1:
                            axi_rdata_unaligned = {16'b0, fifo_rdata_in[15:8],8'b0};

                        // aligned 2,3 position
                        2'd2:
                            axi_rdata_unaligned = {fifo_rdata_in[31:16],16'b0};

                        // unaligned 3 position
                        2'd3:
                            axi_rdata_unaligned = {fifo_rdata_in[31:24],24'b0};

//                        default:
//                        axi_rdata_unaligned = 32'b0;
                    endcase
                end

        // WORD TRANSFER (4 bytes)
        
        3'b010: begin
                    case(rd_addr_unaligned[1:0])

                        // aligned 0,1,2,3 positions
                        2'd0:
                            axi_rdata_unaligned = fifo_rdata_in;

                        // unaligned 1,2,3 positions
                        2'd1:
                            axi_rdata_unaligned = {fifo_rdata_in[31:8], 8'b0};
                        
                        // unaligned 2,3 positions
                        2'd2:
                            axi_rdata_unaligned = {fifo_rdata_in[31:16],16'b0};
                        
                        // unaligned 3 position
                        2'd3:
                            axi_rdata_unaligned = {fifo_rdata_in[31:24],24'b0};
                    endcase
                end

        default: begin
                    axi_rdata_unaligned = fifo_rdata_in;
                end
    endcase
    end

    assign rdata = axi_rdata_unaligned;
*/


// rlast: combinational HIGH in the exact cycle of the last handshake.
assign rlast = (rd_rsp_state == RD_R_POP) && rvalid && (({1'b0,rd_return_count} == rd_total_beats - {{MEM_WIDTH{1'b0}},1'b1}));


endmodule



