# luci-app-turboacc

中文|[English](https://github.com/chenmozhijin/turboacc/blob/luci/README_EN.md)

一个适用于官方openwrt(22.03/23.05) firewall4的turboacc  
包括以下功能：软件流量分载、Shortcut-FE、全锥型 NAT、BBR 拥塞控制算法  

 编译测试：[![TEST Status](https://github.com/chenmozhijin/turboacc/actions/workflows/test.yml/badge.svg)](https://github.com/chenmozhijin/turboacc/actions/workflows/test.yml)  
 依赖自动更新：[![UPDATE Status](https://github.com/chenmozhijin/turboacc/actions/workflows/update.yml/badge.svg)](https://github.com/chenmozhijin/turboacc/actions/workflows/update.yml)

## 使用方法

+ 在openwrt源代码所在目录执行：

    带sfe:

    ```bash
    curl -sSL https://raw.githubusercontent.com/chenmozhijin/turboacc/luci/add_turboacc.sh -o add_turboacc.sh && bash add_turboacc.sh
    ```

    > 这将会下载luci-app-turboacc、nft-fullcone、shortcut-fe 替换firewall4、libnftnl、nftables并打上952、613、953补丁。

    不带sfe:

    ```bash
    curl -sSL https://raw.githubusercontent.com/chenmozhijin/turboacc/luci/add_turboacc.sh -o add_turboacc.sh && bash add_turboacc.sh --no-sfe
    ```

    > 这将会下载luci-app-turboacc、nft-fullcone 替换firewall4、libnftnl、nftables并打上952补丁。

+ 之后执行

```bash
make menuconfig
```

+ 在 > LuCI > 3. Applications中选中luci-app-turboacc
+ 如果你想用要一个用GitHub Actions云编译带turboacc官方源码的openwrt可以看看这个仓库[OpenWrt-K](https://github.com/chenmozhijin/OpenWrt-K)

## 注意

1. 软件流量分载为firewall4自带的功能(见firewall4的[Makefile](https://github.com/openwrt/openwrt/blob/afa229038c05ba0ca20595d7f73bea94db21d3a6/package/network/config/firewall4/Makefile#L25C31-L25C48))按理来说其兼容性与稳定性都比较好，一般不需要sfe(sfe相关的功能我都没有测试过)。
2. 默认的使用方法会把firewall4、libnftnl、nftables替换最新修补后的版本，如你遇到问题可以尝试使用旧版firewall4、libnftnl、nftables。（package分支中有旧版存档）
3. 脚本会自动判断源码树版本：22.03/23.05 (firewall4) 按上述方式处理；21.02 (firewall3) 则保持源码树自带防火墙不动：
   - 全锥NAT通过firewall3的fullcone选项实现（lede/immortalwrt系源码树自带；官方21.02请加 `--fw3-fullcone`，脚本会安装 [fullconenat](fullconenat/) 包与 firewall3 补丁），实现方式参考immortalwrt-mt798x的[luci-app-turboacc-mtk](https://github.com/hanwckf/immortalwrt-mt798x/tree/openwrt-21.02/package/mtk/applications/luci-app-turboacc-mtk)；
   - 5.4内核使用本仓库 [patches/hack-5.4](patches/hack-5.4/) 与 [patches/pending-5.4](patches/pending-5.4/) 的952/953/613适配补丁（已针对官方21.02源码树校准hunk偏移）；
   - fork仓库使用时请设置环境变量，例如 `TURBOACC_GIT_URL=https://github.com/yuos-bit/turboacc bash add_turboacc.sh --fw3-fullcone`；
   - MT7621在21.02上没有硬件NAT驱动（MTK SDK的hnat从未移植到5.4内核），硬件加速不可用，请使用Shortcut-FE或软件流量分载（有线/无线NAT流量均可加速）。

## 插件预览

![插件预览](https://raw.githubusercontent.com/chenmozhijin/turboacc/luci/img/1.png)
![效果预览](https://raw.githubusercontent.com/chenmozhijin/turboacc/luci/img/2.png)

## 关于

此仓库的luci-app-turboacc是基于LEDE仓库的[luci-app-turboacc](https://github.com/coolsnowwolf/luci/tree/master/applications/luci-app-turboacc)修改而来的，去除了DNS相关功能并使其支持firewall4，但不再支持firewall3。

各功能的依赖：

软件流量分载(Flow Offload)：[kmod-nft-offload](https://github.com/openwrt/openwrt/blob/80edfaf675364835e6d2e17d97ebec6afc6b2103/package/kernel/linux/modules/netfilter.mk#L1182C1-L1199C42)(官方openwrt自带)

Shortcut-FE：[shortcut-fe](https://github.com/chenmozhijin/turboacc/tree/package/shortcut-fe)、952补丁、953补丁

全锥型 NAT（FULLCONE NAT）：[nft-fullcone](https://github.com/fullcone-nat-nftables/nft-fullcone)、修补的firewall4、libnftnl、nftables与952补丁

BBR 拥塞控制算法：[kmod-tcp-bbr](https://github.com/openwrt/openwrt/blob/80edfaf675364835e6d2e17d97ebec6afc6b2103/package/kernel/linux/modules/netsupport.mk#L1036C1-L1057C38)(官方openwrt自带)

非官方openwrt自带的依赖存档在[package分支](https://github.com/chenmozhijin/turboacc/tree/package)。

## 感谢

 感谢以下项目：

+ [coolsnowwolf/lede](https://github.com/coolsnowwolf/lede)(952、953补丁与sfe来源)
+ [wongsyrone/lede-1](https://github.com/wongsyrone/lede-1)(firewall4、libnftnl、nftables修补补丁来源)
+ [fullcone-nat-nftables/nft-fullcone](https://github.com/fullcone-nat-nftables/nft-fullcone)(全锥型 NAT依赖)
