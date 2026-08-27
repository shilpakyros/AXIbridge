module apb_master #(
 parameter ADDR_WIDTH = 32,
 parameter DATA_WIDTH = 32,
 parameter WRITE_WIDTH = ADDR_WIDTH + DATA_WIDTH,
 parameter TIMEOUT_CNT_WIDTH = 6,
 parameter TIMEOUT_VALUE = (TIMEOUT_CNT_WIDTH)'(50)
 )(
 input logic pclk,
 input logic prst_n,

 // From arbiter / FIFOs
 input logic [ADDR_WIDTH-1:0] addr_in, // read address (from raddr_fifo)
 input logic [WRITE_WIDTH-1:0] wdata_in, // {waddr, wdata} (from write_fifo)
 input logic wr_req, // arbiter granted write
 input logic rd_req, // arbiter granted read
// input logic wlast_flag, // write_fifo: last entry
// input logic rlast_flag, // raddr_fifo: last entry

 // APB bus
 output logic [ADDR_WIDTH-1:0] paddr,
 output logic psel,
 output logic penable,
 output logic pwrite,
 output logic [DATA_WIDTH-1:0] pwdata,
 input logic [DATA_WIDTH-1:0] prdata,
 input logic pready,
 input logic pslverr,

 // To rdata_fifo
 output logic [DATA_WIDTH-1:0] rdata_out,
 output logic rdata_wr_en,

 // To arbiter
 output logic apb_done, // pready in ACCESS = transaction complete

 output logic wr_done,
 output logic rd_done,

 output logic time_out,
 output logic [TIMEOUT_CNT_WIDTH-1:0] t_counter, // time out counter
 

 output logic err
 );

 typedef enum logic [1:0] { IDLE, SETUP, ACCESS, DONE} state_t;
 state_t current_state, next_state;

 // Registered APB outputs ? stable across SETUP?ACCESS per APB spec
 logic [ADDR_WIDTH-1:0] paddr_r;
 logic [DATA_WIDTH-1:0] pwdata_r;
 logic pwrite_r;

// logic time_out;
// logic [TIMEOUT_CNT_WIDTH-1:0] t_counter; // time out counter

 logic wr_req_r;
 logic rd_req_r;

 logic wr_req_p;
 logic rd_req_p;

// logic pwrite_flag_r;
//logic penable_flag_r;


