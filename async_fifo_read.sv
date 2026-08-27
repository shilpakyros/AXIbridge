
module async_fifo_read #(
    parameter WRITE_WIDTH = 8,
    parameter READ_WIDTH  = 8,
    parameter FIFO_DEPTH  = 16,
    parameter PTR_WIDTH   = $clog2(FIFO_DEPTH)
)(
    input  wire                   w_clk,
    input  wire                   r_clk,
    input  wire                   aresetn,       // active-low async reset
    input  wire                   presetn,
    input  wire                   wr_en,
    input  wire                   rd_en,

    input  wire [WRITE_WIDTH-1:0] write_data,
    output reg  [READ_WIDTH-1:0]  read_data,


//    output reg                    full,
//    output reg                    emty
    output wire                   rd_transfer_flag
);

    // Internal storage
    reg [WRITE_WIDTH-1:0] fifo [FIFO_DEPTH-1:0];
    integer i;

    // Write-domain pointers
    bit [PTR_WIDTH-1:0] write_ptr;
    reg                 write_toggle;

    // Read-domain pointers
    bit [PTR_WIDTH-1:0] read_ptr;
    reg                 read_toggle;
    
    logic emty;
    logic full;


    // 
    // Gray-coded pointers (combinational)
    wire [PTR_WIDTH-1:0] write_gray_ptr;
    wire [PTR_WIDTH-1:0] read_gray_ptr;

    reg [PTR_WIDTH-1:0] wr_ptr_sync1,  write_ptr_rd_clk;
    reg                 wr_tog_sync1,  write_toggle_rd_clk;

    reg [PTR_WIDTH-1:0] rd_ptr_sync1,  read_ptr_wr_clk;
    reg                 rd_tog_sync1,  read_toggle_wr_clk;



    assign write_gray_ptr = write_ptr ^ (write_ptr >> 1);
    assign read_gray_ptr  = read_ptr  ^ (read_ptr  >> 1);



    // 2-stage synchronizers: write side ? r_clk domain
    always @(posedge r_clk or negedge aresetn) begin
        if (!aresetn) begin
            wr_ptr_sync1        <= '0;
            write_ptr_rd_clk    <= '0;
            wr_tog_sync1        <= 1'b0;
            write_toggle_rd_clk <= 1'b0;
        end else begin
            wr_ptr_sync1        <= write_gray_ptr;
            write_ptr_rd_clk    <= wr_ptr_sync1;
            wr_tog_sync1        <= write_toggle;
            write_toggle_rd_clk <= wr_tog_sync1;
        end
    end

    // 2-stage synchronizers: read side ? w_clk domain
 
    always @(posedge w_clk or negedge presetn) begin
        if (!presetn) begin
            rd_ptr_sync1       <= '0;
            read_ptr_wr_clk    <= '0;
            rd_tog_sync1       <= 1'b0;
            read_toggle_wr_clk <= 1'b0;
        end else begin
            rd_ptr_sync1       <= read_gray_ptr;
            read_ptr_wr_clk    <= rd_ptr_sync1;
            rd_tog_sync1       <= read_toggle;
            read_toggle_wr_clk <= rd_tog_sync1;
        end
    end

    // Write logic  (w_clk domain)
    always @(posedge w_clk or negedge presetn) begin
        if (!presetn) begin
            write_ptr    <= {PTR_WIDTH{1'b0}};
            write_toggle <= 1'b0;
            for (i = 0; i < FIFO_DEPTH; i = i + 1)
                fifo[i] <= {WRITE_WIDTH{1'b0}};
        end else begin
            if (wr_en && !full) begin
                fifo[write_ptr] <= write_data;
                if (write_ptr == PTR_WIDTH'(FIFO_DEPTH - 1)) begin
                    write_toggle <= ~write_toggle;
                    write_ptr    <= {PTR_WIDTH{1'b0}};
                end else begin
                    write_ptr <= write_ptr + {{PTR_WIDTH-1{1'b0}},1'b1};
                end
            end
        end
    end

    // Read logic  (r_clk domain)
    always @(posedge r_clk or negedge aresetn) begin
        if (!aresetn) begin
            read_ptr    <= {PTR_WIDTH{1'b0}};
            read_toggle <= 1'b0;
            read_data   <= {READ_WIDTH{1'b0}};
        end else begin
            if (rd_en && !emty) begin
                read_data <= fifo[read_ptr];
                if (read_ptr == PTR_WIDTH'(FIFO_DEPTH - 1)) begin
                    read_toggle <= ~read_toggle;
                    read_ptr    <= {PTR_WIDTH{1'b0}};
                end else begin
                    read_ptr <= read_ptr + {{PTR_WIDTH-1{1'b0}},1'b1};
                end
            end
        end
    end




    // Full / empty flags
    always_comb begin
        emty = (write_ptr_rd_clk == read_gray_ptr) &&
               (write_toggle_rd_clk == read_toggle);

        full = (write_gray_ptr == read_ptr_wr_clk) &&
               (write_toggle   != read_toggle_wr_clk);

     end


    assign rd_transfer_flag = ~emty;

endmodule
