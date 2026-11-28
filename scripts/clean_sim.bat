@echo off
rem clean_sim.bat
rem Removes Vivado simulator output (xvlog / xelab / xsim) from the project root
rem and from sim\. Only deletes generated files; never touches source files.
rem
rem Usage: double-click it, or run  scripts\clean_sim.bat

call :clean "%~dp0.."
call :clean "%~dp0..\sim"
echo Simulation clean-up done.
exit /b 0

:clean
pushd "%~1" 2>nul || exit /b 0
for %%D in (xsim.dir .Xil) do if exist "%%D\" (
    rmdir /s /q "%%D"
    echo removed %%~fD
)
for %%F in (*.log *.jou *.pb *.wdb *.vcd *.str webtalk* hs_err_pid*) do (
    del /f /q "%%F"
    echo removed %%~fF
)
popd
exit /b 0
