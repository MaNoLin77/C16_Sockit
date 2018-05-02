//============================================================================
//  C16
//
//  Port to MiSTer
//  Copyright (C) 2017,2018 Sorgelig
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
//============================================================================

module emu
(
	//Master input clock
	input         CLK_50M,

	//Async reset from top-level module.
	//Can be used as initial reset.
	input         RESET,

	//Must be passed to hps_io module
	inout  [44:0] HPS_BUS,

	//Base video clock. Usually equals to CLK_SYS.
	output        CLK_VIDEO,

	//Multiple resolutions are supported using different CE_PIXEL rates.
	//Must be based on CLK_VIDEO
	output        CE_PIXEL,

	//Video aspect ratio for HDMI. Most retro systems have ratio 4:3.
	output  [7:0] VIDEO_ARX,
	output  [7:0] VIDEO_ARY,

	output  [7:0] VGA_R,
	output  [7:0] VGA_G,
	output  [7:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,
	output        VGA_DE,    // = ~(VBlank | HBlank)

	output        LED_USER,  // 1 - ON, 0 - OFF.

	// b[1]: 0 - LED status is system status OR'd with b[0]
	//       1 - LED status is controled solely by b[0]
	// hint: supply 2'b00 to let the system control the LED.
	output  [1:0] LED_POWER,
	output  [1:0] LED_DISK,

	output [15:0] AUDIO_L,
	output [15:0] AUDIO_R,
	output        AUDIO_S,   // 1 - signed audio samples, 0 - unsigned
	output  [1:0] AUDIO_MIX, // 0 - no mix, 1 - 25%, 2 - 50%, 3 - 100% (mono)
	input         TAPE_IN,

	// SD-SPI
	output        SD_SCK,
	output        SD_MOSI,
	input         SD_MISO,
	output        SD_CS,
	input         SD_CD,

	//High latency DDR3 RAM interface
	//Use for non-critical time purposes
	output        DDRAM_CLK,
	input         DDRAM_BUSY,
	output  [7:0] DDRAM_BURSTCNT,
	output [28:0] DDRAM_ADDR,
	input  [63:0] DDRAM_DOUT,
	input         DDRAM_DOUT_READY,
	output        DDRAM_RD,
	output [63:0] DDRAM_DIN,
	output  [7:0] DDRAM_BE,
	output        DDRAM_WE,

	//SDRAM interface with lower latency
	output        SDRAM_CLK,
	output        SDRAM_CKE,
	output [12:0] SDRAM_A,
	output  [1:0] SDRAM_BA,
	inout  [15:0] SDRAM_DQ,
	output        SDRAM_DQML,
	output        SDRAM_DQMH,
	output        SDRAM_nCS,
	output        SDRAM_nCAS,
	output        SDRAM_nRAS,
	output        SDRAM_nWE
);

assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
assign {SDRAM_DQ, SDRAM_A, SDRAM_BA, SDRAM_CLK, SDRAM_CKE, SDRAM_DQML, SDRAM_DQMH, SDRAM_nWE, SDRAM_nCAS, SDRAM_nRAS, SDRAM_nCS} = 'Z;
assign {DDRAM_CLK, DDRAM_BURSTCNT, DDRAM_ADDR, DDRAM_DIN, DDRAM_BE, DDRAM_RD, DDRAM_WE} = 0;
 
assign LED_USER  = ioctl_download | led_disk;
assign LED_DISK  = 0;
assign LED_POWER = 0;

assign VIDEO_ARX = status[1] ? 8'd16 : 8'd4;
assign VIDEO_ARY = status[1] ? 8'd9  : 8'd3; 

wire [1:0] scale = status[3:2];

`include "build_id.v" 
parameter CONF_STR = {
	"C16;;",
	"-;",
	"F,PRG;",
	"F,BIN,Load Cart(Plus/4);",
	"-;",
	"S,D64;",
	"-;",
	"O1,Aspect ratio,4:3,16:9;",
	"O23,Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%;",
	"-;",
	"O5,Joysticks swap,No,Yes;",
	"-;",
	"O4,Model,C16,Plus/4;",
	"-;",
	"R0,Reset;",
	"J,Fire;",
	"V,v1.00.",`BUILD_DATE
};

/////////////////  CLOCKS  ////////////////////////

wire clk_sys, clk_c16;

pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_sys),
	.outclk_1(clk_c16),
	.outclk_2(CLK_VIDEO)
);


/////////////////  HPS  ///////////////////////////

