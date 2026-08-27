module arbiter #(
    parameter ADDR_WIDTH = 32,
    parameter FIFO_WIDTH = 64
)(
    input  logic pclk,
    input  logic presetn,

    // Requests from FIFOs (pclk domain, ~emty of each FIFO)
    input  logic wr_req_fifo,          // write_fifo has data
    input  logic rd_req_fifo,          // raddr_fifo has data

    // Back-pressure from APB master: one-cycle pulse when transaction completes
    input  logic apb_done,

    // FIFO read-enable: 1-cycle pulse, pops one entry from the respective FIFO
    output logic wr_gnt,          // ? write_fifo.rd_en
    output logic rd_gnt,          // ? raddr_fifo.rd_en

    // APB master enable: level held for entire APB transaction
    output logic wr_gnt_apb,      // ? apb_master.wr_req_fifo
    output logic rd_gnt_apb       // ? apb_master.rd_req_fifo

    // Acknowledgement back to axi_slave (pclk; top_bridge syncs to aclk)
//    output logic wr_grant_from_arbiter,
//    output logic rd_grant_from_arbiter
);

    // State machine
    typedef enum logic [1:0] {
        IDLE,
        GNT_WRITE,
        GNT_READ
    } arb_state_t;

    arb_state_t cstate, next_state;

    // Single alternation bit: 0 = last granted write (or neither), 1 = last read
    logic last_serv;

    // State register
    always_ff @(posedge pclk or negedge presetn) begin
        if (!presetn) 
            cstate <= IDLE;
        else         
            cstate <= next_state;
    end

    // Next-state logic
    always_comb begin
        next_state = cstate;
        case (cstate)
            IDLE: begin
                if (wr_req_fifo && !rd_req_fifo)
                    next_state = GNT_WRITE;
                else if (rd_req_fifo && !wr_req_fifo)
                    next_state = GNT_READ;
                else if (wr_req_fifo && rd_req_fifo)
                    // Alternate: if last served was read, grant write next; else grant read
                    next_state = last_serv ? GNT_WRITE : GNT_READ;
                // both 0 ? stay IDLE
            end
            GNT_WRITE: begin
                // Stay until APB master signals completion
                if (apb_done) next_state = IDLE;
            end
            GNT_READ: begin
                if (apb_done) next_state = IDLE;
            end
            default: next_state = IDLE;
        endcase
    end

    // Output + last_serv register
    always_ff @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            wr_gnt                 <= 1'b0;
            wr_gnt_apb             <= 1'b0;
            rd_gnt                 <= 1'b0;
            rd_gnt_apb             <= 1'b0;
            last_serv              <= 1'b0;
//            wr_grant_from_arbiter  <= 1'b0;
//            rd_grant_from_arbiter  <= 1'b0;
        end else begin
            // Pulse outputs: default to 0 every cycle
            wr_gnt <= 1'b0;
            rd_gnt <= 1'b0;

            case (cstate)

                // IDLE: check for new requests and issue grants
                IDLE: begin
                    wr_gnt_apb            <= 1'b0;
                    rd_gnt_apb            <= 1'b0;
//                    wr_grant_from_arbiter <= 1'b0;
//                    rd_grant_from_arbiter <= 1'b0;

                    if (wr_req_fifo && !rd_req_fifo) begin
                        wr_gnt                <= 1'b1;   // 1-cycle FIFO pop
                        wr_gnt_apb            <= 1'b1;   // level to APB master
//                        wr_grant_from_arbiter <= 1'b1;   // ack to slave
                        last_serv             <= 1'b0;
                    end else if (rd_req_fifo && !wr_req_fifo) begin
                        rd_gnt                <= 1'b1;
                        rd_gnt_apb            <= 1'b1;
//                        rd_grant_from_arbiter <= 1'b1;
                        last_serv             <= 1'b1;
                    end else if (wr_req_fifo && rd_req_fifo) begin
                        if (last_serv) begin              // last was read ? grant write
                            wr_gnt                <= 1'b1;
                            wr_gnt_apb            <= 1'b1;
//                            wr_grant_from_arbiter <= 1'b1;
                            last_serv             <= 1'b0;
                        end else begin                    // last was write (or neither) ? grant read
                            rd_gnt                <= 1'b1;
                            rd_gnt_apb            <= 1'b1;
//                            rd_grant_from_arbiter <= 1'b1;
                            last_serv             <= 1'b1;
                        end
                    end
                end

                // GNT_WRITE: hold wr_gnt_apb until APB completes
                GNT_WRITE: begin
                    wr_gnt_apb            <= apb_done ? 1'b0 : 1'b1;
                    rd_gnt_apb            <= 1'b0;
//                    wr_grant_from_arbiter <= apb_done ? 1'b0 : 1'b1;
//                    rd_grant_from_arbiter <= 1'b0;
                end

                // GNT_READ: hold rd_gnt_apb until APB completes
                GNT_READ: begin
                    rd_gnt_apb            <= apb_done ? 1'b0 : 1'b1;
                    wr_gnt_apb            <= 1'b0;
//                    rd_grant_from_arbiter <= apb_done ? 1'b0 : 1'b1;
//                    wr_grant_from_arbiter <= 1'b0;
                end

                default: begin
                    wr_gnt                <= 1'b0;
                    wr_gnt_apb            <= 1'b0;
                    rd_gnt                <= 1'b0;
                    rd_gnt_apb            <= 1'b0;
//                    wr_grant_from_arbiter <= 1'b0;
//                    rd_grant_from_arbiter <= 1'b0;
                end
            endcase
        end
    end

endmodule
