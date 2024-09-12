module galaksija_top(
    input vidclk,
	 input cpuclk,
	 input audclk,
    input reset_in,
	 input [7:0] key_code,
	 input key_strobe,
	 input key_pressed,
	 input key_extended,
    input ps2_clk,
    input ps2_data,
	 output [7:0] audio,
	 input  cass_in,
    output cass_out,
    output [7:0] video_dat,
    output video_hs,
    output video_vs,
	 output video_blank,
	 input [31:0] status,	 
    input ioctl_download,
    input ioctl_wr,
    input [26:0] ioctl_addr,
    input [7:0] ioctl_dout 
);


reg  [6:0] 	reset_cnt = 0;
wire 			cpu_resetn = reset_cnt[6];
reg [31:0] 	int_cnt = 0;
reg [31:0] 	clock_correct = 0;

always @(posedge vidclk) begin
	if(reset_in == 0) 
		reset_cnt <= 0;
	else if(cpu_resetn == 0) 
		reset_cnt <= reset_cnt + 1;
	if (int_cnt==(25000000 / (50 * 2)))
		begin
			int_n <= 1'b0;		
			int_cnt <= 0;
		end
		else begin
			int_n <= 1'b1;		
			int_cnt <= int_cnt + 1;
		end
end

wire m1_n;
wire iorq_n;
wire rd_n;
wire wr_n;
wire rfsh_n;
wire halt_n;
wire busak_n;
reg int_n = 1'b1;
wire nmi_n;
wire busrq_n = 1'b1;
wire mreq_n;
wire [15:0] addr;
wire [7:0] odata;
reg [7:0] idata;
	
T80s #(
	.Mode(0),
	.T2Write(0),
	.IOWait(1))
cpu(
	.RESET_n(cpu_resetn), 
	.CLK(~cpuclk),
	.WAIT_n(1'b1),
	.INT_n(int_n),
	.NMI_n(nmi_n),
	.BUSRQ_n(busrq_n),
	.M1_n(m1_n),
	.MREQ_n(mreq_n),
	.IORQ_n(iorq_n),
	.RD_n(rd_n),
	.WR_n(wr_n),
	.RFSH_n(rfsh_n),
	.HALT_n(halt_n),
	.BUSAK_n(busak_n),
	.A(addr),
	.DI(idata),
	.DO(odata)
	);	
	
wire [7:0] 	rom1_out;
reg 			rd_rom1;
	
sprom #(//4k
	.init_file("./roms/ROM1.hex"),
	.widthad_a(12),
	.width_a(8))
rom1(
	.address(addr[11:0]),
	.clock(cpuclk & rd_rom1),
	.q(rom1_out)
	);
	
wire [7:0] 	rom2_out;
reg 			rd_rom2;
	
sprom #(//4k
	.init_file("./roms/ROM2.hex"),
	.widthad_a(12),
	.width_a(8))
rom2(
	.address(addr[11:0]),
	.clock(cpuclk & rd_rom2),
	.q(rom2_out)
	);
	

wire [7:0] 	rom3_out;
reg 			rd_rom3;
	
sprom #(//4k
	.init_file("./roms/galplus.hex"),
	.widthad_a(12),
	.width_a(8))
rom3(
	.address(addr[11:0]),
	.clock(cpuclk & rd_rom3),
	.q(rom3_out)
	);
	
wire [7:0] 	rom4_out;
reg 			rd_rom4;
	
sprom #(
    .init_file("./roms/ROM4.hex"), 
    .widthad_a(12),  // 2^12 = 4096 bytes = 4 KB (covering entire $F000 to $FFFF range)
    .width_a(8)      // Data width 8 bits
)
rom4 (
    .address(addr[11:0]),  
    .clock(cpuclk & rd_rom4),
    .q(rom4_out)
);

reg 			rd_mram0, wr_mram0;	
wire 			cs_mram0 = ~addr[15] & ~addr[14];
wire 			we_mram0 = wr_mram0 & cs_mram0;
wire [7:0] 	mram0_out;

spram #(
	.widthad_a(16),   // Updated to 16 bits to address 45KB
	.width_a(8)       // Data width 8 bits
)
ram00(
	.address(addr[15:0]), // Updated to 16 bits
	.clock(cpuclk),
	.wren(wr_mram0),
	.data(odata),
	.q(mram0_out)
);

reg rd_vram;
reg wr_vram;
wire [7:0] vram_out;

