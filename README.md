# Intel HEX 分区检查

在烧录前检查固件镜像的实际写入地址。输入 Intel HEX 文件，以及目标分区在该镜像地址空间中的起始地址和大小。需要 MoonBit 和 Node.js 22.3+。

```powershell
moon run cmd/main -- app.hex app 26000 C7000
```

上述命令要求数据落入 `[0x26000, 0xED000)`。起始地址和长度用不带 `0x` 的十六进制数。从这份镜像对应的链接配置取得分区边界。工具会验证 HEX 记录、校验和、扩展地址、EOF 及重叠，并按地址合并相邻的越界区段。每段报告第一个相关数据记录的行号。退出码 0 表示落在分区内，1 表示越界，2 表示输入非法。此检查的结论只涉及镜像地址，设备擦除行为和启动验证由烧录工具与 bootloader 决定。

## nRF52840 演示

`demo/application.hex` 是用 Clang 和 LLVM 构建的最小 Cortex-M4 应用。分区边界取自 [Adafruit nRF52840 S140 v6 链接脚本](https://github.com/adafruit/Adafruit_nRF52_Arduino/blob/master/cores/nRF5/linker/nrf52840_s140_v6.ld)。应用应通过。另一个测试把它和 [Adafruit Bootloader 0.9.2 的发布镜像](https://github.com/adafruit/Adafruit_nRF52_Bootloader/releases/tag/0.9.2) 合并，模拟误选整包镜像。该测试在本地生成合并文件，原厂文件由脚本下载并校验 SHA-256。

```powershell
moon run cmd/main -- demo/application.hex feather-application 26000 C7000
# 复验误选镜像。需要 Python 和 intelhex 2.3.0。
python -m pip install intelhex==2.3.0
./demo/verify-demo.ps1
```

`demo/build-demo.ps1` 可用 Clang、LLD 和 llvm-objcopy 重建应用。`moon test` 验证了分区边界、校验和、重叠记录以及链接配置解析。

## 真实 BLE 应用与链接配置

直接从 GNU ld 链接脚本中读取 MEMORY 区域，减少手填地址。

```powershell
moon run cmd/main -- --linker application.hex application.ld FLASH
moon build
python -m pip install intelhex==2.3.0
python demo/verify-vendor.py
```

复验脚本固定下载 Makerdiary nRF52840-MDK 的 BLE 闪灯和 BLE 心率应用。
每个例子使用同一提交、同一目录的预编译整包 HEX 及链接脚本。
Python IntelHex 从 FLASH 范围提取应用切片，两种应用的切片分别有 27,048 和
114,968 字节。MoonBit 直接读取链接脚本，应用切片均通过，整包均因包含两个
FLASH 范围外区段被拒绝。所有违规地址与 IntelHex 的地址集合对拍。
回执记录来源及 SHA-256，见 `demo/vendor-verification.json`。

MEMORY 的 ORIGIN/LENGTH 支持十进制、十六进制、K/M、括号与加减。
不支持的表达式明确报错。此案例使用板厂提供的预编译固件，并在静态文件上验证。
详细算法、复用基线和 AI 使用情况见 DESIGN.md。

## 批量检查一份烧录计划

```powershell
moon run cmd/main -- --manifest demo/release-plan.json --json
```

JSON 计划由 `partitions` 与 `images` 两个数组组成。分区提供 `name`、`start` 与 `size`，地址与长度使用 `0x` 十六进制字符串。`reserved: true` 保护不应写入的区域。镜像提供 `name`、`file`、`partition`。相对路径以计划文件为基准，只对可信计划执行文件读取。

执行时逐条检查实际占用的地址区间。结果报告三类问题：镜像写出目标分区、写入保留区、两份镜像写入同一片地址。区间以左闭右开表示，空洞和相邻边界不产生碰撞。JSON 带镜像名、精确地址、相关 HEX 行号以及占用字节数，可接入发布门禁。分区重叠、未知字段和无效文件属于输入错误。退出码 0 通过、1 有地址问题、2 输入有误。

```sh
moon build
python demo/verify-vendor.py
python demo/verify-plan.py
python tools/source-lines.py
```

批量复验用同一个厂商固件的系统和应用切片构造无碰撞计划，再误填整包并加入一个合成的保留区字节。完整报告与 Python IntelHex 的实际地址集合对照。该工具用于静态检查，不烧录、不模拟硬件擦除页和启动行为。

在 MoonBit 项目中可用 `parse_manifest`、`parse` 与 `audit_plan` 分别读取计划、解析镜像和执行检查。文件读取留在应用层，核心可在 JS、WasmGC 和 Native 上运行。
