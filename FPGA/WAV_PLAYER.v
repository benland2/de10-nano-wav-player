module WAV_PLAYER(
	//** input **
	input wire clock50, 
	input wire clock50_2,
	input wire clock50_3,
	input wire rst_n,
	
	// ********************************************** //
	// ** HDMI CONNECTIONS **
	
	// AUDIO
	output HDMI_I2S, // Data I2S
	output HDMI_MCLK,//Master Clock
	output HDMI_LRCLK,//Left and Right Clock
	output HDMI_SCLK,//Serial Clock
	
	// VIDEO
	output [23:0] HDMI_TX_D, // RGBchannel
	output HDMI_TX_VS, // vsync
	output HDMI_TX_HS, // hsync
	output HDMI_TX_DE, // dataEnable
	output HDMI_TX_CLK, // vgaClock
	
	// REGISTERS AND CONFIG LOGIC
	// HPD vient du connecteur
	input HDMI_TX_INT,
	inout HDMI_I2C_SDA, 	// HDMI i2c data
	output HDMI_I2C_SCL, // HDMI i2c clock
	//output READY 			// HDMI is ready signal from i2c module
	output [7:0] led,	// HDMI is ready signal from i2c module
	
	//////////// HPS //////////
    output   [14: 0]    HPS_DDR3_ADDR,
    output   [ 2: 0]    HPS_DDR3_BA,
    output              HPS_DDR3_CAS_N,
    output              HPS_DDR3_CK_N,
    output              HPS_DDR3_CK_P,
    output              HPS_DDR3_CKE,
    output              HPS_DDR3_CS_N,
    output   [ 3: 0]    HPS_DDR3_DM,
    inout    [31: 0]    HPS_DDR3_DQ,
    inout    [ 3: 0]    HPS_DDR3_DQS_N,
    inout    [ 3: 0]    HPS_DDR3_DQS_P,
    output              HPS_DDR3_ODT,
    output              HPS_DDR3_RAS_N,
    output              HPS_DDR3_RESET_N,
    input               HPS_DDR3_RZQ,
    output              HPS_DDR3_WE_N
	
	// ********************************************** //
	);
	
//parameter SCREEN_NUM_LETTERS = 600;
parameter ROM_LETTERS = 22;
//parameter FILES_LETTERS = 40;
//parameter WAV_SAMPLE_DATA = 259463;
parameter GAMEPAD_AXE_CENTER = 0;
parameter GAMEPAD_AXE_TOP = 511;//-1
parameter GAMEPAD_AXE_BOTTOM = 1;
parameter GAMEPAD_BTN_A = 306;//Button to stop audio
parameter GAMEPAD_BTN_B = 305;//Button to play audio
//parameter GAMEPAD_BTN_B = 290;//Button to play audio
parameter GAMEPAD_BTN_C = 307;//Button to test speed
//parameter GAMEPAD_BTN_C = 288;//Button to test speed
parameter FILESIZE_WIDTH = 25; //(26 - 1)

parameter NUM_FCMD_SPEEDTEST = 9;
parameter NUM_FCMD_READ2CHAR = 3;
parameter NUM_FCMD_GETSIZE = 6;
parameter NUM_FCMD_GETNBFILES = 1;
parameter NUM_FCMD_GETNAME = 2;

wire clockHDMI,clockAudio,clockSys,clockFiler,locked,resetAudio_n,resetFiler_n;
wire rst = ~rst_n;
reg [4:0] init_step;
reg sysLastBitAnim;

// ** Gestion pour la RAM pour la liste des fichiers **
reg ram_wren;
reg [7:0] ram_wdata;
wire [7:0] ram_rdata;
reg [12:0] ram_waddr;//Adresse à écrire dans la RAM
reg [12:0] ram_raddr;//Adresse à lire dans la RAM

reg [19:0] sys_Count;
reg [4:0] second_Count;//Permet de rejouer l'audio qprès quelques secondes

reg [9:0] vgaInstruction;//Permet de déclencher le calcul de la frame
wire [9:0] vgaInstructionDone;//Permet de déclencher le calcul de la frame
wire [9:0] rom_textAddr;//Adresse dans la rom
reg [9:0] rom_textAddr_de1;//Adresse dans la rom avec décalage de 1
reg [9:0] vga_textAddr;//Adresse dans la RAM du VGA
reg [9:0] vga_textAddr_de1;//Adresse dans la RAM du VGA avec 1 delai: 1 pour la ROM
//reg [9:0] vga_textAddr_de2;//Adresse dans la RAM du VGA avec 2 delais: 1 pour boucle clockSys + 1 pour la ROM
wire [7:0] rom_textVal;

