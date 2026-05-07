# RK3588-Alientek-AAOS

## 特性

<!-- TODO: 这一个章节是最后需要做的系统安全选项 -->
## 量产安全待办清单

> 以下清单按软件层级分类，覆盖完整车机量产所需的安全加固项。
> 标记说明：`[ ]` 未完成 · `[x]` 已在 V-gatron_defconfig / 当前代码中启用 · `[-]` 不适用/已确认跳过

---

### 一、U-Boot / Bootloader 层

> U-Boot 负责启动链信任根、AVB 校验、A/B slot 选择、调试接口封锁。

**已在 `V-gatron_defconfig` 中启用：**

- [x] **AVB 校验基础设施**：`CONFIG_ANDROID_AVB=y`、`CONFIG_AVB_LIBAVB=y`、`CONFIG_AVB_LIBAVB_AB=y` — U-Boot 启动时对 boot/vbmeta 分区做 AVB 签名校验
- [x] **A/B slot 选择（SPL）**：`CONFIG_SPL_AB=y` — SPL 阶段读取 A/B slot 元数据，自动选择有效启动槽
- [x] **rollback 计数器存储**：`CONFIG_OPTEE_ALWAYS_USE_SECURITY_PARTITION=y` — 通过 OP-TEE 将 AVB rollback index 存入 security 分区
- [x] **AVB ATX 扩展**：`CONFIG_AVB_LIBAVB_ATX=y` — 支持 Android Things Extension 密钥管理（设备唯一密钥绑定）
- [x] **RSA 验签算法**：`CONFIG_RSA=y`、`CONFIG_SPL_RSA=y` — FIT/AVB 签名验证所需的 RSA 4096-bit 支持
- [x] **硬件加密加速**：`CONFIG_ROCKCHIP_CRYPTO_V2=y`、`CONFIG_FIT_HW_CRYPTO=y` — AES/SHA/RSA 由硬件加速，防时序旁路攻击
- [x] **boot.img 整体哈希**：`CONFIG_ANDROID_BOOT_IMAGE_HASH=y` — 对 boot.img 整体计算哈希并校验
- [x] **硬件 TRNG 播种**：`CONFIG_RNG_ROCKCHIP=y`、`CONFIG_BOARD_RNG_SEED=y` — 用硬件真随机数为 U-Boot 随机数库播种，防伪随机数预测
- [x] **OTP 安全读取**：`CONFIG_ROCKCHIP_OTP=y`、`CONFIG_SPL_ROCKCHIP_SECURE_OTP=y` — 读取 SoC 唯一 ID 及安全 OTP 数据
- [x] **pstore 崩溃日志**：`CONFIG_PSTORE=y` — U-Boot 侧启用持久化崩溃日志存储
- [x] **Minidump**：`CONFIG_ROCKCHIP_MINIDUMP=y` — 崩溃时收集最小寄存器/内存快照

**待完成：**

- [ ] **FIT 镜像签名校验**：启用 `CONFIG_FIT_SIGNATURE=y` — RSA 算法已就位，还需注入量产公钥并对 `uboot.img` 做离线签名
- [ ] **Secure Boot 使能**：向 OTP 烧录 RSA 根密钥，启用 Rockchip 硬件 Secure Boot 校验链（ROM → SPL → ATF → U-Boot）
- [ ] **AVB 签名密钥烧录**：将量产 AVB 公钥（`avb_pk.bin`）写入 OTP / security 分区，替换当前的开发测试密钥
- [ ] **vbmeta 正式签名**：构建服务器用私钥对 `boot_a`/`vbmeta_a` 签名，当前为 UNLOCKED 测试模式
- [ ] **Anti-Rollback 激活**：为每个固件分区配置 AVB rollback index 并写入 OTP，禁止刷入旧版本
- [ ] **ATF/OP-TEE 版本锁定**：rkbin 中 BL31/OP-TEE 随量产版本固定，禁止独立降级，升级走 OTA 流程
- [ ] **A/B 主体管理**（视 Android 分区布局而定）：若 Android 侧配套完整 A/B 分区，启用 `CONFIG_ANDROID_AB=y`，由 U-Boot 主体写回 `tries_remaining` / 标记 `successful`
- [ ] **Bootloader 锁定**：生产烧录完成后执行 `fastboot oem lock`，禁止任意 `fastboot flash`
- [ ] **U-Boot shell 关闭**：生产 defconfig 设置 `CONFIG_BOOTDELAY=-2`（当前为 `0`，调试阶段），量产禁止打断启动进入 shell
- [ ] **JTAG 禁用**：通过 OTP 熔丝或 GRF 寄存器永久关闭 JTAG 调试口

---

### 二、Android Kernel 层

> 内核负责运行时分区完整性、加密、内核自身防护和崩溃取证。

- [ ] **dm-verity 启用**：`system_a`/`vendor_a` 挂载时开启 dm-verity，内核逐块校验哈希树（`CONFIG_DM_VERITY=y`）
- [ ] **dm-verity 错误策略**：设置为 `restart`（校验失败自动重启），禁止 `logging` 模式进入生产
- [ ] **FBE 文件加密**：启用 File-Based Encryption（`CONFIG_FS_ENCRYPTION=y`），`/data` 密钥由 KeyMint TA 管理
- [ ] **内核 lockdown 模式**：`CONFIG_SECURITY_LOCKDOWN_LSM=y`，阻止 `/dev/mem`、`kprobes`、`/proc/kcore` 等内核旁路
- [ ] **串口 console 关闭**：量产内核命令行去掉 `earlycon` / `console=ttyFIQ0`（由 U-Boot bootargs 传入，需量产 defconfig 配合）
- [ ] **pstore/Ramoops DTS 节点**：内核 DTS 配置 `ramoops` 节点，与 U-Boot `CONFIG_PSTORE=y` 配合，预留物理内存区域写入崩溃日志
- [ ] **网络隔离**：iptables/nftables 规则隔离车控总线（CAN/LIN）与信息娱乐网络，防跨域攻击

---

### 三、Android Framework / 系统配置层

> Android 侧负责 A/B OTA 流程、访问控制、密钥 Provisioning、运行时监控和网络安全。

**A/B 分区与 OTA**

- [ ] **A/B 分区布局**：Android 构建启用 `AB_OTA_UPDATER=true`，分区表划分 `system_a/b`、`vendor_a/b`、`boot_a/b`、`vbmeta_a/b` 等 slot
- [ ] **bootctl HAL**：实现 `IBootControl` HAL，`update_engine` 通过它切换 slot、写回 `boot_success`
- [ ] **update_engine 集成**：Android OTA 客户端写 inactive slot，payload 签名校验通过后切换，失败自动回退
- [ ] **OTA payload 签名**：`update_engine` 校验 `payload.bin` 的 RSA 签名，禁止安装未签名包
- [ ] **回滚保护联动**：OTA 成功 boot 后，`update_engine` 递增 AVB rollback index 并写入 OTP，防止降级
- [ ] **OTA 传输 TLS 1.3**：OTA 服务器通信强制 TLS 1.3，Certificate Pinning 防中间人

