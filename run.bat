echo off
if "%1" == "" goto error

type rt\lib.c %1 rt\_start.c | build\sectorc68k.r
goto end

:error
echo Usage: run [source.c]
:end