// SDCARD Controller
wire [31:0] sd_data_export;          //         sdctl_data.export
wire [15:0] sd_hps_op_export;          //         sdctl_cmd.export
wire [15:0] sd_hps_reqId_export;
wire [15:0] sd_fcmd_export;
wire [31:0] sd_arg1_export;
wire [31:0] sd_debug_info_export;  
wire hps_fpga_reset_n;
wire [7:0] sdctrl_cmd;
reg [7:0] sdctrl_cmd_value;
wire [FILESIZE_WIDTH:0] sdctrl_arg1;
reg [FILESIZE_WIDTH:0] sdctrl_arg1_value;
wire [3:0] sdctrl_reqId;
reg [3:0] sdctrl_reqId_value;
reg [15:0] hps_reqId_prev;
reg [31:0] speed_count;
wire filer_waitrequest;
wire [31:0] filer_data;
reg [31:0] filer_data_delayed;
reg filer_delayed;
reg filer_read;
reg filer_data_ready;
reg [31:0] filer_debug;


// Audio
reg [FILESIZE_WIDTH:0] FILE_SIZE;
reg [FILESIZE_WIDTH:0] DATA_SIZE;
reg [15:0] HEADER_OFFSET;
reg [31:0] file_data;//On analyse 4 octets avec cette variable
reg [15:0] header_flag;
reg [23:0] header_count;
reg [7:0] fmt_count;
reg [3:0] data_count;//Uniquement pour récupérer le datasize
reg [FILESIZE_WIDTH:0] audio_count;
//reg [FILESIZE_WIDTH:0] filer_pos_prev;

wire [31:0] audio_sample;
reg [31:0] audio_data;
reg [3:0] audio_cmd_value;
reg [21:0] audio_arg1_value;
reg [3:0] audio_reqId_value;
reg [1:0] audio_state;
reg [2:0] audio_channels;
wire audio_samples_empty;
reg audio_wrreq;
wire audio_fifo_full;

// Deboggage
wire [31:0] fifo_debug;

// Interface Vidéo
reg [12:0] FILES_LETTERS;//Number of letters to display
reg [7:0] SPACES_ADDED;
reg [7:0] filename_ptr;
reg [15:0] NUM_FILES;
reg [3:0] file_selected;
reg [3:0] file_selected_next;
reg display_selector;
reg display_selector_de;
reg [7:0] selector_code;

// Gamepad
wire gamepad_evt_waitrequest;
wire [31:0] gamepad_evt_readdata;
reg gamepad_evt_read;
reg gamepad_ready;
reg gamepad_on;
reg [8:0] gamepad_axe;
reg [8:0] gamepad_axe_prev;
reg gamepad_btnB;
reg gamepad_btnB_flag;
reg gamepad_btnA;
reg gamepad_btnA_flag;
reg gamepad_btnC;
reg gamepad_btnC_flag;
reg action_btnB;
reg action_btnB_prev;

// ** VGA CLOCK **
pll_hdmi pll_hdmi(
	.refclk(clock50),
	.rst(rst),
	
	.outclk_0(clockHDMI),
	.locked(locked)
);

// ** FILER CLOCK **
pll_filer pll_filer(
	.refclk(clock50_3),
	.rst(rst),
	
	.outclk_0(clockFiler),	//180 MHz pour avoir une horloge qui lit la carte SD
	.locked(resetFiler_n)
);
//assign clockFiler = clock50_3;

// ** VGA MAIN CONTROLLER **
vgaHdmi vgaHdmi (
	// input
	.clock	(clockHDMI),
	.clock50	(clock50),
	.reset	(~locked),
	
	// ouput
	.hsync	(HDMI_TX_HS),
	.vsync	(HDMI_TX_VS),
	.dataEnable	(HDMI_TX_DE),
	.vgaClock	(HDMI_TX_CLK),
	.RGBchannel	(HDMI_TX_D),
	
	// instructions pour dessin de l'écran
	.instructionNum ( (vgaInstruction > 0) ? vgaInstruction : vgaInstructionDone),//On commence à dessiner seulement si on a le 1er texte de la ROM
	.instructionPrev (vgaInstructionDone),
	.instructionAddr(vga_textAddr_de1),
	.instructionData( (vgaInstruction <= ROM_LETTERS)? rom_textVal : ((display_selector > 0)? selector_code : ram_rdata)  )
	
);


// ** I2C Interface for ADV7513 initial config **
I2C_HDMI_Config I2C_HDMI_Config(
	.iCLK				(clock50),
	.iRST_N			(rst_n),
	.I2C_SCLK		(HDMI_I2C_SCL),
	.I2C_SDAT		(HDMI_I2C_SDA),
	.HDMI_TX_INT	(HDMI_TX_INT),
	.READY			(led[7:4])
);

// ** AUDIO CLOCK **
pll_sys pll_sys(
	.refclk(clock50_2),
	.rst(rst),
	
	.outclk_0(clockAudio),//11.290322 MHz pour l'audio en 44.1 KHz
	.outclk_1(clockSys),	//1 MHz pour avoir une horloge système
	.locked(resetAudio_n)
);

