$ErrorActionPreference = 'Stop'
Push-Location $PSScriptRoot
try {
    clang --target=arm-none-eabi -mcpu=cortex-m4 -mthumb -ffreestanding -c demo-app.c -o demo-app.o
    if ($LASTEXITCODE) { throw 'Clang compilation failed' }
    ld.lld -T feather-app.ld demo-app.o -o demo-app.elf
    if ($LASTEXITCODE) { throw 'Link failed' }
    llvm-objcopy -O ihex demo-app.elf application.hex
    if ($LASTEXITCODE) { throw 'Intel HEX export failed' }
} finally {
    Pop-Location
}