wire [31:0] status;
wire  [1:0] buttons;

wire [15:0] joya, joyb;
wire [10:0] ps2_key;

wire        ioctl_download;
wire  [7:0] ioctl_index;
wire        ioctl_wr;
wire [24:0] ioctl_addr;
wire  [7:0] ioctl_dout;
wire        forced_scandoubler;

wire [31:0] sd_lba;
wire        sd_rd;
wire        sd_wr;
wire        sd_ack;
wire  [8:0] sd_buff_addr;
wire  [7:0] sd_buff_dout;
wire  [7:0] sd_buff_din;
wire        sd_buff_wr;
wire        img_mounted;
wire        img_readonly;

hps_io #(.STRLEN($size(CONF_STR)>>3)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),

	.conf_str(CONF_STR),

	.buttons(buttons),
	.status(status),
	.forced_scandoubler(forced_scandoubler),

	.ps2_key(ps2_key),

	.ioctl_download(ioctl_download),
	.ioctl_index(ioctl_index),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),

	.sd_lba(sd_lba),
	.sd_rd(sd_rd),
	.sd_wr(sd_wr),
	.sd_ack(sd_ack),
	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din(sd_buff_din),
	.sd_buff_wr(sd_buff_wr),
	.img_mounted(img_mounted),
	.img_readonly(img_readonly),

	.joystick_0(joya),
	.joystick_1(joyb)
);

/////////////////  RESET  /////////////////////////

wire sys_reset = RESET | status[0] | buttons[1];
wire reset = sys_reset | ext_reset | cart_reset;

/////////////////   RAM   /////////////////////////

reg [15:0] dl_addr;
reg  [7:0] dl_data;
reg        dl_wr;
reg        model;
reg        ext_reset;

always @(posedge clk_sys) begin
	reg        old_download = 0;
	reg  [3:0] state = 0;
	reg [15:0] addr;
	reg        st=0;

	if(reset) model <= status[4];

	dl_wr <= 0;
	old_download <= ioctl_download;

	if(ioctl_download && (ioctl_index == 1)) begin
		state <= 0;
		if(ioctl_wr) begin
			     if(ioctl_addr == 0) addr[7:0]  <= ioctl_dout;
			else if(ioctl_addr == 1) addr[15:8] <= ioctl_dout;
			else begin
				dl_addr <= addr;
				dl_data <= ioctl_dout;
				dl_wr   <= 1;
				addr    <= addr + 1'd1;
			end
		end
	end

	if(old_download && ~ioctl_download && (ioctl_index == 1)) state <= 1;
	if(state) state <= state + 1'd1;

	case(state)
		 1: begin dl_addr <= 16'h2d; dl_data <= addr[7:0];  dl_wr <= 1; end
		 3: begin dl_addr <= 16'h2e; dl_data <= addr[15:8]; dl_wr <= 1; end
		 5: begin dl_addr <= 16'h2f; dl_data <= addr[7:0];  dl_wr <= 1; end
		 7: begin dl_addr <= 16'h30; dl_data <= addr[15:8]; dl_wr <= 1; end
		 9: begin dl_addr <= 16'h31; dl_data <= addr[7:0];  dl_wr <= 1; end
		11: begin dl_addr <= 16'h32; dl_data <= addr[15:8]; dl_wr <= 1; end
		13: begin dl_addr <= 16'hae; dl_data <= addr[7:0];  dl_wr <= 1; end
		15: begin dl_addr <= 16'haf; dl_data <= addr[15:8]; dl_wr <= 1; end
	endcase

	if(sys_reset) {st, ext_reset} <= 2'b11;

	if(ext_reset & ~sys_reset) begin
		dl_data <= 0;
		st <= 0;

		if(st) begin
			dl_addr <= 0;
			dl_wr <= 1;
		end
		else if(&dl_addr) begin
			ext_reset <= 0;
		end
		else if (~dl_wr) begin
			dl_addr <= dl_addr + 1'd1;
			dl_wr <= 1;
		end
	end
end

wire [7:0] ram_dout;
gen_dpram #(16) main_ram
(
	.clock_a(clk_sys),
	.address_a(dl_addr),
	.data_a(dl_data),
	.wren_a(dl_wr),

	.clock_b(clk_c16),
	.address_b(c16_addr),
	.data_b(c16_dout),
	.wren_b(ram_we),
	.q_b(ram_dout),
	.cs_b(~cs_ram)
);