// ** AUDIO **
AUDIO_IF u_AVG(
	.clk(clockAudio),
	.reset_n(rst_n),// ON par défaut
	.mclk(HDMI_MCLK),
	.sclk(HDMI_SCLK),
	.lrclk(HDMI_LRCLK),
	.i2s(HDMI_I2S),
	.audio_on(audio_state[0]),
	.audio_sample(audio_sample),
	.audio_channels(audio_channels),
	.audio_sample_avail(~audio_samples_empty)
);


initial begin
	init_step = 0;
	vgaInstruction = 0;
	sysLastBitAnim = 0;
	vga_textAddr = 0;
	rom_textAddr_de1 = 0;
	sdctrl_cmd_value = 0;
	sdctrl_arg1_value = 0;
	sdctrl_reqId_value = 0;
	hps_reqId_prev = 0;
	audio_cmd_value = 0;
	audio_reqId_value = 0;
	audio_arg1_value = 0;
	FILES_LETTERS = 0;
	SPACES_ADDED = 0;
	filename_ptr = 0;
	ram_wren = 0;
	ram_raddr = 0;
	file_selected = 0;
	file_selected_next = 0;
	gamepad_evt_read = 0;
	gamepad_ready = 0;
	gamepad_axe_prev = GAMEPAD_AXE_CENTER;//Gamepad Center
	gamepad_btnB = 0;
	gamepad_btnB_flag = 0;
	gamepad_btnA = 0;
	gamepad_btnA_flag = 0;
	gamepad_btnC = 0;
	gamepad_btnC_flag = 0;
	
	filer_data_ready = 0;
	
	action_btnB = 0;
	audio_wrreq = 0;

end

fifo_audio fifo_audio0(
	.data(audio_data),
	.wrclk(clockFiler),
	.wrreq(audio_wrreq),
	
	.rdclk(HDMI_LRCLK),
	.rdreq(audio_state[0]),
	.q(audio_sample),
	
	.rdempty(audio_samples_empty),
	.wrfull(audio_fifo_full)
);


/*fifo_async fifo_audio0(
	.wclk(clock50_2), 
	.wrst_n(rst_n),
	.rclk(HDMI_LRCLK), 
	.rrst_n(rst_n),
	.w_en(audio_wrreq), 
	.r_en(audio_state[0]),
	.data_in(audio_data),
	.data_out(audio_sample),
	.full(audio_fifo_full),
	.empty(audio_samples_empty),
	.fifo_debug(fifo_debug)
);*/

player_rom tr(
	.address(rom_textAddr),
	.clock(clockSys),
	.q(rom_textVal)
);

sdcard_controller sd_controller(
	.sd_clk(clockFiler),
	.hData(sd_data_export),
	.hOp(sd_hps_op_export),
	.hReqId(sd_hps_reqId_export),
	.fCmd(sd_fcmd_export),
	.fArg1(sd_arg1_export),
	.fDebug_info(sd_debug_info_export),
	.sdLed(led[1]),
	.sys_cmd(sdctrl_cmd),
	.sys_arg1(sdctrl_arg1),
	.sys_reqId(sdctrl_reqId),
	
	.fGamepad_evt(file_selected),
	//.fDebug_input(fifo_debug)
	.fDebug_input(filer_debug)
);

/*wav_parser wav_parser0(
	.clk(clockFiler),
	.parser_ena((sd_hps_op_export == 9 && sdctrl_cmd_value == 8'd31) ? 1 :0)
);*/

