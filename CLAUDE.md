# CLAUDE.md — turboacc (luci 分支)

本文件供 Claude Code 在此仓库工作时使用，描述项目结构、实现逻辑与版本兼容设计。

## 项目概述

一个适用于官方 OpenWrt 的 Turbo ACC 网络加速套件，包含以下功能：

- 软件流量分载 (Flow Offloading)
- Shortcut-FE（fast-classifier / shortcut-fe-cm）
- 全锥型 NAT (FullCone NAT，含 IPv6)
- BBR 拥塞控制算法
- MediaTek HNAT (mtkhnat) / MTK WED WO（MTK 平台）

**双防火墙兼容（核心设计）**：同时兼容官方 OpenWrt 22.03/23.05 的 **firewall4**（nftables）
与官方 OpenWrt 21.02 的 **firewall3**（iptables）。21.02 的实现方式参考
[hanwckf/immortalwrt-mt798x 的 luci-app-turboacc-mtk（openwrt-21.02 分支）](https://github.com/hanwckf/immortalwrt-mt798x/tree/openwrt-21.02/package/mtk/applications/luci-app-turboacc-mtk)。

上游来源：基于 coolsnowwolf/lede 的 luci-app-turboacc 修改（去除 DNS 功能），由
chenmozhijin/turboacc 维护。本仓库即该项目的 luci 分支工作副本。

## 目录结构

```
add_turboacc.sh                 # 一键注入脚本：向 OpenWrt 源码树添加 turboacc 包
luci-app-turboacc/
  Makefile                      # OpenWrt 包定义（LUCI_DEPENDS / 可选编译开关）
  luasrc/controller/turboacc.lua # 路由 + status JSON 接口（调用 init.d check_status）
  luasrc/model/cbi/turboacc.lua  # 设置页面（按设备能力动态显示选项）
  luasrc/view/turboacc/turboacc_status.htm  # 运行状态轮询 (XHR.poll 5s)
  root/etc/config/turboacc      # UCI 默认配置
  root/etc/init.d/turboacc      # 服务脚本：应用配置、加载/卸载内核模块、check_status
  root/etc/uci-defaults/luci-turboacc      # 首次安装初始化 + ucitrack 注册
  root/usr/share/ucitrack/luci-app-turboacc.json
  po/zh-cn/turboacc.po          # 中文翻译
patches/                        # 本仓库内置补丁（package 分支没有的内核版本用）
  hack-5.4/952-*.patch          # conntrack 多注册者事件（lede 版，已适配官方 21.02 树）
  hack-5.4/953-*.patch          # Shortcut-FE 内核支持（lede 版，已适配官方 21.02 树）
  pending-5.4/613-*.patch       # 可选 TCP 窗口检查（lede pending-5.4 版）
  firewall3/100-fullconenat.patch  # fw3 全锥 NAT 选项补丁（MASQUERADE→FULLCONENAT）
fullconenat/                    # xt_FULLCONENAT 包（Chion Tang fullconenat，
                                # 自行从 Chion82/netfilter-full-cone-nat 拉源码）
.github/workflows/test.yml     # CI：对 master/22.03/23.05/24.10/25.12 矩阵编译验证
.github/workflows/update.yml   # CI：自动更新依赖版本
.github/scripts/collect-openwrt-debug.sh  # CI 失败时收集 OpenWrt 调试产物
img/                           # 插件截图
```

## 版本判断与 firewall3/firewall4 兼容设计

### 编译期：add_turboacc.sh

在 OpenWrt 源码树根目录执行。检测逻辑：

1. **OpenWrt 版本**：从 `include/version.mk` 的 `VERSION_NUMBER` 提取形如
   `2X.YY` 的版本号（如 `21.02`、`23.05`），仅用于日志展示。
2. **防火墙类型 `FIREWALL_FLAVOR`**（决策依据）：以
   `./package/network/config/firewall4` 目录是否存在判断——存在为 `fw4`，
   不存在为 `fw3`（21.02 / lede / immortalwrt-mt798x 类树）。

分支行为：

| | fw4 (22.03/23.05) | fw3 (21.02) |
|---|---|---|
| luci-app-turboacc | 安装 | 安装 |
| shortcut-fe 包 | 安装（`--no-sfe` 跳过） | 安装（`--no-sfe` 跳过） |
| nft-fullcone 包 | 安装 | **跳过**（fw3 不用 nft fullcone） |
| 替换 firewall4/libnftnl/nftables | 是（换为 fullcone 修补版） | **跳过**，保持源码树自带防火墙 |
| 952/953/613 内核补丁 | 支持内核 5.10/5.15/6.1/6.6/6.12/6.18（补丁来自 package 分支） | 5.10 按原逻辑打补丁；**5.4**：树中已有 952 补丁（lede 系自带）→ 保留；否则使用本仓库 `patches/hack-5.4`、`patches/pending-5.4` 的适配补丁（针对官方 21.02 树调整过 hunk 偏移）；两处都没有 → 警告并继续（仅软件流量分载可用） |
| luci-app Makefile | 原样 | 自动 sed：删除 `kmod-nft-fullcone` 依赖并把 `INCLUDE_NFT_FULLCONE` 默认改为 n（fw3 树无此 kmod，否则编译失败） |
| `CONFIG_NF_CONNTRACK_CHAIN_EVENTS` / `CONFIG_SHORTCUT_FE` | 追加到 `target/linux/generic/config-*`（grep 去重） | 同左（有补丁的内核） |

参数：
- `--no-sfe`：不装 shortcut-fe。
- `--fw3-fullcone`：仅 fw3 模式生效。官方 21.02 的 firewall3 没有 fullcone 选项，
  加此参数会 1) 把 `fullconenat` 包（kmod-ipt-fullconenat + iptables-mod-fullconenat）
  装进 package/turboacc；2) 把 `patches/firewall3/100-fullconenat.patch` 放进
  `package/network/config/firewall/patches/`（MASQUERADE→FULLCONENAT，恩山/lede 经典方案）。
  lede/immortalwrt 系树 fw3 已自带 fullcone，无需此参数。
