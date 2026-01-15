set_global_assignment -entity "pll_filer" -library "lib_pll_filer" -name IP_TOOL_NAME "altera_pll"
set_global_assignment -entity "pll_filer" -library "lib_pll_filer" -name IP_TOOL_VERSION "24.1"
set_global_assignment -entity "pll_filer" -library "lib_pll_filer" -name IP_TOOL_ENV "mwpim"
set_global_assignment -library "lib_pll_filer" -name SPD_FILE [file join $::quartus(sip_path) "pll_filer.spd"]

set_global_assignment -library "lib_pll_filer" -name MISC_FILE [file join $::quartus(sip_path) "pll_filer_sim/pll_filer.vo"]
