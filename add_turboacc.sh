#!/usr/bin/env bash
# shellcheck disable=SC2016

trap 'rm -rf "$TMPDIR"' EXIT
TMPDIR=$(mktemp -d) || exit 1

NO_SFE=false
FW3_FULLCONE=false
LOCAL_PACKAGE=""
# Repo to clone the luci branch from (patches/ and fullconenat/ included).
# Override when running against a fork, e.g.:
#   TURBOACC_GIT_URL=https://github.com/yuos-bit/turboacc bash add_turboacc.sh
TURBOACC_GIT_URL="${TURBOACC_GIT_URL:-https://github.com/chenmozhijin/turboacc}"

while [[ $# -gt 0 ]]; do
    case $1 in
        --no-sfe)
            NO_SFE=true
            shift
            ;;
        --fw3-fullcone)
            FW3_FULLCONE=true
            shift
            ;;
        --local-pkg)
            LOCAL_PACKAGE="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

if ! [ -d "./package" ]; then
    echo "./package not found"
    exit 1
fi

VERSION_NUMBER=$(sed -n '/VERSION_NUMBER:=$(if $(VERSION_NUMBER),$(VERSION_NUMBER),.*)/p' include/version.mk | sed -e 's/.*$(VERSION_NUMBER),//' -e 's/)//')
# Detect the OpenWrt version (e.g. "21.02", "22.03", "23.05") from VERSION_NUMBER
OPENWRT_VERSION=$(echo "$VERSION_NUMBER" | grep -oE '2[0-9]\.[0-9]{2}' | head -n 1)
# Firewall flavor: firewall4 exists in OpenWrt >= 22.03, older trees (21.02 and
# lede/immortalwrt-mt798x style forks) use firewall3 (iptables).
if [ -d "./package/network/config/firewall4" ]; then
    FIREWALL_FLAVOR="fw4"
else
    FIREWALL_FLAVOR="fw3"
fi
echo "OpenWrt version: ${OPENWRT_VERSION:-unknown} ($VERSION_NUMBER), firewall flavor: $FIREWALL_FLAVOR"
kernel_versions="$(find "./include" | sed -n '/kernel-[0-9]/p' | sed -e "s@./include/kernel-@@" | sed ':a;N;$!ba;s/\n/ /g')"
if [ -z "$kernel_versions" ]; then
    kernel_versions="$(find "./target/linux/generic" | sed -n '/kernel-[0-9]/p' | sed -e "s@./target/linux/generic/kernel-@@" | sed ':a;N;$!ba;s/\n/ /g')"
fi
if [ -z "$kernel_versions" ]; then
    echo "Error: Unable to get kernel version, script exited"
    exit 1
fi
echo "kernel version: $kernel_versions, No SFE: $NO_SFE"

if [ -d "./package/turboacc" ]; then
    echo "./package/turboacc already exists, delete it? [Y/N]"
    read -r answer
    if [[ $answer =~ ^[Yy]$ ]]; then
        rm -rf "./package/turboacc"
    else
        echo "You selected 'No', script exited"
        exit 0
    fi
fi

git clone --depth=1 --single-branch "$TURBOACC_GIT_URL" "$TMPDIR/repo" || exit 1
if [ -n "$LOCAL_PACKAGE" ]; then
    echo "Using local package: $LOCAL_PACKAGE"
    cp -RT "$LOCAL_PACKAGE" "$TMPDIR/package" || exit 1
else
    git clone --depth=1 --single-branch --branch "package" https://github.com/chenmozhijin/turboacc "$TMPDIR/package" || exit 1
fi

cp -r "$TMPDIR/repo/luci-app-turboacc" "$TMPDIR/turboacc/luci-app-turboacc"
if [ "$FIREWALL_FLAVOR" = "fw3" ]; then
    # kmod-nft-fullcone only exists on firewall4 trees; on firewall3 fullcone is
    # provided by the firewall3 option (lede/immortalwrt) or the fullconenat
    # package (--fw3-fullcone), so drop the kmod-nft-fullcone dependency and
    # default the option off (avoids unresolvable dependency on 21.02).
    sed -i '/INCLUDE_NFT_FULLCONE:kmod-nft-fullcone/d' "$TMPDIR/turboacc/luci-app-turboacc/Makefile"
    sed -i '/bool "Include NFT FULLCONE"/{n;s/default y/default n/}' "$TMPDIR/turboacc/luci-app-turboacc/Makefile"
