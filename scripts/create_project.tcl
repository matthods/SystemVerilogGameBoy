# create_project.tcl
# Rebuilds the Vivado project from the source files in this repository.
#
# Run it from the Vivado Tcl Console (note the word "source"):
#   source D:/VivadoProjects/SystemVerilogGameBoy/scripts/create_project.tcl
# Or from a terminal:
#   vivado -source scripts/create_project.tcl
#
# The project is created in the vivado/ folder next to scripts/.
# WARNING: -force deletes and recreates that folder every time. Add and
# edit source files in rtl/, sim/, and constraints/ (not inside the Vivado
# GUI), then re-run this script to pick up new files.

# ---- Settings you may want to change -------------------------------------
set proj_name  systemveriloggameboy
set part       xc7a100tcsg324-1      ;# Nexys A7-100T FPGA
set top_module gb_top                ;# top level of the design
set sim_top    tb_bus_decoder        ;# which testbench to simulate

# ---- Find the project root (the folder above scripts/) -------------------
set script_dir [file dirname [file normalize [info script]]]
set root       [file dirname $script_dir]
puts "Project root: $root"

# ---- Close any project that is already open ------------------------------
catch {close_project}

# ---- Create the project --------------------------------------------------
create_project $proj_name [file join $root vivado] -part $part -force

# ---- Design sources: every .sv file in rtl/ and its subfolders -----------
set rtl_files [concat \
  [glob -nocomplain [file join $root rtl *.sv]] \
  [glob -nocomplain [file join $root rtl * *.sv]]]
if {[llength $rtl_files] > 0} {
  add_files -fileset sources_1 -norecurse $rtl_files
}

# ---- ROM memory files (.mem) used by $readmemh ---------------------------
set mem_files [glob -nocomplain [file join $root roms mem *.mem]]
if {[llength $mem_files] > 0} {
  add_files -fileset sources_1 -norecurse $mem_files
}

# ---- Constraints (pin assignments) ---------------------------------------
set xdc_files [glob -nocomplain [file join $root constraints *.xdc]]
if {[llength $xdc_files] > 0} {
  add_files -fileset constrs_1 -norecurse $xdc_files
}

# ---- Simulation sources (testbenches) ------------------------------------
set sim_files [glob -nocomplain [file join $root sim *.sv]]
if {[llength $sim_files] > 0} {
  add_files -fileset sim_1 -norecurse $sim_files
}

# ---- Top-level modules ---------------------------------------------------
set_property top $top_module [get_filesets sources_1]
set_property top $sim_top    [get_filesets sim_1]

# ---- Run simulations to the end instead of stopping at 1000 ns -----------
set_property -name {xsim.simulate.runtime} -value {-all} -objects [get_filesets sim_1]

# ---- Let Vivado work out the compile order (packages before users) -------
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

puts "Added [llength $rtl_files] design file(s), [llength $sim_files] simulation file(s), [llength $xdc_files] constraint file(s)."
puts "Project '$proj_name' created in [file join $root vivado]"

# ---- Optional: build everything from the command line --------------------
# Uncomment these lines to synthesize, implement, and make the bitstream
# (the file that programs the FPGA) without opening the GUI.
#
# launch_runs synth_1 -jobs 4
# wait_on_run synth_1
# launch_runs impl_1 -to_step write_bitstream -jobs 4
# wait_on_run impl_1