reg ram_we;
always @(posedge clk_c16) begin
	reg old_cs;
	ram_we <= 0;
	
	old_cs <= cs_ram;
	if(old_cs & ~cs_ram) ram_we <= ~c16_rnw;
end

/////////////////   ROM   /////////////////////////

// Kernal rom
wire [7:0] kernal_dout;
gen_rom #("roms/c16_kernal.mif") kernal
(
	.wrclock(clk_sys),
	.wraddress(ioctl_addr[13:0]),
	.data(ioctl_dout),
	.wren(ioctl_wr && (ioctl_addr[24:14]==1) && !ioctl_index),

	.rdclock(clk_c16),
	.rdaddress(c16_addr[13:0]),
	.q(kernal_dout),
	.cs(~cs1 && (!romh || kern))
);

// Basic rom
wire [7:0] basic_dout;
gen_rom #("roms/c16_basic.mif") basic
(
	.wrclock(clk_sys),
	.wraddress(ioctl_addr[13:0]),
	.data(ioctl_dout),
	.wren(ioctl_wr && (ioctl_addr[24:14]==2) && !ioctl_index),

	.rdclock(clk_c16),
	.rdaddress(c16_addr[13:0]),
	.q(basic_dout),
	.cs(~cs0 && !roml)
);

// Func low
wire [7:0] fl_dout;
gen_rom #("roms/3-plus-1_low.mif") funcl
(
	.wrclock(clk_sys),
	.wraddress(ioctl_addr[13:0]),
	.data(ioctl_dout),
	.wren(ioctl_wr && (ioctl_addr[24:14]==3) && !ioctl_index),

	.rdclock(clk_c16),
	.rdaddress(c16_addr[13:0]),
	.q(fl_dout),
	.cs(~cs0 && roml==2)
);

// Func high
wire [7:0] fh_dout;
gen_rom #("roms/3-plus-1_high.mif") funch
(
	.wrclock(clk_sys),
	.wraddress(ioctl_addr[13:0]),
	.data(ioctl_dout),
	.wren(ioctl_wr && (ioctl_addr[24:14]==4) && !ioctl_index),

	.rdclock(clk_c16),
	.rdaddress(c16_addr[13:0]),
	.q(fh_dout),
	.cs(~cs1 && romh==2 && ~kern)
);

// Cart low
wire [7:0] cartl_dout;
gen_rom cart_l
(
	.wrclock(clk_sys),
	.wraddress(ioctl_addr[13:0]),
	.data(ioctl_dout),
	.wren(ioctl_wr && (ioctl_addr[24:14]==0) && (ioctl_index==2)),

	.rdclock(clk_c16),
	.rdaddress(c16_addr[13:0]),
	.q(cartl_dout),
	.cs(~cs0 && cartl && roml==1)
);

// Cart high
wire [7:0] carth_dout;
gen_rom cart_h
(
	.wrclock(clk_sys),
	.wraddress(ioctl_addr[13:0]),
	.data(ioctl_dout),
	.wren(ioctl_wr && (ioctl_addr[24:14]==1) && (ioctl_index==2)),

	.rdclock(clk_c16),
	.rdaddress(c16_addr[13:0]),
	.q(carth_dout),
	.cs(~cs1 && carth && romh==1 && ~kern)
);

wire cart_reset = model & ioctl_download & (ioctl_index==2);
reg cartl,carth;
always @(posedge clk_sys) begin
	if(sys_reset) {cartl,carth} <= 0;
	if(ioctl_wr && (ioctl_addr[24:14]==0) && (ioctl_index==2)) cartl <= 1;
	if(ioctl_wr && (ioctl_addr[24:14]==1) && (ioctl_index==2)) carth <= 1;
end

