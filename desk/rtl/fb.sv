// Bitmap display: BG pattern and attribute fetches answered from a 256x240 2bpp framebuffer
// with a palette per 8x1 span; nametable contents are ignored, scroll must be 0, sprites stay in CHR.
module fb_disp(
	input clk,
	input PpuBus ppu,
	output ppu_oe,
	output [7:0] ppu_do,
	// port B, CPU and blitter side: spans as {plane 1, plane 0}, and their palettes
	input [12:0] fb_addr,
	input [15:0] fb_d,
	input [1:0] fb_be,
	input fb_we,
	output [15:0] fb_q,
	input [12:0] pal_addr,
	input [1:0] pal_d,
	input pal_we,
	output [1:0] pal_q
);
	localparam ROWS = 30, IDLE_VBL = 11'd1000; // 20 us without a fetch: vblank
	wire [13:0] pa = ppu.addr;
//************************************************************* fetch tracking
	reg [13:0] fa1, fa2, fa3;
	reg [2:0] oe_q;
	always @(posedge clk) begin
		fa1 <= pa;
		fa2 <= fa1;
		fa3 <= fa2;
		oe_q <= {oe_q[1:0], ppu.oe};
	end
	wire f_ok = oe_q[2] & !oe_q[1] & fa1 == fa2 & fa2 == fa3;
	wire at_f = fa2[13] & fa2[9:6] == 4'hF;
	wire nt_ev = f_ok & fa2[13] & !at_f;
	wire other_ev = f_ok & !(fa2[13] & !at_f);
