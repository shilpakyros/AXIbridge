
package axi_typedef_pkg;

                    parameter STRB_WIDTH = 4;                    
                    parameter FIFO_DEPTH = 256; // 256;
					parameter ADDR_WIDTH = 32;
					parameter DATA_WIDTH = 32;
					parameter FIFO_WIDTH = ADDR_WIDTH + DATA_WIDTH;
                    parameter ADDR_LSB = $clog2(DATA_WIDTH/8);
                    parameter logic[31:0] ERR_DEPTH = 32'hFFFF_FFFB;//4294967291;
                    parameter PTR_WIDTH   = $clog2(FIFO_DEPTH);


                    //axi slave

                    //apb_master

typedef enum logic [1:0]{
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

typedef enum {WRITE_TXN, READ_ADDR_TXN, READ_DATA_TXN} txn_type_e;
				


endpackage
