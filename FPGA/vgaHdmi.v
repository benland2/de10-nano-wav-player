 /**
Description
Module qui synchronise les signaux (hsync et vsync)
d'un contrôleur VGA 640x480 60hz, fonctionne avec une horloge de 25Mhz

Il dispose également des coordonnées des pixels H (axe x)
et des pixels V (axe y). Pour envoyer le signal RVB correspondant
à chaque pixel

------------------------------------------------------------------------------------
vgaHdmi.v
------------------------------------------------------------------------------------
*/

module vgaHdmi(
	// ** input **
	input clock, clock50, reset,
	
	// ** output **
	output reg hsync, vsync,
	output reg dataEnable,
	output vgaClock,//type wire
	output [23:0] RGBchannel,
	
	input [9:0] instructionNum,
	input [9:0] instructionAddr,
	input [7:0] instructionData,
	output reg [9:0] instructionPrev
);

reg [10:0] pixelH, pixelV; // état interne des pixels du module
reg [9:0]	pixel_x, pixel_y;// pixel pour la position sur la partie visible

reg [23:0] r_pixel;
wire [2:0] text_pixel;

reg h_act, v_act;

wire h_max, hs_end, hr_start,hr_end;
wire v_max, vs_end, vr_start,vr_end;

//Gestion des décalages
reg pre1_vga_de, pre2_vga_de, pre3_vga_de, pre4_vga_de;

reg [12:0] frame_waddr;
reg [7:0] frame_wdata;
reg frame_wren;

//reg frameInstruction;

// Videos Modeline
/*parameter h_display = 1024;
parameter h_front_porch = 40;
parameter h_sync = 104;
parameter h_back_porch = 144;
parameter h_total = 1312;

parameter v_display = 600;
parameter v_front_porch = 3;
parameter v_sync = 10;
parameter v_back_porch = 11;
parameter v_total = 624;*/

parameter h_display = 640;
parameter h_front_porch = 16;
parameter h_sync = 96;
parameter h_back_porch = 48;
parameter h_total = 800;

parameter v_display = 480;
parameter v_front_porch = 10;
parameter v_sync = 2;
parameter v_back_porch = 33;
parameter v_total = 525;

initial begin
	hsync = 1;
	vsync = 1;
	pixelH = 0;
	pixelV = 0;
	dataEnable = 0;
	pre1_vga_de = 0;
	pre2_vga_de = 0;
	pre3_vga_de = 0;
	pre4_vga_de = 0;
	
	//pour gérer l'écriture dans la la frame
	frame_waddr = 0;
	frame_wdata = 0;
	frame_wren = 0;
	instructionPrev = 0;
end


// Génération des signaux de synchronisations (logique négative)
assign h_max = pixelH == (h_total - 1);
assign hs_end = pixelH >= (h_sync - 1);
assign hr_start = pixelH == (h_sync + h_back_porch - 3);// - 1 - 2(delqy)
assign hr_end = pixelH == (h_sync + h_back_porch - 3 + h_display);

assign v_max = pixelV == (v_total - 1);
assign vs_end = pixelV >= (v_sync - 1);
assign vr_start = pixelV == (v_sync + v_back_porch - 1);
assign vr_end = pixelV == (v_sync + v_back_porch - 1 + v_display);

always @(posedge clock or posedge reset) begin
	if(reset) begin
		hsync <= 1;
		vsync <= 1;
		pixelH <= 0;
		pixelV <= 0;
	end
	else begin
		// Gestion du signal Horizontal		
		if(h_max)
			pixelH <= 11'b0;
		else
			pixelH <= pixelH + 11'b1;
			
		if (h_act)
			pixel_x	<=	pixel_x + 11'b1;
		else
			pixel_x	<=	11'b0;
		
		if(hs_end && !h_max)
			hsync  <= 1'b1;
		else 
			hsync <= 1'b0;
			
		if(hr_start)
			h_act <= 1'b1;
		else if(hr_end)
			h_act <= 1'b0;

		// Gestion du signal vertical
		if (h_max)
		begin
			if(v_max)
				pixelV <= 11'b0;
			else
				pixelV <= pixelV + 11'b1;
				
			if (v_act)
				pixel_y	<=	pixel_y + 11'b1;
			else
				pixel_y	<=	11'b0;
				
			if(vs_end && !v_max)
				vsync  <= 1'b1;
			else 
				vsync <= 1'b0;
				
			if(vr_start)
				v_act <= 1'b1;
			else if(vr_end)
				v_act <= 1'b0;
		end
	end
end

// dataEnable signal
always @(posedge clock or posedge reset) begin
	if(reset) begin
		dataEnable <= 0;
		pre1_vga_de <= 0;
		pre2_vga_de <= 0;
		pre3_vga_de <= 0;
		pre4_vga_de <= 0;
	end
	else begin
		//2 pixels de décalage pour se synchroniser avec framework (1 délai pour les coordonnées x,y + 1 délay pour la rom +  + 1 délay pour la ram)
		dataEnable <= pre3_vga_de;
		pre2_vga_de <= pre1_vga_de;
		pre3_vga_de <= pre2_vga_de;
		//pre4_vga_de <= pre3_vga_de;
		
		pre1_vga_de <= v_act && h_act;
	end
end

assign vgaClock = clock;


//frame=1 au début de la ligne 481 (v_display), lorsque la zone d'affichage a été balayé
assign frame = (hr_start) && (pixelV == (v_sync + v_back_porch + v_display));

framebuffer fb(
	.clk(clock),
	.wrclk(clock50),
	.x(pixel_x),
	.y(pixel_y),
	.o_pixel(text_pixel),
	.ram_waddr(frame_waddr),
	.ram_wdata(frame_wdata),
	.ram_wren(frame_wren)
);

/* boucle qui calcul la frame à afficher (cette frame sera écrite en RAM) */
always @(posedge clock50) begin
	if(instructionNum != instructionPrev) begin // Détecte une nouvelle instruction
		//frame_waddr <= frame_waddr + 1;
		frame_waddr <= instructionAddr;
		frame_wren <= 1;
		frame_wdata <= instructionData;
		
		instructionPrev <= instructionNum;
	end
	else begin
		frame_wren <= 0;
	end
end

// Affichage des pixels
always @(posedge clock or posedge reset) begin
	if(reset) begin
		
	end
	else begin

		if(text_pixel != 0) begin
			r_pixel[23:16] <= 8'd255 * text_pixel[2];
			r_pixel[15:8] <= 8'd255 * text_pixel[1];
			r_pixel[7:0] <= 8'd255 * text_pixel[0];
		end
		else begin
			r_pixel[23:16] <= 8'd44;
			r_pixel[15:8] <= 8'd39;
			//r_pixel[7:0] <= 8'd156;
			r_pixel[7:0] <= 8'd86;
		end
		
	end
end

assign RGBchannel[23:16] = r_pixel[23:16];
assign RGBchannel[15:8] = r_pixel[15:8];
assign RGBchannel[7:0] = r_pixel[7:0];

endmodule