soc_system u0(
					//SD Controller
					.hdata_export(sd_data_export),
					.hop_export(sd_hps_op_export),
					.hreqid_export(sd_hps_reqId_export),
					.fcmd_export(sd_fcmd_export),
					.farg1_export(sd_arg1_export),
					.fdebug_info_export(sd_debug_info_export),
					
					//Gamepad
					.gamepad_evt_readdata(gamepad_evt_readdata),
					.gamepad_evt_read(gamepad_evt_read),
					.gamepad_evt_waitrequest(gamepad_evt_waitrequest),
					
					//Filer
					.file_data_readdata(filer_data),
					.file_data_read(filer_read),
					.file_data_waitrequest(filer_waitrequest),
					
               //Clock&Reset
               .clk_clk(clockFiler),                                      //                            clk.clk
               .reset_reset_n(hps_fpga_reset_n),                            //                          reset.reset_n
               //HPS ddr3
               .memory_mem_a(HPS_DDR3_ADDR),                                //                         memory.mem_a
               .memory_mem_ba(HPS_DDR3_BA),                                 //                               .mem_ba
               .memory_mem_ck(HPS_DDR3_CK_P),                               //                               .mem_ck
               .memory_mem_ck_n(HPS_DDR3_CK_N),                             //                               .mem_ck_n
               .memory_mem_cke(HPS_DDR3_CKE),                               //                               .mem_cke
               .memory_mem_cs_n(HPS_DDR3_CS_N),                             //                               .mem_cs_n
               .memory_mem_ras_n(HPS_DDR3_RAS_N),                           //                               .mem_ras_n
               .memory_mem_cas_n(HPS_DDR3_CAS_N),                           //                               .mem_cas_n
               .memory_mem_we_n(HPS_DDR3_WE_N),                             //                               .mem_we_n
               .memory_mem_reset_n(HPS_DDR3_RESET_N),                       //                               .mem_reset_n
               .memory_mem_dq(HPS_DDR3_DQ),                                 //                               .mem_dq
               .memory_mem_dqs(HPS_DDR3_DQS_P),                             //                               .mem_dqs
               .memory_mem_dqs_n(HPS_DDR3_DQS_N),                           //                               .mem_dqs_n
               .memory_mem_odt(HPS_DDR3_ODT),                               //                               .mem_odt
               .memory_mem_dm(HPS_DDR3_DM),                                 //                               .mem_dm
               .memory_oct_rzqin(HPS_DDR3_RZQ),                             //                               .oct_rzqin
                                                                            // button_pio_external_connection.export
               .hps_0_h2f_reset_reset_n(hps_fpga_reset_n)                   //                hps_0_h2f_reset.reset_n

           );
			  
/*sys_ram sys_ram0(
	.data(ram_wdata),
	.rdaddress(text_address),
	.rdclock(clk),
	.wraddress(ram_waddr ),
	.wrclock(wrclk),
	.wren(ram_wren),//Write enabled
	.q(text_value)
);*/

ram_filelist ram_filelist0(
	.data(ram_wdata),
	.wraddress(ram_waddr ),
	.wrclock(clockFiler),
	.wren(ram_wren),//Write enabled
	
	.rdaddress(ram_raddr),
	.rdclock(clockSys),
	.q(ram_rdata)
);

