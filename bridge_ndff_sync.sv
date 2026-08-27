
module bridge_ndff_sync(
					input logic clk,
					input logic resetn,
					input logic data_in,
					output logic sync_out
				);

logic ff1;

always@(posedge clk or negedge resetn)begin
	if(!resetn)begin
		ff1 <= 1'b0;
        sync_out <= 1'b0;       // not reseted the sync_out signal previously
	end
	else begin
		ff1 <= data_in;
		sync_out <= ff1;
	end
end

endmodule
