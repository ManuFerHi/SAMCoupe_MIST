//============================================================================
// 
//  SamCoupe replica for MiST board
//  Copyright (C) 2016 Sorgelig
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//
//============================================================================

`default_nettype none

module SamCoupe
(
   input         CLOCK_27,   // Input clock 27 MHz

   output  [5:0] VGA_R,
   output  [5:0] VGA_G,
   output  [5:0] VGA_B,
   output        VGA_HS,
   output        VGA_VS,

   output        LED,

   output        AUDIO_L,
   output        AUDIO_R,

   input         SPI_SCK,
   output        SPI_DO,
   input         SPI_DI,
   input         SPI_SS2,
   input         SPI_SS3,
   input         CONF_DATA0,

   output [12:0] SDRAM_A,
   inout  [15:0] SDRAM_DQ,
   output        SDRAM_DQML,
   output        SDRAM_DQMH,
   output        SDRAM_nWE,
   output        SDRAM_nCAS,
   output        SDRAM_nRAS,
   output        SDRAM_nCS,
   output  [1:0] SDRAM_BA,
   output        SDRAM_CLK,
   output        SDRAM_CKE
);
`default_nettype none

assign LED = ~(ioctl_erasing | ioctl_download | fdd_sel);


////////////////////   CLOCKS   ///////////////////
wire clk_sys;
wire locked;

pll pll
(
	.inclk0(CLOCK_27),
	.c0(clk_sys),
	.c1(SDRAM_CLK),
	.locked(locked)
);

reg  ce_psg;  //8MHz
reg  ce_6mp;
reg  ce_6mn;
reg  ce_24m;
reg  cpu_en;
wire ce_cpu_p = cpu_en & ce_6mp;
wire ce_cpu_n = cpu_en & ce_6mn;
wire ce_cpu   = ce_6mn;

always @(negedge clk_sys) begin
	reg [3:0] counter = 0;
	reg [3:0] psg_div = 0;

	counter <=  counter + 1'd1;

	ce_24m  <= !counter[1:0];
	ce_6mp  <= !counter[3] & !counter[2:0];
	ce_6mn  <=  counter[3] & !counter[2:0];
	
	if(counter[3] & !counter[2:0]) cpu_en <= ~cpu_wait;

	psg_div <= psg_div + 1'd1;
	if(psg_div == 11) psg_div <= 0;
	ce_psg  <= !psg_div;
end


//////////////////   MIST ARM I/O   ///////////////////
wire        ps2_kbd_clk;
wire        ps2_kbd_data;

wire  [7:0] joystick_0;
wire  [7:0] joystick_1;
wire  [1:0] buttons;
wire  [1:0] switches;
wire        scandoubler_disable;
wire  [7:0] status;

wire [31:0] sd_lba = 0;
wire        sd_rd = 0;
wire        sd_wr = 0;
wire        sd_ack;
wire        sd_ack_conf;
wire        sd_conf = 0;
wire        sd_sdhc = 1;
wire  [8:0] sd_buff_addr;
wire  [7:0] sd_buff_dout;
wire  [7:0] sd_buff_din = 0;
wire        sd_buff_wr;
wire        sd_mounted;

wire        ioctl_wr;
wire [24:0] ioctl_addr;
wire  [7:0] ioctl_dout;
wire        ioctl_download;
wire        ioctl_erasing;
wire  [4:0] ioctl_index;
reg         ioctl_force_erase = 0;

mist_io #(.STRLEN(33)) user_io
(
	.*,
	.conf_str
	(
        "SAMCOUPE;DSK;O5,Contention,Off,On"
	),

	// unused
	.joystick_analog_0(),
	.joystick_analog_1(),
	.ps2_mouse_clk(),
	.ps2_mouse_data(),
	.sd_mounted()
);


///////////////////   CPU   ///////////////////
wire [15:0] addr;
wire  [7:0] cpu_din;
wire  [7:0] cpu_dout;
wire        nM1;
wire        nMREQ;
wire        nIORQ;
wire        nRD;
wire        nWR;
wire        nRFSH;
wire        nBUSACK;
wire        nINT   = ~(INT_line | INT_frame);
wire        nBUSRQ = ~(ioctl_download | ioctl_erasing);
wire        reset  = buttons[1] | status[0] | cold_reset | warm_reset;
wire        cold_reset = (mod[1] & Fn[11]) | init_reset;
wire        warm_reset =  mod[2] & Fn[11];