**访问控制**

- [ ] **关闭 ADB**：`ro.adb.secure=1` + `ro.debuggable=0`，禁止 ADB 未授权连接
- [ ] **SELinux Enforcing**：`BOARD_SEPOLICY_DIRS` 策略覆盖所有自研服务，禁止 `permissive` 域进入生产
- [ ] **去除 root / su**：量产镜像不包含 `su` 二进制，`adbd` 无法提权
- [ ] **最小权限原则**：自研 HAL/服务只申请必要的 SELinux 类型和 Android 权限，禁止 `domain=priv_app` 等过宽标签
- [ ] **只读 `system`/`vendor`**：分区以 `ro` 方式挂载，禁止 `adb remount`

**密钥与安全存储**

- [ ] **KeyMaster/KeyMint TA**：OP-TEE 侧 KeyMaster TA 编译并部署，作为 Android 密钥库的硬件后端
- [ ] **设备唯一密钥（DevKey）工厂烧录**：产线烧录唯一对称密钥到 OTP，不可读出、不可导出
- [ ] **Widevine L1 Provisioning**：通过 Widevine Provisioning Server 写入设备证书到 OP-TEE 安全存储，支持硬件级 DRM
- [ ] **HDCP 2.x 密钥**：外接显示场景需 Provisioning HDCP 密钥，由 OP-TEE TA 保护
- [ ] **TLS 证书存储**：系统 CA 证书存入只读分区，不可被用户或 OTA 随意替换

**运行时监控**

- [ ] **Minidump 上报服务**：Android 侧对接 Minidump 上报流程，与 `CONFIG_ROCKCHIP_MINIDUMP=y` 配合完成端到端崩溃分析
- [ ] **Measured Boot / Attestation**：OP-TEE 记录每级固件哈希，支持远程设备合规性证明（可选，视车厂要求）
- [ ] **安全审计日志**：OTA 安装、AVB 状态变更、密钥 Provisioning 等敏感操作写入防篡改日志分区

**网络与通信**

- [ ] **蓝牙/Wi-Fi 攻击面收敛**：关闭不必要的蓝牙 Profile 和 Wi-Fi 功能，禁用 WPS

---

<!-- TODO: 目录结构最后要重构 -->
## 目录结构

```text
.
├── .editorconfig                          # 编辑器通用格式规范（缩进/换行/编码）
├── .env.example                           # 环境变量模板（GH_TOKEN / BGM_TOKEN）
├── .gitignore                             # Git 忽略规则
├── .github/                               # GitHub 仓库配置与文档
│   ├── dependabot.yml                     # Dependabot 自动依赖更新配置
│   ├── docs/                              # 项目文档
│   │   ├── ci/                            # CI 文档
│   │   │   └── ci-checks.md               # CI 检查规则说明
│   │   ├── hooks/                         # Git Hook 文档
│   │   │   └── git-guard.md               # git-guard PreToolUse hook 说明
│   │   ├── mcp/                           # MCP 工具文档
│   │   │   └── github-tools.md            # GitHub MCP Server 工具清单（26 个工具）
│   │   └── settings/                      # 仓库 Settings 配置操作记录
│   ├── hooks/                             # Git Hook 脚本
│   │   ├── git-guard.json                 # Claude Code PreToolUse hook 注册配置
│   │   └── scripts/                       # Hook 脚本目录
│   │       └── git-guard.sh               # git/gh 危险写操作拦截脚本
│   ├── instructions/                      # GitHub Copilot 指令文件
│   │   └── git-workflow.instructions.md   # AI git 操作行为规范（授权要求/分支/提交/PR）
│   ├── ISSUE_TEMPLATE/                    # Issue 模板
│   │   ├── bug_report_en.md               # Bug 报告模板（英文）
│   │   ├── bug_report_zh.md               # Bug 报告模板（中文）
│   │   ├── config.yml                     # Issue 模板配置（禁用空白 Issue）
│   │   ├── feature_request_en.md          # 功能请求模板（英文）
│   │   └── feature_request_zh.md          # 功能请求模板（中文）
│   ├── PULL_REQUEST_TEMPLATE.md           # PR 描述模板
│   └── workflows/                         # GitHub Actions 工作流
│       └── lint.yml                       # CI Lint 工作流
├── .vscode/                               # VS Code 工作区配置
│   ├── mcp.json                           # MCP Server 配置（GitHub MCP）
│   └── settings.json                      # 工作区设置（工具审批策略 / cSpell 词典）
├── .lintrc/                               # 各工具 Lint 配置
│   ├── docs/                              # 文档相关
│   │   └── markdown/                      # Markdown 相关
│   │       └── .markdownlint.json         # Markdown lint 规则
│   ├── frontend/                          # 前端/TypeScript 相关
│   │   ├── knip.json                      # Knip 未使用导出检查配置
│   │   ├── prettier/                      # Prettier 配置
│   │   │   └── .prettierrc                # Prettier 格式化配置
│   │   └── typescript/                    # TypeScript 相关
│   │       ├── .eslintrc-ts.json          # ESLint TypeScript 规则
│   │       └── tsconfig-lint.json         # ESLint 专用 tsconfig
│   ├── general/                           # 通用规范
│   │   ├── .ls-lint.yml                   # 文件命名规范检查
│   │   ├── .yamllint.yml                  # YAML lint 规则
│   │   └── cspell.json                    # 拼写检查词典配置
│   ├── git/                               # Git 提交规范
│   │   └── .commitlintrc.cjs              # Commit message 规范
│   └── security/                          # 安全扫描
│       └── .gitleaks.toml                 # 密钥泄露扫描规则
├── CODE_OF_CONDUCT.md                     # 行为准则
├── CONTRIBUTING.md                        # 贡献指南
├── LICENSE                                # GPL-3.0 许可证
├── README.md                              # 本文件
└── SECURITY.md                            # 安全漏洞披露政策
```

## 本地配置

1. 复制 Token 模板文件：

   ```bash
   cp .env.example .env
   ```

2. 编辑 `.env`，填入对应 Token：

   ```ini
   # GitHub CLI 操作（PR / Issue / Release 等）
   GH_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxx
   ```

   > - `GH_TOKEN`：GitHub → Settings → Developer settings → Personal access tokens

3. 加载环境变量（每次新开终端执行一次）：

   ```bash
   export GH_TOKEN="$(grep '^GH_TOKEN=' .env | cut -d= -f2- | tr -d '\r')"
   ```

4. 验证配置：

   ```bash
   gh auth status
   ```

## 获取源码

克隆仓库时加上 `--recurse-submodules` 可一并拉取以下子模块源码：