//On fait une boucle système qui va gérer l'affichage du texte
always @(posedge clockSys or negedge rst_n)
begin
	if(!rst_n)
	begin
		init_step <= 0;
		action_btnB_prev <= 0;
	end
	else begin
		if(sys_Count >= 20'd999999) begin
			sys_Count <= 0;
			
			
			/****if(second_Count < 9)  second_Count <= second_Count + 1;
			else second_Count <= 0;****/
			
			//if(SIN_Count >= SIN_SAMPLE_DATA - 1) SIN_Count <= 0;
			//else SIN_Count <= SIN_Count + 1;
			
			if(init_step <= 8) begin
				init_step <= init_step + 1;
				
				
			end
			//else ram_wren <= 0;
			
		end
		else begin 
			if(sys_Count[8] != sysLastBitAnim) begin // Permet d'avoir une petite animation sur l'affichage du texte
				sysLastBitAnim <= sys_Count[8];
				
				//Envoi d'instruction au VGA
				if(vgaInstruction < (ROM_LETTERS) ) begin
					//Permet d'assurer la synchro
					if(vgaInstruction == 0 || vgaInstruction == vgaInstructionDone)
					begin 
						// si rom_textAddr_de1 = 0: on n'a pas encore la 1ère valeur de la ROM, donc pas d'instruction
						if(rom_textAddr_de1 > 0) begin
							vga_textAddr_de1 <= vga_textAddr - 1;
							
							//Le changement de valeur sur vgaInstruction permet de faire exécuter une nouvelle tache au module VGA
							vgaInstruction <= vgaInstruction + 1;
						end
						
						rom_textAddr_de1 <= rom_textAddr_de1 + 1;
						
						//vga_textAddr permet de calculer la prochaine position dans la RAM
						if(vgaInstruction == (ROM_LETTERS - 1) ) begin
							ram_raddr <= 0;//Prépare l'adresse pour la prochaine lecture
							vga_textAddr <= (40 + (40*(vga_textAddr/40))) + 1 ;//Saut de ligne + 1 espace pour les titres
							display_selector_de <= 1;//On prépare l'affichage du sélecteur pour le prochain cycle
							if(file_selected == 0) begin
								if(action_btnB) selector_code <= 8'd125;
								else selector_code <= 8'd62;
							end
							else selector_code <= 0;
							SPACES_ADDED <= 1;
						end
						else begin
							if(rom_textVal == 8'd10) vga_textAddr <= (40 + (40*(vga_textAddr/40))) + 1 ;//Saut de ligne
							else vga_textAddr <= vga_textAddr + 1;
						end
						
					end
				end
				else if(vgaInstruction < (ROM_LETTERS + FILES_LETTERS + SPACES_ADDED) && FILES_LETTERS > 0 ) begin //Affichage des noms de fichiers
					if(vgaInstruction == vgaInstructionDone) begin
						vga_textAddr_de1 <= vga_textAddr - 1;
						vgaInstruction <= vgaInstruction + 1;
						
						if(ram_rdata == 8'd10) begin
							if(SPACES_ADDED < NUM_FILES) SPACES_ADDED <= SPACES_ADDED + 1;//Compte de nombre d'espaces ajoutés au début de chaque titre
							vga_textAddr <= (40 + (40*(vga_textAddr/40))) + 1;//Saut de ligne + 1 espace
							display_selector_de <= 1;
							if(file_selected == (((40 + vga_textAddr)/40) - 2) ) begin
								if(action_btnB) selector_code <= 8'd125;
								else selector_code <= 8'd62;
							end
							else selector_code <= 0;
						end
						else begin 
							vga_textAddr <= vga_textAddr + 1;
							display_selector_de <= 0;
						end
						
						if (display_selector_de == 1) begin
							display_selector <= 1;//unselected (0) / selected (62)
						end
						else begin
							display_selector <= 0;
							filename_ptr <= filename_ptr + 1;
							ram_raddr <= filename_ptr + 1;
						end
						
					end
					
				end
			end
			
			sys_Count <= sys_Count + 1;
		end
		
		/***** Events for redraw *****/
		if(gamepad_axe_prev != gamepad_axe) begin
			gamepad_axe_prev <= gamepad_axe;
			
			if((gamepad_axe == GAMEPAD_AXE_TOP) || (gamepad_axe == GAMEPAD_AXE_BOTTOM) ) begin
				vgaInstruction <= 0;
				vga_textAddr <= 0;
				vga_textAddr_de1 <= 0;
				rom_textAddr_de1 <= 0 ;
				filename_ptr <= 0;
				ram_raddr <= 0;
			end
			
			if(gamepad_axe == GAMEPAD_AXE_TOP)	file_selected = (file_selected - 1);
			if(gamepad_axe == GAMEPAD_AXE_BOTTOM)	file_selected = (file_selected + 1);
		end
		
		if(action_btnB_prev != action_btnB) begin
			action_btnB_prev <= action_btnB;
			
			vgaInstruction <= 0;
			vga_textAddr <= 0;
			vga_textAddr_de1 <= 0;
			rom_textAddr_de1 <= 0 ;
			filename_ptr <= 0;
			ram_raddr <= 0;
		end
		//file_selected <= file_selected_next;
	end
end

//Boucle système qui va gérer la lecture de la carte SD
always @(posedge clockFiler or negedge rst_n)
begin
	if(!rst_n)
	begin
		sdctrl_cmd_value <= 0;
		sdctrl_reqId_value <= sdctrl_reqId_value + 1;
		
		speed_count <= 0;
		filer_read <= 0;
		filer_debug <= 0;
		filer_delayed <= 0;
	end
	else begin
		// Gestion de la lecture audio depuis la SD Card
		if (led[1] == 1'b1) begin
			filer_data_ready <= !filer_waitrequest;//Permet de rattraper le décalage lié à la FIFO
			
			if(!filer_waitrequest) begin
				filer_read <= 1;
				
				/*if (sdctrl_cmd_value != 3 && sdctrl_cmd_value != 31 && sdctrl_cmd_value != 34 && sdctrl_cmd_value != 9) begin
					filer_data_delayed <= filer_data;//On purge la FIFO (A tester si c'est vraiment nécessaire)
				end*/
			end
			else begin
				if (sdctrl_cmd_value != 3 && sdctrl_cmd_value != 31 && sdctrl_cmd_value != 34 && sdctrl_cmd_value != NUM_FCMD_SPEEDTEST && sdctrl_cmd_value != NUM_FCMD_GETSIZE && sdctrl_cmd_value != NUM_FCMD_GETNBFILES && sdctrl_cmd_value != NUM_FCMD_GETNAME) begin
					if(filer_read) filer_read <= 0;
				end
			end
			
			if(sd_hps_reqId_export != hps_reqId_prev || filer_data_ready || filer_delayed) begin
				hps_reqId_prev <= sd_hps_reqId_export;
				if(filer_delayed) filer_delayed <= 0;
				
				if(sd_hps_op_export == 1) begin // Card ready
					sdctrl_cmd_value <= NUM_FCMD_GETNBFILES; // Get numbers files
					filer_read <= 1;
					//filer_debug <= sdctrl_reqId_value + 1;
					filer_debug <= 22;
					
					sdctrl_arg1_value <= 11;
					sdctrl_reqId_value <= sdctrl_reqId_value + 1;
				end
				if(sd_hps_op_export == 2) begin // Return Number of files
					NUM_FILES <= filer_data[15:0];
				
					if(filer_data[15:0] > 0) begin
						sdctrl_cmd_value <= NUM_FCMD_GETNAME;// Get name of file (file number 0 to start)
						sdctrl_arg1_value <= 0;//File Number 0
						sdctrl_reqId_value <= sdctrl_reqId_value + 1;
						FILES_LETTERS <= 0;
					end
				end
				if(sd_hps_op_export[3:0] == 3) begin // Return a char of name at pos ptr_string
						ram_wren <= 1;
						ram_waddr <= FILES_LETTERS;
						ram_wdata <= filer_data[7:0];
						
						FILES_LETTERS <= FILES_LETTERS + 1;
						
						sdctrl_cmd_value <= NUM_FCMD_GETNAME; // Continue request to get names of files
						sdctrl_reqId_value <= sdctrl_reqId_value + 1;
				end
				if(sd_hps_op_export[3:0] == 4) begin // Return name completed
					ram_wren <= 0;
					
					if((sdctrl_arg1_value + 1) < NUM_FILES) begin // Get name of next file
						sdctrl_cmd_value <= NUM_FCMD_GETNAME;
						sdctrl_arg1_value <= sdctrl_arg1_value + 1;
					end
					else sdctrl_cmd_value <= 5;//Pending action
					
					sdctrl_reqId_value <= sdctrl_reqId_value + 1;
				end
				if(sd_hps_op_export == 6) begin // Transfert audio data ended
					action_btnB <= 0;
					sdctrl_cmd_value <= 16'h5; // Pending action
					sdctrl_reqId_value <= sdctrl_reqId_value + 1;
					audio_wrreq <= 0;
				end
				if(sd_hps_op_export == 8) begin // Transfert filesize
					FILE_SIZE <= filer_data[FILESIZE_WIDTH:0];
					DATA_SIZE <= 0;//DataSize inconnu
					header_flag <= 0;// Recherche du bloc fmt_
					header_count <= 0;
					data_count <= 0;
					file_data <= 0;
					//sdctrl_cmd_value <= 3;// Request to open file and start read at pos 0
					//cmd 3 => pour récupérer par 2 chars (utile pour lire l'audio)
					//cmd 31 => pour récupérer par 1 char (utile pour parser le block fmt et data)
					sdctrl_cmd_value <= 8'd31;// Request to open file and start read 1 char at pos 0
					sdctrl_arg1_value <= 0;
					sdctrl_reqId_value <= sdctrl_reqId_value + 1;
					filer_read <= 1;
				end
				if(sd_hps_op_export == 5 || sd_hps_op_export == 8'd10 ) begin // Send 2 or 4 char from file content
					audio_state <= 2'd1;//soit 01
					/*if(sd_hps_op_export == 16'd10) audio_data <= sd_data_export[31:0];
					else audio_data <= {16'd0,sd_data_export[15:0]};*/
					
					//if(header_flag == 3) header_flag <= 4;
					
					if(filer_delayed) begin
						if(sd_hps_op_export == 16'd10) audio_data <= filer_data_delayed[31:0];
						else audio_data <= {16'd0,filer_data_delayed[15:0]};
						
						filer_debug <= {16'd0,filer_data_delayed[15:0]};
					end
					else begin
						if(sd_hps_op_export == 16'd10) audio_data <= filer_data[31:0];
						else audio_data <= {16'd0,filer_data[15:0]};
						
						filer_debug <= {16'd0,filer_data[15:0]};
						//filer_debug <= (audio_count + HEADER_OFFSET);
					end
						
					if(audio_fifo_full == 0) begin
						audio_wrreq <= 1;//Permet de stoquer les samples dans la FIFO pour l'audio
						//filer_pos_prev <= audio_count + HEADER_OFFSET;
						
						// Continue to read file at pos arg1 + 2 or 4 (car on ne lit que les audios en 16 bits)
						if(audio_channels == 2) begin
							sdctrl_arg1_value <= audio_count + 4 + HEADER_OFFSET;
						end
						else begin
							sdctrl_arg1_value <= audio_count + 2 + HEADER_OFFSET;
						end
						
						sdctrl_cmd_value <= (audio_channels == 2)? 34 : NUM_FCMD_READ2CHAR;
						
						if( audio_count < (DATA_SIZE - 2) && !gamepad_btnA_flag) begin
							if(audio_channels == 2) audio_count <= audio_count + 4;
							else audio_count <= audio_count + 2;
						end
						else begin 
							filer_read <= 0;
							sdctrl_cmd_value <= 4;//Close file
							sdctrl_arg1_value <= DATA_SIZE;//Pour debuggage
						end
						
						sdctrl_reqId_value <= sdctrl_reqId_value + 1;
					end
					else begin
						audio_wrreq <= 0;//On fait un coup d'attente
						filer_delayed <= 1;
						filer_data_delayed <= filer_data;
						
						filer_debug <= 111;
					end
				end
				if(sd_hps_op_export == 9) begin // Send 1 char from file content
					if(header_flag == 1) fmt_count <= fmt_count + 1;
					if(header_flag == 2) data_count <= data_count + 1;
					
					filer_debug <= filer_data;
					
					if(header_flag == 2  && data_count == 3 ) begin // datasize
						//DATA_SIZE <= {sd_data_export[7:0],file_data[31:8]};
						DATA_SIZE <= {filer_data[7:0],file_data[31:8]};
						HEADER_OFFSET <= (header_count + 1);
						//HEADER_OFFSET <= (header_count);// PAS de +1 car on rattrappe le décallage de la FIFO
						audio_count <= 0;
						filer_debug <= 222;
						
						//filer_pos_prev <= header_count;
						
						sdctrl_cmd_value <= (audio_channels == 2)? 34 : NUM_FCMD_READ2CHAR;
						sdctrl_arg1_value <= 0 + (header_count + 1);//Start audio from pos 0 + HEADER_OFFSET
						//sdctrl_arg1_value <= 0 + (header_count);//Start audio from pos 0 + HEADER_OFFSET
						sdctrl_reqId_value <= sdctrl_reqId_value + 1;
						
						header_flag <= 3;
					end
					else if(header_flag == 1  && ({filer_data[7:0],file_data[31:8]} == 32'h61746164) ) begin // data found
						//On recherche le "data" (32'h64617461 soit 32'h61746164 dans notre cas)
						
						header_count <= header_count + 1;
						header_flag <= 2;//bloc data found
						filer_debug <= 40;
						
						header_count <= header_count + 1;
						sdctrl_cmd_value <= 8'd31;// Continue to read 1 char
						sdctrl_arg1_value <= header_count + 1;
						sdctrl_reqId_value <= sdctrl_reqId_value + 1;
					end
					else if(header_flag == 1  && fmt_count == 7 ) begin //Nb channels
						//audio_channels <= {sd_data_export[7:0],file_data[31:24]};
						audio_channels <= {filer_data[7:0],file_data[31:24]};
						
						file_data <= file_data >> 8;//Décalage à droite
						//file_data[31:24] <= sd_data_export[7:0];
						file_data[31:24] <= filer_data[7:0];
						filer_debug <= 30;
						
						header_count <= header_count + 1;
						sdctrl_cmd_value <= 8'd31;// Continue to read 1 char
						sdctrl_arg1_value <= header_count + 1;
						sdctrl_reqId_value <= sdctrl_reqId_value + 1;
					end
					else if(header_flag == 0  && ({filer_data[7:0],file_data[31:8]} == 32'h20746D66) ) begin //fmt_ found
						//On recherche le "fmt_" (32'h666D7420 soit 32'h20746D66 dans notre cas)
						header_flag <= 1;//FMT_ Found
						fmt_count <= 0;
						
						file_data <= file_data >> 8;//Décalage à droite
						file_data[31:24] <= filer_data[7:0];
						filer_debug <= 20;
						
						header_count <= header_count + 1;
						sdctrl_cmd_value <= 8'd31;// Continue to read 1 char
						sdctrl_arg1_value <= header_count + 1;
						sdctrl_reqId_value <= sdctrl_reqId_value + 1;
					end
					else if( header_count < (FILE_SIZE - 1)) begin
						file_data <= file_data >> 8;//Décalage à droite
						file_data[31:24] <= filer_data[7:0];
						filer_debug <= filer_data[7:0];
						//filer_debug <= header_flag;
						//filer_debug <= 10;
						
						header_count <= header_count + 1;
						
						sdctrl_cmd_value <= 8'd31;// Continue to read 1 char
						sdctrl_arg1_value <= (header_count + 1);
						sdctrl_reqId_value <= sdctrl_reqId_value + 1;
					end
					else begin
						sdctrl_cmd_value <= 4;//Close file
						sdctrl_arg1_value <= header_flag;//Pour avoir du debuggage
						sdctrl_reqId_value <= sdctrl_reqId_value + 1;
					end
					
				end
				
				if(sd_hps_op_export == 11) begin // Test speed sd card
					if(speed_count < 32'd1800000) begin
						speed_count <= (speed_count + 1);
						sdctrl_cmd_value <= 9;// Continue to speed test of sd card
						sdctrl_arg1_value <= speed_count[7:0];
						sdctrl_reqId_value <= sdctrl_reqId_value + 1;
						filer_debug <= filer_data;
					end
					else begin
						gamepad_btnC_flag <= 0;
						filer_read <= 0;
						
						sdctrl_cmd_value <= 10;// End test speed sd card
						sdctrl_arg1_value <= speed_count;
						sdctrl_reqId_value <= sdctrl_reqId_value + 1;
					end
				end
				
				if(sd_hps_op_export == 7) begin // Waiting for request
					if(audio_samples_empty) audio_state <= 2'b0;
					if(filer_read) filer_read <= 0;
					
					if(gamepad_btnB_flag == 1 ) begin
						gamepad_btnB_flag <= 0;
						
						if(!action_btnB) begin
							sdctrl_cmd_value <= NUM_FCMD_GETSIZE;// Request to get size of selected file
							//sdctrl_arg1_value <= {20'd0,file_selected};
							sdctrl_arg1_value <= file_selected;
							sdctrl_reqId_value <= sdctrl_reqId_value + 1;
							action_btnB <= 1;
							
						end
					end
					
					if(gamepad_btnA_flag == 1 ) begin //Audio is stopped
						gamepad_btnA_flag <= 0;
					end
					
					if(gamepad_btnC_flag == 1) begin
						filer_read <= 1;
						speed_count <= 0;
						sdctrl_cmd_value <= NUM_FCMD_SPEEDTEST;// Start speed test sd card
						sdctrl_arg1_value <= 2;
						sdctrl_reqId_value <= sdctrl_reqId_value + 1;
					end
				end
			end
			else begin
				//if(sd_hps_op_export != 5 && sd_hps_op_export != 8'd10) audio_wrreq <= 0;//On n'écrit pas dans la FIFO quand pas de données
				audio_wrreq <= 0;//On n'écrit pas dans la FIFO quand pas de données
			end
			
			/**** On écoute les events sur le gamepad qui ont une action sur la lecture de la SD Card ****/
			if(gamepad_btnB == 1 && !gamepad_btnB_flag && !action_btnB) begin
				gamepad_btnB_flag <= 1;
			end
			
			if(gamepad_btnA == 1 && !gamepad_btnA_flag) begin
				gamepad_btnA_flag <= 1;
			end
			
			if(gamepad_btnC == 1 && !gamepad_btnC_flag) begin
				gamepad_btnC_flag <= 1;
			end
			
		end
	end
	
end

//Boucle système qui va lire les events du gamepad
always @(posedge clockFiler or negedge rst_n)
begin
	if(!rst_n)
	begin
		gamepad_evt_read <= 0;
		gamepad_ready <= 0;
		gamepad_on <= 0;
	end
	else begin
		if(!gamepad_evt_waitrequest) begin
			gamepad_ready <= 1;
			gamepad_evt_read <= 1;//On lira la donnée au prochain cycle
			if(gamepad_evt_read == 1) begin //Il y a une donnée qui vient d'être lue
				gamepad_evt_read <= 0;
			end
		end
		else begin
			if(gamepad_evt_read == 1) begin
				gamepad_evt_read <= 0;
			end
		end
		
		gamepad_on <= gamepad_btnB;
		
		//file_selected <= file_selected_next;
	end
	
end

always @(gamepad_evt_readdata) 
begin 
	if(gamepad_ready) begin		
		
		if(gamepad_evt_readdata[10:9] == 0) gamepad_axe <= gamepad_evt_readdata[8:0];
		else if(gamepad_evt_readdata[10:9] == 2) begin 
			if(gamepad_evt_readdata[8:0] == GAMEPAD_BTN_B) gamepad_btnB <= 1;
			else if(gamepad_evt_readdata[8:0] == GAMEPAD_BTN_A) gamepad_btnA <= 1;
			else if(gamepad_evt_readdata[8:0] == GAMEPAD_BTN_C) gamepad_btnC <= 1;
		end
		else begin
			if(gamepad_evt_readdata[8:0] == GAMEPAD_BTN_B) gamepad_btnB <= 0;
			else if(gamepad_evt_readdata[8:0] == GAMEPAD_BTN_A) gamepad_btnA <= 0;
			else if(gamepad_evt_readdata[8:0] == GAMEPAD_BTN_C) gamepad_btnC <= 0;
		end
	end
	else begin
		gamepad_axe <= GAMEPAD_AXE_CENTER;//Gamepad Center
		gamepad_btnB <= 0;
		gamepad_btnA <= 0;
		gamepad_btnC <= 0;
		
	end
end


//assign led[0] = audio_state[0];
assign led[0] = !audio_samples_empty;
//assign led[0] = !filer_waitrequest;
//assign led[0] = audio_state[0];

assign led[2] = gamepad_on;
//assign led[0] = (sd_hps_op_export == 5) ? 1'b1 : 1'b0;
assign rom_textAddr = (rom_textAddr_de1 == 0) ? rom_textAddr_de1 : (rom_textAddr_de1 - 1);

assign sdctrl_cmd = sdctrl_cmd_value;
assign sdctrl_arg1 = sdctrl_arg1_value;
assign sdctrl_reqId = sdctrl_reqId_value;

//assign ram_wren = (init_step == 1)? 1 :0;
//assign ram_data = 8'd65;//écrit la lettre A

endmodule