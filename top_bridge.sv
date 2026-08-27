
import axi_typedef_pkg::*;

module top_bridge #(
    parameter FIFO_DEPTH  = 8,
    parameter ADDR_WIDTH  = 32,
    parameter DATA_WIDTH  = 32,
    parameter PTR_WIDTH   = $clog2(FIFO_DEPTH),
    parameter STRB_WIDTH  = 4,                         // FIX: was STRBE_WIDTH
    parameter FIFO_WIDTH  = ADDR_WIDTH + DATA_WIDTH,    // 64
    parameter TIMEOUT_CNT_WIDTH = 6 ,
    parameter TIMEOUT_VALUE = (TIMEOUT_CNT_WIDTH)'(50)

)(
    input  logic pclk,
    input  logic aclk,
    input  logic resetn,
//    input  logic presetn,

    // Write address channel
    input  logic                    awvalid,
    input  logic [ADDR_WIDTH-1:0]   awaddr,
    input  logic [7:0]              awlen,
    input  logic [2:0]              awsize,
    input  bust_t                   awburst,
    output logic                    awready,

    // Write data channel
    input  logic                    wvalid,
    input  logic [DATA_WIDTH-1:0]   wdata,
    input  logic [STRB_WIDTH-1:0]   wstrb,            // FIX: STRB_WIDTH
    input  logic                    wlast,
    output logic                    wready,

    // Write response channel
    input  logic                    bready,
    output bresp_t                  bresp,
    output logic                    bvalid,

    // Read address channel
    input  logic                    arvalid,
    input  logic [ADDR_WIDTH-1:0]   araddr,
    input  logic [7:0]              arlen,
    input  logic [2:0]              arsize,
    input  bust_t                   arburst,
    output logic                    arready,

    // Read data / response channel
    input  logic                    rready,
    output logic                    rvalid,
    output logic [DATA_WIDTH-1:0]   rdata,
    output bresp_t                  rresp,
    output logic                    rlast,

    // APB master bus
    output logic                    psel,
    output logic [ADDR_WIDTH-1:0]   paddr,
    output logic [DATA_WIDTH-1:0]   pwdata,
    output logic                    penable,
    output logic                    pwrite,
    input  logic                    pready,
    input  logic [DATA_WIDTH-1:0]   prdata,
    input  logic                    pslverr,

    // Trace
    output logic [7:0]              trace_id_o,
    output logic [DATA_WIDTH-1:0]   trace_data_o
);

    // =========================================================================
    // Internal signals
    // =========================================================================

    // Write path (aclk ? pclk via write_fifo)
    logic [FIFO_WIDTH-1:0]  write_to_fifo;          // slave  ? write_fifo
    logic                   wr_en_waddr_w;           // slave  ? write_fifo.wr_en
    logic [FIFO_WIDTH-1:0]  write_to_arbiter;        // write_fifo.read_data ? apb_master
    logic                   full_flag_data;          // write_fifo.full ? slave
    logic                   transfer_flag_wt;        // write_fifo.transfer_flag (~emty)

    // Read address path (aclk ? pclk via raddr_fifo)
    logic [ADDR_WIDTH-1:0]  raddr_to_fifo;          // slave  ? raddr_fifo
    logic                   wr_en_raddr;             // slave  ? raddr_fifo.wr_en
    logic [ADDR_WIDTH-1:0]  raddr_to_arbiter;        // raddr_fifo.read_data ? apb_master.addr_in
    logic                   full_flag_rdata;         // raddr_fifo.full ? slave
    logic                   emty_fifo_raddr;         // raddr_fifo.transfer_flag (~emty)

    // Read data path (pclk ? aclk via rdata_fifo)
    logic [DATA_WIDTH-1:0]  read_data_w;             // apb_master.rdata_out ? rdata_fifo
    logic                   rdata_wr_en_wire;        // apb_master.rdata_wr_en ? rdata_fifo.wr_en
    logic [DATA_WIDTH-1:0]  rdata_to_axi;            // rdata_fifo.read_data ? slave
