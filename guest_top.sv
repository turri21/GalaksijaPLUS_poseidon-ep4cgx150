`default_nettype none

module guest_top
(
        input         CLOCK_27,
`ifdef USE_CLOCK_50
        input         CLOCK_50,
`endif

	output        LED,

	output [VGA_BITS-1:0] VGA_R,
	output [VGA_BITS-1:0] VGA_G,
	output [VGA_BITS-1:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,

`ifdef USE_HDMI
	output        HDMI_RST,
	output  [7:0] HDMI_R,
	output  [7:0] HDMI_G,
	output  [7:0] HDMI_B,
	output        HDMI_HS,
	output        HDMI_VS,
	output        HDMI_PCLK,
	output        HDMI_DE,
	inout         HDMI_SDA,
	inout         HDMI_SCL,
	input         HDMI_INT,
`endif

	input         SPI_SCK,
	inout         SPI_DO,
	input         SPI_DI,
	input         SPI_SS2,    // data_io
	input         SPI_SS3,    // OSD
	input         CONF_DATA0, // SPI_SS for user_io

`ifdef USE_QSPI
	input         QSCK,
	input         QCSn,
	inout   [3:0] QDAT,
`endif
`ifndef NO_DIRECT_UPLOAD
	input         SPI_SS4,
`endif

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
	output        SDRAM_CKE,

`ifdef DUAL_SDRAM
	output [12:0] SDRAM2_A,
	inout  [15:0] SDRAM2_DQ,
	output        SDRAM2_DQML,
	output        SDRAM2_DQMH,
	output        SDRAM2_nWE,
	output        SDRAM2_nCAS,
	output        SDRAM2_nRAS,
	output        SDRAM2_nCS,
	output  [1:0] SDRAM2_BA,
	output        SDRAM2_CLK,
	output        SDRAM2_CKE,
`endif

	output        AUDIO_L,
	output        AUDIO_R,
`ifdef I2S_AUDIO
	output        I2S_BCK,
	output        I2S_LRCK,
	output        I2S_DATA,
`endif
`ifdef I2S_AUDIO_HDMI
	output        HDMI_MCLK,
	output        HDMI_BCK,
	output        HDMI_LRCK,
	output        HDMI_SDATA,
`endif
`ifdef SPDIF_AUDIO
	output        SPDIF,
`endif
`ifdef USE_AUDIO_IN
	input         AUDIO_IN,
`endif
`ifdef USE_MIDI_PINS
	output        MIDI_OUT,
	input         MIDI_IN,
`endif
`ifdef SIDI128_EXPANSION
	input         UART_CTS,
	output        UART_RTS,
	inout         EXP7,
	inout         MOTOR_CTRL,
`endif
	input         UART_RX,
	output        UART_TX
);

`ifdef NO_DIRECT_UPLOAD
localparam bit DIRECT_UPLOAD = 0;
wire SPI_SS4 = 1;
`else
localparam bit DIRECT_UPLOAD = 1;
`endif

`ifdef USE_QSPI
localparam bit QSPI = 1;
assign QDAT = 4'hZ;
`else
localparam bit QSPI = 0;
`endif

`ifdef VGA_8BIT
localparam VGA_BITS = 8;
`else
localparam VGA_BITS = 6;
`endif

`ifdef USE_HDMI
localparam bit HDMI = 1;
assign HDMI_RST = 1'b1;
`else
localparam bit HDMI = 0;
`endif

`ifdef BIG_OSD
localparam bit BIG_OSD = 1;
`define SEP "-;",
`else
localparam bit BIG_OSD = 0;
`define SEP
`endif

`include "build_id.v"
localparam CONF_STR = {
	"Galaksija;;",
	"-;",
   "F,TAPGTP;",
	"-;",
	"O23,Screen Color,White,Green,Amber,Cyan;",
	"T5,Break;",
	"T9,Reset;",	
	"-;",	
	"T4,Type OLD before loading!;",
	"V,Poseidon-",`BUILD_DATE
};

