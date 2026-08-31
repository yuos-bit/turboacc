local kernel_version = luci.sys.exec("echo -n $(uname -r)")

m = Map("turboacc")
m.title	= translate("Turbo ACC Acceleration Settings")
m.description = translate("Opensource Flow Offloading driver (Fast Path or Hardware NAT)")

m:append(Template("turboacc/turboacc_status"))

s = m:section(TypedSection, "turboacc", "")
s.addremove = false
s.anonymous = true

-- nftables: nft_flow_offload is built-in mod (firewall4);
-- firewall3 (21.02) uses the iptables FLOWOFFLOAD target instead
if nixio.fs.access("/lib/modules/" .. kernel_version .. "/nft_flow_offload.ko")
or nixio.fs.access("/lib/modules/" .. kernel_version .. "/xt_FLOWOFFLOAD.ko") then
sw_flow = s:option(Flag, "sw_flow", translate("Software flow offloading"))
sw_flow.default = 0
sw_flow.description = translate("Software based offloading for routing/NAT")
sw_flow:depends("sfe_flow", 0)
end

-- Hardware flow offloading needs firewall4 (flowtable hw offload) plus a NIC
-- driver that implements it (mediatek/filogic mt7622/mt798x). MT7621/MT7620
-- have no hw offload driver on 21.02/fw3, so hide the option there.
if luci.sys.call("command -v fw4 >\"/dev/null\" 2>&1 && cat /etc/openwrt_release | grep -Eq 'mediatek|filogic' ") == 0 then
hw_flow = s:option(Flag, "hw_flow", translate("Hardware flow offloading"))
hw_flow.default = 0
hw_flow.description = translate("Requires hardware NAT support, implemented at least for mt762x")
hw_flow:depends("sw_flow", 1)
end

if luci.sys.call("cat /etc/openwrt_release | grep -Eq 'mediatek' ") == 0 then
if nixio.fs.access("/lib/modules/" .. kernel_version .. "/mt7915e.ko") then
hw_wed = s:option(Flag, "hw_wed", translate("MTK WED WO offloading"))
hw_wed.default = 0
hw_wed.description = translate("Requires hardware support, implemented at least for Filogic 8x0")
hw_wed:depends("hw_flow", 1)
end
-- MediaTek HNAT (mtkhnat), used on 21.02 based MTK targets (immortalwrt-mt798x)
if nixio.fs.access("/lib/modules/" .. kernel_version .. "/mtkhnat.ko") then
hnat_flow = s:option(Flag, "hnat_flow", translate("MediaTek HWNAT offloading"))
hnat_flow.default = 0
hnat_flow.description = translate("MediaTek HNAT hardware offloading (mtkhnat)")
hnat_flow:depends("sw_flow", 0)
hnat_flow:depends("sfe_flow", 0)
end
end

if nixio.fs.access("/lib/modules/" .. kernel_version .. "/shortcut-fe-cm.ko")
or nixio.fs.access("/lib/modules/" .. kernel_version .. "/fast-classifier.ko")
then
sfe_flow = s:option(Flag, "sfe_flow", translate("Shortcut-FE flow offloading"))
sfe_flow.default = 0
sfe_flow.description = translate("Shortcut-FE based offloading for routing/NAT")
sfe_flow:depends("sw_flow", 0)
sfe_flow:depends("hnat_flow", 0)
end

-- nftables (firewall4) or iptables FULLCONENAT (firewall3, 21.02)
if nixio.fs.access("/lib/modules/" .. kernel_version .. "/nft_fullcone.ko")
or luci.sys.call("iptables -m FULLCONENAT -h >\"/dev/null\" 2>&1") == 0
then
fullcone_nat = s:option(Flag, "fullcone_nat", translate("FullCone NAT"))
fullcone_nat.default = 0
fullcone_nat.description = translate("Using FullCone NAT can improve gaming performance effectively")
fullcone6 = s:option(Flag, "fullcone6", translate("IPv6 Full Cone NAT"))
fullcone6.default = 0
fullcone6.description = translate("Enabling IPv6 Full Cone NAT adds an extra layer of NAT to IPv6. In IPv6, if you obtain an IPv6 prefix through IPv6 Prefix Delegation, each device can be assigned a public IPv6 address, eliminating the need for IPv6 Full Cone NAT.")
fullcone6:depends("fullcone_nat", 1)
end

if nixio.fs.access("/lib/modules/" .. kernel_version .. "/tcp_bbr.ko") then
bbr_cca = s:option(Flag, "bbr_cca", translate("BBR CCA"))
bbr_cca.default = 0
bbr_cca.description = translate("Using BBR CCA can improve TCP network performance effectively")
end

return m