//    logic                   full_flag_apb;           // rdata_fifo.full (unused but declared)
    logic                   rdata_fifo_empty;        // rdata_fifo.emty ? slave.rdata_req(inverted)

    // rdata_fifo read-enable: registered to avoid combinational loop
    // rvalid ? rd_en ? emty ? rdata_req ? rvalid
    logic                   rdata_fifo_rd_en;

    // APB master control
    logic                   apb_done_w;              // apb_master.done ? arbiter.apb_done
    logic                   apb_err_w;               // unused externally

    // Arbiter outputs
    logic                   req_write;               // arbiter.wr_gnt  ? write_fifo.rd_en
    logic                   req_read;                // arbiter.rd_gnt  ? raddr_fifo.rd_en
    logic                   wr_gnt_apb_w;            // arbiter.wr_gnt_apb ? apb_master.wr_req
    logic                   rd_gnt_apb_w;            // arbiter.rd_gnt_apb ? apb_master.rd_req


    // pslverr CDC: pclk ? aclk
    logic                   slverr_to_axi;

    logic                   apb_wr_done_w;
    logic                   apb_rd_done_w;
    logic                   apb_wr_done2axi_w;
    logic                   apb_rd_done2axi_w;
   
//    logic                   aresetn;
    logic                   presetn;

    logic                   rst_reg0;

    localparam TRACE_AWADDR = 8'h00;

    localparam TRACE_WDATA_WSTRB0 = 8'h04;
    localparam TRACE_WDATA_WSTRB1 = 8'h08;
    localparam TRACE_WDATA_WSTRB2 = 8'h0C;
    localparam TRACE_WDATA_WSTRB3 = 8'h10;
    localparam TRACE_WDATA_WSTRB4 = 8'h14;
    localparam TRACE_WDATA_WSTRB5 = 8'h18;
    localparam TRACE_WDATA_WSTRB6 = 8'h1C;
    localparam TRACE_WDATA_WSTRB7 = 8'h20;
    localparam TRACE_WDATA_WSTRB8 = 8'h24;
    localparam TRACE_WDATA_WSTRB9 = 8'h28;
    localparam TRACE_WDATA_WSTRB10 = 8'h2C;
    localparam TRACE_WDATA_WSTRB11 = 8'h30;
    localparam TRACE_WDATA_WSTRB12 = 8'h34;
    localparam TRACE_WDATA_WSTRB13 = 8'h38;
    localparam TRACE_WDATA_WSTRB14 = 8'h3C;
    localparam TRACE_WDATA_WSTRB15 = 8'h40;
    localparam TRACE_WADDR_FIFOW   = 8'h44;

    localparam TRACE_BRESP         = 8'h48;

    localparam TRACE_ARADDR        = 8'h4C;
    localparam TRACE_WR_EN_ARADDR  = 8'h50;

//    localparam TRACE_RDATA         = 8'h54; // fifo data in both will be same 
    localparam TRACE_RDATA       = 8'h54;
    localparam TRACE_RRESP = 8'h58;

    // ARBITER

    localparam TRACE_WR_GNT = 8'h60;
    localparam TRACE_RD_GNT = 8'h64;

    //APB MASTER
    localparam TRACE_PADDR = 8'h68;
    localparam TRACE_PWDATA = 8'h6C;
    localparam TRACE_PRDATA = 8'h70;
    localparam TRACE_WR_DONE = 8'h74;
    localparam TRACE_RD_DONE = 8'h78;
    localparam TRACE_PSLVERR = 8'h7C;
    localparam TRACE_TIME_OUT = 8'h80;
    localparam TRACE_ERR    = 8'h84;
    localparam TRACE_TIME_COUNTER = 8'h88;
    
    // FIFO
    localparam TRACE_WFIFO_FULL = 8'h8C;
    localparam TRACE_WR_TRANSFER_FLAG = 8'h90;
    localparam TRACE_RD_TRANSFER_FLAG = 8'h94;
    localparam TRACE_WR_EN_FULL = 8'h98;
    localparam TRACE_RD_EN_EMPTY = 8'h9C;


//    assign aresetn = resetn;
//    assign presetn = resetn;


    always_ff@(posedge pclk or negedge resetn) begin
      if(!resetn) begin
          rst_reg0 <= 1'b0;
          presetn  <= 1'b0;
      end else begin
          rst_reg0 <= 1'b1;
          presetn  <= rst_reg0;
      end
    end

 logic [TIMEOUT_CNT_WIDTH-1:0] apb_t_counter; // time out counter

  logic axi_apb_rd_error_seen;