| 子模块 | 本地路径 | 说明 |
| --- | --- | --- |
| [Rockchip-RK3588-u-boot](https://github.com/VaillerTeeter/Rockchip-RK3588-u-boot) | `Android-13/u-boot` | U-Boot 源码 |
| [Rockchip-RK3588-rkbin](https://github.com/VaillerTeeter/Rockchip-RK3588-rkbin) | `Android-13/rkbin` | Rockchip 固件 bin 文件 |

```bash
git clone --recurse-submodules https://github.com/VaillerTeeter/RK3588-Alientek-AAOS
```

若已克隆但未初始化子模块，执行：

```bash
git submodule update --init --recursive
```

## 编译工具链

U-Boot 构建脚本硬编码了 **gcc-linaro-6.3.1** 工具链路径，不能用系统自带的 GCC 替代。

工具链压缩包已内置于本仓库，执行 `apply-patches.sh` 时会自动解压到 Android 工程的对应目录：

```text
Android-13/
├── u-boot/                  # U-Boot 源码（submodule）
├── rkbin/                   # Rockchip bin 固件（submodule）
└── prebuilts/
    └── gcc/
        └── linux-x86/
            ├── arm/
            │   ├── gcc-linaro-6.3.1-2017.05-x86_64_arm-linux-gnueabihf.tar.xz   # 32 位压缩包（内置）
            │   └── gcc-linaro-6.3.1-2017.05-x86_64_arm-linux-gnueabihf/          # 解压后目录（脚本自动生成）
            └── aarch64/
                ├── gcc-linaro-6.3.1-2017.05-x86_64_aarch64-linux-gnu.tar.xz     # 64 位压缩包（内置）
                └── gcc-linaro-6.3.1-2017.05-x86_64_aarch64-linux-gnu/            # 解压后目录（脚本自动生成）
```

## 平台定义

### ATF / OPTEE

U-Boot 充电待机要求的 ATF/OPTEE 最低版本：

| 芯片 | 最低版本号 |
| --- | --- |
| RK3588 | `rk3588_bl31_v1.24.elf` |

### Clock

CPU 提频功能支持列表：

| 芯片 | 支持情况 | 提频处理项 |
| --- | --- | --- |
| RK3588 | N/A | N/A |

### Defconfig

各平台的 defconfig 支持情况（以 SDK 发布为准）：

> `[芯片]_defconfig` 或 `[芯片].config` 通常都是全功能版本，其余为特定 feature 版本。

| 芯片 | defconfig | 支持 kernel dtb | 说明 |
| --- | --- | :---: | --- |
| RK3588 | `rk3588_defconfig` | Y | 通用版本 |
| RK3588 | `rk3588-ramboot.config` | Y | 无存储器件（内存启动） |
| RK3588 | `rk3588-sata.config` | Y | 双存储支持 sata 启动 |
| RK3588 | `rk3588-aarch32.config` | Y | 支持 aarch32 模式 |
| RK3588 | `rk3588-ipc.config` | Y | ipc sdk 上使用 |
| RK3588 | `V-gatron_defconfig` | Y | 正点原子 RK3588 开发板定制版（基于 rk3588_defconfig，调试增强） |

#### `V-gatron_defconfig` 配置项详解

按功能模块分类：

**1. 架构与目标板**

| 配置项 | 值 | 说明 |
| --- | --- | --- |
| `CONFIG_ARM` | `y` | 选择 ARM 体系结构（AArch64） |
| `CONFIG_ARCH_ROCKCHIP` | `y` | 启用 Rockchip SoC 平台层代码 |
| `CONFIG_ROCKCHIP_RK3588` | `y` | 指定芯片型号为 RK3588 |
| `CONFIG_TARGET_EVB_RK3588` | `y` | 目标板选择 Rockchip RK3588 EVB 评估板 |
| `CONFIG_DEFAULT_DEVICE_TREE` | `rk3588-evb` | 编译时默认使用 `arch/arm/dts/rk3588-evb.dts` |

**2. SPL 基础支持**

| 配置项 | 值 | 说明 |
| --- | --- | --- |
| `CONFIG_SPL_GPIO_SUPPORT` | `y` | SPL 阶段启用 GPIO 驱动 |
| `CONFIG_SPL_LIBCOMMON_SUPPORT` | `y` | SPL 链接公共库（console/printf 等） |
| `CONFIG_SPL_LIBGENERIC_SUPPORT` | `y` | SPL 链接通用库（string/div 等） |
| `CONFIG_SPL_SERIAL_SUPPORT` | `y` | SPL 阶段启用串口输出 |
| `CONFIG_SPL_DRIVERS_MISC_SUPPORT` | `y` | SPL 链接 misc 驱动 |
| `CONFIG_SPL_LIBDISK_SUPPORT` | `y` | SPL 支持磁盘分区解析 |
| `CONFIG_SPL_SPI_FLASH_SUPPORT` | `y` | SPL 支持从 SPI Flash 启动 |
| `CONFIG_SPL_SPI_SUPPORT` | `y` | SPL 启用 SPI 控制器驱动 |
| `CONFIG_SPL_BOARD_INIT` | `y` | SPL 执行板级自定义初始化钩子 |
| `CONFIG_SPL_SEPARATE_BSS` | `y` | SPL BSS 段独立于 text 段放置 |
| `CONFIG_SPL_MTD_SUPPORT` | `y` | SPL 启用 MTD 子系统 |
| `CONFIG_SPL_ATF` | `y` | SPL 加载并跳转至 ARM Trusted Firmware |
| `CONFIG_SPL_AB` | `y` | SPL 阶段支持读取 A/B slot 元数据 |
| `# CONFIG_SPL_RAW_IMAGE_SUPPORT` | not set | 禁用 SPL 加载裸二进制镜像 |
| `# CONFIG_SPL_LEGACY_IMAGE_SUPPORT` | not set | 禁用 SPL 加载旧式 mkimage 格式 |
| `# CONFIG_SPL_SYS_DCACHE_OFF` | not set | SPL 阶段保持 D-Cache 开启 |

**3. 内存**

| 配置项 | 值 | 说明 |
| --- | --- | --- |
| `CONFIG_SYS_MALLOC_F_LEN` | `0x80000` | SPL 早期（pre-reloc）malloc 内存池大小：512 KiB |

**4. FIT 镜像**

| 配置项 | 值 | 说明 |
| --- | --- | --- |
| `CONFIG_SPL_FIT_GENERATOR` | `arch/arm/mach-rockchip/make_fit_atf.sh` | 生成 FIT its 文件的脚本路径 |
| `CONFIG_ROCKCHIP_FIT_IMAGE` | `y` | 使用 Rockchip 扩展 FIT 镜像格式 |
| `CONFIG_ROCKCHIP_FIT_IMAGE_PACK` | `y` | 调用 Rockchip 脚本自动打包 `uboot.img` |
| `CONFIG_FIT` | `y` | 主 U-Boot 阶段支持解析 FIT 格式 |
| `CONFIG_FIT_IMAGE_POST_PROCESS` | `y` | FIT 加载后执行后处理（校验/解密） |
| `CONFIG_FIT_HW_CRYPTO` | `y` | FIT 后处理使用硬件加密加速 |
| `CONFIG_SPL_LOAD_FIT` | `y` | SPL 从 FIT 镜像中加载 U-Boot/ATF/OP-TEE |
| `CONFIG_SPL_FIT_IMAGE_POST_PROCESS` | `y` | SPL FIT 加载后执行后处理 |
| `CONFIG_SPL_FIT_HW_CRYPTO` | `y` | SPL FIT 后处理使用硬件加密加速 |

**5. Rockchip 平台特性**

| 配置项 | 值 | 说明 |
| --- | --- | --- |
| `CONFIG_ROCKCHIP_HWID_DTB` | `y` | 根据硬件 ID（SARADC 读值）自动选择对应 DTB |
| `CONFIG_ROCKCHIP_VENDOR_PARTITION` | `y` | 支持 vendor-storage 分区（存储板级 calibration/序列号等） |
| `CONFIG_USING_KERNEL_DTB_V2` | `y` | 从 boot/recovery 分区的内核 DTB 叠加板级 overlay（V2 机制） |
| `CONFIG_ROCKCHIP_NEW_IDB` | `y` | 使用新版 IDB（Image Download Block）格式，兼容新版 rkdeveloptool |
| `CONFIG_PSTORE` | `y` | 启用 pstore，将内核 panic/oops 日志写入持久化存储 |
| `CONFIG_ROCKCHIP_MINIDUMP` | `y` | 启用 Minidump：崩溃时收集最小必要寄存器/内存快照 |

**6. 调试串口**

| 配置项 | 值 | 说明 |
| --- | --- | --- |
| `CONFIG_DEBUG_UART` | `y` | 启用早期调试串口（early console） |
| `CONFIG_BAUDRATE` | `1500000` | 串口波特率 1.5 Mbps（Rockchip 标准） |
| `CONFIG_DEBUG_UART_BASE` | `0xFEB50000` | UART2 基地址（RK3588 调试串口） |
| `CONFIG_DEBUG_UART_CLOCK` | `24000000` | 串口时钟源频率 24 MHz（晶振） |
| `CONFIG_DEBUG_UART_SHIFT` | `2` | 寄存器地址步长移位（4 字节对齐） |

**7. Android 启动**

| 配置项 | 值 | 说明 |
| --- | --- | --- |
| `CONFIG_ANDROID_BOOTLOADER` | `y` | 启用 Android bootloader 流程（读取 misc 分区、处理 boot/recovery） |
| `CONFIG_ANDROID_AVB` | `y` | 启用 Android Verified Boot（AVB）镜像校验 |
| `CONFIG_ANDROID_BOOT_IMAGE_HASH` | `y` | 对 boot.img 整体计算哈希并校验 |
| `CONFIG_IMAGE_GZIP` | `y` | 支持解压 gzip 压缩的内核镜像 |

**8. 启动行为**

| 配置项 | 值 | 说明 |
| --- | --- | --- |
| `CONFIG_BOOTDELAY` | `0` | 自动启动倒计时为 0 秒，不等待用户输入 |
| `# CONFIG_SYS_CONSOLE_INFO_QUIET` | not set | 打印 `In/Out/Err: serial@...` 设备绑定信息 |
| `CONFIG_DISPLAY_CPUINFO` | `y` | 打印 CPU 型号和三组核心频率（`print_cpuinfo()` 实现） |

**9. MMC / eMMC**

| 配置项 | 值 | 说明 |
| --- | --- | --- |
| `CONFIG_SYS_MMCSD_RAW_MODE_U_BOOT_USE_PARTITION` | `y` | SPL 按分区号定位 U-Boot 在 MMC 中的位置 |
| `CONFIG_SYS_MMCSD_RAW_MODE_U_BOOT_PARTITION` | `0x1` | U-Boot 存放在 MMC boot0/boot1 分区 |
| `CONFIG_MMC_DW` | `y` | DesignWare Mobile Storage Host 控制器驱动 |
| `CONFIG_MMC_DW_ROCKCHIP` | `y` | Rockchip 对 DW MMC 的平台定制层 |
| `CONFIG_MMC_SDHCI` | `y` | SD Host Controller Interface 标准驱动 |
| `CONFIG_MMC_SDHCI_SDMA` | `y` | SDHCI 使用 SDMA 模式传输 |
| `CONFIG_MMC_SDHCI_ROCKCHIP` | `y` | Rockchip SDHCI 平台驱动（eMMC 5.1 HS400） |

**10. SPI Flash**

| 配置项 | 值 | 说明 |
| --- | --- | --- |
| `CONFIG_SPI_FLASH_SFDP_SUPPORT` | `y` | 通过 SFDP 表自动识别 SPI Flash 参数 |
| `CONFIG_SPI_FLASH` | `y` | SPI Flash 核心框架 |
| `CONFIG_SF_DEFAULT_SPEED` | `80000000` | SPI Flash 默认传输频率 80 MHz |
| `CONFIG_SPI_FLASH_EON` | `y` | 支持旺宏 EON 系列 NOR Flash |
| `CONFIG_SPI_FLASH_GIGADEVICE` | `y` | 支持 GigaDevice 系列 NOR Flash |
| `CONFIG_SPI_FLASH_MACRONIX` | `y` | 支持旺宏 Macronix 系列 NOR Flash |
| `CONFIG_SPI_FLASH_SST` | `y` | 支持 Microchip SST 系列 NOR Flash |
| `CONFIG_SPI_FLASH_WINBOND` | `y` | 支持华邦 Winbond 系列 NOR Flash |
| `CONFIG_SPI_FLASH_XMC` | `y` | 支持武汉新芯 XMC 系列 NOR Flash |
| `CONFIG_SPI_FLASH_XTX` | `y` | 支持芯天下 XTX 系列 NOR Flash |
| `CONFIG_SPI_FLASH_MTD` | `y` | 将 SPI Flash 注册为 MTD 设备 |
| `CONFIG_MTD_SPI_NAND` | `y` | 支持 SPI NAND Flash |

**11. MTD / NAND**

| 配置项 | 值 | 说明 |
| --- | --- | --- |
| `CONFIG_MTD` | `y` | MTD（Memory Technology Device）子系统核心 |
| `CONFIG_MTD_BLK` | `y` | 将 MTD 设备抽象为块设备 |
| `CONFIG_MTD_DEVICE` | `y` | 启用 MTD 设备注册接口 |
| `CONFIG_NAND` | `y` | NAND Flash 支持 |

**12. USB**

| 配置项 | 值 | 说明 |
| --- | --- | --- |
| `CONFIG_USB` | `y` | USB 子系统核心 |
| `CONFIG_USB_XHCI_HCD` | `y` | xHCI 主机控制器（USB 3.x） |
| `CONFIG_USB_XHCI_DWC3` | `y` | DWC3 控制器的 xHCI 前端 |
| `CONFIG_USB_EHCI_HCD` | `y` | EHCI 主机控制器（USB 2.0） |
| `CONFIG_USB_EHCI_GENERIC` | `y` | 通用 DT 绑定的 EHCI 驱动 |
| `CONFIG_USB_OHCI_HCD` | `y` | OHCI 主机控制器（USB 1.1） |
| `CONFIG_USB_OHCI_GENERIC` | `y` | 通用 DT 绑定的 OHCI 驱动 |
| `CONFIG_USB_DWC3` | `y` | DesignWare USB3 控制器核心 |
| `CONFIG_USB_DWC3_GADGET` | `y` | DWC3 Gadget（Device）模式 |
| `CONFIG_USB_DWC3_GENERIC` | `y` | DWC3 通用 DT 绑定 |
| `CONFIG_USB_STORAGE` | `y` | USB Mass Storage 类支持（U 盘） |
| `CONFIG_USB_GADGET` | `y` | USB Gadget 框架（模拟 USB 设备） |
| `CONFIG_USB_GADGET_MANUFACTURER` | `Rockchip` | Gadget 厂商字符串 |
| `CONFIG_USB_GADGET_VENDOR_NUM` | `0x2207` | Rockchip USB Vendor ID |
| `CONFIG_USB_GADGET_PRODUCT_NUM` | `0x350a` | RK3588 USB Product ID |
| `CONFIG_USB_GADGET_DOWNLOAD` | `y` | 支持 USB 下载（dfu/fastboot） |
| `CONFIG_PHY_ROCKCHIP_INNO_USB2` | `y` | Rockchip INNO USB2 PHY 驱动 |
| `CONFIG_PHY_ROCKCHIP_SAMSUNG_HDPTX` | `y` | Samsung HDPTX（USB3/DP combo）PHY |
| `CONFIG_PHY_ROCKCHIP_USBDP` | `y` | Rockchip USB3/DP Combo PHY 驱动 |

**13. Fastboot**

| 配置项 | 值 | 说明 |
| --- | --- | --- |
| `CONFIG_FASTBOOT_BUF_ADDR` | `0xc00800` | Fastboot 下载缓冲区起始地址 |
| `CONFIG_FASTBOOT_BUF_SIZE` | `0x07000000` | Fastboot 下载缓冲区大小：112 MiB |
| `CONFIG_FASTBOOT_FLASH` | `y` | 支持 `fastboot flash` 命令 |
| `CONFIG_FASTBOOT_FLASH_MMC_DEV` | `0` | Fastboot flash 目标设备为 MMC0（eMMC） |

**14. 网络 / 以太网**

| 配置项 | 值 | 说明 |
| --- | --- | --- |
| `CONFIG_DM_ETH` | `y` | Driver Model 以太网框架 |
| `CONFIG_DM_ETH_PHY` | `y` | Driver Model PHY 管理层 |
| `CONFIG_DWC_ETH_QOS` | `y` | DesignWare Ethernet QoS（GMAC）控制器驱动 |
| `CONFIG_GMAC_ROCKCHIP` | `y` | Rockchip GMAC 平台 glue 层 |

**15. 显示**

| 配置项 | 值 | 说明 |
| --- | --- | --- |
| `CONFIG_DM_VIDEO` | `y` | Driver Model 视频/显示框架 |
| `CONFIG_DISPLAY` | `y` | 显示输出总开关 |
| `CONFIG_DRM_ROCKCHIP` | `y` | Rockchip DRM（Direct Rendering Manager）驱动框架 |
| `CONFIG_DRM_ROCKCHIP_DW_HDMI_QP` | `y` | HDMI 2.1（QP 版本）显示输出 |
| `CONFIG_DRM_ROCKCHIP_DW_MIPI_DSI2` | `y` | MIPI DSI2 显示接口 |
| `CONFIG_DRM_ROCKCHIP_DW_DP` | `y` | DisplayPort 1.4 显示接口 |
| `CONFIG_DRM_ROCKCHIP_ANALOGIX_DP` | `y` | eDP（Analogix DP）显示接口 |
| `CONFIG_DRM_ROCKCHIP_SAMSUNG_MIPI_DCPHY` | `y` | Samsung MIPI D-PHY/C-PHY 驱动 |
| `CONFIG_PHY_ROCKCHIP_SAMSUNG_HDPTX_HDMI` | `y` | Samsung HDPTX PHY 的 HDMI 工作模式 |

**16. GPIO / I2C / SPI / PWM / Pinctrl**

| 配置项 | 值 | 说明 |
| --- | --- | --- |
| `CONFIG_GPIO_HOG` | `y` | 支持在 DTS 中声明 GPIO hog（自动控制固定方向引脚） |
| `CONFIG_ROCKCHIP_GPIO` | `y` | Rockchip GPIO 控制器驱动 |
| `CONFIG_ROCKCHIP_GPIO_V2` | `y` | Rockchip GPIO V2 版本（RK3588 使用） |
| `CONFIG_NCA9539_GPIO` | `y` | NCA9539 I2C GPIO 扩展器驱动 |
| `CONFIG_SYS_I2C_ROCKCHIP` | `y` | Rockchip I2C 控制器驱动 |
| `CONFIG_I2C_MUX` | `y` | I2C 多路复用器支持 |
| `CONFIG_SPL_I2C_SUPPORT` | `y` | SPL 阶段启用 I2C（用于读取 PMIC） |
| `CONFIG_ROCKCHIP_SPI` | `y` | Rockchip SPI 控制器驱动 |
| `# CONFIG_ROCKCHIP_SFC` | not set | 板上无 SPI Flash 芯片，禁用 SFC 控制器（避免 SPL 启动时打印无意义的 `unrecognized JEDEC id` 日志） |
| `CONFIG_PWM_ROCKCHIP` | `y` | Rockchip PWM 驱动（背光控制等） |
| `CONFIG_PINCTRL` | `y` | Pinctrl 子系统（引脚复用/驱动能力配置） |
| `CONFIG_SPL_PINCTRL` | `y` | SPL 阶段启用 Pinctrl |

**17. PMIC / 电源 / 充电**

| 配置项 | 值 | 说明 |
| --- | --- | --- |
| `CONFIG_DM_PMIC` | `y` | Driver Model PMIC 框架 |
| `CONFIG_PMIC_SPI_RK8XX` | `y` | RK806/RK808/RK818 系列 PMIC SPI 驱动 |
| `CONFIG_REGULATOR_RK860X` | `y` | RK860x 系列 Buck 稳压器驱动 |
| `CONFIG_REGULATOR_RK8XX` | `y` | RK8XX 系列内部 LDO/Buck 调节器驱动 |
| `CONFIG_REGULATOR_PWM` | `y` | PWM 信号控制的可调稳压器 |
| `CONFIG_DM_REGULATOR_FIXED` | `y` | 固定电压稳压器（DT 静态配置） |
| `CONFIG_DM_REGULATOR_GPIO` | `y` | GPIO 控制使能的稳压器 |
| `CONFIG_DM_FUEL_GAUGE` | `y` | Driver Model 电量计框架 |
| `CONFIG_POWER_FG_CW201X` | `y` | CellWise CW2015 电量计驱动 |
| `CONFIG_POWER_FG_CW221X` | `y` | CellWise CW2217 电量计驱动 |
| `CONFIG_DM_POWER_DELIVERY` | `y` | USB Power Delivery 协议栈框架 |
| `CONFIG_TYPEC_TCPM` | `y` | Type-C 端口管理器（TCPM）核心 |
| `CONFIG_TYPEC_TCPCI` | `y` | TCPCI 标准接口控制器驱动 |
| `CONFIG_TYPEC_HUSB311` | `y` | Hynetek HUSB311 TCPCI 芯片驱动 |
| `CONFIG_TYPEC_FUSB302` | `y` | ON Semi FUSB302 Type-C 控制器驱动 |
| `CONFIG_CHARGER_BQ25700` | `y` | TI BQ25700 充电管理芯片驱动 |
| `CONFIG_CHARGER_BQ25890` | `y` | TI BQ25890 充电管理芯片驱动 |
| `CONFIG_CHARGER_SC8551` | `y` | Southchip SC8551 充电泵驱动 |
| `CONFIG_CHARGER_SGM41542` | `y` | SG Micro SGM41542 充电管理驱动 |
| `CONFIG_DM_CHARGE_DISPLAY` | `y` | 充电时屏幕显示框架 |
| `CONFIG_CHARGE_ANIMATION` | `y` | 充电动画显示（关机充电界面） |

**18. 按键**

| 配置项 | 值 | 说明 |
| --- | --- | --- |
| `CONFIG_DM_KEY` | `y` | Driver Model 按键框架 |
| `CONFIG_RK8XX_PWRKEY` | `y` | RK8XX PMIC 内置电源键驱动 |
| `CONFIG_ADC_KEY` | `y` | ADC 采样按键驱动（音量键/恢复键） |

**19. 时钟 / SCMI**

| 配置项 | 值 | 说明 |
| --- | --- | --- |
| `CONFIG_CLK` | `y` | Driver Model 时钟框架 |
| `CONFIG_SPL_CLK` | `y` | SPL 阶段启用时钟驱动 |
| `CONFIG_CLK_SCMI` | `y` | 通过 SCMI 协议访问 ATF 管理的时钟 |
| `CONFIG_SPL_CLK_SCMI` | `y` | SPL 阶段启用 SCMI 时钟 |
| `CONFIG_SCMI_FIRMWARE` | `y` | SCMI 固件接口（ARM System Control and Management Interface） |
| `CONFIG_SPL_SCMI_FIRMWARE` | `y` | SPL 阶段启用 SCMI 固件接口 |

**20. 加密 / 安全 / OTP**

| 配置项 | 值 | 说明 |
| --- | --- | --- |
| `CONFIG_DM_CRYPTO` | `y` | Driver Model 加密引擎框架 |
| `CONFIG_SPL_DM_CRYPTO` | `y` | SPL 阶段启用加密引擎 |
| `CONFIG_ROCKCHIP_CRYPTO_V2` | `y` | Rockchip Crypto V2 硬件加速驱动（AES/SHA/RSA） |
| `CONFIG_SPL_ROCKCHIP_CRYPTO_V2` | `y` | SPL 阶段启用 Crypto V2 |
| `CONFIG_DM_RNG` | `y` | Driver Model 随机数生成器框架 |
| `CONFIG_RNG_ROCKCHIP` | `y` | Rockchip 硬件 TRNG 驱动 |
| `CONFIG_BOARD_RNG_SEED` | `y` | 用硬件 TRNG 为 U-Boot 随机数库播种 |
| `CONFIG_RSA` | `y` | RSA 公钥加密算法（用于 FIT/AVB 签名验证） |
| `CONFIG_SPL_RSA` | `y` | SPL 阶段启用 RSA |
| `CONFIG_RSA_N_SIZE` | `0x200` | RSA 模数大小：512 字节（4096-bit 密钥） |
| `CONFIG_RSA_E_SIZE` | `0x10` | RSA 公钥指数大小：16 字节 |
| `CONFIG_RSA_C_SIZE` | `0x20` | RSA 计算临时空间大小：32 字节 |
| `CONFIG_ROCKCHIP_OTP` | `y` | Rockchip OTP（一次性可编程）读取驱动 |
| `CONFIG_SPL_ROCKCHIP_SECURE_OTP` | `y` | SPL 阶段读取安全 OTP（存储 SoC 唯一 ID 等） |

**21. OP-TEE / AVB**

| 配置项 | 值 | 说明 |
| --- | --- | --- |
| `CONFIG_OPTEE_CLIENT` | `y` | OP-TEE Client 接口（U-Boot 与 OP-TEE 通信） |
| `CONFIG_OPTEE_V2` | `y` | 使用 OP-TEE v2 协议（SMC 调用接口） |
| `CONFIG_OPTEE_ALWAYS_USE_SECURITY_PARTITION` | `y` | 强制使用 security 分区而非 RPMB |
| `CONFIG_AVB_LIBAVB` | `y` | Google AVB（Android Verified Boot）核心库 |
| `CONFIG_AVB_LIBAVB_AB` | `y` | AVB A/B slot 管理库 |
| `CONFIG_AVB_LIBAVB_ATX` | `y` | AVB Android Things Extension 支持 |
| `CONFIG_AVB_LIBAVB_USER` | `y` | AVB 用户层接口 |
| `CONFIG_RK_AVB_LIBAVB_USER` | `y` | Rockchip AVB 用户层扩展 |

**22. RAM / Reset / Misc**

| 配置项 | 值 | 说明 |
| --- | --- | --- |
| `CONFIG_RAM` | `y` | DDR RAM 初始化驱动框架 |
| `CONFIG_SPL_RAM` | `y` | SPL 阶段 RAM 驱动 |
| `CONFIG_TPL_RAM` | `y` | TPL 阶段 RAM 驱动（预留） |
| `CONFIG_DM_RAMDISK` | `y` | Driver Model Ramdisk 支持 |
| `CONFIG_RAMDISK_RO` | `y` | Ramdisk 只读挂载 |
| `CONFIG_DM_RESET` | `y` | Driver Model 复位控制器框架 |
| `CONFIG_SPL_DM_RESET` | `y` | SPL 阶段启用复位控制器 |
| `CONFIG_SPL_RESET_ROCKCHIP` | `y` | Rockchip SPL 复位控制器驱动 |
| `CONFIG_SYSRESET` | `y` | 系统复位命令支持（`reset` 命令） |
| `CONFIG_MISC` | `y` | Misc 设备框架 |
| `CONFIG_SPL_MISC` | `y` | SPL Misc 框架 |
| `CONFIG_MISC_DECOMPRESS` | `y` | Misc 解压接口 |
| `CONFIG_SPL_MISC_DECOMPRESS` | `y` | SPL Misc 解压接口 |
| `CONFIG_ROCKCHIP_HW_DECOMPRESS` | `y` | Rockchip 硬件解压引擎驱动（DECOM） |
| `CONFIG_SPL_ROCKCHIP_HW_DECOMPRESS` | `y` | SPL 阶段启用硬件解压 |

**23. 设备树 / 寄存器映射**

| 配置项 | 值 | 说明 |
| --- | --- | --- |
| `CONFIG_SPL_OF_CONTROL` | `y` | SPL 从内置 DTB 读取配置（DM 节点） |
| `CONFIG_SPL_DTB_MINIMUM` | `y` | SPL 只内置最小必要节点（减小 SPL 体积） |
| `CONFIG_OF_LIVE` | `y` | 运行时可动态修改的 Live DT（替代 flat FDT） |
| `CONFIG_OF_SPL_REMOVE_PROPS` | `clock-names ...` | SPL DTB 中剔除的属性（减小体积） |
| `CONFIG_OF_U_BOOT_REMOVE_PROPS` | `pinctrl-0 ...` | U-Boot DTB 中剔除的属性 |
| `CONFIG_REGMAP` | `y` | 寄存器映射抽象层 |
| `CONFIG_SPL_REGMAP` | `y` | SPL 阶段启用 regmap |
| `CONFIG_SYSCON` | `y` | 系统控制器（GRF/PMUGRF 等）抽象 |
| `CONFIG_SPL_SYSCON` | `y` | SPL 阶段启用 syscon |
| `# CONFIG_SARADC_ROCKCHIP` | not set | 禁用旧版 SARADC 驱动 |
| `CONFIG_SARADC_ROCKCHIP_V2` | `y` | 启用 V2 版 SARADC 驱动（RK3588 使用） |

**24. 压缩算法**

| 配置项 | 值 | 说明 |
| --- | --- | --- |
| `CONFIG_XBC` | `y` | XBC（Zstd-based）压缩格式支持 |
| `CONFIG_LZ4` | `y` | LZ4 极速解压算法 |
| `CONFIG_LZMA` | `y` | LZMA 高压缩比算法 |

**25. Shell 命令**

| 配置项 | 值 | 说明 |
| --- | --- | --- |
| `CONFIG_CMD_BOOTZ` | `y` | `bootz` 命令（启动 zImage 格式内核） |
| `CONFIG_CMD_DTIMG` | `y` | `dtimg` 命令（操作 Android DTB image） |
| `CONFIG_CMD_ELF` | `y` | `bootelf` 命令（加载运行 ELF 格式程序） |
| `CONFIG_CMD_IMI` | `y` | `iminfo` 命令（查看 mkimage 镜像头信息） |
| `# CONFIG_CMD_IMLS` | not set | 禁用（需并行 NOR Flash CFI 驱动，RK3588 无此硬件） |
| `CONFIG_CMD_XIMG` | `y` | `ximimage` 命令（从 multi 镜像提取子镜像） |
| `CONFIG_CMD_LZMADEC` | `y` | `lzmadec` 命令（手动解压 LZMA） |
| `# CONFIG_CMD_UNZIP` | not set | 禁用（依赖完整 zlib deflate，U-Boot 仅有 inflate） |
| `CONFIG_CMD_FLASH` | `y` | `flinfo`/`erase` 命令（并行 NOR Flash 操作，RK3588 无此硬件，保留备用） |
| `CONFIG_CMD_FPGA` | `y` | `fpga` 命令（FPGA 配置加载） |
| `CONFIG_CMD_GPIO` | `y` | `gpio` 命令（读写 GPIO） |
| `CONFIG_CMD_GPT` | `y` | `gpt` 命令（操作 GPT 分区表） |
| `CONFIG_CMD_LOADB` | `y` | `loadb` 命令（串口 Kermit 协议下载） |
| `CONFIG_CMD_LOADS` | `y` | `loads` 命令（串口 S-record 格式下载） |
| `CONFIG_CMD_BOOT_ANDROID` | `y` | `bootrkp` 命令（启动 Android 镜像） |
| `CONFIG_CMD_MMC` | `y` | `mmc` 命令（操作 MMC/eMMC） |
| `CONFIG_CMD_SF` | `y` | `sf` 命令（操作 SPI Flash） |
| `CONFIG_CMD_SPI` | `y` | `sspi` 命令（SPI 原始传输） |
| `CONFIG_CMD_USB` | `y` | `usb` 命令（USB 主机操作） |
| `CONFIG_CMD_USB_MASS_STORAGE` | `y` | `ums` 命令（暴露为 USB 存储设备） |
| `CONFIG_CMD_ITEST` | `y` | `itest` 命令（整数比较测试，boot script 调试） |
| `CONFIG_CMD_SETEXPR` | `y` | `setexpr` 命令（环境变量数学/字符串运算） |
| `CONFIG_CMD_TFTPPUT` | `y` | `tftpput` 命令（向 TFTP 服务器上传文件） |
| `CONFIG_CMD_TFTP_BOOTM` | `y` | 从 TFTP 下载并启动内核 |
| `CONFIG_CMD_TFTP_FLASH` | `y` | 从 TFTP 下载并写入 Flash |
| `CONFIG_CMD_MISC` | `y` | `sleep`/`base` 等杂项命令 |
| `CONFIG_CMD_MTD_BLK` | `y` | `mtd` 块设备操作命令 |

**26. 分区**

| 配置项 | 值 | 说明 |
| --- | --- | --- |
| `# CONFIG_SPL_DOS_PARTITION` | not set | SPL 不解析 DOS/MBR 分区表 |
| `# CONFIG_ISO_PARTITION` | not set | 不支持 ISO9660 分区 |
| `CONFIG_EFI_PARTITION_ENTRIES_NUMBERS` | `64` | GPT 最大分区条目数（Android 通常 20 余个） |

**27. 杂项**

| 配置项 | 值 | 说明 |
| --- | --- | --- |
| `CONFIG_USE_TINY_PRINTF` | `y` | 使用轻量级 printf 实现（减小体积） |
| `CONFIG_LIB_RAND` | `y` | 软件随机数库 |
| `CONFIG_SPL_TINY_MEMSET` | `y` | SPL 使用简化版 memset（减小体积） |
| `CONFIG_ERRNO_STR` | `y` | 启用 errno 转字符串函数（调试用） |
| `# CONFIG_EFI_LOADER` | not set | 不支持 EFI 应用加载器（Android 不需要） |
| `# CONFIG_NET_TFTP_VARS` | not set | 不使用 TFTP 环境变量自动设置 |

**28. Android A/B**

> `rk3588_defconfig` 只在 SPL 阶段支持 A/B（`CONFIG_SPL_AB=y`，已列于第 2 节），U-Boot 主体不介入 A/B 管理。

| 配置项 | 值 | 说明 |
| --- | --- | --- |
| `CONFIG_SPL_AB` | `y` | SPL 阶段读取 A/B slot metadata，选择启动槽（见第 2 节） |
| `# CONFIG_ANDROID_AB` | not set | U-Boot 主体不介入 A/B，需配套完整 A/B 分区的 Android 才能启用 |
| `# CONFIG_CMD_ANDROID_AB_SELECT` | not set | 禁用 `ab_select` 交互命令（由代码自动处理，不需要手动命令） |

### DFU

DFU 功能支持列表：

| 芯片 | defconfig |
| --- | --- |
| RK3588 | `rk3568-dfu.config` |

### Optee

Optee client 接口在各平台的适用性：

| API | RK3588 |
| --- | :---: |
| `trusty_read_vbootkey_hash` | √ |
| `trusty_write_vbootkey_hash` | √ |
| `trusty_read_vbootkey_enable_flag` | √ |
| `trusty_write_oem_otp_key` | √ |
| `trusty_oem_otp_key_is_written` | √ |
| `trusty_set_oem_hr_otp_read_lock` | √ |
| `trusty_oem_otp_key_cipher` | √ |

## 开发工作流

### 补丁工作流

本仓库通过 `apply-patches.sh` / `clean-patches.sh` 将定制代码注入已有的 Android 13 工程目录（`repo sync` 拉下来的原始 AOSP 工程），无需 fork 整个 Android 工程。

#### 补丁内容

`apply-patches.sh` 按顺序执行以下 4 步：

| 步骤 | 操作 | 说明 |
| :---: | --- | --- |
| 1 | 复制 `init-RK3588.sh` | 编译环境初始化脚本，包含源码修复和 `lunch` 目标设置 |
| 2 | 复制 `Android-13/u-boot/` | 定制 U-Boot 源码，覆盖 Android 工程中的同名目录 |
| 3 | 复制 `Android-13/rkbin/` | Rockchip 固件 bin 文件（ATF/OP-TEE），U-Boot 打包依赖 |
| 4 | 解压 GCC 工具链 | 将 `gcc-linaro-6.3.1` 工具链解压到 `prebuilts/gcc/linux-x86/` |

> **冲突保护**：脚本启动时会检测目标目录下是否已存在上述文件/目录，若存在则**拒绝执行**并提示先执行 `repo sync` 恢复干净状态，防止意外覆盖工程中已有的修改。

#### 使用流程

```bash
# 1. 合入补丁（ANDROID_ROOT 为 Android 13 工程根目录）
bash apply-patches.sh /path/to/android13

# 2. 初始化编译环境
cd /path/to/android13
source init-RK3588.sh

# 3. 清理补丁（恢复 Android 工程到 repo sync 状态）
bash clean-patches.sh /path/to/android13
```

#### 刷机后进入 Recovery 的处理

刷完固件后如果系统循环进入 Recovery，通常是 `misc` 分区残留了 `recovery` 启动原因（由刷机工具写入或 misc.img 本身为 recovery 状态）。清除方法：

```bash
# 方法 1：fastboot 清除 misc 分区（推荐）
fastboot erase misc

# 方法 2：在 Recovery shell 中用 adb 清零 misc
adb shell dd if=/dev/zero of=/dev/block/by-name/misc bs=512 count=1
```

清除后重启即可正常进入系统。

### U-Boot SPL 编译注意事项

#### 修改 U-Boot 源码后必须使用自编 SPL 打包

修改任何 U-Boot 源码（包括 DTS、驱动、defconfig、板级初始化代码等）后，**仅靠** `./make.sh V-gatron` **不足以**将改动带入最终的 loader 二进制。

原因：`./make.sh V-gatron` 在打包 loader 时，`boot_merger` 读取的是 `rkbin/RKBOOT/RK3588MINIALL.ini`，其中：

```ini
[LOADER_OPTION]
FlashBoot=bin/rk35/rk3588_spl_v1.13.bin   ← 预编译的 rkbin SPL，与本地源码无关
```

因此无论本地改动是否正确编译，刷入板子的 SPL 始终是 rkbin 中的预编译版本，本地改动对其无效。

> **建议**：只要修改了 U-Boot 源码，且不确定改动是否涉及 SPL（绝大多数情况都涉及），一律使用下方三步流程，确保编译结果与实际运行的 SPL 一致。

#### 正确的编译+打包流程（三步）

```bash
# 第 1 步：完整编译，生成 spl/u-boot-spl.bin
./make.sh V-gatron

# 第 2 步：用自编 SPL 替换 rkbin 中的预编译版本
cp spl/u-boot-spl.bin ../rkbin/bin/rk35/rk3588_spl_v1.13.bin

# 第 3 步：再次完整编译，boot_merger 此时会打包替换后的 SPL
./make.sh V-gatron
```

> **验证方法**：刷机后观察串口开机日志，SPL banner 中的编译时间应与第 1 步的编译时间一致：
>
> ```
> U-Boot SPL board init
> U-Boot SPL 2017.09-gcd17e277b8-250620-dirty #vodka (May 05 2026 - 23:47:38)
> ```
>
> 若时间仍为旧日期（如 `Sep 25 2023`），说明刷入的还是旧 loader，需重新拷贝文件并刷机。

刷机时需同时烧录这两个文件（均需为第 3 步之后生成的版本）：

- `rk3588_spl_loader_v1.19.113.bin` ← 下载 IDB
- `uboot.img`（约 4 MB）← 下载 uboot

## CI 检查说明

> 详细的 CI 检查规则文档已独立维护，请参阅 [ci-checks.md](.github/docs/ci/ci-checks.md)。

## AI Agent 开发说明

本项目主要通过 AI Agent（GitHub Copilot / Claude）进行日常开发和维护工作。

在每次会话开始时，请发送以下提示词，让 AI 优先读取项目规范后再开始工作：

> 开始工作前，先读取 `.github/instructions/` 目录下所有 `.instructions.md` 文件，完全理解其中的规则后再响应。

目前包含的指令文件：

| 文件 | 说明 |
| --- | --- |
| [git-workflow.instructions.md](.github/instructions/git-workflow.instructions.md) | AI git 操作行为规范（授权要求、分支命名、提交规范、PR 工作流） |

## 相关链接

### 本项目

- [RK3588-Alientek-AAOS](https://github.com/VaillerTeeter/RK3588-Alientek-AAOS) — 本仓库
- [模板仓库 Example-of-Github-Repo](https://github.com/VaillerTeeter/Example-of-Github-Repo) — CI 配置、lint 规则、Issue/PR 模板、行为准则等通用配置均继承自此仓库

### 子模块

> 以下仓库均 fork 自 [rockchip-linux](https://github.com/rockchip-linux)，在上游基础上叠加了正点原子 RK3588 板级适配。

- [Rockchip-RK3588-u-boot](https://github.com/VaillerTeeter/Rockchip-RK3588-u-boot) — U-Boot 源码（`Android-13/u-boot`），fork 自 [rockchip-linux/u-boot](https://github.com/rockchip-linux/u-boot)
- [Rockchip-RK3588-rkbin](https://github.com/VaillerTeeter/Rockchip-RK3588-rkbin) — Rockchip 固件 bin 文件，U-Boot 打包依赖（`Android-13/rkbin`），fork 自 [rockchip-linux/rkbin](https://github.com/rockchip-linux/rkbin)
- [Rockchip-RK3588-kernel-5.10](https://github.com/VaillerTeeter/Rockchip-RK3588-kernel-5.10) — Android 13 内核 5.10 源码（`Android-13/rk-kernel-5.10`，shallow），fork 自 [rockchip-linux/kernel](https://github.com/rockchip-linux/kernel)

### 作者

- [GitHub Profile](https://github.com/VaillerTeeter)