fi
# "$TMPDIR/repo" is kept around: the 5.4 kernel patches (patches/) and the fw3
# fullcone materials (patches/firewall3, fullconenat) are copied from it later.
# It lives outside "$TMPDIR/turboacc" so it is not packaged, and the EXIT trap
# cleans it up.
if [ "$FIREWALL_FLAVOR" = "fw4" ]; then
    cp -r "$TMPDIR/package/nft-fullcone" "$TMPDIR/turboacc/nft-fullcone" || exit 1
fi
if [ "$NO_SFE" = false ]; then
    cp -r "$TMPDIR/package/shortcut-fe" "$TMPDIR/turboacc/shortcut-fe"
fi

for kernel_version in $kernel_versions; do
    SRC_PATCH_DIR=""
    patch_953_path="./target/linux/generic/hack-$kernel_version/953-net-patch-linux-kernel-to-support-shortcut-fe.patch"
    patch_613_path="./target/linux/generic/pending-$kernel_version/613-netfilter_optional_tcp_window_check.patch"
    if [ "$kernel_version" = "6.18" ] || [ "$kernel_version" = "6.12" ] || [ "$kernel_version" = "6.6" ] || [ "$kernel_version" = "6.1" ] || [ "$kernel_version" = "5.15" ]; then
        patch_952_path="./target/linux/generic/hack-$kernel_version/952-add-net-conntrack-events-support-multiple-registrant.patch"
        patch_952="952-add-net-conntrack-events-support-multiple-registrant.patch"
    elif [ "$kernel_version" = "5.10" ]; then
        patch_952_path="./target/linux/generic/hack-$kernel_version/952-net-conntrack-events-support-multiple-registrant.patch"
        patch_952="952-net-conntrack-events-support-multiple-registrant.patch"
    else
        # Kernel versions without bundled patches in the package branch (e.g. 5.4
        # on 21.02 based trees). lede style 21.02 trees already ship the 952/953
        # patches in target/linux/generic; otherwise fall back to the 5.4 patches
        # adapted for official 21.02 trees bundled in this repo
        # (patches/hack-5.4, patches/pending-5.4).
        patch_952="952-net-conntrack-events-support-multiple-registrant.patch"
        patch_952_path="./target/linux/generic/hack-$kernel_version/$patch_952"
        if [ -e "$TMPDIR/repo/patches/hack-$kernel_version/$patch_952" ]; then
            SRC_PATCH_DIR="$TMPDIR/repo/patches"
        elif [ -e "./target/linux/generic/hack-$kernel_version/952-add-net-conntrack-events-support-multiple-registrant.patch" ] || \
             [ -e "$patch_952_path" ]; then
            echo "Kernel $kernel_version: 952/953 patches already exist in tree, skip patching."
            continue
        elif [ "$FIREWALL_FLAVOR" = "fw3" ]; then
            echo "Kernel $kernel_version: no kernel patches available, skip patching (Shortcut-FE will not build if selected, flow offloading still works)."
            continue
        else
            echo "Unsupported kernel version: $kernel_version"
            exit 1
        fi
    fi

    for file_path in "$patch_952_path" "$patch_953_path" "$patch_613_path"; do
        if [ -a "$file_path" ]; then
            echo "$file_path already exists, delete."
            rm -rf "$file_path"
        fi
    done

    if [ -n "$SRC_PATCH_DIR" ]; then
        cp -f "$SRC_PATCH_DIR/hack-$kernel_version/$patch_952" "$patch_952_path"
        if [ "$NO_SFE" = false ]; then
            cp -f "$SRC_PATCH_DIR/hack-$kernel_version/953-net-patch-linux-kernel-to-support-shortcut-fe.patch" "$patch_953_path"
            cp -f "$SRC_PATCH_DIR/pending-$kernel_version/613-netfilter_optional_tcp_window_check.patch" "$patch_613_path"
        fi
    else
        cp -f "$TMPDIR/package/hack-$kernel_version/$patch_952" "$patch_952_path"
        if [ "$NO_SFE" = false ]; then
            cp -f "$TMPDIR/package/hack-$kernel_version/953-net-patch-linux-kernel-to-support-shortcut-fe.patch" "$patch_953_path"
            cp -f "$TMPDIR/package/pending-$kernel_version/613-netfilter_optional_tcp_window_check.patch" "$patch_613_path"
        fi
    fi

    if ! grep -q "CONFIG_NF_CONNTRACK_CHAIN_EVENTS" "./target/linux/generic/config-$kernel_version"; then
        echo "# CONFIG_NF_CONNTRACK_CHAIN_EVENTS is not set" >> "./target/linux/generic/config-$kernel_version"
    fi
    if [ "$NO_SFE" = false ] && ! grep -q "CONFIG_SHORTCUT_FE" "./target/linux/generic/config-$kernel_version"; then
        echo "# CONFIG_SHORTCUT_FE is not set" >> "./target/linux/generic/config-$kernel_version"
    fi