wire        cpu_wait = ((mem_contention & ~nMREQ & ~rom0_sel & ~rom1_sel) | (io_contention  & ~nIORQ & (~nRD | ~nWR))) & status[5];

T80pa cpu
(
	.RESET_n(~reset),
	.CLK(clk_sys),
	.CEN_p(ce_cpu_p),
	.CEN_n(ce_cpu_n),
	.WAIT_n(1),
	.INT_n(nINT),
	.NMI_n(1),
	.BUSRQ_n(nBUSRQ),
	.M1_n(nM1),
	.MREQ_n(nMREQ),
	.IORQ_n(nIORQ),
	.RD_n(nRD),
	.WR_n(nWR),
	.RFSH_n(nRFSH),
	.HALT_n(1),
	.BUSAK_n(nBUSACK),
	.A(addr),
	.DO(cpu_dout),
	.DI(cpu_din)
);

always_comb begin
	case({nMREQ, ~nM1 | nIORQ | nRD})
	    'b01: cpu_din = mem_dout;
	    'b10: cpu_din = asic_dout;
	 default: cpu_din = 8'hFF;
	endcase
end

reg init_reset = 1;
always @(posedge clk_sys) begin
	reg old_download;
	old_download <= ioctl_download;
	if(~ioctl_download & old_download & !ioctl_index) init_reset <= 0;
end


//////////////////   MEMORY   //////////////////
wire        dma = (reset | ~nBUSACK) & ~nBUSRQ;
reg  [24:0] ram_addr;
wire  [7:0] ram_din = dma ? ioctl_dout : cpu_dout;
wire        ram_we  = dma ? ioctl_wr   : ~(rom0_sel | rom1_sel | ram_wp) & ~nMREQ & ~nWR;
wire        ram_rd  = dma ? 1'b0       : (fdd_read | ~nMREQ) & ~nRD;

always_comb begin
	casex({dma, fdd_read, rom0_sel | rom1_sel, addr[15:14]})
		'b1XX_XX: ram_addr = ioctl_addr;
		'b01X_XX: ram_addr = {2'd2, fdd_addr};
		'b001_XX: ram_addr = {6'h20,addr[15], addr[13:0]};
		'b000_00: ram_addr = {page_ab,        addr[13:0]};
		'b000_01: ram_addr = {page_ab + 1'b1, addr[13:0]};
		'b000_10: ram_addr = {page_cd,        addr[13:0]};
		'b000_11: ram_addr = {page_cd + 1'b1, addr[13:0]};
	endcase
end

wire [7:0] ram_dout;
sram ram
(
	.*,
	.init(~locked),
	.clk(clk_sys),
	.addr(ram_addr),
	.dout(ram_dout),
	.din(ram_din),
	.we(ram_we),
	.rd(ram_rd),
	
	.d_cli(),
	.ready(),

	.vid_addr1(vram_addr1),
	.vid_addr2(vram_addr2),
	.vid_data1(vram_dout1),
	.vid_data2(vram_dout2),

	.misc_addr(0),
	.misc_data(),
	.misc_rd(0),
	.misc_ready()
);

wire [7:0] mem_dout = ext_ram ? 8'hFF : ram_dout;


////////////////////  ASIC PORTS  ///////////////////
reg  [7:0] brdr;
wire [3:0] border_color = {brdr[5], brdr[2:0]};
wire       ear_out = brdr[4];
wire       mic_out = brdr[3];

reg  [7:0] lmpr;
wire [4:0] page_ab  = lmpr[4:0];
wire       rom0_sel =~lmpr[5] & !addr[15:14];
wire       rom1_sel = lmpr[6] & &addr[15:14];
wire       ram_wp   = lmpr[7] & !addr[15:14];

reg  [7:0] hmpr;
wire [4:0] page_cd  = hmpr[4:0];
wire [1:0] mode3_hi = hmpr[6:5];
wire       ext_ram  = hmpr[7] &  addr[15];

wire       stat_sel = (addr[7:0] == 249);
wire       lmpr_sel = (addr[7:0] == 250);
wire       hmpr_sel = (addr[7:0] == 251);
wire       kbdr_sel = (addr[7:0] == 254);
wire       brdr_sel = (addr[7:0] == 254);
wire       fdd1_sel = (addr[7:0] >= 224) & (addr[7:0] <= 231);
//wire       fdd2_sel = (addr[7:0] >= 240) & (addr[7:0] <= 247);