// assign err = pready ? pslverr : (time_out ? 1'b1 : 1'b0);

 always_ff@(posedge pclk or negedge prst_n) begin
    if(!prst_n) begin
        err <= 1'b0;
    end else if(pready && penable) begin
        err <= pslverr;
    end else if(time_out) begin
        err <= 1'b1;
    end else begin
        err <= 1'b0;
    end
 end

 always_ff@(posedge pclk or negedge prst_n) begin
    if(!prst_n) begin
        t_counter <= TIMEOUT_VALUE;
        time_out <= 1'b0;
    end else if(psel && penable && pready) begin // && (t_counter == TIMEOUT_VALUE)) begin
        t_counter <= TIMEOUT_VALUE;
        time_out <= 1'b0;
    end else if(psel && penable && !pready) begin
        if(t_counter == {TIMEOUT_CNT_WIDTH{1'b0}}) begin
            t_counter <= TIMEOUT_VALUE;
            time_out <= 1'b1;
        end else begin
            t_counter <= t_counter - {{TIMEOUT_CNT_WIDTH-1{1'b0}},1'b1};
            time_out <= 1'b0;
        end
    end
 end


 always_ff @(posedge pclk, negedge prst_n) begin
    if(!prst_n) begin
        wr_req_r <= 1'b0;
        rd_req_r <= 1'b0;
        wr_req_p <= 1'b0;
        rd_req_p <= 1'b0;
    end
    else begin
        wr_req_r <= wr_req;
        rd_req_r <= rd_req;
        wr_req_p <= ~wr_req_r && wr_req;
        rd_req_p <= ~rd_req_r && rd_req;
    end
 end


 // State register
 always_ff @(posedge pclk or negedge prst_n) begin
    if (!prst_n) 
        current_state <= IDLE;
    else 
        current_state <= next_state;
 end

 // Next-state
 always_comb begin
    next_state = current_state;
    case (current_state)
        IDLE: begin
                next_state = SETUP;
              end
        SETUP: begin
                if (wr_req_p || rd_req_p)
                    next_state = ACCESS;
                else
                    next_state = SETUP;
               end
        ACCESS: begin
                    if ((pready && penable) || time_out) begin
                        // If arbiter has already re-asserted a request for the next
                        // beat (back-to-back), go straight to SETUP; else back to IDLE.
                        next_state = DONE;
                    end
                    else begin
                        next_state = ACCESS;
                    end
                        // else stay in ACCESS (wait-state)
                end
        DONE: begin
                next_state = SETUP;
              end
//        default: next_state = IDLE;
    endcase
 end

/*
always_ff@(posedge pclk or negedge prst_n) begin
    if(!prst_n) begin
        pwrite_flag_r <= 1'b0;
    end else begin
        pwrite_flag_r <= pwrite_r;
    end
end
*
always_ff@(posedge pclk or negedge prst_n) begin
    if(!prst_n) begin
        penable_flag_r <= 1'b0;
    end else if(current_state == ACCESS && penable) begin
        penable_flag_r <= 1'b1;
    end else if((current_state == ACCESS && ((penable_flag_r && pready) || time_out) || current_state == DONE)) begin
        penable_flag_r <= 1'b0;
    end
end
*/
 // Latch APB address/data/direction at SETUP entry ? hold stable through ACCESS
 always_ff @(posedge pclk or negedge prst_n) begin
    if (!prst_n) begin
        paddr_r <= {ADDR_WIDTH{1'b0}};
        pwdata_r <= {DATA_WIDTH{1'b0}};
        pwrite_r <= 1'b0;
    end else if (current_state == SETUP) begin
        paddr_r <= wr_req_p ? wdata_in[WRITE_WIDTH-1:DATA_WIDTH] : addr_in;
        pwdata_r <= wr_req_p ? wdata_in[DATA_WIDTH-1:0] : {DATA_WIDTH{1'b0}};
        pwrite_r <= wr_req_p;
    end
    else if((current_state == ACCESS) && ((pready && penable) || time_out)) begin
        pwrite_r <= 1'b0;
    end
    // Hold values unchanged in ACCESS
    end

 assign paddr = paddr_r;
 assign pwdata = pwdata_r;
 assign pwrite = pwrite_r;

 // psel / penable
 always_ff @(posedge pclk or negedge prst_n) begin
    if (!prst_n) begin
        psel <= 1'b0;
    end 
    else begin
        if((current_state == ACCESS) && ((pready && penable) || time_out)) begin
            psel <= 1'b0;
        end else if(current_state == SETUP && (wr_req_p || rd_req_p)) begin
            psel <= 1'b1;
        end
    end
 end

 always_ff @(posedge pclk or negedge prst_n) begin
    if (!prst_n) begin
        penable <= 1'b0;
    end 
    else begin
        if(current_state == IDLE) begin
            penable <= 1'b0;
        end else if(current_state == ACCESS && !penable) begin
            penable <= 1'b1;
        end
        else if((current_state == ACCESS) && ((pready && penable) || time_out)) begin
            penable <= 1'b0;
        end
    end
 end

 // done: one-cycle pulse to arbiter when transaction completes
 assign apb_done = current_state==DONE;//((current_state == ACCESS || next_state == SETUP) && pready && penable && psel) || (penable && (current_state == ACCESS || next_state == SETUP) && time_out && psel);

// assign wr_done = apb_done && pwrite_flag_r; //(pwrite && pready && penable && (current_state == ACCESS || next_state == SETUP)) || (pwrite && time_out && penable && psel && (current_state == ACCESS || next_state == SETUP));
// assign rd_done = apb_done && !pwrite_flag_r; //(!pwrite && pready && penable && (current_state == ACCESS || next_state == SETUP)) || (!pwrite && time_out && penable && psel && (current_state == ACCESS || next_state == SETUP));


// cdc clearance
logic done_is_write;

always_ff @(posedge pclk or negedge prst_n) begin
    if(!prst_n)
        done_is_write <= 1'b0;
    else if(current_state == ACCESS &&
            ((pready && penable) || time_out))
        done_is_write <= pwrite_r;
end

always_ff @(posedge pclk or negedge prst_n) begin
    if(!prst_n) begin
        wr_done <= 1'b0;
        rd_done <= 1'b0;
    end
    else begin
        wr_done <= (current_state == DONE) && done_is_write;
        rd_done <= (current_state == DONE) && !done_is_write;
    end
end




 // rdata capture: valid only in ACCESS when pready && read transaction
 always_comb begin
    rdata_wr_en = 1'b0;
    rdata_out = {DATA_WIDTH{1'b0}};
    if((current_state == ACCESS) && pready && penable && !pwrite_r && rd_req) begin
        rdata_wr_en = 1'b1;
        rdata_out = prdata;
    end else begin
        if(time_out) begin
            rdata_wr_en = 1'b1;
            rdata_out   = {DATA_WIDTH{1'b0}};
        end else begin
            rdata_wr_en = 1'b0;
            rdata_out   = {DATA_WIDTH{1'b0}};
        end
    end
 end

endmodule
