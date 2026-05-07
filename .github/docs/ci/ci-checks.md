# CI 检查说明

本项目有以下 GitHub Actions 工作流：

| 工作流 | 文件 | 说明 |
| --- | --- | --- |
| Lint | [lint.yml](../../../.github/workflows/lint.yml) | 代码质量、格式、安全扫描 |

---

## Lint 工作流

所有 Pull Request 合并到 `master` 前，必须通过 [.github/workflows/lint.yml](../../../.github/workflows/lint.yml) 中定义的所有检查。最终由 `all-checks` job 聚合所有子 job 结果，任意子 job `failure` 或 `cancelled` 均导致门禁失败。

### 触发时机

- **PR 创建 / 更新**：目标分支为 `master` 时自动触发
- **直接 push 到 master**：同样触发检查

### 上游目录排除范围

以下目录属于上游第三方代码，所有 lint job 均跳过：

- `Android-13/rk-kernel-5.10/`
- `Android-13/u-boot/`
- `Android-13/rkbin/`
- `Android-13/prebuilts/`

---

## Markdown Lint

**工具**：[markdownlint-cli2-action@v19](https://github.com/DavidAnson/markdownlint-cli2-action)
**配置**：[.lintrc/docs/markdown/.markdownlint.json](../../../.lintrc/docs/markdown/.markdownlint.json)
**扫描范围**：`**/*.md`（含上游目录）

| 规则 | 状态 | 说明 |
| --- | --- | --- |
| 默认全部规则 | ✅ 启用 | 标题格式、列表缩进、空行等 |
| MD013 行长度 | ⚙️ 放宽 | 最长 400 字符，表格和代码块不限 |
| MD033 内联 HTML | ⚙️ 部分允许 | 仅允许 `!--`（注释标签） |
| MD041 首行必须是 H1 | ❌ 关闭 | 允许文件不以 H1 开头 |

---

## YAML Lint

**工具**：[yamllint](https://yamllint.readthedocs.io/) 1.35.1
**配置**：两阶段扫描

| 阶段 | 配置文件 | 扫描范围 | 行宽限制 |
| --- | --- | --- | --- |
| 第一阶段（宽松） | [.lintrc/general/.yamllint.yml](../../../.lintrc/general/.yamllint.yml) | 所有 `*.yml` / `*.yaml`（排除上游） | 80 字符（`error` 级别） |
| 第二阶段（极严格） | [.lintrc/data-formats/.yamllint.yml](../../../.lintrc/data-formats/.yamllint.yml) | 项目自有数据配置 YAML（排除 `.lintrc/` 和上游） | 80 字符（`error` 级别） |

### 通用配置（两阶段共同规则）

| 规则 | 配置 | 说明 |
| --- | --- | --- |
| 缩进 | 2 空格，`indent-sequences: true` | 检查多行字符串缩进 |
| 空行 | 最多 1 行，文件首尾禁止空行 | |
| 花括号 / 方括号 | 内部无空格 | |
| 冒号 / 逗号 | 规范格式 | |
| 引号 | 必要时使用双引号 | `required: only-when-needed` |

### 第二阶段额外规则

| 规则 | 配置 | 说明 |
| --- | --- | --- |
| `document-start` | 必须有 `---`（`error`） | |
| `document-end` | 禁止 `...` | |
| `new-lines` | Unix LF | |
| `key-ordering` | 字母序排列（`error`） | |
| 尾随空格 | 禁止（`error`） | |

---

## TOML Lint

**工具**：[taplo](https://taplo.tamasfe.dev/) 0.9.3
**配置**：[.lintrc/data-formats/toml/taplo.toml](../../../.lintrc/data-formats/toml/taplo.toml)
**命令**：`taplo fmt --check --config .lintrc/data-formats/toml/taplo.toml`
**扫描范围**：所有 `*.toml`，排除上游目录

| 选项 | 值 | 说明 |
| --- | --- | --- |
| `align_entries` | `true` | key-value 条目纵向对齐 |
| `align_comments` | `true` | 行尾注释垂直对齐 |
| `column_width` | `80` | 最大行宽 80 字符 |
| `compact_arrays` | `true` | 单行数组：`[1, 2]` 而非 `[ 1, 2 ]` |
| `array_trailing_comma` | `true` | 多行数组末尾保留逗号 |
| `indent_string` | 2 空格 | |
| `reorder_keys` | `true` | 同块内 key 按字母序排列 |
| `reorder_arrays` | `true` | 同块内数组值按字母序排列 |
| `trailing_newline` | `true` | 文件末尾必须有换行符 |
| `crlf` | `false` | 强制 LF，禁止 CRLF |

---

## Protobuf Lint

**工具**：[buf](https://buf.build/) 1.47.2
**配置**：[.lintrc/data-formats/protobuf/buf.yaml](../../../.lintrc/data-formats/protobuf/buf.yaml)
**扫描范围**：所有 `*.proto`，排除上游目录；无 proto 文件则自动跳过

| 检查 | 规则集 | 说明 |
| --- | --- | --- |
| 语法 lint | `ALL`（含 `COMMENT_*`、`PACKAGE_VERSION_SUFFIX` 等） | 所有规则，无任何豁免 |
| 破坏性变更 | `WIRE_JSON` | 同时保证 wire 和 JSON 兼容性 |

关键策略：

- `allow_comment_ignores: false`：禁止通过注释绕过 lint 规则
- `enum_zero_value_suffix: _UNSPECIFIED`
- `service_suffix: Service`
- 破坏性变更对比目标：PR base 分支

---

## C/C++ Lint

**工具**：clang-format-18 + clang-tidy-18
**配置**：

- clang-format：[.lintrc/backend/c-cpp/.clang-format](../../../.lintrc/backend/c-cpp/.clang-format)
- clang-tidy（C）：[.lintrc/backend/c-cpp/.clang-tidy](../../../.lintrc/backend/c-cpp/.clang-tidy)
- clang-tidy（C++）：[.lintrc/backend/c-cpp/.clang-tidy-cpp](../../../.lintrc/backend/c-cpp/.clang-tidy-cpp)

**扫描范围**：`*.c` / `*.h` / `*.cpp` / `*.cc` / `*.hpp`，排除上游目录

### clang-format 关键配置

| 选项 | 值 | 说明 |
| --- | --- | --- |
| `BasedOnStyle` | `LLVM` | |
| `IndentWidth` | 4 | |
| `ColumnLimit` | 100 | |
| `BreakBeforeBraces` | `Allman` | 大括号独占一行 |
| `InsertBraces` | `true` | 自动为单语句体插入大括号 |
| `AllowShortBlocksOnASingleLine` | `Never` | 禁止短代码合并为单行 |

### clang-tidy 关键配置（C）

| 选项 | 值 | 说明 |
| --- | --- | --- |
| 启用检查类别 | `android-*`、`bugprone-*`、`cert-*`、`clang-analyzer-*`、`linuxkernel-*`、`misc-*`、`performance-*`、`readability-*` 等 | |
| `WarningsAsErrors` | `"*"` | 所有警告即错误 |
| 函数最大行数 | 200 | |
| 函数最大分支数 | 30 | |
| 最大嵌套深度 | 6 | |

---

## Python Lint

**工具**：ruff 0.9.1 + mypy 1.14.1（Python 3.12 环境）
**配置**：

- ruff：[.lintrc/backend/python/ruff.toml](../../../.lintrc/backend/python/ruff.toml)
- mypy：[.lintrc/backend/python/mypy.ini](../../../.lintrc/backend/python/mypy.ini)

**扫描范围**：所有 `*.py`，排除上游目录

| 检查 | 工具 | 说明 |
| --- | --- | --- |
| lint 静态分析 | `ruff check` | E/W/F/I/N/UP/B/C4/SIM/ANN/S/PT/RET/RUF 等多规则集 |
| 格式检查 | `ruff format --check` | |
| 类型检查 | `mypy` | |

### 关键 ruff 配置

| 选项 | 值 | 说明 |
| --- | --- | --- |
| `target-version` | `py311` | |
| `line-length` | 100 | |

---

## Shell Lint

**工具**：[ShellCheck](https://www.shellcheck.net/) via [ludeeus/action-shellcheck@2.0.0](https://github.com/ludeeus/action-shellcheck)
**配置**：[.lintrc/infrastructure/shell/.shellcheckrc](../../../.lintrc/infrastructure/shell/.shellcheckrc)
**扫描范围**：全仓库 `.sh` 文件，排除上游目录
**严重级别**：`style`（捕获所有级别：style / info / warning / error）

| 配置 | 值 | 说明 |
| --- | --- | --- |
| `shell` | `bash` | 目标 shell 方言（无 shebang 时使用此默认值） |
| `extended-analysis` | `true` | 扩展数据流分析 |
| `external-sources` | `true` | 跟踪 `source` / `.` 语句 |
| `source-path` | `SCRIPTDIR` | 在脚本所在目录查找被 source 的文件 |
| `enable` | `all` | 启用全部可选检查（`require-variable-braces`、`require-double-brackets` 等） |

---

## Go Lint

**工具**：[golangci-lint](https://golangci-lint.run/) v1.62.2（Go 1.22 环境）
**配置**：[.lintrc/backend/go/.golangci.yml](../../../.lintrc/backend/go/.golangci.yml)
**命令**：`golangci-lint run --config .lintrc/backend/go/.golangci.yml --timeout 10m --path-prefix .`

启用的主要 linter 类别：

| 类别 | 代表 linter | 说明 |
| --- | --- | --- |
| 错误处理 | `errcheck`、`errname`、`errorlint`、`goerr113`、`wrapcheck` | 跨包 error 必须 wrap |
| 代码质量 | `cyclop`、`gocognit`、`gocyclo`、`funlen`、`maintidx` | 复杂度与函数长度限制 |
| 安全 | `gosec`、`gochecknoglobals`、`gochecknoinits` | 禁止全局变量和 init() |
| 并发 | `contextcheck`、`containedctx` | context 传递规范 |
| 依赖 | `exhaustruct`、`decorder`、`godox` | 禁止 TODO/FIXME 残留 |

---

## Rust Lint

**工具**：clippy + rustfmt（stable 工具链，含 `clippy` 和 `rustfmt` 组件）
**配置**：

- Clippy：[.lintrc/backend/rust/.clippy.toml](../../../.lintrc/backend/rust/.clippy.toml)（运行前复制到仓库根目录）
- rustfmt：[.lintrc/backend/rust/rustfmt.toml](../../../.lintrc/backend/rust/rustfmt.toml)（运行前复制到仓库根目录）

**扫描范围**：所有 `*.rs`，排除上游目录；无 `.rs` 文件则跳过

| 检查 | 命令 | 说明 |
| --- | --- | --- |
| 格式 | `cargo fmt --all -- --check` | |
| 静态分析 | `cargo clippy --all-targets -- -D warnings` | 警告即失败 |

### 关键 Clippy 配置

| 选项 | 值 | 说明 |
| --- | --- | --- |
| `msrv` | `1.80.0` | 最低支持 Rust 版本（与 AOSP 预置 rustc 一致） |
| `cognitive-complexity-threshold` | `8` | 认知复杂度阈值 |
| `excessive-nesting-threshold` | `4` | 最大嵌套深度 |
| `too-many-arguments-threshold` | `5` | 函数最大参数数量 |
| `too-many-lines-threshold` | `50` | 函数最大行数 |
| `max-fn-params-bools` | `1` | 函数参数中 bool 最多 1 个 |
| `max-struct-bools` | `1` | 结构体中 bool 字段最多 1 个 |
| `single-char-binding-names-threshold` | `0` | 完全禁止单字符绑定名 |
| `large-error-threshold` | `64` | Error 类型最大字节数（嵌入式栈控制） |
| `allow-unwrap-in-tests` | `false` | 测试代码中也禁止 `unwrap()` |
| `allow-expect-in-tests` | `false` | 测试代码中也禁止 `expect()` |
| `allow-panic-in-tests` | `false` | 测试代码中也禁止 `panic!` |

### 关键 rustfmt 配置

| 选项 | 值 | 说明 |
| --- | --- | --- |
| `edition` | `2021` | Rust Edition |
| `max_width` | `100` | 行宽上限 |
| `newline_style` | `Unix` | 强制 LF |
| `trailing_comma` | `Always` | 始终添加尾随逗号 |
| `use_small_heuristics` | `Off` | 严格遵守 `max_width`，禁止启发式折行 |
| `imports_granularity` | `Crate`（nightly） | 合并 use 到 crate 级别 |
| `group_imports` | `StdExternalCrate`（nightly） | std → 外部 crate → 自身 |

---

## Java Lint

**工具**：Checkstyle 10.21.4 + PMD 7.8.0 + SpotBugs 4.8.6（Java 17 / Temurin）
**配置**：

- Checkstyle：[.lintrc/backend/java/checkstyle.xml](../../../.lintrc/backend/java/checkstyle.xml)
- PMD：[.lintrc/backend/java/pmd-ruleset.xml](../../../.lintrc/backend/java/pmd-ruleset.xml)
- SpotBugs：[.lintrc/backend/java/spotbugs-exclude.xml](../../../.lintrc/backend/java/spotbugs-exclude.xml)

**扫描范围**：所有 `*.java`，排除 `Android-13/`；无 Java 文件则跳过

### Checkstyle 关键规则

| 规则 | 配置 | 说明 |
| --- | --- | --- |
| 行长度 | 100 字符 | 不含 package/import/URL |
| 文件长度 | 800 行 | |
| 禁止 Tab | `eachLine: true` | |
| 类名 / 接口名 | PascalCase | |
| 方法名 | lowerCamelCase | |
| severity | error | 所有违规均为错误 |

### PMD 关键规则

| 规则集 | 说明 |
| --- | --- |
| `bestpractices.xml` | 全量启用 |
| `codestyle.xml` | 全量启用（短变量名最短 2 字符，长变量名最长 40 字符） |
| `design.xml` | 圈复杂度上限 10（方法）/ 40（类） |
| `errorprone.xml` | 全量启用 |
| `performance.xml` | 全量启用 |
| `security.xml` | 全量启用 |
| `multithreading.xml` | 全量启用 |

### SpotBugs

- 分析级别：`-effort:max`，报告 `-high` 优先级 bug
- 需要编译后的 `.class` 文件；无 class 文件则跳过

---

## Kotlin Lint

**工具**：detekt 1.23.7 + ktlint 1.5.0
**配置**：

- detekt：[.lintrc/backend/kotlin/detekt.yml](../../../.lintrc/backend/kotlin/detekt.yml)
- ktlint：[.lintrc/backend/kotlin/.editorconfig-kotlin](../../../.lintrc/backend/kotlin/.editorconfig-kotlin)

**扫描范围**：所有 `*.kt`，排除 `Android-13/`；无文件则跳过

### 关键 detekt 配置

| 规则 | 限制 | 说明 |
| --- | --- | --- |
| `maxIssues` | `0` | 任何 issue 均导致失败（`warningsAsErrors: true`） |
| `CyclomaticComplexMethod` | 10 | |
| `CognitiveComplexMethod` | 10 | |
| `LongMethod` | 60 行 | |
| `LongParameterList` | 5 个 | |
| `LargeClass` | 400 行 | |
| `TooManyFunctions` | 文件 10 / 类 15 | |
| `NestedBlockDepth` | 3 | |

---

## Perl Lint

**工具**：[perlcritic](https://metacpan.org/dist/Perl-Critic)（通过 `libperl-critic-perl` apt 包安装）
**配置**：[.lintrc/backend/perl/.perlcriticrc](../../../.lintrc/backend/perl/.perlcriticrc)
**扫描范围**：所有 `*.pl`，排除上游目录；无文件则跳过

| 配置 | 值 | 说明 |
| --- | --- | --- |
| `severity` | `1` | 报告所有级别（1–5）的违规（最严格） |
| `theme` | `core + pbp + security + bugs + maintenance` | 多主题组合 |
| `--verbose` | `11` | 详细输出 |

---

## CMake Lint

**工具**：[cmakelang](https://cmake-format.readthedocs.io/) 0.6.13（含 cmake-format + cmake-lint）
**配置**：[.lintrc/infrastructure/build-systems/.cmake-format.yml](../../../.lintrc/infrastructure/build-systems/.cmake-format.yml)
**扫描范围**：`*.cmake` / `CMakeLists.txt`，排除 `Android-13/`；无文件则跳过

| 选项 | 值 | 说明 |
| --- | --- | --- |
| `line_width` | 80 | |
| `tab_size` | 2 | |
| `command_case` | `canonical` | 与 CMake 官方文档一致 |
| `keyword_case` | `upper` | |
| `line_ending` | `unix` | |

---

## Makefile Lint

**工具**：[checkmake](https://github.com/mrtazz/checkmake)（通过 Go 1.22 安装）
**配置**：[.lintrc/infrastructure/build-systems/.checkmake.ini](../../../.lintrc/infrastructure/build-systems/.checkmake.ini)
**扫描范围**：`*.mk` / `Makefile` / `Kbuild`，排除上游目录；无文件则跳过

| 规则 | 配置 | 说明 |
| --- | --- | --- |
| `maxbodylength` | 5 | 单个 recipe 最大行数 |
| `minphony` | 2 | 最少声明 2 个 `.PHONY` target |
| `phonydeclared` | `true` | 不产生文件的 target 必须声明为 `.PHONY` |
| `maxvarlength` | 32 | 变量名最大字符数 |
| 行长度 | 120 | |

---

## Buildifier Lint

**工具**：[buildifier](https://github.com/bazelbuild/buildtools) 7.3.1
**配置**：[.lintrc/infrastructure/build-systems/.buildifier.json](../../../.lintrc/infrastructure/build-systems/.buildifier.json)
**命令**：`buildifier --config=... --mode=check --lint=warn`
**扫描范围**：`*.bazel` / `*.bzl` / `BUILD` / `WORKSPACE`，排除 `Android-13/`；无文件则跳过

| 配置 | 值 | 说明 |
| --- | --- | --- |
| `type` | `auto` | 自动检测文件类型 |
| `lint.mode` | `warn` | 所有 lint 警告均报告 |
| `lint.warnings` | `all` | 全量 lint 规则 |

---

## Device Tree Validate

**工具**：device-tree-compiler（`dtc`）+ dtschema（`dt-validate`，`pip install dtschema`）
**配置**：[.lintrc/embedded/device-tree/dt-validate.yaml](../../../.lintrc/embedded/device-tree/dt-validate.yaml)
**扫描范围**：所有 `*.dts` / `*.dtsi`，排除上游目录

### dtc 语法检查

- 命令：`dtc -I dts -O dtb -Werror -@ -o /dev/null <file>`
- `suppress_warnings` 必须为空（由 CI 脚本校验配置文件中此字段不得有任何值）

### RK3588 GPIO Bank 策略检查

- CI 脚本读取配置中 `rk3588.max_gpio_bank`（值为 4），检查 DTS 文件中引用的 GPIO bank 编号是否越界

### 节点 / 属性命名规范

| 对象 | 规则 |
| --- | --- |
| 节点名 | `^[a-z][a-z0-9-]*(@[0-9a-f]+)?$` |
| 属性名 | `^#?[a-z][a-z0-9,.-]*$` |
| 标签名 | `^[a-z][a-z0-9_]*$` |
| compatible | `^[a-z][a-z0-9,-]+,[a-z][a-z0-9,-]+$` |

---

## SELinux Lint

**工具**：[selint](https://github.com/SELinuxProject/selint) 1.4.3
**配置**：[.lintrc/embedded/selinux/selint.conf](../../../.lintrc/embedded/selinux/selint.conf)
**命令**：`selint --config ... --source --recursive --summary .`
**扫描范围**：所有 `*.te`，排除 `Android-13/`；无文件则跳过

| 检查码 | 说明 |
| --- | --- |
| C-001 | 声明顺序约定违规 |
| C-002 | 风格约定违规（命名、空格、注释格式） |
| W-001 | 类型声明后无任何访问规则 |
| W-002 | `.te` 文件中存在 `ifdef` 结构 |
| W-003 | permissive domain（生产策略中禁止） |
| W-004 | allow 规则使用 self |
| E-001 | 引用了未定义的类型、属性或角色 |
| E-002 | 空块 |

最低报告级别：`C`（Convention，捕获所有问题）

---

## Kconfig Lint

**工具**：[kconfiglib](https://github.com/ulfalizer/Kconfiglib) 14.1.0
**配置**：[.lintrc/embedded/kconfig/kconfiglint.yaml](../../../.lintrc/embedded/kconfig/kconfiglint.yaml)
**扫描范围**：所有 `Kconfig` 和 `*defconfig`，排除 `Android-13/`；无文件则跳过

### Kconfig 语法检查

使用 `kconfiglib.Kconfig(f)` 解析每个文件，解析失败即报错。

### defconfig 策略检查（读取配置文件）

| 策略 | 来源字段 | 说明 |
| --- | --- | --- |
| `forbidden_in_production` | `defconfig.forbidden_in_production[]` | 生产构建中禁止启用的 symbol |
| `required_in_production` | `defconfig.required_in_production[]` | 生产构建中必须启用的 symbol |

---

## Secret Scan

**工具**：[Gitleaks](https://github.com/gitleaks/gitleaks-action) v2
**配置**：[.lintrc/security/.gitleaks.toml](../../../.lintrc/security/.gitleaks.toml)
**触发**：`fetch-depth: 0`（完整提交历史）

- 基于默认规则集（`useDefault = true`）扫描提交历史中的密钥泄漏
- 自定义检测规则：通用 API Key（`api[_-]?key`）、通用 Secret（`secret|passwd|password`）
- 白名单路径：`.gitleaks.toml`、二进制文件（`.jpg`/`.bin`/`.dtb`/`.elf`/`.so` 等）、许可证文件、`Android/rkbin/`、`Android/prebuilts/`、`.env.example`
- 白名单 regex：AWS 文档示例凭证、GitHub Actions `${{ secrets.* }}` 引用

---

## Semgrep Security Scan

**工具**：[Semgrep](https://semgrep.dev/)（最新版）
**配置**：[.lintrc/security/.semgrep.yml](../../../.lintrc/security/.semgrep.yml)
**附加规则集**：`p/owasp-top-ten`、`p/c`、`p/java`、`p/python`、`p/security-audit`、`p/android`
**扫描范围**：全仓库（排除上游四个目录），`--error` 模式（任何发现均失败）

目标语言：C / C++（内核驱动、U-Boot、HAL）、Bash（构建脚本）、Python（工具脚本）、Java（Android AAOS 组件）

| 类别 | 规则示例 |
| --- | --- |
| A02 加密失效 | 硬编码凭证（C/C++、Python、Java） |
| A03 注入 | OS 命令注入（C、Python）、SQL 拼接 |
| A05 安全配置 | `unsafe` 块、`unwrap()`/`expect()` |

---

## Commit Message Lint

**工具**：[@commitlint/cli](https://commitlint.js.org/) 19.6.0 + `@commitlint/config-conventional` 19.6.0
**配置**：[.lintrc/git/.commitlintrc.cjs](../../../.lintrc/git/.commitlintrc.cjs)
**触发**：仅在 PR 时运行（检查范围：`base.sha` → `head.sha`）

遵循 [Conventional Commits](https://www.conventionalcommits.org/) 规范：

| 规则 | 配置 | 说明 |
| --- | --- | --- |
| type 枚举 | `feat`/`fix`/`docs`/`style`/`refactor`/`perf`/`test`/`build`/`ci`/`chore`/`revert`/`security`/`deps` | |
| `scope-empty` | `never` | scope 为必填项，用于追溯变更模块 |
| `subject-min-length` | 10 字符 | |
| `subject-max-length` | 100 字符 | |
| `header-max-length` | 120 字符 | |
| `header-min-length` | 15 字符 | |
| `subject-case` | 禁止 `sentence-case`、`start-case`、`pascal-case`、`upper-case` | |
| `body-leading-blank` | 必须有空行 | |
| `body-max-line-length` | 200 字符 | |
| `footer-max-line-length` | 100 字符 | |

---

## Spelling Check

**工具**：[cspell](https://cspell.org/) 8.17.1
**配置**：[.lintrc/general/cspell.json](../../../.lintrc/general/cspell.json)
**扫描范围**：`"**"`，排除 `.lintrc/`、上游四个目录、`out/`、`LICENSE`

| 配置 | 值 | 说明 |
| --- | --- | --- |
| 词典 | `en_US`、`companies`、`softwareTerms`、`misc`、`filetypes`、`cpp`、`python`、`bash`、`git`、`markdown` 等 | |
| `words[]` | 空（待随项目开发填入） | |
| `flagWords` | `hte`、`teh`、`recieve`、`occured`、`doesnt` 等 | 常见笔误触发报错 |
| `--gitignore` | 启用 | 遵循 `.gitignore` 排除规则 |

---

## File Naming Check

**工具**：[ls-lint](https://ls-lint.org/) 2.3.1
**配置**：[.lintrc/general/.ls-lint.yml](../../../.lintrc/general/.ls-lint.yml)
**命令**：`ls-lint --config .lintrc/general/.ls-lint.yml`

### 全局默认规则

| 文件类型 | 规则 | 示例 |
| --- | --- | --- |
| `.c` / `.h` / `.cpp` / `.hpp` | `snake_case` | `rockchip_drm.c` |
| `.sh` | `snake_case` 或 `kebab-case` | `init-RK3588.sh` |
| `.py` | `snake_case` | `check_android_rc.py` |
| `.dts` / `.dtsi` | `kebab-case` | `rk3588-evb.dts` |
| `.mk` | `snake_case` 或 `kebab-case` | |
| `.json` | `kebab-case` 或 `snake_case` | |
| `.yml` / `.yaml` | `kebab-case` 或全大写（`[A-Z._-]+`） | `lint.yml`、`CODEOWNERS` |
| `.toml` | `kebab-case` 或 `snake_case` | |
| `.cfg` / `.ini` / `.conf` | `regex:\.?[a-z][a-z0-9._-]*` | |
| `.md` | `SCREAMING_SNAKE_CASE` 或 `kebab-case` | `README.md`、`ci-checks.md` |
| `.rst` | `SCREAMING_SNAKE_CASE`、`kebab-case` 或 `snake_case` | |

### 目录级覆盖规则

| 目录 | 文件类型 | 规则 |
| --- | --- | --- |
| `.github/` | `.yml` / `.yaml` / `.json` | 仅 `kebab-case` |
| `.github/` | `.md` | `SCREAMING_SNAKE_CASE` 或 `kebab-case` |

**忽略路径**：`.git`、`Android/rk-kernel-5.10`、`Android/u-boot`、`Android/rkbin`、`Android/prebuilts`

---

## Groovy / Gradle Lint

**工具**：[npm-groovy-lint](https://github.com/nvuillam/npm-groovy-lint) 14.6.0（内置 CodeNarc）
**配置**：[.lintrc/backend/groovy/codenarc.xml](../../../.lintrc/backend/groovy/codenarc.xml)
**扫描范围**：`**/*.groovy` / `**/*.gradle`，排除 `Android-13/`；无文件则跳过
**失败阈值**：`--failon warning`（warning 及以上均失败）

启用规则集：`basic`、`braces`、`comments`、`concurrency`、`convention`、`design`、`dry`、`exceptions`、`formatting`、`generic`、`groovyism`、`imports`、`junit`、`logging`、`naming`、`security`、`serialization`、`size`、`unnecessary`、`unused`

---

## RST Lint

**工具**：rstcheck 6.2.4（含 sphinx 扩展）+ doc8 1.1.2
**配置**：

- rstcheck：[.lintrc/docs/rst/rstcheck.cfg](../../../.lintrc/docs/rst/rstcheck.cfg)
- doc8：[.lintrc/docs/rst/doc8.ini](../../../.lintrc/docs/rst/doc8.ini)

**扫描范围**：所有 `*.rst`，排除 `Android-13/`；无文件则跳过

### rstcheck 配置

| 配置 | 值 | 说明 |
| --- | --- | --- |
| `report_level` | `1`（INFO） | 捕获所有级别的问题 |
| `ignore_directives` | 空 | 不豁免任何自定义指令 |
| `ignore_roles` | 空 | 不豁免任何自定义角色 |
| `ignore_languages` | 空 | 所有嵌入代码块均检查语法 |

### doc8 配置

| 规则 | 配置 | 说明 |
| --- | --- | --- |
| `max-line-length` | 79 | PEP 8 / RST 社区标准 |
| `allow-long-titles` | `false` | 不允许超长装饰线 |
| `ignore` | 空 | D000–D005 全部强制执行 |
| `sphinx` | `true` | 保留 Sphinx 专属语法 |

---

## JSON Lint

**工具**：Biome 1.9.4 + ESLint 8 + eslint-plugin-jsonc 2 + check-jsonschema 0.31.3
**配置**：

- Biome：[.lintrc/data-formats/json/](../../../.lintrc/data-formats/json/)
- ESLint JSONC：[.lintrc/data-formats/json/.eslintrc-jsonc.json](../../../.lintrc/data-formats/json/.eslintrc-jsonc.json)
- Schema 映射：[.lintrc/data-formats/json/jsonschema-validators.yaml](../../../.lintrc/data-formats/json/jsonschema-validators.yaml)

**扫描范围**：所有 `*.json` / `*.jsonc`，排除 `Android-13/`；无文件则跳过

| 检查 | 工具 | 说明 |
| --- | --- | --- |
| 格式 / 语法 | `biome ci` | |
| JSONC 注释语法 | `eslint --max-warnings 0` | |
| Schema 校验 | `check-jsonschema` | 按 `jsonschema-validators.yaml` 中的映射逐文件校验 |

已配置 Schema 映射的文件类型包括：`BundleConfig.pb.json`（Android App Bundle）、`.github/workflows/*.json`（GitHub Actions）、`CMakePresets.json`、`.clang-format`、`.clang-tidy`、`pyproject.toml` 等。

---

## Android.bp Lint

**工具**：Python 策略脚本（读取配置文件）
**配置**：[.lintrc/embedded/android-bp/bpfmt.yaml](../../../.lintrc/embedded/android-bp/bpfmt.yaml)
**扫描范围**：所有 `*.bp`，排除 `Android-13/`；无文件则跳过

禁止在 `cflags` 中出现的标志：

| 标志 | 说明 |
| --- | --- |
| `-w` | 屏蔽全部编译警告 |
| `-fpermissive` | 允许非法 C++ 代码 |
| `-Wno-error` | 将警告降级 |
| `-O0` | 生产构建禁止关闭优化 |

---

## Android Init RC Lint

**工具**：Python 策略脚本（读取配置文件）
**配置**：[.lintrc/embedded/android-rc/android-rc-checks.yaml](../../../.lintrc/embedded/android-rc/android-rc-checks.yaml)
**扫描范围**：所有 `*.rc`，排除 `Android-13/`；无文件则跳过

| 策略 | 规则 |
| --- | --- |
| 禁止 user | `root`、`shell` |
| 禁止权能 | 配置文件 `capabilities.forbidden_capabilities[]` 中声明的权能 |
| 禁止 setprop | 配置文件 `properties.forbidden_setprop[]` 中声明的属性 |
| 禁止 chmod 777 | `filesystem.forbid_chmod_777: true` |
| 禁止废弃关键字 | 配置文件 `deprecated.forbidden_keywords[]` 中声明的关键字 |

---

## AIDL Lint

**工具**：Python 策略脚本（读取配置文件）
**配置**：[.lintrc/embedded/aidl/aidl-lint.yaml](../../../.lintrc/embedded/aidl/aidl-lint.yaml)
**扫描范围**：所有 `*.aidl`，排除 `Android-13/`；无文件则跳过

| 策略 | 规则 |
| --- | --- |
| 接口命名 | `^I[A-Z][A-Za-z0-9]+$`（配置字段 `naming.interface_pattern`） |
| 禁止原始 IBinder | `policy.forbid_raw_ibinder: true` |

编译器强制参数（配置文件声明，供参考）：

- `structured: true`：强制结构化 parcelable
- `stability: vintf`：所有跨进程 HAL 接口必须标注 `@VintfStability`
- 支持后端：java / cpp / ndk / rust

---

## HIDL Lint

**工具**：Python 策略脚本（读取配置文件）
**配置**：[.lintrc/embedded/hidl/hidl-lint.yaml](../../../.lintrc/embedded/hidl/hidl-lint.yaml)
**扫描范围**：全仓库 `*.hal` 文件（排除 `Android-13/` 和 `.git/`）

政策：Android 12+ 新 HAL 必须使用 AIDL，禁止新建 HIDL 接口（`.hal` 文件）。

CI 脚本读取配置中 `policy.forbid_new_hidl_interfaces`（值为 `true`），发现任何 `.hal` 文件即失败。
