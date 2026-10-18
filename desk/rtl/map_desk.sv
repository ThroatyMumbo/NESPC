// map_desk -- NES 2.0 mapper 773: fixed 16 KB kernel at $C000, banked 16 KB PSRAM window at $8000 ($5010),
// 8 KB PRG RAM at $6000, a bitmap BG with its blitter (fb.sv, blit.sv), sprites in CHR RAM, host pad and menu return.

module map_desk(
	input  MapIn  mai,
	output MapOut mao
);
//************************************************************* base header
	CpuBus cpu;
	PpuBus ppu;
	SysCfg cfg;
	SSTBus sst;
	assign cpu = mai.cpu;
	assign ppu = mai.ppu;
	assign cfg = mai.cfg;
	assign sst = mai.sst;

	MemCtrl prg;
	MemCtrl chr;
	MemCtrl srm;
	assign mao.prg = prg;
	assign mao.chr = chr;
	assign mao.srm = srm;

	assign prg.dati			= cpu.data;
	assign chr.dati			= ppu.data;
	assign srm.dati			= cpu.data;

	wire mr_oe;
	wire [7:0] mr_do;
	reg [7:0] host_pad;
	reg [7:0] bank;
	reg [7:0] beat;
	wire gfx_oe, fb_oe;
	wire [7:0] gfx_do, fb_do, gfx_st, gfx_rows;
	wire pad_oe = cpu.m2 & cpu.rw & cpu.addr == 16'h5008;
	assign mao.map_cpu_oe	= mr_oe | pad_oe | gfx_oe | (srm.ce & srm.oe) | (prg.ce & prg.oe);
	assign mao.map_cpu_do	= mr_oe ? mr_do : pad_oe ? host_pad : gfx_oe ? gfx_do : srm.ce ? mai.srm_do : mai.prg_do;

	assign mao.map_ppu_oe	= (chr.ce & chr.oe) | fb_oe;
	assign mao.map_ppu_do	= fb_oe ? fb_do : mai.chr_do;
//************************************************************* configuration
	assign mao.prg_mask_off = 1; // banks sit past the 32 KB image
	assign mao.chr_mask_off = 0;
	assign mao.srm_mask_off = 0;
	assign mao.mir_4sc		= 0;
	assign mao.bus_cf 		= 0;
//************************************************************* host tap reads
	assign mao.sst_di[7:0] =
		sst.addr == 0 ? "D" : sst.addr == 1 ? "E" : sst.addr == 2 ? "S" : sst.addr == 3 ? "K" :
		sst.addr == 13'h10 ? host_pad : sst.addr == 13'h11 ? bank : sst.addr == 13'h12 ? gfx_st :
		sst.addr == 13'h13 ? gfx_rows : sst.addr == 13'h14 ? beat :
		sst.addr[7:0] == 127 ? cfg.map_idx : 8'hff;
//************************************************************* host tap writes
	reg [2:0] we_s;
	always @(posedge mai.clk) we_s <= {we_s[1:0], sst.we};
	wire host_we = we_s[1] & !we_s[2];

	// buttons pressed from the host, ORed into pad 1 by the NES (tap 0x10, CPU $5008)
	always @(posedge mai.clk)
		if (mai.map_rst) host_pad <= 0;
		else if (host_we && sst.addr == 13'h10) host_pad <= sst.dato;
//************************************************************* $8000 bank: 0 = the image's first 16 KB, $40 on = apps
	reg [1:0] m2_s;
	always @(posedge mai.clk) begin
		m2_s <= {m2_s[0], cpu.m2};
		if (mai.map_rst) bank <= 0;
		else if (m2_s == 2'b11 && !cpu.rw && cpu.addr == 16'h5010) bank <= cpu.data;
	end

	// a heartbeat from the main loop once the boot is past its card reads (tap 0x14, CPU $5009)
	always @(posedge mai.clk)
		if (mai.map_rst) beat <= 0;
		else if (m2_s == 2'b11 && !cpu.rw && cpu.addr == 16'h5009) beat <= cpu.data;
//************************************************************* the bitmap and its blitter
	wire [12:0] fb_addr, pal_addr;
	wire [15:0] fb_d, fb_q;
	wire [1:0] fb_be, pal_d, pal_q;
	wire fb_we, pal_we;
	fb_disp disp(.clk(mai.clk), .ppu(ppu), .ppu_oe(fb_oe), .ppu_do(fb_do),
		.fb_addr(fb_addr), .fb_d(fb_d), .fb_be(fb_be), .fb_we(fb_we), .fb_q(fb_q),
		.pal_addr(pal_addr), .pal_d(pal_d), .pal_we(pal_we), .pal_q(pal_q));
	desk_gfx gfx(.clk(mai.clk), .rst(mai.map_rst), .cpu(cpu), .cpu_oe(gfx_oe), .cpu_do(gfx_do),
		.fb_addr(fb_addr), .fb_d(fb_d), .fb_be(fb_be), .fb_we(fb_we), .fb_q(fb_q),
		.pal_addr(pal_addr), .pal_d(pal_d), .pal_we(pal_we), .pal_q(pal_q), .dbg_st(gfx_st), .dbg_rows(gfx_rows));
//************************************************************* mapper-controlled pins
	assign srm.ce				= {cpu.addr[15:13], 13'd0} == 16'h6000;
	assign srm.oe				= cpu.rw;
	assign srm.we				= !cpu.rw;
	assign srm.addr[12:0]	= cpu.addr[12:0];

	assign prg.ce				= cpu.addr[15];
	assign prg.oe 				= cpu.rw;
	assign prg.we				= !cpu.rw & cpu.addr[15:14] == 2'b10 & bank != 0;
	assign prg.addr			= {1'b0, cpu.addr[14] ? 8'd1 : bank, cpu.addr[13:0]};

	assign chr.ce 				= !ppu.addr[13] & ppu.addr[12]; // sprites; $0000-$0FFF is the bitmap
	assign chr.oe 				= !ppu.oe;
	assign chr.we 				= !ppu.we & chr.ce;
	assign chr.addr[12:0]	= ppu.addr[12:0];

	assign mao.ciram_a10 	= cfg.mir_v ? ppu.addr[10] : ppu.addr[11];
	assign mao.ciram_ce 		= 1; // high disables CIRAM: fb_disp answers nametable and attribute reads

	assign mao.irq				= 0;
	assign mao.led 			= 0;
	assign mao.chr_xram_ce	= 0;
	assign mao.snd			= 0;
//************************************************************* return to the menu (host tap 0x1FFF, CPU $5007)
	menu_ret mret(.clk(mai.clk), .map_rst(mai.map_rst), .cpu(cpu), .host_we(host_we),
		.host_addr(sst.addr), .cpu_oe(mr_oe), .cpu_do(mr_do), .menu_req(mao.menu_req));

endmodule
