// Framebuffer CPU side: registers at $5020-$5034, a 2 KB window at $5800, and the blitter.
// Every operation is a rect of pixels in screen coordinates, clipped; the CPU wins port B over the blitter.
module desk_gfx(
	input clk,
	input rst,
	input CpuBus cpu,
	output cpu_oe,
	output [7:0] cpu_do,
	output logic [12:0] fb_addr,
	output logic [15:0] fb_d,
	output logic [1:0] fb_be,
	output logic fb_we,
	input [15:0] fb_q,
	output logic [12:0] pal_addr,
	output logic [1:0] pal_d,
	output logic pal_we,
	input [1:0] pal_q,
	output [7:0] dbg_st, // host tap: busy, the operation and the engine's state
	output [7:0] dbg_rows
);
	localparam OP_FILL = 1, OP_COPY = 2, OP_EXPAND = 3, OP_IMAGE = 4, OP_PAL = 5;
	localparam F_BG_CLEAR = 0, F_KEY = 1, F_XOR = 2, F_OVER = 3, F_PAL = 4;
//************************************************************* CPU cycles: the bus taken 200 ns into M2 high
	reg [1:0] m2_s;
	reg [4:0] m2_cnt;
	reg [15:0] wa, ra;
	reg [7:0] wd;
	reg wrw, rrw, taken;
	always @(posedge clk) begin
		m2_s <= {m2_s[0], cpu.m2};
		m2_cnt <= !m2_s[1] ? 5'd0 : m2_cnt == 5'd31 ? m2_cnt : m2_cnt + 1'd1;
		taken <= m2_cnt == 10;
		// the address is settled once M2 is high; reads need it early, write data needs 200 ns
		if (m2_cnt == 2) begin
			ra <= cpu.addr;
			rrw <= cpu.rw;
		end
		if (m2_cnt == 10) begin
			wa <= cpu.addr;
			wd <= cpu.data;
			wrw <= cpu.rw;
		end
	end
	wire wr_ev = taken & !wrw;
	wire reg_ev = wr_ev & wa[15:4] == 12'h502;

	reg [7:0] r_dx, r_dy, r_w, r_h, r_sx, r_sy, r_key, r_flags, r_cx0, r_cy0, r_cx1, r_cy1;
	reg [7:0] r_mx0, r_my0, r_mx1, r_my1;
	reg [1:0] r_fg, r_bg;
	reg [3:0] r_win;
	wire op_ev = reg_ev & wa[3:0] == 4'hE;
	wire data_ev = reg_ev & wa[3:0] == 4'hF;
	reg busy;
	reg [2:0] op;
	// a streamed rect moves the pen past itself as it starts, so DX written after that wins
	wire adv = op_ev & !busy & (wd[2:0] == OP_EXPAND | wd[2:0] == OP_IMAGE);
	wire [8:0] w9 = r_w == 0 ? 9'd256 : {1'b0, r_w};
	always @(posedge clk)
		if (rst) begin
			r_cx0 <= 0; r_cy0 <= 0; r_cx1 <= 0; r_cy1 <= 240; r_flags <= 0; r_win <= 0;
			r_mx0 <= 0; r_mx1 <= 0;
		end else begin
			if (reg_ev)
				case (wa[3:0])
					4'h0: r_dx <= wd;
					4'h1: r_dy <= wd;
					4'h2: r_w <= wd;
					4'h3: r_h <= wd;
					4'h4: r_sx <= wd;
					4'h5: r_sy <= wd;
					4'h6: r_fg <= wd[1:0];
					4'h7: r_bg <= wd[1:0];
					4'h8: r_key <= wd;
					4'h9: r_flags <= wd;
					4'hA: r_cx0 <= wd;
					4'hB: r_cy0 <= wd;
					4'hC: r_cx1 <= wd;
					4'hD: r_cy1 <= wd;
				endcase
			if (wr_ev & wa == 16'h5030) r_win <= wd[3:0];
			if (wr_ev & wa == 16'h5031) r_mx0 <= wd;
			if (wr_ev & wa == 16'h5032) r_my0 <= wd;
			if (wr_ev & wa == 16'h5033) r_mx1 <= wd;
			if (wr_ev & wa == 16'h5034) r_my1 <= wd;
			if (adv) r_dx <= r_dx + r_w;
		end
//************************************************************* the window: {r_win, A10-A0}, spans' bytes then their palettes
	// decoded from registered samples only: the raw bus glitches through $58xx between cycles
	wire win_cyc = m2_s[1] & m2_cnt > 2 & ra[15:11] == 5'b01011;
	wire win_now = win_cyc & rrw;
	wire [14:0] u_now = {r_win, ra[10:0]};
	wire [14:0] u_wr = {r_win, wa[10:0]};
	wire win_wr = wr_ev & wa[15:11] == 5'b01011;
	function automatic fb_area(input [14:0] u); fb_area = !u[14] & u[13:0] < 14'h3C00; endfunction
	function automatic pal_area(input [14:0] u); pal_area = u[14] & u[13:0] < 14'h1E00; endfunction
	wire grant = !win_cyc & !win_wr;

	wire win_bus = cpu.addr[15:11] == 5'b01011;
	assign cpu_oe = cpu.m2 & cpu.rw & (win_bus | cpu.addr == 16'h502E);
	assign cpu_do = !win_bus ? {busy, 7'd0} :
		fb_area(u_now) ? (u_now[0] ? fb_q[15:8] : fb_q[7:0]) : pal_area(u_now) ? {6'd0, pal_q} : 8'hFF;
//************************************************************* line buffer: two rows of up to 33 spans
	reg [6:0] lb_wa;
	logic [6:0] lb_ra;
	reg [15:0] lb_wd;
	reg lb_we;
	(* ramstyle = "M9K" *) reg [15:0] lb[0:127];
	reg [15:0] lb_q;
	always @(posedge clk) begin
		if (lb_we) lb[lb_wa] <= lb_wd;
		lb_q <= lb[lb_ra];
	end
//************************************************************* the operation's state, latched at its start
	reg [7:0] dx, dy, sx, sy, key, flags, cx0, cy0, cx1, cy1, mx0, my0, mx1, my1;
	reg [8:0] w, h;
	reg [1:0] fg, bg;
	reg rev;
	reg [8:0] r;      // rows done
	reg [8:0] rr;     // the row being drawn, from the top of the rect
	reg [8:0] ydst;
	reg [5:0] d, d1;  // span on the row, its last
	reg [5:0] nj, nw; // next line buffer word, words a row
	reg [5:0] li;     // words of the row being streamed in
	reg lbank, pbank; // bank the CPU fills, the bank drawn
	reg [1:0] full;
	reg lo_byte;      // IMAGE: plane 0 of the word in, plane 1 next
	reg [7:0] lo_d;
	reg [8:0] loaded; // streamed rows taken
	reg [15:0] wa_w, wb_w, dq;
	reg [2:0] e;
	reg q_neg;

	localparam S_IDLE = 0, S_LOAD0 = 1, S_LOAD1 = 2, S_ROW = 3, S_PRE0 = 4, S_PRE1 = 5, S_SPAN0 = 6,
		S_SPAN1 = 7, S_SPAN2 = 8, S_PAL = 9, S_NEXT = 10, S_WAIT = 11, S_NEXT_ROW = 12;
	reg [3:0] st;

	wire streamed = op == OP_EXPAND | op == OP_IMAGE;
	assign dbg_st = {busy, op, st};
	assign dbg_rows = r[7:0];
	wire [8:0] rr_n = rev ? h - 1'd1 - r : r;
	wire [8:0] ysrc = {1'b0, sy} + rr;
	wire [8:0] y_n = {1'b0, dy} + rr_n;
	wire y_ok = ydst < 240 && ydst >= cy0 && (cy1 == 0 || ydst < cy1);
	// the mask: a rect only GF_OVER draws into, off while x0 == x1
	wire y_mask = !flags[F_OVER] && mx0 != mx1 && ydst >= my0 && (my1 == 0 || ydst < my1);
	wire [9:0] last_x = {2'b0, dx} + w - 1'd1;
	wire [3:0] base = (op == OP_COPY ? {1'b0, sx[2:0]} : 4'd0) - {1'b0, dx[2:0]}; // -7 to 7
	wire [5:0] nw_n = op == OP_COPY ? ({3'b0, sx[2:0]} + w + 9'd7) >> 3 : (w + 9'd7) >> 3;
	wire [5:0] src_span = {1'b0, sx[7:3]} + nj;

	// a span's pixels: source window, rect, clip, transparency, then written over or XORed onto dq
	wire [15:0] pw0 = {wa_w[7:0], wb_w[7:0]} << e;
	wire [15:0] pw1 = {wa_w[15:8], wb_w[15:8]} << e;
	reg [15:0] merged;
	always @* begin
		merged = dq;
		for (int i = 0; i < 8; i++) begin
			logic [7:0] x;
			logic [8:0] k;
			logic s0, s1, tr, en;
			logic [1:0] c, dc, nc;
			x = {d[4:0], i[2:0]};
			k = {1'b0, x} - {1'b0, dx};
			s0 = pw0[15 - i];
			s1 = pw1[15 - i];
			case (op)
				OP_FILL: begin c = fg; tr = 0; end
				OP_EXPAND: begin c = s0 ? fg : bg; tr = !s0 & flags[F_BG_CLEAR]; end
				default: begin c = {s1, s0}; tr = flags[F_KEY] & c == key[1:0]; end
			endcase
			en = k < w && x >= cx0 && (cx1 == 0 || x < cx1) && !tr &&
				!(y_mask && x >= mx0 && (mx1 == 0 || x < mx1));
			dc = {dq[15 - i], dq[7 - i]};
			nc = flags[F_XOR] ? dc ^ c : c;
			if (en) begin
				merged[7 - i] = nc[0];
				merged[15 - i] = nc[1];
			end
		end
	end
	wire [7:0] span_x0 = {d[4:0], 3'd0};
	wire span_clip = {1'b0, span_x0} + 9'd7 >= cx0 && (cx1 == 0 || span_x0 < cx1) &&
		!(y_mask && {1'b0, span_x0} + 9'd7 >= mx0 && (mx1 == 0 || span_x0 < mx1));
	// read addresses are taken at the clock edge, so the data is there in the next state
	wire [12:0] eng_addr = st == S_LOAD0 ? {ysrc[7:0], src_span[4:0]} : {ydst[7:0], d[4:0]};
	// COPY with F_PAL: the source row's span palettes; a span takes the one its first pixel came from
	reg [1:0] plb[0:32];
	wire [1:0] copy_pal = plb[nj == 0 ? 6'd0 : nj - 1'd1];
	wire pal_copy = op == OP_COPY & flags[F_PAL];
	assign lb_ra = {op == OP_COPY ? 1'b0 : pbank, st == S_PRE0 ? 6'd0 : nj};

	always @(posedge clk) begin
		lb_we <= 0;
		if (rst) begin
			st <= S_IDLE;
			busy <= 0;
		end else begin
			// a streamed row byte from the CPU, into the bank it is filling
			if (data_ev && busy && streamed && loaded != h && !full[lbank]) begin
				if (op == OP_IMAGE && !lo_byte) begin
					lo_d <= wd;
					lo_byte <= 1;
				end else begin
					lb_wa <= {lbank, li};
					lb_wd <= op == OP_IMAGE ? {wd, lo_d} : {8'h00, wd};
					lb_we <= 1;
					lo_byte <= 0;
					if (li + 1'd1 == nw) begin
						li <= 0;
						full[lbank] <= 1;
						lbank <= !lbank;
						loaded <= loaded + 1'd1;
					end else
						li <= li + 1'd1;
				end
			end

			case (st)
			S_IDLE:
				if (op_ev && wd[2:0] >= OP_FILL && wd[2:0] <= OP_PAL) begin
					op <= wd[2:0];
					dx <= r_dx; dy <= r_dy; sx <= r_sx; sy <= r_sy;
					w <= w9; h <= r_h == 0 ? 9'd256 : {1'b0, r_h};
					fg <= r_fg; bg <= r_bg; key <= r_key; flags <= r_flags;
					cx0 <= r_cx0; cy0 <= r_cy0; cx1 <= r_cx1; cy1 <= r_cy1;
					mx0 <= r_mx0; my0 <= r_my0; mx1 <= r_mx1; my1 <= r_my1;
					rev <= wd[2:0] == OP_COPY && r_dy > r_sy;
					r <= 0;
					li <= 0; lbank <= 0; pbank <= 0; full <= 0; lo_byte <= 0; loaded <= 0;
					busy <= 1;
					st <= S_NEXT;
				end
			S_NEXT: begin // per row: work out its geometry, then fetch its source
				rr <= rr_n;
				ydst <= y_n;
				nw <= nw_n;
				d1 <= last_x > 255 ? 6'd31 : {1'b0, last_x[7:3]};
				e <= base[2:0];
				q_neg <= base[3];
				nj <= 0;
				st <= op == OP_COPY ? S_LOAD0 : streamed ? S_WAIT : S_ROW;
			end
			S_WAIT:
				if (full[pbank]) st <= S_ROW;
			S_LOAD0: // COPY: the source row into the line buffer, a span per two cycles
				if (grant) st <= S_LOAD1;
			S_LOAD1: begin
				lb_wa <= {1'b0, nj};
				lb_wd <= ysrc < 240 && src_span < 32 ? fb_q : 16'h0;
				lb_we <= 1;
				plb[nj] <= ysrc < 240 && src_span < 32 ? pal_q : 2'd0;
				if (nj + 1'd1 == nw) begin
					nj <= 0;
					st <= S_ROW;
				end else begin
					nj <= nj + 1'd1;
					st <= S_LOAD0;
				end
			end
			S_ROW: begin
				d <= {1'b0, dx[7:3]};
				if (!y_ok) st <= S_NEXT_ROW;
				else if (op == OP_PAL) st <= S_PAL;
				else begin
					nj <= q_neg ? 6'd0 : 6'd1;
					st <= S_PRE0;
				end
			end
			S_PRE0: st <= S_PRE1;
			S_PRE1: begin
				wa_w <= q_neg ? 16'h0 : lb_q;
				st <= S_SPAN0;
			end
			S_SPAN0: // the span under the rect and the next source word
				if (grant) st <= S_SPAN1;
			S_SPAN1: begin
				dq <= fb_q;
				wb_w <= nj < nw ? lb_q : 16'h0;
				st <= S_SPAN2;
			end
			S_SPAN2:
				if (grant) begin
					wa_w <= wb_w;
					nj <= nj + 1'd1;
					d <= d + 1'd1;
					st <= d == d1 ? S_NEXT_ROW : S_SPAN0;
				end
			S_PAL:
				if (grant) begin
					d <= d + 1'd1;
					if (d == d1) st <= S_NEXT_ROW;
				end
			S_NEXT_ROW: begin
				if (streamed) begin
					full[pbank] <= 0;
					pbank <= !pbank;
				end
				r <= r + 1'd1;
				if (r + 1'd1 == h) begin
					busy <= 0;
					st <= S_IDLE;
				end else
					st <= S_NEXT;
			end
			endcase
		end
	end
//************************************************************* port B: the CPU's window cycle, else the blitter's
	always @* begin
		fb_addr = eng_addr;
		fb_be = 2'b11;
		fb_d = merged;
		fb_we = 0;
		pal_addr = eng_addr;
		pal_d = op == OP_COPY ? copy_pal : fg;
		pal_we = 0;
		if (win_wr) begin
			fb_addr = u_wr[13:1];
			fb_d = {wd, wd};
			fb_be = u_wr[0] ? 2'b10 : 2'b01;
			fb_we = fb_area(u_wr);
			pal_addr = u_wr[12:0];
			pal_d = wd[1:0];
			pal_we = pal_area(u_wr);
		end else if (win_now) begin
			fb_addr = u_now[13:1];
			pal_addr = u_now[12:0];
		end else begin
			fb_we = st == S_SPAN2 & grant;
			pal_we = (st == S_PAL | st == S_SPAN2 & pal_copy) & span_clip & grant;
		end
	end
endmodule
