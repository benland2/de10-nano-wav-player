module sdcard_controller #(parameter FILESIZE_WIDTH=25)(
	input sd_clk,
	input [15:0] hOp,
	input [31:0] hData,
	input [15:0] hReqId,//Permet de déclencher les updates
	
	input [7:0] sys_cmd,//Sert à recevoir des commandes depuis la boucle Audio dans le TOP
	input [FILESIZE_WIDTH:0] sys_arg1,//Sert à recevoir des arguments pour lire une pos sur la carte SD
	input [3:0] sys_reqId,//Permet de déclencher les nouvelles requetes
	
	input [31:0] fGamepad_evt,
	input [31:0] fDebug_input,
	
	output [7:0] fCmd, // Commande pour lire la carte SD : 1 => ls
	output [31:0] fArg1, // Commande pour lire la carte SD : 1 => ls
	output [31:0] fDebug_info,
	output sdLed
);
	parameter WAV_SAMPLE_DATA = 44100;
	
	reg [15:0] num_files;
	reg [31:0] fDebug_info_value;
	reg [15:0] cmd_value;
	//reg [3:0] ptr_string;
	//reg [16*8:0] filename;
	reg led_value;
	reg [15:0] reqId_prev;
	reg [31:0] fArg1_value;
	//reg [3:0] sys_cmd_prev;
	reg [3:0] sys_reqId_prev;
	
	initial begin
		num_files = 0;
		fDebug_info_value = 0;
		led_value = 0;
		reqId_prev = 0;
		cmd_value = 0;
		//sys_cmd_prev = 0;
		sys_reqId_prev = 0;
	end
	
	//assign cmd = (sdInstruction == 0)? 16'h1 :  16'h2;
	assign fDebug_info = fDebug_info_value;
	assign fCmd = cmd_value;
	assign sdLed = led_value;
	assign fArg1 = fArg1_value;
	
	////always_comb begin
	always @ (posedge(sd_clk)) begin
		//led_value <= ~led_value;
		//led_value <= hReqId[0];
		if( sys_reqId_prev != sys_reqId) begin // En priorité on fait passer les commande du système
			//sys_cmd_prev <= sys_cmd;
			sys_reqId_prev <= sys_reqId;
			
			cmd_value <= {8'b0, sys_cmd};
			//fDebug_info_value <= sys_cmd;
			////fDebug_info_value <= hData;
			fDebug_info_value <= sys_reqId;
			
			if(sys_cmd == 6'd1 || sys_cmd == 6'd3 || sys_cmd == 6'd31 || sys_cmd == 6'd34 || sys_cmd == 6'd4 || sys_cmd == 6'd2 || sys_cmd == 6'd6 || sys_cmd == 6'd9 || sys_cmd == 6'd10) begin
				fArg1_value <= {7'b0,sys_arg1};
				
				if(sys_cmd == 6'd3 || sys_cmd == 6'd31 || sys_cmd == 6'd9 || sys_cmd == 6'd1) fDebug_info_value <= fDebug_input;
			end
		end
		else begin
			
			if (reqId_prev[1:0] != hReqId[1:0]) begin
				reqId_prev <= hReqId;
				//led_value <= hReqId[0];
			
				case (hOp[3:0]) 
					4'd1 : begin //SDcard is ready
						if(cmd_value == 16'd5) cmd_value <= 0;//Re-initialize the fpga command
						//cmd_value <= 16'h1; // Request to get numbers files
						fDebug_info_value <= 99;
						num_files <= 0;
						led_value <= 1;
					end
					4'd2 : begin // Num files received
						//cmd_value <= 16'h2; // Request to get names of files
						//num_files <= hData;
						fDebug_info_value <= hData;
					end
					4'd3 : begin // Return a char of name at pos ptr_string
						//filename[hOp[6:3]*8] <= hData[7:0];
						fDebug_info_value <= hData[7:0];
						
						//cmd_value <= 16'h2; // Request to get names of files
					end
					4'd4 : begin // Return name completed
						fDebug_info_value <= num_files;
						//cmd_value <= 16'h3; // Request to open file and start read at pos arg1 (Mode test)
						//fArg1_value <= 31'h0;
						
					end
					4'd5 : begin // Return value at pos requested
						//fDebug_info_value <= hData;
						//fDebug_info_value <= sys_reqId;
						fDebug_info_value <= fDebug_input;
						
						//Cette partie sera à gérer avec AUDIO_IF
						/*if (fArg1_value >= WAV_SAMPLE_DATA) begin
							cmd_value <= 16'h4; // Request to close file
						end 
						else begin
							cmd_value <= 16'h3; // Request to continue read file (Mode test)
							//fArg1_value <= fArg1_value + 1;
							fArg1_value <= {10'b0,sys_arg1};
						end*/
					end
					4'd6 : begin // Confirm reading ended
						fDebug_info_value <= hReqId;
						//cmd_value <= 16'h5; // Stop all
					end
					4'd7 : begin // Confirm reading ended
						fDebug_info_value <= fGamepad_evt;
						//cmd_value <= 16'h5; // Stop all
					end
					4'd8 : begin // Return number of audio samples
						fDebug_info_value <= hData;
					end
					4'd9 : begin // Return number of audio samples
						fDebug_info_value <= hData;
					end
					4'd10 : begin // Return number of audio samples
						fDebug_info_value <= hData;
					end
					default : begin
						cmd_value <= 16'd0;//Do nothing
						//fDebug_info_value <= num_files;
						//fDebug_info_value <= hData;
						//fDebug_info_value <= fGamepad_evt;
						fDebug_info_value <= 98;
					end
				endcase
			end
		end
		
	end
	

endmodule