done

# Official 21.02 firewall3 has no fullcone option: --fw3-fullcone installs the
# xt_FULLCONENAT package and a firewall3 patch that adds the "fullcone" option
# (MASQUERADE -> FULLCONENAT, the classic 恩山/lede approach).
if [ "$FIREWALL_FLAVOR" = "fw3" ] && [ "$FW3_FULLCONE" = true ]; then
    cp -r "$TMPDIR/repo/fullconenat" "$TMPDIR/turboacc/fullconenat" || exit 1
fi

cp -r "$TMPDIR/turboacc" "./package/turboacc"

if [ "$FIREWALL_FLAVOR" = "fw4" ]; then
    # OpenWrt 22.03/23.05 (firewall4): replace firewall4/libnftnl/nftables with
    # fullcone-NAT patched versions from the package branch.
    FIREWALL4_VERSION=$(grep -o 'PKG_SOURCE_VERSION:=.*' ./package/network/config/firewall4/Makefile | cut -d '=' -f 2)
    NFTABLES_VERSION=$(grep -o 'PKG_VERSION:=.*' ./package/network/utils/nftables/Makefile | cut -d '=' -f 2)
    LIBNFTNL_VERSION=$(grep -o 'PKG_VERSION:=.*' ./package/libs/libnftnl/Makefile | cut -d '=' -f 2)

    rm -rf ./package/libs/libnftnl ./package/network/config/firewall4 ./package/network/utils/nftables

    if ! [ -d "$TMPDIR/package/firewall4-$FIREWALL4_VERSION" ]; then
        echo "firewall4 version $FIREWALL4_VERSION not found, using latest version"
        FIREWALL4_VERSION=$(grep -o 'FIREWALL4_VERSION=.*' "$TMPDIR/package/version" | cut -d '=' -f 2)
    fi
    if ! [ -d "$TMPDIR/package/nftables-$NFTABLES_VERSION" ]; then
        echo "nftables version $NFTABLES_VERSION not found, using latest version"
        NFTABLES_VERSION=$(grep -o 'NFTABLES_VERSION=.*' "$TMPDIR/package/version" | cut -d '=' -f 2)
    fi
    if ! [ -d "$TMPDIR/package/libnftnl-$LIBNFTNL_VERSION" ]; then
        echo "libnftnl version $LIBNFTNL_VERSION not found, using latest version"
        LIBNFTNL_VERSION=$(grep -o 'LIBNFTNL_VERSION=.*' "$TMPDIR/package/version" | cut -d '=' -f 2)
    fi
    cp -RT "$TMPDIR/package/firewall4-$FIREWALL4_VERSION/firewall4" ./package/network/config/firewall4
    cp -RT "$TMPDIR/package/libnftnl-$LIBNFTNL_VERSION/libnftnl" ./package/libs/libnftnl
    cp -RT "$TMPDIR/package/nftables-$NFTABLES_VERSION/nftables" ./package/network/utils/nftables
else
    # OpenWrt 21.02 (firewall3): keep the tree's own firewall packages untouched.
    # On lede/immortalwrt style trees the firewall3 "fullcone" option already
    # works; on official 21.02 pass --fw3-fullcone to install fullcone support.
    echo "firewall3 detected, keep firewall/libnftnl/nftables untouched (fullcone via firewall3 option)"
    if [ "$FW3_FULLCONE" = true ]; then
        mkdir -p ./package/network/config/firewall/patches
        cp -f "$TMPDIR/repo/patches/firewall3/100-fullconenat.patch" ./package/network/config/firewall/patches/ || exit 1
        echo "firewall3 fullcone support installed (firewall3 patch + fullconenat package)"
    else
        echo "hint: pass --fw3-fullcone to enable FullCone NAT on official firewall3 (21.02)"
    fi
fi

echo "Finish"
exit 0