wire       asic_we  = ~nIORQ & ~nWR & nM1;
always @(posedge clk_sys) begin
	reg old_we;
	
	if(reset) begin
		lmpr <= 0;
		hmpr <= 0;
		brdr <= 'b10000000; // mode 4 + screen off to hide garbage on startup.
	end else if(ce_6mn) begin
		old_we <= asic_we;
		if(asic_we & ~old_we) begin
			if(brdr_sel) brdr <= cpu_dout;
			if(lmpr_sel) lmpr <= cpu_dout;
			if(hmpr_sel) hmpr <= cpu_dout;
		end
	end
end

reg [7:0] asic_dout;
always_comb begin
	casex({kbdr_sel, stat_sel, lmpr_sel, hmpr_sel, vid_sel, fdd1_sel})
		'b1XXXXX: asic_dout = {soff, tape_in, 1'b0, key_data[4:0]};
		'b01XXXX: asic_dout = {key_data[7:5], 1'b1, ~INT_frame, 2'b11, ~INT_line};
		'b001XXX: asic_dout = lmpr;
		'b0001XX: asic_dout = hmpr;
		'b00001X: asic_dout = vid_dout;
		'b000001: asic_dout = fdd_dout;
		'b000000: asic_dout = 8'hFF;
	endcase
end


////////////////////   AUDIO   ///////////////////
wire [7:0] sound_data;
wire [7:0] psg_ch_l;
wire [7:0] psg_ch_r;
wire       tape_in = 0;

saa1099 psg
(
	.clk_sys(clk_sys),  
	.ce(ce_psg),
	.rst_n(~reset),
	.cs_n((addr[7:0] != 255) | nIORQ),
	.a0(addr[8]),
	.wr_n(nWR),
	.din(cpu_dout),
	.out_l(psg_ch_l),
	.out_r(psg_ch_r)
);

sigma_delta_dac #(8) dac_l
(
	.CLK(clk_sys),
	.RESET(reset),
	.DACin({1'b0, psg_ch_l} + {1'b0, ear_out, mic_out, tape_in, 5'b00000}),
	.DACout(AUDIO_L)
);

sigma_delta_dac #(8) dac_r
(
	.CLK(clk_sys),
	.RESET(reset),
	.DACin({1'b0, psg_ch_r} + {1'b0, ear_out, mic_out, tape_in, 5'b00000}),
	.DACout(AUDIO_R)
);


////////////////////   VIDEO   ///////////////////
wire [18:0] vram_addr1;
wire [18:0] vram_addr2;
wire        vram_rd1;
wire        vram_rd2;
wire [15:0] vram_dout1;
wire [15:0] vram_dout2;
wire  [7:0] vid_dout;
wire        vid_sel;
wire        soff = brdr[7] & mode34;
wire        mode34;
wire        INT_line;
wire        INT_frame;
wire        mem_contention;
wire        io_contention;
video video(.*, .din(cpu_dout), .dout(vid_dout), .dout_en(vid_sel));


//////////////////   KEYBOARD   //////////////////
wire [11:1] Fn;
wire  [2:0] mod;
wire  [7:0] key_data;
keyboard kbd( .* );


///////////////////   FDC   ///////////////////
wire [19:0] fdd_addr;
wire [19:0] fdd_size;
wire        fdd_rd;
reg         fdd_ready;
reg         fdd_side;
wire        fdd_sel  = fdd1_sel & ~nIORQ & nM1;
wire        fdd_read = fdd_rd & fdd_sel;
wire  [7:0] fdd_dout;

always @(posedge clk_sys) begin
	reg old_wr;
	reg old_download;
	reg old_m1;

	old_wr <= nWR;
	if(old_wr & ~nWR & fdd_sel) fdd_side <= addr[2];

	old_download <= ioctl_download;
	if(cold_reset) begin
		fdd_ready <= 0;
		fdd_size  <= 0;
	end else begin
		if(~ioctl_download & old_download & (ioctl_index == 1)) begin
			fdd_ready <= 1;
			fdd_size  <= ioctl_addr[19:0] + 1'b1;
		end
	end
end

wd1793 fdd
(
	.clk_sys(clk_sys),
	.ce(ce_cpu),
	.reset(reset),
	.io_en(fdd_sel),
	.rd(~nRD),
	.wr(~nWR),
	.addr(addr[1:0]),
	.din(cpu_dout),
	.dout(fdd_dout),
	
	.buff_size(fdd_size),
	.buff_addr(fdd_addr),
	.buff_read(fdd_rd),
	.buff_din(ram_dout),

	.size_code(4),
	.side(fdd_side),
	.ready(fdd_ready)
);


endmodule