- `--local-pkg <dir>`：用本地包目录代替 package 分支克隆（CI 使用）。
- 环境变量 `TURBOACC_GIT_URL`：luci 分支仓库地址（默认
  `https://github.com/chenmozhijin/turboacc`），fork 仓库使用时覆盖，例如
  `TURBOACC_GIT_URL=https://github.com/yuos-bit/turboacc`。5.4 补丁、fw3 fullcone
  材料与 fullconenat 包都从该克隆中取。

注意：21.02 的 `.config` 中不要选 `luci-app-turboacc_INCLUDE_NFT_FULLCONE`（脚本已
自动将默认改为 n）；全锥 NAT 由 firewall3 fullcone 选项提供。

### 运行期：init.d/turboacc

`detect_fw()` 以 `command -v fw4` 判断：有 `fw4` 命令 → fw4，否则 → fw3。

- **软件/硬件流量分载模块判断**：fw4 检查 `nft_flow_offload.ko`；fw3 检查
  `xt_FLOWOFFLOAD.ko`（iptables FLOWOFFLOAD target，来自 kmod-ipt-offload）。
  模块缺失时强制 `sw_flow=0, hw_flow=0`。
- **UCI 选项**（两代防火墙统一写入，fw3 对不认识的选项静默忽略）：
  - `firewall.@defaults[0].flow_offloading` / `flow_offloading_hw`（fw3 与 fw4 均支持）
  - `firewall.@defaults[0].fullcone`：fw4 走修补版 firewall4 + nft-fullcone；
    fw3 走 immortalwrt/lede 修补版 firewall3 的 fullcone 选项（与 mtk 仓库
    21.02 实现一致，见其 init.d 的 `uci -q set firewall.@defaults[0].fullcone`）
  - `fullcone6`（zone 级）：仅修补版 fw4 支持；fw3 上 `uci show | grep` 循环为空，自然跳过
- **MTK 平台**：
  - `load_wed/unload_wed`：mt7915e WED 开关（写 /etc/modules.conf）
  - `load_hnat/unload_hnat`：mtkhnat 硬件 NAT，通过 debugfs
    `/sys/kernel/debug/hnat/hook_toggle` 控制（参照 mtk 仓库 mediatek_hnat 实现）
- **BBR**：`sysctl net.ipv4.tcp_congestion_control` 切换 bbr/cubic
- `check_status {fastpath|fullconenat|bbr}`：供 LuCI 状态页与 controller 查询；
  fastpath 依次探测 nft_flow_offload → HWNAT(hnat_version) → QCA NSS/ECM → Shortcut-FE

### LuCI 界面 (cbi/turboacc.lua)

按 `/lib/modules/$(uname -r)/` 下模块文件是否存在动态显示选项（fw3 兼容点）：

- `sw_flow`：`nft_flow_offload.ko` **或** `xt_FLOWOFFLOAD.ko`（fw3）存在时显示
- `hw_flow`：mediatek/filogic/mt762 设备显示
- `hw_wed`：mediatek 且 mt7915e.ko 存在；`hnat_flow`：mtkhnat.ko 存在
- `sfe_flow`：shortcut-fe-cm.ko 或 fast-classifier.ko 存在
- `fullcone_nat`/`fullcone6`：`nft_fullcone.ko` **或** `iptables -m FULLCONENAT`
  可用（fw3 路径）时显示
- `bbr_cca`：tcp_bbr.ko 存在