galaksija_video#(
	.h_visible(10'd640),
	.h_front(10'd16),
	.h_sync(10'd96),
	.h_back(10'd48),
	.v_visible(10'd480),
	.v_front(10'd10),
	.v_sync(10'd2),
	.v_back(10'd33))
galaksija_video(
	.clk(vidclk),
	.resetn(reset_in),
	.vga_dat(video_dat),
	.vga_hsync(video_hs),
	.vga_vsync(video_vs),
	.vga_blank(video_blank),
	.rd_ram1(rd_vram),
	.wr_ram1(wr_vram),
	.ram1_out(vram_out),
	.addr(addr[10:0]),
	.data(odata),
	
	// Tape progress bar
	.addr_max(addr_max),
	.read_counter(read_counter[19:6]),
	.download_active(reading_tape)
	);
	
	reg [7:0] g_latch = 8'b10111100;

	always @(*)
	begin
	   idata = 8'hff;
		rd_rom1 = 1'b0;		
		rd_rom2 = 1'b0;
		rd_rom3 = 1'b0;
		rd_rom4 = 1'b0;
		rd_vram = 1'b0;
		rd_mram0 = 1'b0;
		wr_vram = 1'b0;
		wr_mram0 = 1'b0;
		rd_key = 1'b0;

		
		
		casex ({~wr_n,~rd_n,mreq_n,addr[15:0]})
			//$0000...$0FFF — ROM "A" or "1" – 4 KB contains bootstrap, core control and Galaksija BASIC interpreter code
			{3'b010,16'b0000xxxxxxxxxxxx}: begin idata = rom1_out; rd_rom1 = 1'b1; end
			
			//$1000...$1FFF — ROM "B" or "2" – 4 KB (optional) – additional Galaksija BASIC commands, assembler, machine code monitor, etc.
			{3'b010,16'b0001xxxxxxxxxxxx}: begin idata = rom2_out; rd_rom2 = 1'b1; end
			
			//$2000... Tape
			{3'b010,16'b0010000000000000}: begin idata = 8'hff & tape_bit_out; end
			
			//$2000...$27FF — keyboard and latch			
			{3'b010,16'b00100xxxxxxxxxxx}: begin idata = 8'hff & key_out; rd_key = 1'b1; end
			{3'b100,16'b00100xxxxx111xxx}: g_latch = odata;				
			
			// Address range: $2800 to $2BFF - Video RAM
			{3'b010, 16'b001010xxxxxxxxxx}: begin idata = vram_out; rd_vram = 1'b1; end
			{3'b100, 16'b001010xxxxxxxxxx}: wr_vram = 1'b1;

			//$2C00...$DFFF - RAM 
			{3'b010, 16'b001xxxxxxxxxxxxx}: begin idata = mram0_out; rd_mram0 = 1'b1; end
			{3'b100, 16'b001xxxxxxxxxxxxx}: wr_mram0 = 1'b1;

			
			// $C600...$DFFF — High res Video RAM
         //{3'b010,16'b110xxxxxxxxxxxxx}: begin idata = vram_out2; rd_vram2 =1'b1; end
         //{3'b100,16'b110xxxxxxxxxxxxx}: wr_vram2=1'b1;
			
			//$E000...$FFFF — ROM "3" + "4" IC13: 8 KB – Graphic primitives in BASIC language, Full Screen Source Editor and soft scrolling
			{3'b010,16'b1110xxxxxxxxxxxx}: begin idata = rom3_out; rd_rom3 = 1'b1; end
			       
			//$F000...$FFFF   ROM D/M aka ROM4 
			//ROMC initialization excludes ROMD, so instead of USR(&E000) you should type USR(&F000) with the same effect!       
			{3'b010,16'b1111xxxxxxxxxxxx}: begin idata = rom4_out; rd_rom4 = 1'b1; end
	
			default : idata = 8'hff;
		endcase
	end

wire key_out;
wire rd_key;
wire [10:0] ps2_key; // Internal signal for PS/2 key


// Instantiate the key_to_ps2_converter module
key_to_ps2_converter key_converter (
    .clk(vidclk),
    .key_code(key_code),
    .key_pressed(key_pressed),
    .key_strobe(key_strobe),
    .ps2_key(ps2_key)
);


galaksija_keyboard galaksija_keyboard(
	.clk(vidclk),
	.addr(addr[5:0]),
	.reset(~reset_in),
	.ps2_key(ps2_key),
	.key_out(key_out)
);
//////////////////////////////////////////////////////////////////////
// Tape interface
//////////////////////////////////////////////////////////////////////

wire [7:0] tape_buf_out;
	
reg [19:0] read_counter = 0;
reg [15:0] delay_counter = 0;

reg [13:0] addr_max = 0;

galaksija_tape_buf_ram tape_buf_ram(
   .address_a(ioctl_addr[13:0]),
   .clock_a(vidclk),
   .data_a(ioctl_dout),
   .wren_a(ioctl_wr && ioctl_download),
   
   .clock_b(cpuclk),
   .address_b(read_counter[19:6]),
   .wren_b(0),
   .data_b(0),
   .q_b(tape_buf_out)
);	


assign audio = reading_tape ? {tape_bit_out, 7'b0} : 1'b0;


wire tape_bit_out = |read_counter[1:0] | (read_counter[2] > tape_buf_out[read_counter[5:3]]);
reg reading_tape = 0;
reg old_ioctl_download;

always @(posedge cpuclk) begin
	old_ioctl_download <= ioctl_download;
	
	if (ioctl_download & ioctl_wr)
		addr_max <= ioctl_addr;
				
	if (old_ioctl_download & ~ioctl_download) begin		
		reading_tape <= 1'b1;
		read_counter <= 20'h0;
	end	
	else if (read_counter[19:6] > addr_max)
		reading_tape <= 1'b0;
		
	if (clock_correct < 3072000 & reading_tape) begin
		delay_counter <= delay_counter > (read_counter[5:0] == 6'b111111 ? 16'd13000 : 16'd1150) ? 16'd0 : delay_counter + 1'b1;				
	   
		if(delay_counter == 0)
			read_counter <= read_counter + 1'b1;									
	end	
end 

wire PIN_A = (1'b1 & 1'b1 & wr_n);
wire [7:0]chan_A, chan_B, chan_C;
wire A02 = ~(C00 | PIN_A);
wire B02 = ~(C00 | addr[0]);
wire D02 = ~(addr[6] | iorq_n);
wire C00 = ~(D02 & m1_n);
//assign audio = chan_A & chan_B & chan_C;

AY8912 AY8912(
   .CLK(vidclk),
	.CE(audclk),
   .RESET(~reset_in),
   .BDIR(A02),
   .BC(B02),
   .DI(odata),
   .DO(),//not used
   .CHANNEL_A(chan_A),
   .CHANNEL_B(chan_B),
   .CHANNEL_C(chan_C),
   .SEL(1'b1),//
	.IO_in(),//not used
	.IO_out()//not used
	);

endmodule