assign LED = ~ioctl_download;

/* Keep the max volume reasonable */
//assign AUDIO_R = {audio, 5'b0};
//assign AUDIO_L = {audio, 5'b0};

wire CLK_VIDEO;
wire				clk_6p25, clk_3p125;
//wire 				clk_1p7, clk_25, clk_6p25, locked;
wire clk_25, clk_1p7, locked;

/* Clock */

pll pll 
(
    .areset(0),
	 .inclk0 ( CLOCK_50 ), 
	 .c0     ( clk_1p7  ), // Outputs 1.7 MHz
	 .c1     ( clk_25   ), // Outputs 25 MHz
	 .locked ( locked   )
);

assign clk_6p25 = div_clk[2];
assign clk_3p125 = div_clk[3];
assign CLK_VIDEO = clk_6p25;

reg [3:0] div_clk;

always @(posedge CLOCK_50) begin
	div_clk <= div_clk + 1'b1;
end

wire [7:0] video;
wire hs, vs;
wire blank;

wire ypbpr, no_csync;
wire scandoubler_disable;
wire [2:0] scanlines = status[7:6];

wire  [1:0] buttons;
wire  [1:0] switches;
wire	[31:0] status;
wire	[9:0]  audio;
wire [10:0] ps2_key = {key_strobe, key_pressed, key_extended, key_code};
wire ps2_kbd_clk,ps2_kbd_data;


wire        key_pressed;
wire [7:0]  key_code;
wire        key_strobe;
wire        key_extended;

wire ioctl_download, ioctl_wr;
wire [26:0] ioctl_addr;
wire [7:0] ioctl_dout;

galaksija_top galaksija_top (
   .cpuclk(clk_3p125),
	.vidclk(clk_25),
	.audclk(clk_1p7),
   .reset_in(~(status[0] | status[9] | buttons[1])),
   .ps2_key(ps2_key),
   .audio(audio),
	
   .video_dat(video),
   .video_hs(hs),
   .video_vs(vs),
   .video_blank(blank),
	
   .status(status),
   .ioctl_download(ioctl_download),
   .ioctl_wr(ioctl_wr),
   .ioctl_dout(ioctl_dout),
   .ioctl_addr(ioctl_addr)
);	

