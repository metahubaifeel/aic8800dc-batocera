#!/bin/bash
# ============================================================
# 开机自定义脚本 — 由 Claude 维护（2026-10-03 更新）
# 本脚本在 S00（最早）执行，此时 /userdata 还没挂载（约开机 30 秒后才挂），
# 所以这里只做「不依赖 /userdata」的事（写 /etc），
# 依赖 /userdata 的任务（代理 mihomo、AIC8800 网卡驱动）统一交给
# /userdata/system/aic8800/boot-late.sh，丢到后台等挂载完成后再执行。
# 原理：游戏机的根目录每次开机重置，所以每次开机重新打补丁（幂等，可重复执行）
# 想停用：把本文件改名或删掉即可
# 旧版备份：boot-custom.sh.bak-claude / boot-custom.sh.bak2-claude
# ============================================================
PROXY="http://127.0.0.1:7890"
NOPROXY="localhost,127.0.0.1,192.168.0.0/16,10.0.0.0/8,172.16.0.0/12"

case "${1:-start}" in
start)
	# 1) X 会话：EmulationStation / RetroArch / Kodi / 内容下载器等全部继承代理
	XINITRC=/etc/X11/xinit/xinitrc
	if [ -f "$XINITRC" ] && ! grep -q "clash-lan-proxy" "$XINITRC"; then
		sed -i "s|^openbox --config-file|# clash-lan-proxy\nexport http_proxy=\"$PROXY\"\nexport https_proxy=\"$PROXY\"\nexport no_proxy=\"$NOPROXY\"\nopenbox --config-file|" "$XINITRC"
	fi
	# 2) SSH 登录的命令行也带上代理（方便 batocera-upgrade / wget 等）
	printf 'export http_proxy="%s"\nexport https_proxy="%s"\nexport no_proxy="%s"\n' "$PROXY" "$PROXY" "$NOPROXY" > /etc/profile.d/99-clash-proxy.sh
	# 3) AIC8800 USB 无线网卡：装 udev 规则（把网卡的“U 盘模式”自动弹出，切成 WLAN 模式）
	#    规则内容内嵌在这里，因为 S00 阶段读不到 /userdata 里的源文件
	cat > /etc/udev/rules.d/99-aic-eject.rules <<-'EOF'
	KERNEL=="sd*", ATTRS{idVendor}=="a69c", ATTRS{idProduct}=="5721",  SYMLINK+="aicudisk", RUN+="/usr/bin/eject /dev/%k"
	KERNEL=="sd*", ATTRS{idVendor}=="a69c", ATTRS{idProduct}=="5723",  SYMLINK+="tendaudisk", RUN+="/usr/bin/eject /dev/%k"
	KERNEL=="sd*", ATTRS{idVendor}=="a69c", ATTRS{idProduct}=="5724",  SYMLINK+="ugreenudisk", RUN+="/usr/bin/eject /dev/%k"
	EOF
	udevadm control --reload-rules 2>/dev/null
	# 4) 等 /userdata 挂载后再做的任务（代理 + 网卡驱动），后台执行不阻塞启动
	#    （不能在 S00 里同步等待：/userdata 要等后面的 S02/S04 脚本才挂载）
	setsid nohup sh -c '
		for i in $(seq 1 120); do [ -x /userdata/system/aic8800/boot-late.sh ] && break; sleep 1; done
		[ -x /userdata/system/aic8800/boot-late.sh ] && exec /userdata/system/aic8800/boot-late.sh
	' < /dev/null > /dev/null 2>&1 &
	;;
esac
exit 0
