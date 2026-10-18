// Host-driven return to the menu: host write to tap 0x1FFF raises $5007 bit 7; the NES then runs
// `sta $5007; jmp ($FFFC)` from RAM, so the write switches in the menu mapper before the vector fetch.
module menu_ret(
	input clk,
	input map_rst,
	input CpuBus cpu,
	input host_we,
	input [12:0] host_addr,
	output cpu_oe,
	output [7:0] cpu_do,
	output reg menu_req
);
	reg flag;
	reg [1:0] m2_s;
	wire reg5007 = cpu.addr == 16'h5007;

	always @(posedge clk) begin
		m2_s <= {m2_s[0], cpu.m2};
		if (map_rst) begin
			flag <= 0;
			menu_req <= 0;
		end else begin
			if (host_we && host_addr == 13'h1FFF) flag <= 1;
			if (m2_s == 2'b11 && !cpu.rw && reg5007) menu_req <= 1;
		end
	end

	assign cpu_oe = cpu.m2 & cpu.rw & reg5007;
	assign cpu_do = {flag, 7'd0};
endmodule
