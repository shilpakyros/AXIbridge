module top_bridge_assert (
    input logic        pclk,
    input logic        aclk,
    input logic        resetn,
    input logic        presetn,

    input logic        wvalid,
    input logic        wready,
    input logic        full_flag_data,
    input logic        wr_en_waddr_w,

    input logic        transfer_flag_wt,
    input logic        emty_fifo_raddr,

    input logic        req_write,
    input logic        req_read,

    input logic        apb_done_w,
    input logic        wr_gnt_apb_w,
    input logic        rd_gnt_apb_w,

    input logic [1:0]  cstate,
    input logic        wr_req_fifo,
    input logic        rd_req_fifo,
    input logic        last_serv,
    input logic        wr_gnt,
    input logic        rd_gnt,
    input logic         psel,
    input logic         penable,
    input logic        rdata_wr_en_wire,
    input logic        apb_rd_done_w,
    input logic        pwrite,
    input logic        pready,
    input logic [31:0] paddr,
    input logic [31:0] pwdata,
    input logic [31:0] read_data_w,
    input logic [31:0] prdata,
    input logic        apb_time_out,
    input logic        rdata_fifo_rd_en,
    input logic        rvalid,
    input logic	       rready,
    input logic	       rlast,
    input logic	       rdata,
    input logic        apb_rd_error_seen,
    input logic [1:0]  rresp,
    input logic        rdata_fifo_empty

);    

// A01 - presetn must remain low when resetn is low
    property p_presetn_reset;
        @(posedge pclk)
        !resetn |=> !presetn;
    endproperty

    assert property (p_presetn_reset);

    property c_presetn_release;
        @(posedge pclk)
        resetn && !presetn ##1 presetn;
    endproperty

    cover property (c_presetn_release);


    // A02 - Write FIFO enable only on valid AXI write data when FIFO is not full
    property p_write_fifo_enable;
        @(posedge aclk)
        wr_en_waddr_w |-> (wvalid && wready && !full_flag_data);
    endproperty

    assert property (p_write_fifo_enable);

    property c_write_fifo_transfer;
        @(posedge aclk)
        wvalid && wready && !full_flag_data ##1 wr_en_waddr_w;
    endproperty

    cover property (c_write_fifo_transfer);


    // A03 - Write FIFO enable must be low when FIFO is full
    property p_write_fifo_not_full;
        @(posedge aclk)
        full_flag_data |-> !wr_en_waddr_w;
    endproperty

    assert property (p_write_fifo_not_full);

    property c_write_fifo_full;
        @(posedge aclk)
        full_flag_data;
    endproperty

    cover property (c_write_fifo_full);


