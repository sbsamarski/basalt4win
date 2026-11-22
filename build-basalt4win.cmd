@echo off
rem Configure and build Basalt4Win from the checked-out fork, the same way the live
rem install at D:\Sergey\Basalt was configured: Ninja + MSVC Build Tools + CUDA 13.4.
rem Nothing here touches D:\Sergey\Basalt.
setlocal
call "C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\VC\Auxiliary\Build\vcvars64.bat" || exit /b 1
cd /d D:\Sergey\Basalt4Win
cmake -S . -B build -G Ninja ^
  -DCMAKE_BUILD_TYPE=Release ^
  -DCMAKE_CUDA_COMPILER="C:/Program Files/NVIDIA GPU Computing Toolkit/CUDA/v13.4/bin/nvcc.exe" ^
  -DCMAKE_CUDA_ARCHITECTURES=120 || exit /b 2
cmake --build build -j 12 || exit /b 3
echo BUILD-DONE