user_io #(.STRLEN($size(CONF_STR)>>3), .SD_IMAGES(1), .PS2DIV(500), .FEATURES(32'h0 | (BIG_OSD << 13) | (HDMI << 14))) user_io
(	
	.clk_sys        	(clk_25           ),
	.clk_sd           (clk_25           ),
	.conf_str       	(CONF_STR       	),
	.SPI_CLK        	(SPI_SCK        	),
	.SPI_SS_IO      	(CONF_DATA0     	),
	.SPI_MISO       	(SPI_DO        	),
	.SPI_MOSI       	(SPI_DI         	),
	.buttons        	(buttons        	),
	.switches       	(switches      	),
	.ypbpr          	(ypbpr          	),

	.ps2_kbd_clk      (ps2_kbd_clk      ),
	.ps2_kbd_data     (ps2_kbd_data     ),
	.key_strobe     	(key_strobe     	),
	.key_pressed    	(key_pressed    	),
	.key_extended   	(key_extended   	),
	.key_code       	(key_code       	),
//	.joystick_0       (joystick_0       ),
//	.joystick_1       (joystick_1       ),
	.status         	(status         	),
   .scandoubler_disable(1'b1),
`ifdef USE_HDMI
	.i2c_start        (i2c_start        ),
	.i2c_read         (i2c_read         ),
	.i2c_addr         (i2c_addr         ),
	.i2c_subaddr      (i2c_subaddr      ),
	.i2c_dout         (i2c_dout         ),
	.i2c_din          (i2c_din          ),
	.i2c_ack          (i2c_ack          ),
	.i2c_end          (i2c_end          ),
`endif
);	

data_io data_io(
	.clk_sys          (clk_6p25         ),
	.SPI_SCK          (SPI_SCK          ),
	.SPI_SS2          (SPI_SS2          ),
`ifdef NO_DIRECT_UPLOAD
   .SPI_SS4          (SPI_SS4          ),
`endif
	.SPI_DI           (SPI_DI           ),
	.SPI_DO           (SPI_DO           ),
	.clkref_n         (1'b0             ),
	.ioctl_download   (ioctl_download   ),
//	.ioctl_index      (ioctl_index      ),
	.ioctl_wr         (ioctl_wr         ),
	.ioctl_addr       (ioctl_addr       ),
	.ioctl_dout       (ioctl_dout       )
);


wire [5:0] r_out, g_out, b_out;  // 6-bit color channels

assign {r_out, g_out, b_out} = get_color(video);

function [17:0] get_color;  // Returns 18 bits total (6 bits per channel)
   input [5:0] pixel;       // Now takes 6-bit input
begin
   case(status[3:2])
      // White (24'hFFFFFF -> 6'h3F,6'h3F,6'h3F)
      2'b00: get_color = pixel ? {6'h3F, 6'h3F, 6'h3F} : 18'b0;
      
      // Green (24'h33FF33 -> 6'h0D,6'h3F,6'h0D)
      2'b01: get_color = pixel ? {6'h0D, 6'h3F, 6'h0D} : 18'b0;
      
      // Amber (24'hFFCC00 -> 6'h3F,6'h33,6'h00)
      2'b10: get_color = pixel ? {6'h3F, 6'h33, 6'h00} : 18'b0;
      
      // Cyan (24'h40FFA6 -> 6'h10,6'h3F,6'h29)
      2'b11: get_color = pixel ? {6'h10, 6'h3F, 6'h29} : 18'b0;
   endcase
end
endfunction

mist_video #(.COLOR_DEPTH(6), .SD_HCNT_WIDTH(10), .OUT_COLOR_DEPTH(VGA_BITS), .BIG_OSD(BIG_OSD)) mist_video
(
	.clk_sys      (clk_25     ),
	.SPI_SCK      (SPI_SCK    ),
	.SPI_SS3      (SPI_SS3    ),
	.SPI_DI       (SPI_DI     ),
   .R   (blank ? 0 : r_out   ),  // Transformed colors
   .G   (blank ? 0 : g_out   ),
   .B   (blank ? 0 : b_out   ),
	.HSync        (hs         ),
	.VSync        (vs         ),
	.VGA_R        (VGA_R      ),
	.VGA_G        (VGA_G      ),
	.VGA_B        (VGA_B      ),
	.VGA_VS       (VGA_VS     ),
	.VGA_HS       (VGA_HS     ),
	.ce_divider   (3'b0       ),
	.ypbpr        (ypbpr      ),
	.scandoubler_disable ( 1'b1 ),
   .scanlines   (scanlines     ),
	.rotate       ( 2'b00     ),
	.blend        ( 1'b0      )
);

`ifdef I2S_AUDIO
wire [31:0] clk_rate =  32'd01_700_000;

i2s i2s (
	.reset(0),
	.clk(clk_1p7),
	.clk_rate(clk_rate),

	.sclk(I2S_BCK),
	.lrclk(I2S_LRCK),
	.sdata(I2S_DATA),

	.left_chan({1'b0, audio[9:0], 5'd0}),
	.right_chan({1'b0, audio[9:0], 5'd0})
);

`ifdef I2S_AUDIO_HDMI
assign HDMI_MCLK = 0;
always @(posedge clk_sys) begin
	HDMI_BCK <= I2S_BCK;
	HDMI_LRCK <= I2S_LRCK;
	HDMI_SDATA <= I2S_DATA;
end
`endif
`endif


endmodule