// A04.1 - Write request only must generate write grant
property p_write_request_grant;
    @(posedge pclk)
    disable iff (!presetn)
    ((cstate == 2'd0) && wr_req_fifo && !rd_req_fifo)
    |=> wr_gnt;
endproperty

assert property (p_write_request_grant);

property c_write_request_grant;
    @(posedge pclk)
    disable iff (!presetn)
    ((cstate == 2'd0) && wr_req_fifo && !rd_req_fifo)
    ##1 wr_gnt;
endproperty

cover property (c_write_request_grant);


// A04.2 - Read request only must generate read grant
property p_read_request_grant;
    @(posedge pclk)
    disable iff (!presetn)
    ((cstate == 2'd0) && rd_req_fifo && !wr_req_fifo)
    |=> rd_gnt;
endproperty

assert property (p_read_request_grant);

property c_read_request_grant;
    @(posedge pclk)
    disable iff (!presetn)
    ((cstate == 2'd0) && rd_req_fifo && !wr_req_fifo)
    ##1 rd_gnt;
endproperty

cover property (c_read_request_grant);


// A04.3 - Both requests and last_serv = 1 must generate write grant
property p_both_request_write_grant;
    @(posedge pclk)
    disable iff (!presetn)
    ((cstate == 2'd0) && wr_req_fifo && rd_req_fifo && last_serv)
    |=> wr_gnt;
endproperty

assert property (p_both_request_write_grant);

property c_both_request_write_grant;
    @(posedge pclk)
    disable iff (!presetn)
    ((cstate == 2'd0) && wr_req_fifo && rd_req_fifo && last_serv)
    ##1 wr_gnt;
endproperty

cover property (c_both_request_write_grant);


// A04.4 - Both requests and last_serv = 0 must generate read grant
property p_both_request_read_grant;
    @(posedge pclk)
    disable iff (!presetn)
    ((cstate == 2'd0) && wr_req_fifo && rd_req_fifo && !last_serv)
    |=> rd_gnt;
endproperty

assert property (p_both_request_read_grant);

property c_both_request_read_grant;
    @(posedge pclk)
    disable iff (!presetn)
    ((cstate == 2'd0) && wr_req_fifo && rd_req_fifo && !last_serv)
    ##1 rd_gnt;
endproperty

cover property (c_both_request_read_grant);

// A05 - Write APB grant must remain active until APB completion
property p_write_grant_until_done;
    @(posedge pclk)
    disable iff (!presetn)
    wr_gnt_apb_w && !apb_done_w |=> wr_gnt_apb_w;
endproperty

assert property (p_write_grant_until_done);

property c_write_grant_until_done;
    @(posedge pclk)
    disable iff (!presetn)
    wr_gnt_apb_w && !apb_done_w |=> wr_gnt_apb_w;
endproperty

cover property (c_write_grant_until_done);

// A06 - Read and write APB grants must not be active together
property p_no_simultaneous_apb_grant;
    @(posedge pclk)
    disable iff (!presetn)
    !(wr_gnt_apb_w && rd_gnt_apb_w);
endproperty

assert property (p_no_simultaneous_apb_grant);

property c_no_simultaneous_apb_grant;
    @(posedge pclk)
    disable iff (!presetn)
    !(wr_gnt_apb_w && rd_gnt_apb_w);
endproperty

cover property (c_no_simultaneous_apb_grant);

// A07 - APB completion must release the active grant
property p_apb_done_releases_grant;
    @(posedge pclk)
    disable iff (!presetn)
    apb_done_w |=> (!wr_gnt_apb_w && !rd_gnt_apb_w);
endproperty

assert property (p_apb_done_releases_grant);

property c_apb_done_releases_grant;
    @(posedge pclk)
    disable iff (!presetn)
    apb_done_w |=> (!wr_gnt_apb_w && !rd_gnt_apb_w);
endproperty

cover property (c_apb_done_releases_grant);
// A08 - PENABLE can be high only when PSEL is high
property p_penable_requires_psel;
    @(posedge pclk)
    disable iff (!presetn)
    penable |-> psel;
endproperty

assert property (p_penable_requires_psel);

property c_penable_requires_psel;
    @(posedge pclk)
    disable iff (!presetn)
    penable;
endproperty

cover property (c_penable_requires_psel);

// A09 - APB write grant must be released after APB transaction completion
property p_write_grant_release;
    @(posedge pclk)
    disable iff (!presetn)
    wr_gnt_apb_w && apb_done_w |=> !wr_gnt_apb_w;
endproperty

assert property (p_write_grant_release);

property c_write_grant_release;
    @(posedge pclk)
    disable iff (!presetn)
    wr_gnt_apb_w && apb_done_w;
endproperty

cover property (c_write_grant_release);

// A10 - APB transfer must have an active write or read grant
property p_apb_transfer_has_grant;
    @(posedge pclk)
    disable iff (!presetn)
    penable |-> (wr_gnt_apb_w || rd_gnt_apb_w);
endproperty

assert property (p_apb_transfer_has_grant);

property c_apb_transfer_has_grant;
    @(posedge pclk)
    disable iff (!presetn)
    penable;
endproperty

cover property (c_apb_transfer_has_grant);

// A11 - Write FIFO pop must have corresponding APB write grant
property p_write_fifo_pop_has_apb_grant;
    @(posedge pclk)
    disable iff (!presetn)
    req_write |-> wr_gnt_apb_w;
endproperty

assert property (p_write_fifo_pop_has_apb_grant);

property c_write_fifo_pop_has_apb_grant;
    @(posedge pclk)
    disable iff (!presetn)
    req_write && wr_gnt_apb_w;
endproperty

cover property (c_write_fifo_pop_has_apb_grant);

// A12 - Read FIFO pop must have corresponding APB read grant
property p_read_fifo_pop_has_apb_grant;
    @(posedge pclk)
    disable iff (!presetn)
    req_read |-> rd_gnt_apb_w;
endproperty

assert property (p_read_fifo_pop_has_apb_grant);

property c_read_fifo_pop_has_apb_grant;
    @(posedge pclk)
    disable iff (!presetn)
    req_read && rd_gnt_apb_w;
endproperty

cover property (c_read_fifo_pop_has_apb_grant);

// A13 - Read data FIFO write must occur only for a completed APB read
property p_rdata_fifo_write_has_read_grant;
    @(posedge pclk)
    disable iff (!presetn)
    rdata_wr_en_wire |-> rd_gnt_apb_w;
endproperty

assert property (p_rdata_fifo_write_has_read_grant);
property c_rdata_fifo_write_has_read_grant;
    @(posedge pclk)
    disable iff (!presetn)
    rdata_wr_en_wire && rd_gnt_apb_w;
endproperty

cover property (c_rdata_fifo_write_has_read_grant);

// A14 - Read APB grant remains active until APB completion
property p_read_grant_until_done;
    @(posedge pclk)
    disable iff (!presetn)
    rd_gnt_apb_w && !apb_done_w |=> rd_gnt_apb_w;
endproperty

assert property (p_read_grant_until_done);

property c_read_grant_until_done;
    @(posedge pclk)
    disable iff (!presetn)
    rd_gnt_apb_w && !apb_done_w |=> rd_gnt_apb_w;
endproperty

cover property (c_read_grant_until_done);

// A15 - Read and write FIFO pop requests must not occur together
property p_no_simultaneous_fifo_pop;
    @(posedge pclk)
    disable iff (!presetn)
    !(req_write && req_read);
endproperty

assert property (p_no_simultaneous_fifo_pop);

property c_no_simultaneous_fifo_pop;
    @(posedge pclk)
    disable iff (!presetn)
    (req_write ^ req_read);
endproperty

cover property (c_no_simultaneous_fifo_pop);

// A16 - APB select must have a corresponding APB grant
property p_psel_requires_apb_grant;
    @(posedge pclk)
    disable iff (!presetn)
    psel |-> (wr_gnt_apb_w || rd_gnt_apb_w);
endproperty

assert property (p_psel_requires_apb_grant);

property c_psel_requires_apb_grant;
    @(posedge pclk)
    disable iff (!presetn)
    psel && (wr_gnt_apb_w || rd_gnt_apb_w);
endproperty

cover property (c_psel_requires_apb_grant);

// A17 - APB write and read grants must be mutually exclusive
property p_no_simultaneous_apb_write_read_grant;
    @(posedge pclk)
    disable iff (!presetn)
    !(wr_gnt_apb_w && rd_gnt_apb_w);
endproperty

assert property (p_no_simultaneous_apb_write_read_grant);

property c_no_simultaneous_apb_write_read_grant;
    @(posedge pclk)
    disable iff (!presetn)
    !(wr_gnt_apb_w && rd_gnt_apb_w);
endproperty

cover property (c_no_simultaneous_apb_write_read_grant);

// A18 - APB write control requires an active write grant
property p_pwrite_requires_write_grant;
    @(posedge pclk)
    disable iff (!presetn)
    pwrite |-> wr_gnt_apb_w;
endproperty

assert property (p_pwrite_requires_write_grant);

property c_pwrite_requires_write_grant;
    @(posedge pclk)
    disable iff (!presetn)
    pwrite && wr_gnt_apb_w;
endproperty

cover property (c_pwrite_requires_write_grant);

// A19 - APB read transfer requires an active read grant
property p_apb_read_requires_read_grant;
    @(posedge pclk)
    disable iff (!presetn)
    (psel && !pwrite) |-> rd_gnt_apb_w;
endproperty

assert property (p_apb_read_requires_read_grant);

property c_apb_read_requires_read_grant;
    @(posedge pclk)
    disable iff (!presetn)
    (psel && !pwrite) && rd_gnt_apb_w;
endproperty

cover property (c_apb_read_requires_read_grant);

// A20 - APB address remains stable while ACCESS is waiting
property p_apb_address_stable;
    @(posedge pclk)
    disable iff (!presetn)
    (psel && penable && !pready) |=> $stable(paddr);
endproperty

assert property (p_apb_address_stable);

property c_apb_address_stable;
    @(posedge pclk)
    disable iff (!presetn)
    (psel && penable && !pready) |=> $stable(paddr);
endproperty

cover property (c_apb_address_stable);

// A21 - APB write control remains stable during non-timeout ACCESS
property p_apb_write_control_stable;
    @(posedge pclk)
    disable iff (!presetn)
    (psel && penable && pwrite && !pready && !apb_time_out) |=> pwrite;
endproperty

assert property (p_apb_write_control_stable);

property c_apb_write_control_stable;
    @(posedge pclk)
    disable iff (!presetn)
    (psel && penable && pwrite && !pready && !apb_time_out) |=> pwrite;
endproperty

cover property (c_apb_write_control_stable);

// A22 - APB timeout leads to APB completion
property p_apb_timeout_leads_to_done;
    @(posedge pclk)
    disable iff (!presetn)
    apb_time_out |=> apb_done_w;
endproperty

assert property (p_apb_timeout_leads_to_done);

property c_apb_timeout_leads_to_done;
    @(posedge pclk)
    disable iff (!presetn)
    apb_time_out |=> apb_done_w;
endproperty

cover property (c_apb_timeout_leads_to_done);

// A23 - APB timeout terminates the active APB transfer
property p_apb_timeout_releases_control;
    @(posedge pclk)
    disable iff (!presetn)
    apb_time_out |=> (!psel && !penable);
endproperty

assert property (p_apb_timeout_releases_control);

property c_apb_timeout_releases_control;
    @(posedge pclk)
    disable iff (!presetn)
    apb_time_out |=> (!psel && !penable);
endproperty

cover property (c_apb_timeout_releases_control);

// A24 - APB write data remains stable during non-timeout ACCESS
property p_apb_write_data_stable;
    @(posedge pclk)
    disable iff (!presetn)
    (psel && penable && pwrite && !pready && !apb_time_out) |=> 
        $stable(pwdata);
endproperty

assert property (p_apb_write_data_stable);

property c_apb_write_data_stable;
    @(posedge pclk)
    disable iff (!presetn)
    (psel && penable && pwrite && !pready && !apb_time_out) |=> 
        $stable(pwdata);
endproperty

cover property (c_apb_write_data_stable);
// A24 - APB ready leads to transaction completion
property p_apb_ready_leads_to_done;
    @(posedge pclk)
    disable iff (!presetn)
    (psel && penable && pready) |=> apb_done_w;
endproperty

assert property (p_apb_ready_leads_to_done);

property c_apb_ready_leads_to_done;
    @(posedge pclk)
    disable iff (!presetn)
    (psel && penable && pready) |=> apb_done_w;
endproperty

cover property (c_apb_ready_leads_to_done);

// A25 - APB SETUP phase transitions to ACCESS phase
property p_apb_setup_to_access;
    @(posedge pclk)
    disable iff (!presetn)
    (psel && !penable) |=> (psel && penable);
endproperty

assert property (p_apb_setup_to_access);

property c_apb_setup_to_access;
    @(posedge pclk)
    disable iff (!presetn)
    (psel && !penable) |=> (psel && penable);
endproperty

cover property (c_apb_setup_to_access);

// A26 - APB ACCESS phase with ready completes the transaction
property p_apb_access_ready_completion;
    @(posedge pclk)
    disable iff (!presetn)
    (psel && penable && pready) |=> apb_done_w;
endproperty

assert property (p_apb_access_ready_completion);

property c_apb_access_ready_completion;
    @(posedge pclk)
    disable iff (!presetn)
    (psel && penable && pready) |=> apb_done_w;
endproperty

cover property (c_apb_access_ready_completion);

// A27 - APB select remains asserted while waiting for ready
property p_apb_psel_stable_wait;
    @(posedge pclk)
    disable iff (!presetn)
    (psel && penable && !pready && !apb_time_out) |=> psel;
endproperty

assert property (p_apb_psel_stable_wait);

property c_apb_psel_stable_wait;
    @(posedge pclk)
    disable iff (!presetn)
    (psel && penable && !pready && !apb_time_out) |=> psel;
endproperty

cover property (c_apb_psel_stable_wait);

// A28 - APB enable remains asserted while waiting for ready
property p_apb_penable_stable_wait;
    @(posedge pclk)
    disable iff (!presetn)
    (psel && penable && !pready && !apb_time_out) |=> penable;
endproperty

assert property (p_apb_penable_stable_wait);

property c_apb_penable_stable_wait;
    @(posedge pclk)
    disable iff (!presetn)
    (psel && penable && !pready && !apb_time_out) |=> penable;
endproperty

cover property (c_apb_penable_stable_wait);

// A29 - APB write data remains stable while waiting for ready
property p_apb_write_data_stable_wait;
    @(posedge pclk)
    disable iff (!presetn)
    (psel && penable && pwrite && !pready && !apb_time_out) |=> $stable(pwdata);
endproperty

assert property (p_apb_write_data_stable_wait);

property c_apb_write_data_stable_wait;
    @(posedge pclk)
    disable iff (!presetn)
    (psel && penable && pwrite && !pready && !apb_time_out) |=> $stable(pwdata);
endproperty

cover property (c_apb_write_data_stable_wait);

// A30 - APB write data remains stable during ACCESS wait
property p_apb_write_data_stable_access;
    @(posedge pclk)
    disable iff (!presetn)
    (psel && penable && pwrite && !pready && !apb_time_out)
        |=> (psel && penable && pwrite && $stable(pwdata));
endproperty

assert property (p_apb_write_data_stable_access);

property c_apb_write_data_stable_access;
    @(posedge pclk)
    disable iff (!presetn)
    (psel && penable && pwrite && !pready && !apb_time_out)
        |=> (psel && penable && pwrite && $stable(pwdata));
endproperty

cover property (c_apb_write_data_stable_access);

// A31 - APB write control remains stable during ACCESS wait
property p_apb_pwrite_stable_wait;
    @(posedge pclk)
    disable iff (!presetn)
    (psel && penable && pwrite && !pready && !apb_time_out) |=> pwrite;
endproperty

assert property (p_apb_pwrite_stable_wait);

property c_apb_pwrite_stable_wait;
    @(posedge pclk)
    disable iff (!presetn)
    (psel && penable && pwrite && !pready && !apb_time_out) |=> pwrite;
endproperty

cover property (c_apb_pwrite_stable_wait);

// A32 - APB read completion generates read-data FIFO write enable
property p_apb_read_data_capture;
    @(posedge pclk)
    disable iff (!presetn)
    (psel && penable && !pwrite && pready) |-> rdata_wr_en_wire;
endproperty

assert property (p_apb_read_data_capture);

property c_apb_read_data_capture;
    @(posedge pclk)
    disable iff (!presetn)
    (psel && penable && !pwrite && pready) |-> rdata_wr_en_wire;
endproperty

cover property (c_apb_read_data_capture);

// A33 - Read-data FIFO write enable occurs only on read completion or timeout
property p_rdata_fifo_write_valid_source;
    @(posedge pclk)
    disable iff (!presetn)
    rdata_wr_en_wire |-> 
        (apb_time_out || (psel && penable && !pwrite && pready));
endproperty

assert property (p_rdata_fifo_write_valid_source);

property c_rdata_fifo_write_valid_source;
    @(posedge pclk)
    disable iff (!presetn)
    rdata_wr_en_wire &&
    (apb_time_out || (psel && penable && !pwrite && pready));
endproperty

cover property (c_rdata_fifo_write_valid_source);

// A34 - APB read data captured into the read-data FIFO matches prdata
property p_apb_read_data_matches_prdata;
    @(posedge pclk)
    disable iff (!presetn)
    (rdata_wr_en_wire &&
     !apb_time_out &&
     psel &&
     penable &&
     !pwrite &&
     pready) |-> (read_data_w == prdata);
endproperty

assert property (p_apb_read_data_matches_prdata);

property c_apb_read_data_matches_prdata;
    @(posedge pclk)
    disable iff (!presetn)
    (rdata_wr_en_wire &&
     !apb_time_out &&
     psel &&
     penable &&
     !pwrite &&
     pready) |-> (read_data_w == prdata);
endproperty

cover property (c_apb_read_data_matches_prdata);

// A35 - Read-data FIFO read enable follows FIFO data availability
property p_rdata_fifo_read_after_available;
    @(posedge aclk)
    disable iff (!resetn)
    rdata_fifo_rd_en |-> $past(rdata_fifo_empty);
endproperty

assert property (p_rdata_fifo_read_after_available);

property c_rdata_fifo_read_after_available;
    @(posedge aclk)
    disable iff (!resetn)
    rdata_fifo_rd_en && $past(rdata_fifo_empty);
endproperty

cover property (c_rdata_fifo_read_after_available);

// A36 - AXI read data valid follows a previous read-data FIFO pop
property p_rvalid_after_fifo_read;
    @(posedge aclk)
    disable iff (!resetn)
    rvalid |-> $past(rdata_fifo_rd_en);
endproperty

assert property (p_rvalid_after_fifo_read);

property c_rvalid_after_fifo_read;
    @(posedge aclk)
    disable iff (!resetn)
    rvalid && $past(rdata_fifo_rd_en);
endproperty

cover property (c_rvalid_after_fifo_read);
// A37 - AXI last signal is asserted only with valid read data
property p_rlast_requires_rvalid;
    @(posedge aclk)
    disable iff (!resetn)
    rlast |-> rvalid;
endproperty

assert property (p_rlast_requires_rvalid);

property c_rlast_requires_rvalid;
    @(posedge aclk)
    disable iff (!resetn)
    rlast && rvalid;
endproperty

cover property (c_rlast_requires_rvalid);

// A38 - AXI read valid clears after the last read-data handshake
property p_rvalid_clear_after_last;
    @(posedge aclk)
    disable iff (!resetn)
    (rvalid && rready && rlast) |=> !rvalid;
endproperty

assert property (p_rvalid_clear_after_last);

property c_rvalid_clear_after_last;
    @(posedge aclk)
    disable iff (!resetn)
    (rvalid && rready && rlast) |=> !rvalid;
endproperty

cover property (c_rvalid_clear_after_last);

// A39 - AXI read valid is associated with a read-data FIFO response
property p_rvalid_with_read_response;
    @(posedge aclk)
    disable iff (!resetn)
    rvalid |-> (rdata_fifo_rd_en || $past(rdata_fifo_rd_en));
endproperty

assert property (p_rvalid_with_read_response);

property c_rvalid_with_read_response;
    @(posedge aclk)
    disable iff (!resetn)
    rvalid && (rdata_fifo_rd_en || $past(rdata_fifo_rd_en));
endproperty

cover property (c_rvalid_with_read_response);

 // A40 - AXI read response uses only OKAY or SLVERR when rvalid is asserted
property p_read_response_encoding;
    @(posedge aclk)
    disable iff (!resetn)
    rvalid |-> (rresp == 2'b00 || rresp == 2'b10);
endproperty

assert property (p_read_response_encoding);

property c_read_response_encoding;
    @(posedge aclk)
    disable iff (!resetn)
    rvalid && (rresp == 2'b00 || rresp == 2'b10);
endproperty

cover property (c_read_response_encoding);endmodule

bind top_bridge top_bridge_assert u_top_bridge_assert (
    .pclk           (pclk),
    .aclk           (aclk),
    .resetn         (resetn),
    .presetn        (presetn),
     .pwrite         (pwrite),
    .pready         (pready),
    .paddr          (paddr),
    .pwdata         (pwdata),
    .apb_time_out   (apb_time_out),
    .wvalid         (wvalid),
    .wready         (wready),
    .full_flag_data (full_flag_data),
    .wr_en_waddr_w  (wr_en_waddr_w),
    .transfer_flag_wt (transfer_flag_wt),
    .emty_fifo_raddr  (emty_fifo_raddr),
    .req_write      (req_write),
    .req_read       (req_read),
    .apb_done_w     (apb_done_w),
    .wr_gnt_apb_w   (wr_gnt_apb_w),
    .rd_gnt_apb_w   (rd_gnt_apb_w),
    .cstate         (arbtr.cstate),
    .wr_req_fifo    (arbtr.wr_req_fifo),
    .rd_req_fifo    (arbtr.rd_req_fifo),
    .last_serv      (arbtr.last_serv),
    .wr_gnt         (arbtr.wr_gnt),
    .rd_gnt         (arbtr.rd_gnt),
    .psel   	    (psel),
    .penable        (penable),
    .read_data_w    (read_data_w),
    .prdata         (prdata),
    .rvalid         (rvalid),
    .rready	     (rready),
    .rlast	     (rlast),
    .rdata	     (rdata),
    .rdata_wr_en_wire (rdata_wr_en_wire),
    .rdata_fifo_rd_en (rdata_fifo_rd_en),
    .rdata_fifo_empty  (rdata_fifo_empty),
    .apb_rd_error_seen (apb_rd_error_seen),
    .rresp             (rresp),
    .apb_rd_done_w   ( apb_rd_done_w)
   );