选项互斥通过 `:depends()` 表达：sw_flow ↔ sfe_flow ↔ hnat_flow 相互排斥。

## 关键依赖对应

| 功能 | fw4 (22.03/23.05) | fw3 (21.02) |
|---|---|---|
| 软件流量分载 | kmod-nft-offload（nft_flow_offload.ko） | kmod-ipt-offload（已验证 21.02/22.03/23.05 官方树均存在，提供 xt_FLOWOFFLOAD.ko） |
| 全锥 NAT | kmod-nft-fullcone + 修补版 firewall4/libnftnl/nftables | 修补版 firewall3 的 `fullcone` 选项（lede/immortalwrt 树自带；官方 21.02 需 `--fw3-fullcone`） |
| Shortcut-FE | 952/953 补丁 + shortcut-fe 包（package 分支） | 同左（5.4 用本仓库 patches/hack-5.4、patches/pending-5.4 适配补丁） |
| BBR | kmod-tcp-bbr（官方自带） | 同左 |

## MT7621 (ramips) 与 21.02 硬件加速的调查结论（2026-08 调查）

背景：用户固件为 MT7621 设备（小米 R3G/R4/R4A-G/红米与小米 AC2100 等），
21.02 树（yuos-bit/openwrt openwrt-21.02，内核 5.4）+ MTK SDK 无线驱动
（kmod-mt7603e / kmod-mt7612e / kmod-mt7615d，mt7615d 带 whnat/WED 插件源码）。

**结论：21.02 上 MT7621 硬件 NAT（PPE/HNAT/mtkhnat）不可用，也不应再尝试引入**：

1. 用户 openwrt-21.02 树中没有任何 HNAT/PPE 相关内核文件（全树搜索确认）。
2. immortalwrt 18.06 / 18.06-k5.4 / immortalwrt-mt798x 中均无 MT7621 的 HNAT
   驱动（只有 mt798x 的 mtkhnat，与 ramips 无关）。
3. GitHub 全网搜索无公开的 MT7621 HNAT 内核 5.4 移植仓库；MTK SDK 4.4 的 hnat
   驯化到 5.4 属大工程，无法验证。
4. mt7615d 的 whnat/WED 插件需要内核侧 HNAT/WED 才能生效，无 HNAT 时仅为死代码；
   mt7603e/mt7612e 驱动本身无任何 offload 钩子。
5. MT7621 上被验证有效的加速路径（恩山共识）：**Shortcut-FE（952/953 补丁）+
   firewall3 fullcone + BBR**。SFE 在 netfilter 层加速，有线与无线（mt7603e/
   mt7612e/mt7615d 客户端）NAT 流量都能加速，无需无线驱动参与。

因此对 MT7621/21.02 的"兼容"落地为：5.4 补丁集（patches/）+ --fw3-fullcone +
UI 修正——`hw_flow`（硬件流量分载）选项现在只在 **fw4 且 mediatek/filogic**
（mt7622/mt798x）设备显示，MT7621/MT7620 不再显示无实际效果的选项。

## 约定与注意事项

- shell 脚本：init.d 为 `/etc/rc.common` 风格（**tab 缩进**，POSIX sh）；add_turboacc.sh 为 bash。
- Lua 使用 LuCI 0.x/legacy CBI API（`luci-compat`），兼容 21.02 的 Lua LuCI，不使用 clientview JS。
- Makefile 编译开关：`INCLUDE_OFFLOADING`（默认 y）、`INCLUDE_SHORTCUT_FE`/`_CM`/`_DRV`（互斥，依赖 OFFLOADING=n）、`INCLUDE_BBR_CCA`、`INCLUDE_NFT_FULLCONE`。
- 修改 init.d 后运行 `sh -n` 校验语法；修改 add_turboacc.sh 后运行 `bash -n` 校验。
- 非官方 OpenWrt 自带的依赖（shortcut-fe、nft-fullcone、修补版 firewall4 等）存档于上游 package 分支（chenmozhijin/turboacc `package`），版本清单在该分支 `version` 文件。
- CI 矩阵见 `.github/workflows/test.yml`（分支 × 编译模式），改动后可参考其流程本地验证。
- 翻译改动同步更新 `po/zh-cn/turboacc.po`。

## 参考实现

- immortalwrt-mt798x (openwrt-21.02) `luci-app-turboacc-mtk`：
  - `root/etc/init.d/turboacc`：fastpath（mediatek_hnat/fast_classifier/shortcut_fe_cm）
    切换、hook_toggle 控制、`firewall.@defaults[0].fullcone` 写入 —— fw3 兼容的参照来源
  - `root/etc/uci-defaults/turboacc`：按已存在内核模块自动选择默认 fastpath
  - `root/usr/libexec/rpcd/luci.turboacc`：状态查询