logic        axi_trace_req;
logic [7:0]  axi_trace_id;
logic [31:0] axi_trace_data;
// AXI TRACE logic
always_ff @(posedge aclk or negedge resetn) begin
    if(!resetn) begin
        axi_trace_req  <= 1'b0;
        axi_trace_id   <= 8'h00;
        axi_trace_data <= 32'h0;
    end
    else begin

        // Default
        axi_trace_req <= 1'b0;

        // Highest priority first

        if(awvalid && awready) begin
            axi_trace_req  <= 1'b1;
            axi_trace_id   <= TRACE_AWADDR;
            axi_trace_data <= awaddr;
        end

        else if(wvalid && wready && (wstrb == 4'd0)) begin
            axi_trace_req  <= 1'b1;
            axi_trace_id   <= TRACE_WDATA_WSTRB0;
            axi_trace_data <= write_to_fifo[31:0];
        end

        else if(wvalid && wready && (wstrb == 4'd1)) begin
            axi_trace_req  <= 1'b1;
            axi_trace_id   <= TRACE_WDATA_WSTRB1;
            axi_trace_data <= write_to_fifo[31:0];
        end

        else if(wvalid && wready && (wstrb == 4'd2)) begin
            axi_trace_req  <= 1'b1;
            axi_trace_id   <= TRACE_WDATA_WSTRB2;
            axi_trace_data <= write_to_fifo[31:0];
        end

        else if(wvalid && wready && (wstrb == 4'd3)) begin
            axi_trace_req  <= 1'b1;
            axi_trace_id   <= TRACE_WDATA_WSTRB3;
            axi_trace_data <= write_to_fifo[31:0];
        end

        else if(wvalid && wready && (wstrb == 4'd4)) begin
            axi_trace_req  <= 1'b1;
            axi_trace_id   <= TRACE_WDATA_WSTRB4;
            axi_trace_data <= write_to_fifo[31:0];
        end

        else if(wvalid && wready && (wstrb == 4'd5)) begin
            axi_trace_req  <= 1'b1;
            axi_trace_id   <= TRACE_WDATA_WSTRB5;
            axi_trace_data <= write_to_fifo[31:0];
        end

        else if(wvalid && wready && (wstrb == 4'd6)) begin
            axi_trace_req  <= 1'b1;
            axi_trace_id   <= TRACE_WDATA_WSTRB6;
            axi_trace_data <= write_to_fifo[31:0];
        end

        else if(wvalid && wready && (wstrb == 4'd7)) begin
            axi_trace_req  <= 1'b1;
            axi_trace_id   <= TRACE_WDATA_WSTRB7;
            axi_trace_data <= write_to_fifo[31:0];
        end

        else if(wvalid && wready && (wstrb == 4'd8)) begin
            axi_trace_req  <= 1'b1;
            axi_trace_id   <= TRACE_WDATA_WSTRB8;
            axi_trace_data <= write_to_fifo[31:0];
        end

        else if(wvalid && wready && (wstrb == 4'd9)) begin
            axi_trace_req  <= 1'b1;
            axi_trace_id   <= TRACE_WDATA_WSTRB9;
            axi_trace_data <= write_to_fifo[31:0];
        end

        else if(wvalid && wready && (wstrb == 4'd10)) begin
            axi_trace_req  <= 1'b1;
            axi_trace_id   <= TRACE_WDATA_WSTRB10;
            axi_trace_data <= write_to_fifo[31:0];
        end

        else if(wvalid && wready && (wstrb == 4'd11)) begin
            axi_trace_req  <= 1'b1;
            axi_trace_id   <= TRACE_WDATA_WSTRB11;
            axi_trace_data <= write_to_fifo[31:0];
        end

        else if(wvalid && wready && (wstrb == 4'd12)) begin
            axi_trace_req  <= 1'b1;
            axi_trace_id   <= TRACE_WDATA_WSTRB12;
            axi_trace_data <= write_to_fifo[31:0];
        end

        else if(wvalid && wready && (wstrb == 4'd13)) begin
            axi_trace_req  <= 1'b1;
            axi_trace_id   <= TRACE_WDATA_WSTRB13;
            axi_trace_data <= write_to_fifo[31:0];
        end

        else if(wvalid && wready && (wstrb == 4'd14)) begin
            axi_trace_req  <= 1'b1;
            axi_trace_id   <= TRACE_WDATA_WSTRB14;
            axi_trace_data <= write_to_fifo[31:0];
        end


        else if(wvalid && wready && (wstrb == 4'd15)) begin
            axi_trace_req  <= 1'b1;
            axi_trace_id   <= TRACE_WDATA_WSTRB15;
            axi_trace_data <= write_to_fifo[31:0];
        end

        else if(wr_en_waddr_w) begin
            axi_trace_req  <= 1'b1;
            axi_trace_id   <= TRACE_WADDR_FIFOW;
            axi_trace_data <= write_to_fifo[63:32];
        end

        else if(bvalid && bready) begin
            axi_trace_req  <= 1'b1;
            axi_trace_id   <= TRACE_BRESP;
            axi_trace_data <= {{30{1'b0}},bresp};
        end

        else if(arvalid && arready) begin
            axi_trace_req  <= 1'b1;
            axi_trace_id   <= TRACE_ARADDR;
            axi_trace_data <= araddr;
        end

        else if(wr_en_raddr) begin
            axi_trace_req  <= 1'b1;
            axi_trace_id   <= TRACE_WR_EN_ARADDR;
            axi_trace_data <= araddr;
        end

        else if(rvalid && rready) begin
            axi_trace_req  <= 1'b1;
            axi_trace_id   <= TRACE_RDATA;
            axi_trace_data <= rdata;
        end

        else if(axi_apb_rd_error_seen) begin
            axi_trace_req  <= 1'b1;
            axi_trace_id   <= TRACE_RRESP;
            axi_trace_data <= {{30{1'b0}},rresp};
        end

    end
end

logic apb_time_out;


logic        apb_trace_req;
logic [7:0]  apb_trace_id;
logic [31:0] apb_trace_data;
// APB TRACE logic
always_ff @(posedge pclk or negedge presetn) begin

    if(!presetn) begin
        apb_trace_req  <= 1'b0;
        apb_trace_id   <= 8'h00;
        apb_trace_data <= 32'h0;
    end
    else begin

        apb_trace_req <= 1'b0;

        if(req_write) begin     //wr_gnt
            apb_trace_req  <= 1'b1;
            apb_trace_id   <= TRACE_WR_GNT;
            apb_trace_data <= 32'h1;
        end

        else if(req_read) begin
            apb_trace_req  <= 1'b1;
            apb_trace_id   <= TRACE_RD_GNT;
            apb_trace_data <= 32'h1;
        end

        else if(psel) begin
            apb_trace_req  <= 1'b1;
            apb_trace_id   <= TRACE_PADDR;
            apb_trace_data <= paddr;
        end

        else if(psel && penable && pwrite && pready) begin
            apb_trace_req  <= 1'b1;
            apb_trace_id   <= TRACE_PWDATA;
            apb_trace_data <= pwdata;
        end

        else if(psel && penable && !pwrite && pready) begin
            apb_trace_req  <= 1'b1;
            apb_trace_id   <= TRACE_PRDATA;
            apb_trace_data <= prdata;
        end

        else if(apb_wr_done_w) begin
            apb_trace_req  <= 1'b1;
            apb_trace_id   <= TRACE_WR_DONE;
            apb_trace_data <= 32'h1;
        end

        else if(apb_rd_done_w) begin
            apb_trace_req  <= 1'b1;
            apb_trace_id   <= TRACE_RD_DONE;
            apb_trace_data <= 32'h1;
        end

        else if(psel && penable && pready && pslverr) begin
            apb_trace_req  <= 1'b1;
            apb_trace_id   <= TRACE_PSLVERR;
            apb_trace_data <= paddr;
        end

        else if(psel && penable && apb_time_out) begin
            apb_trace_req  <= 1'b1;
            apb_trace_id   <= TRACE_TIME_OUT;
            apb_trace_data <= paddr;
        end

        else if(apb_err_w) begin
            apb_trace_req  <= 1'b1;
            apb_trace_id   <= TRACE_ERR;
            apb_trace_data <= 32'h1;
        end

        else if(apb_time_out) begin
            apb_trace_req  <= 1'b1;
            apb_trace_id   <= TRACE_TIME_COUNTER;
            apb_trace_data <= {{(32-TIMEOUT_CNT_WIDTH){1'b0}}, apb_t_counter};
        end
/*
        else if(full_flag_data) begin
            apb_trace_req  <= 1'b1;
            apb_trace_id   <= TRACE_WFIFO_FULL;
            apb_trace_data <= 32'h1;
        end

        else if(wr_transfer_flag) begin
            apb_trace_req  <= 1'b1;
            apb_trace_id   <= TRACE_WR_TRANSFER_FLAG;
            apb_trace_data <= 32'h1;
        end

        else if(rd_transfer_flag) begin
            apb_trace_req  <= 1'b1;
            apb_trace_id   <= TRACE_RD_TRANSFER_FLAG;
            apb_trace_data <= 32'h1;
        end

        else if(wr_en_waddr_w && full_flag_data) begin    // write fifo write channel
            apb_trace_req  <= 1'b1;
            apb_trace_id   <= TRACE_WR_EN_FULL;
            apb_trace_data <= write_data[31:0];
        end

        else if( && emty) begin    // read addr channel
            apb_trace_req  <= 1'b1;
            apb_trace_id   <= TRACE_RD_EN_EMPTY;
            apb_trace_data <= 32'h1;
        end
*/
    end

end

//logic [31:0] axi_trace_data;
//logic [7:0] axi_trace_id;
//logic axi_trace_req;
logic [31:0] axi_trace_data_pclk;
logic [7:0] axi_trace_id_pclk;

//-----------------------------------------------------
// Trace FIFO
//-----------------------------------------------------

logic        trace_fifo_wr_en;
logic        trace_fifo_rd_en;

logic [39:0] trace_fifo_wr_data;
logic [39:0] trace_fifo_rd_data;

logic        trace_fifo_full;
logic        trace_fifo_valid;

//always_ff@(posedge aclk or negedge resetn) begin
//  if(!resetn) begin
//      trace_fifo_wr_en = 1'b0;
//  end else begin
//      trace_fifo_wr_en = axi_trace_req & (~trace_fifo_full);
//  end
//end


assign trace_fifo_wr_en =
            axi_trace_req &
           ~trace_fifo_full;

assign trace_fifo_wr_data =
{
    axi_trace_id,
    axi_trace_data
};

always_ff @(posedge pclk or negedge presetn)
begin

    if(!presetn)
        trace_fifo_rd_en <= 1'b0;

    else
        trace_fifo_rd_en <=
            (~apb_trace_req) &
             trace_fifo_valid;

end

always_ff @(posedge pclk or negedge presetn)
begin

    if(!presetn)
    begin
        axi_trace_id_pclk   <= 8'h00;
        axi_trace_data_pclk <= 32'h0;
    end

    else if(trace_fifo_rd_en)
    begin
        axi_trace_id_pclk   <= trace_fifo_rd_data[39:32];
        axi_trace_data_pclk <= trace_fifo_rd_data[31:0];
    end

end


async_fifo_write #(
    .WRITE_WIDTH (40),
    .READ_WIDTH  (40),
    .FIFO_DEPTH  (32)
) trace_fifo (

    .w_clk(aclk),
    .r_clk(pclk),

        .aresetn        (resetn),
        .presetn        (presetn),

    .wr_en(trace_fifo_wr_en),
    .rd_en(trace_fifo_rd_en),

    .write_data(trace_fifo_wr_data),
    .read_data(trace_fifo_rd_data),

    .full(trace_fifo_full),

    .wr_transfer_flag(trace_fifo_valid)

);




logic trace_fifo_overflow;
always_ff @(posedge aclk or negedge resetn)
begin

    if(!resetn)
        trace_fifo_overflow <= 1'b0;

    else if(trace_fifo_wr_en && trace_fifo_full)
        trace_fifo_overflow <= 1'b1;

end

always_ff @(posedge pclk or negedge presetn)
begin

    if(!presetn)
    begin
        trace_id_o   <= 8'h00;
        trace_data_o <= 32'h0;
    end

    else if(trace_fifo_rd_en)
    begin
        trace_id_o   <= apb_trace_id;
        trace_data_o <= apb_trace_data;
    end
 
   else if(apb_trace_req) 
    begin
        trace_id_o   <= axi_trace_id_pclk;
        trace_data_o <= axi_trace_data_pclk;
    end

end


    // =========================================================================
    // AXI slave
    // =========================================================================
    axi_slave #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH),
        .STRB_WIDTH (STRB_WIDTH),
        .PTR_WIDTH  (PTR_WIDTH)
    ) slave (
        .aclk                   (aclk),
        .aresetn                (resetn),

        // Write address channel
        .awvalid                (awvalid),
        .awaddr                 (awaddr),
        .awlen                  (awlen),
        .awsize                 (awsize),
        .awburst                (awburst),
        .awready                (awready),

        // Write data channel
        .wvalid                 (wvalid),
        .wdata                  (wdata),
        .wstrb                  (wstrb),
        .wlast                  (wlast),
        .wready                 (wready),

        // Write response channel
        .bready                 (bready),
        .bresp                  (bresp),
        .bvalid                 (bvalid),

        // Read address channel
        .arvalid                (arvalid),
        .araddr                 (araddr),
        .arlen                  (arlen),
        .arsize                 (arsize),
        .arburst                (arburst),
        .arready                (arready),

        // Read data / response channel
        .rready                 (rready),
        .rvalid                 (rvalid),
        .rdata                  (rdata),
        .rresp                  (rresp),
        .rlast                  (rlast),

        // FIFO write path
        .fifo_write             (write_to_fifo),
        .wr_en_waddr            (wr_en_waddr_w),

        // FIFO read address path
        .fifo_raddr_out         (raddr_to_fifo),
        .wr_en_raddr            (wr_en_raddr),

        // Read data from rdata_fifo
        .fifo_rdata_in          (rdata_to_axi),

        // Flow-control from FIFOs
        .full_flag              (full_flag_data),
        .full_flag_rdata        (full_flag_rdata),
        .rdata_rd_en            (rdata_fifo_rd_en),

        // rdata_req: 1 when rdata_fifo has data (not empty)
        .rdata_req              (rdata_fifo_empty),

        // pslverr (CDC-synced from pclk to aclk)
        .apb_error                (slverr_to_axi),
        .apb_wr_done           (apb_wr_done2axi_w),
        .apb_rd_done            (apb_rd_done2axi_w),
        .apb_rd_error_seen      (axi_apb_rd_error_seen)


    );

    // =========================================================================
    // Write FIFO: aclk (write) ? pclk (read)
    // Carries packed {waddr[31:0], wdata[31:0]}
    // =========================================================================
    async_fifo_write #(
        .WRITE_WIDTH (FIFO_WIDTH),
        .READ_WIDTH  (FIFO_WIDTH),
        .FIFO_DEPTH  (FIFO_DEPTH)
    ) write_fifo (
        .w_clk          (aclk),
        .r_clk          (pclk),
        .aresetn        (resetn),
        .presetn        (presetn),
        .wr_en          (wr_en_waddr_w),
        .rd_en          (req_write),       // 1-cycle pulse from arbiter
        .write_data     (write_to_fifo),
        .read_data      (write_to_arbiter),
        .full           (full_flag_data),
        .wr_transfer_flag  (transfer_flag_wt) // ~emty ? arbiter wr_req (after sync)
    );

    // =========================================================================
    // Read address FIFO: aclk (write) ? pclk (read)
    // Carries read addresses generated by the AR/R channel state machine
    // =========================================================================
    async_fifo_write #(
        .WRITE_WIDTH (ADDR_WIDTH),         
        .READ_WIDTH  (ADDR_WIDTH),         
        .FIFO_DEPTH  (FIFO_DEPTH)
    ) raddr_fifo (
        .w_clk          (aclk),
        .r_clk          (pclk),
        .aresetn        (resetn),
        .presetn        (presetn),
        .wr_en          (wr_en_raddr),
        .rd_en          (req_read),        // 1-cycle pulse from arbiter
        .write_data     (raddr_to_fifo),
        .read_data      (raddr_to_arbiter),
        .full           (full_flag_rdata),
        .wr_transfer_flag  (emty_fifo_raddr)  // ~emty ? arbiter rd_req (after sync)
    );

    // =========================================================================
    // Read data FIFO: pclk (write) ? aclk (read)
    // APB master writes prdata here; AXI slave reads it
    // =========================================================================


    async_fifo_read #(
        .WRITE_WIDTH (DATA_WIDTH),
        .READ_WIDTH  (DATA_WIDTH),
        .FIFO_DEPTH  (FIFO_DEPTH)
    ) rdata_fifo (
        .w_clk      (pclk),
        .r_clk      (aclk),
        .aresetn    (resetn),
        .presetn    (presetn),
        .wr_en      (rdata_wr_en_wire),
        .rd_en      (rdata_fifo_rd_en),   
        .write_data (read_data_w),
        .read_data  (rdata_to_axi),
//        .full       (full_flag_apb),
        .rd_transfer_flag       (rdata_fifo_empty) // ~emty ? arbiter wr_req (after sync)
    );

    // =========================================================================
    // APB master
    // =========================================================================
    apb_master #(
        .ADDR_WIDTH  (ADDR_WIDTH),
        .DATA_WIDTH  (DATA_WIDTH),
        .WRITE_WIDTH (FIFO_WIDTH),
        .TIMEOUT_CNT_WIDTH (TIMEOUT_CNT_WIDTH)		                ,
		.TIMEOUT_VALUE	(TIMEOUT_VALUE)		

    ) apb_m (
        .pclk        (pclk),
        .prst_n      (presetn),
        .addr_in     (raddr_to_arbiter),  // read address from raddr_fifo
        .wdata_in    (write_to_arbiter),  // {waddr,wdata} from write_fifo
        .wr_req      (wr_gnt_apb_w),      // level from arbiter
        .rd_req      (rd_gnt_apb_w),      // level from arbiter
        .paddr       (paddr),
        .psel        (psel),
        .penable     (penable),
        .pwrite      (pwrite),
        .pwdata      (pwdata),
        .prdata      (prdata),
        .pready      (pready),
        .pslverr     (pslverr),
        .rdata_out   (read_data_w),
        .rdata_wr_en (rdata_wr_en_wire),
        .apb_done        (apb_done_w),
        .wr_done     (apb_wr_done_w),
        .rd_done     (apb_rd_done_w),
        .time_out    (apb_time_out),
        .t_counter   (apb_t_counter),
        .err         (apb_err_w)
    );

    // =========================================================================
    // Arbiter
    // =========================================================================
    arbiter arbtr (
        .pclk                   (pclk),
        .presetn                (presetn),
        .wr_req_fifo            (transfer_flag_wt),   // slave request AND data present
        .rd_req_fifo            (emty_fifo_raddr),    // slave request AND addr present
        .apb_done               (apb_done_w),
        .wr_gnt                 (req_write),
        .wr_gnt_apb             (wr_gnt_apb_w),
        .rd_gnt                 (req_read),
        .rd_gnt_apb             (rd_gnt_apb_w)
//        .wr_grant_from_arbiter  (wr_grant_arb_pclk),
//        .rd_grant_from_arbiter  (rd_grant_arb_pclk)
    );

    // =========================================================================
    // CDC synchronizers
    // =========================================================================

/*
     bridge_ndff_sync apb_rd_done_sync (
        .clk      (aclk),
        .resetn   (resetn),
        .data_in  (apb_rd_done_w),
        .sync_out (apb_rd_done2axi_w)
    );

    bridge_ndff_sync apb_rd_done_sync (
        .clk      (pclk),
        .resetn   (resetn),
        .data_in  (apb_rd_done_w),
        .sync_out (apb_rd_done2axi_w)
    );
*/

    // pslverr: pclk ? aclk
    bridge_ndff_sync slverr_sync (
        .clk      (aclk),
        .resetn   (resetn),
        .data_in  (apb_err_w),
        .sync_out (slverr_to_axi)
    );


    // apb_wr_done / apb_rd_done: each beat done in write and read synchronized and sending to the axi_slave
    bridge_ndff_sync apb_wr_done_sync (
        .clk      (aclk),
        .resetn   (resetn),
        .data_in  (apb_wr_done_w),
        .sync_out (apb_wr_done2axi_w)
    );

    bridge_ndff_sync apb_rd_done_sync (
        .clk      (aclk),
        .resetn   (resetn),
        .data_in  (apb_rd_done_w),
        .sync_out (apb_rd_done2axi_w)
    );




endmodule
