#!/bin/sh
# connman 崩溃自愈守护（Claude 维护，2026-10-03）
# 背景：Batocera 自带的 connman 在「有线掉线、无线接管默认路由」的瞬间会段错误崩溃。
# 崩溃后 WiFi 链路本身仍在（内核 + wpa_supplicant 都活着），但 connman 的联网管理
# （游戏机面板里的网络菜单、自动重连）会失效，所以这里每 20 秒检查一次，掉了就拉起来。
LOG=/userdata/system/aic8800/connman-watchdog.log
while true; do
	sleep 20
	if ! pgrep -x connmand >/dev/null 2>&1; then
		echo "$(date '+%F %T') connmand 不在，重新拉起" >> "$LOG"
		/etc/init.d/S08connman start >> "$LOG" 2>&1
	fi
done
