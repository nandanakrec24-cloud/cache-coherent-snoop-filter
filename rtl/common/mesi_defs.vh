`ifndef MESI_DEFS_VH
`define MESI_DEFS_VH

// Shared encodings. These MUST match rtl/cache/l1_cache.v.
`define MESI_I       2'b00
`define MESI_S       2'b01
`define MESI_E       2'b10
`define MESI_M       2'b11

`define MISS_READ    2'b00
`define MISS_RDX     2'b01
`define MISS_UPGRADE 2'b10

// Initial backing-memory command encoding (separate from miss request types).
`define MEM_READ     1'b0
`define MEM_WRITE    1'b1

`endif