//************************************************************* scanline: three identical NT fetches start a line (as MMC5)
	reg [4:0] col, row;
	reg [13:0] last_nt;
	reg [1:0] same;
	reg [8:0] line; // -1 on the pre-render line
	reg after_spr;  // past the sprite fetches: the two prefetched tiles belong to the next line
	reg [10:0] idle;
	wire [8:0] tile_line = after_spr ? line + 1'd1 : line;
	always @(posedge clk) begin
		if (f_ok) idle <= 0;
		else if (idle != 11'h7FF) idle <= idle + 1'd1;
		if (idle == IDLE_VBL) begin
			line <= 9'h1FF;
			same <= 0;
			after_spr <= 0;
		end else if (nt_ev) begin
			col <= fa2[4:0];
			row <= fa2[9:5];
			last_nt <= fa2;
			if (fa2 != last_nt || same == 0) same <= 1;
			else if (same == 1) same <= 2;
			else if (same == 2) begin
				same <= 3;
				line <= line + 1'd1;
				after_spr <= 0;
			end
		end else if (other_ev) begin
			same <= 0;
			if (!fa2[13] & fa2[12]) after_spr <= 1;
		end
	end
//************************************************************* the RAMs' PPU ports
	reg [12:0] pal_ra;
	reg pal_ok;
	always @(posedge clk)
		if (nt_ev) begin
			pal_ra <= {fa2[9:5], tile_line[2:0], fa2[4:0]};
			pal_ok <= fa2[9:5] < ROWS;
		end
	wire [15:0] fb_qa;
	wire [1:0] pal_qa;
	fb_ram fbr(.clk(clk), .a_addr({row, fa1[2:0], col}), .a_q(fb_qa),
		.b_addr(fb_addr), .b_d(fb_d), .b_be(fb_be), .b_we(fb_we), .b_q(fb_q));
	pal_ram palr(.clk(clk), .a_addr(pal_ra), .a_q(pal_qa),
		.b_addr(pal_addr), .b_d(pal_d), .b_we(pal_we), .b_q(pal_q));

	wire fb_ok = row < ROWS;
	wire [1:0] pal = pal_ok ? pal_qa : 2'd0;
	assign ppu_oe = !ppu.oe & (pa[13] | !pa[12]);
	assign ppu_do = pa[13] ? (pa[9:6] == 4'hF ? {4{pal}} : 8'h00) :
		!fb_ok ? 8'h00 : pa[3] ? fb_qa[15:8] : fb_qa[7:0];
endmodule


// 7680 spans x 16 bits, true dual port: A reads for the PPU, B reads and writes bytes (15 M9K as 512x16)
module fb_ram(
	input clk,
	input [12:0] a_addr,
	output [15:0] a_q,
	input [12:0] b_addr,
	input [15:0] b_d,
	input [1:0] b_be,
	input b_we,
	output [15:0] b_q
);
`ifdef VERILATOR
	reg [15:0] m[0:7679];
	reg [15:0] qa, qb;
	assign a_q = qa;
	assign b_q = qb;
	always @(posedge clk) begin
		qa <= a_addr < 7680 ? m[a_addr] : 16'h0;
		if (b_we && b_addr < 7680) begin
			if (b_be[0]) m[b_addr][7:0] <= b_d[7:0];
			if (b_be[1]) m[b_addr][15:8] <= b_d[15:8];
		end
		qb <= b_addr < 7680 ? m[b_addr] : 16'h0;
	end
`else
	altsyncram #(
		.intended_device_family("Cyclone IV E"),
		.lpm_type("altsyncram"),
		.operation_mode("BIDIR_DUAL_PORT"),
		.width_a(16), .widthad_a(13), .numwords_a(7680),
		.width_b(16), .widthad_b(13), .numwords_b(7680),
		.maximum_depth(512),
		.byte_size(8), .width_byteena_a(2), .width_byteena_b(2),
		.outdata_reg_a("UNREGISTERED"), .outdata_reg_b("UNREGISTERED"),
		.address_reg_b("CLOCK0"), .indata_reg_b("CLOCK0"),
		.wrcontrol_wraddress_reg_b("CLOCK0"), .byteena_reg_b("CLOCK0"),
		.read_during_write_mode_mixed_ports("DONT_CARE"),
		.read_during_write_mode_port_b("NEW_DATA_NO_NBE_READ"),
		.power_up_uninitialized("FALSE"),
		.clock_enable_input_a("BYPASS"), .clock_enable_input_b("BYPASS"),
		.clock_enable_output_a("BYPASS"), .clock_enable_output_b("BYPASS")
	) ram(
		.clock0(clk), .address_a(a_addr), .data_a(16'h0), .byteena_a(2'b11), .wren_a(1'b0), .q_a(a_q),
		.address_b(b_addr), .data_b(b_d), .byteena_b(b_be), .wren_b(b_we), .q_b(b_q)
	);
`endif
endmodule


// 7680 span palettes x 2 bits, true dual port as fb_ram (2 M9K as 4096x2)
module pal_ram(
	input clk,
	input [12:0] a_addr,
	output [1:0] a_q,
	input [12:0] b_addr,
	input [1:0] b_d,
	input b_we,
	output [1:0] b_q
);
`ifdef VERILATOR
	reg [1:0] m[0:7679];
	reg [1:0] qa, qb;
	assign a_q = qa;
	assign b_q = qb;
	always @(posedge clk) begin
		qa <= a_addr < 7680 ? m[a_addr] : 2'd0;
		if (b_we && b_addr < 7680) m[b_addr] <= b_d;
		qb <= b_addr < 7680 ? m[b_addr] : 2'd0;
	end
`else
	altsyncram #(
		.intended_device_family("Cyclone IV E"),
		.lpm_type("altsyncram"),
		.operation_mode("BIDIR_DUAL_PORT"),
		.width_a(2), .widthad_a(13), .numwords_a(7680),
		.width_b(2), .widthad_b(13), .numwords_b(7680),
		.maximum_depth(4096),
		.outdata_reg_a("UNREGISTERED"), .outdata_reg_b("UNREGISTERED"),
		.address_reg_b("CLOCK0"), .indata_reg_b("CLOCK0"), .wrcontrol_wraddress_reg_b("CLOCK0"),
		.read_during_write_mode_mixed_ports("DONT_CARE"),
		.read_during_write_mode_port_b("NEW_DATA_NO_NBE_READ"),
		.power_up_uninitialized("FALSE"),
		.clock_enable_input_a("BYPASS"), .clock_enable_input_b("BYPASS"),
		.clock_enable_output_a("BYPASS"), .clock_enable_output_b("BYPASS")
	) ram(
		.clock0(clk), .address_a(a_addr), .data_a(2'd0), .wren_a(1'b0), .q_a(a_q),
		.address_b(b_addr), .data_b(b_d), .wren_b(b_we), .q_b(b_q)
	);
`endif
endmodule
