
module soc_system (
	clk_clk,
	farg1_export,
	fcmd_export,
	fdebug_info_export,
	gamepad_evt_readdata,
	gamepad_evt_read,
	gamepad_evt_waitrequest,
	hdata_export,
	hop_export,
	hps_0_h2f_reset_reset_n,
	hreqid_export,
	memory_mem_a,
	memory_mem_ba,
	memory_mem_ck,
	memory_mem_ck_n,
	memory_mem_cke,
	memory_mem_cs_n,
	memory_mem_ras_n,
	memory_mem_cas_n,
	memory_mem_we_n,
	memory_mem_reset_n,
	memory_mem_dq,
	memory_mem_dqs,
	memory_mem_dqs_n,
	memory_mem_odt,
	memory_mem_dm,
	memory_oct_rzqin,
	reset_reset_n,
	file_data_readdata,
	file_data_read,
	file_data_waitrequest);	

	input		clk_clk;
	input	[31:0]	farg1_export;
	input	[15:0]	fcmd_export;
	input	[31:0]	fdebug_info_export;
	output	[31:0]	gamepad_evt_readdata;
	input		gamepad_evt_read;
	output		gamepad_evt_waitrequest;
	output	[31:0]	hdata_export;
	output	[15:0]	hop_export;
	output		hps_0_h2f_reset_reset_n;
	output	[15:0]	hreqid_export;
	output	[12:0]	memory_mem_a;
	output	[2:0]	memory_mem_ba;
	output		memory_mem_ck;
	output		memory_mem_ck_n;
	output		memory_mem_cke;
	output		memory_mem_cs_n;
	output		memory_mem_ras_n;
	output		memory_mem_cas_n;
	output		memory_mem_we_n;
	output		memory_mem_reset_n;
	inout	[7:0]	memory_mem_dq;
	inout		memory_mem_dqs;
	inout		memory_mem_dqs_n;
	output		memory_mem_odt;
	output		memory_mem_dm;
	input		memory_oct_rzqin;
	input		reset_reset_n;
	output	[31:0]	file_data_readdata;
	input		file_data_read;
	output		file_data_waitrequest;
endmodule