wire kern = (c16_addr[15:8]==8'hFC);

reg [1:0] roml, romh;
always @(posedge clk_c16) begin
	reg old_cs;

	old_cs <= cs_io;

	if(reset) {romh,roml} <= 0;
	else if(model && old_cs && ~cs_io && ~c16_rnw && c16_addr[15:4] == 12'hFDD) {romh,roml} <= c16_addr[3:0];
end

///////////////////////////////////////////////////

wire  [7:0] c16_dout;
wire [15:0] c16_addr;
wire        c16_rnw;

wire  [7:0] c16_din = ram_dout&kernal_dout&basic_dout&fh_dout&fl_dout&cartl_dout&carth_dout;

wire        cs_ram,cs0,cs1,cs_io;
C16 c16
(
	.CLK28   ( clk_c16 ), // NTSC 28.636299, PAL 28.384615. Use NTSC clock as PAL is not much different.
	.RESET   ( reset ),
	.WAIT    ( 0 ),

	.CE_PIX  ( ce_pix ),
	.HSYNC   ( hs ),
	.VSYNC   ( vs ),
	.HBLANK  ( hblank ),
	.VBLANK  ( vblank ),
	.RED     ( r ),
	.GREEN   ( g ),
	.BLUE    ( b ),

	.RnW     ( c16_rnw ),
	.ADDR    ( c16_addr ),
	.DOUT    ( c16_dout ),
	.DIN     ( c16_din ),
	.CS_RAM  ( cs_ram ),
	.CS0     ( cs0 ),
	.CS1     ( cs1 ),
	.CS_IO   ( cs_io ),

	.JOY0    ( status[5] ? joyb[4:0] : joya[4:0] ),
	.JOY1    ( status[5] ? joya[4:0] : joyb[4:0] ),

	.ps2_key ( ps2_key ),

	.IEC_DATAOUT ( c16_iec_data_o ),
	.IEC_DATAIN  ( !c16_iec_data_i ),
	.IEC_CLKOUT  ( c16_iec_clk_o ),
	.IEC_CLKIN   ( !c16_iec_clk_i ),
	.IEC_ATNOUT  ( c16_iec_atn_o ),
	.IEC_RESET   ( iec_reset ),

	.sound   ( audio )
);

wire [4:0] audio;

assign AUDIO_L = {audio, audio, audio, 1'b0};
assign AUDIO_R = AUDIO_L;
assign AUDIO_MIX = 0;
assign AUDIO_S = 0;

wire hs, vs, hblank, vblank, ce_pix;
wire [3:0] r,g,b;

reg ce_vid;
always @(posedge CLK_VIDEO) begin
	reg old_ce;
	
	old_ce <= ce_pix;
	ce_vid <= ~old_ce & ce_pix;
end

video_mixer #(456, 1) mixer
(
	.clk_sys(CLK_VIDEO),
	
	.ce_pix(ce_vid),
	.ce_pix_out(CE_PIXEL),

	.hq2x(scale == 1),
	.scanlines({scale==3, scale==2}),
	.scandoubler(scale || forced_scandoubler),

	.R(r),
	.G(g),
	.B(b),

	.mono(0),

	.HSync(~hs),
	.VSync(~vs),
	.HBlank(hblank),
	.VBlank(vblank),

	.VGA_R(VGA_R),
	.VGA_G(VGA_G),
	.VGA_B(VGA_B),
	.VGA_VS(VGA_VS),
	.VGA_HS(VGA_HS),
	.VGA_DE(VGA_DE)
);

///////////////////////////////////////////////////

wire led_disk;
wire iec_reset;

wire c1541_iec_atn_o;
wire c1541_iec_data_o;
wire c1541_iec_clk_o;

wire c16_iec_atn_o;
wire c16_iec_data_o;
wire c16_iec_clk_o;

wire c16_iec_atn_i  = c16_iec_atn_o  | c1541_iec_atn_o;
wire c16_iec_data_i = c16_iec_data_o | c1541_iec_data_o;
wire c16_iec_clk_i  = c16_iec_clk_o  | c1541_iec_clk_o;


reg c1541_reset;
always @(posedge clk_sys) begin
	reg rst;
	rst <= iec_reset;
	c1541_reset <= rst;
end

c1541_sd c1541_sd
(
	.clk32 (clk_sys),
	.reset (c1541_reset),

	.c1541rom_clk(clk_sys),
	.c1541rom_addr(ioctl_addr[13:0]),
	.c1541rom_data(ioctl_dout),
	.c1541rom_wr(ioctl_wr && (ioctl_addr[24:14] == 0) && !ioctl_index),

   .disk_change ( img_mounted ),
	.disk_readonly ( img_readonly ),

	.iec_atn_i  ( c16_iec_atn_i ),
	.iec_data_i ( c16_iec_data_i ),
	.iec_clk_i  ( c16_iec_clk_i ),

	.iec_atn_o  ( c1541_iec_atn_o  ),
	.iec_data_o ( c1541_iec_data_o ),
	.iec_clk_o  ( c1541_iec_clk_o  ),

   .led (led_disk),

	.sd_lba(sd_lba),
	.sd_rd(sd_rd),
	.sd_wr(sd_wr),
	.sd_ack(sd_ack),

	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din(sd_buff_din),
	.sd_buff_wr(sd_buff_wr)
);

endmodule
