#!/bin/sh
# ============================================================
# 延迟启动任务（Claude 维护，2026-10-03）
# 由 /boot/boot-custom.sh 在 S00 阶段丢到后台启动。
# 为什么需要它：/userdata 分区要到开机 30 秒左右才挂载（S02/S04 才挂），
# 而 boot-custom.sh 在 S00（最早）执行时根本看不到 /userdata，
# 所以所有依赖 /userdata 的事情都放到这里、等挂载完成后再做。
# 内容：
#   1) 启动本机代理 mihomo（配置在 /userdata/system/mihomo/）
#   2) 加载 AIC8800 USB 无线网卡驱动（仅在 enable-autostart 标记存在时）
#   3) connman 崩溃自愈守护
# ============================================================
AIC_DIR=/userdata/system/aic8800
MIHOMO_DIR=/userdata/system/mihomo

# 等 /userdata 挂载好（最多 120 秒）
for i in $(seq 1 120); do
	[ -d /userdata/system ] && break
	sleep 1
done
[ -d /userdata/system ] || exit 0

# ---------- 1) 本机代理 mihomo ----------
if [ -x "$MIHOMO_DIR/mihomo" ] && ! pgrep -x mihomo >/dev/null 2>&1; then
	mkdir -p /userdata/system/logs
	setsid nohup "$MIHOMO_DIR/mihomo" -d "$MIHOMO_DIR" > /userdata/system/logs/mihomo.log 2>&1 < /dev/null &
fi

# ---------- 2) AIC8800 无线网卡驱动 ----------
[ -f "$AIC_DIR/enable-autostart" ] || exit 0
[ -f "$AIC_DIR/modules/aic8800_fdrv.ko" ] || exit 0
LOG="$AIC_DIR/aic8800-boot.log"

# 等网卡出现（U 盘模式 a69c:5721 或网卡模式 2357:0147），最多 20 秒
for i in $(seq 1 20); do
	lsusb | grep -qE "2357:0147|a69c:5721" && break
	sleep 1
done
# 还停在 U 盘模式就手动弹出切换（内置盘是 sda，要排除）
if lsusb | grep -q "a69c:5721"; then
	DONGLE_DEV=$(ls /dev/sd? 2>/dev/null | grep -v "^/dev/sda$" | head -1)
	[ -n "$DONGLE_DEV" ] && eject "$DONGLE_DEV"
	for i in $(seq 1 15); do
		lsusb | grep -q "2357:0147" && break
		sleep 1
	done
fi
if lsusb | grep -q "2357:0147"; then
	insmod "$AIC_DIR/modules/aic_load_fw.ko" aic_fw_path="$AIC_DIR/fw"
	insmod "$AIC_DIR/modules/aic8800_fdrv.ko" aic_fw_path="$AIC_DIR/fw" aicwf_dbg_level=3
	sleep 3
	rfkill unblock wifi
	connmanctl enable wifi >/dev/null 2>&1
	echo "$(date '+%F %T') insmod done; wlan=$(ls /sys/class/net | grep -c '^wlan')" >> "$LOG"

	# 开机时就没插网线（eth0 无 IP）且 WiFi 未自动连上 -> 主动连已保存的 WiFi
	# （Batocera 的 S08connman 只在开机头 15 秒等 wlan0，我们的驱动 30 秒后才加载，
	#   所以无网线冷启动时它等不到、已放弃；这里补一刀）
	sleep 5
	if ! ip -4 addr show eth0 2>/dev/null | grep -q "inet " && \
	   ! ip -4 addr show wlan0 2>/dev/null | grep -q "inet "; then
		SVC=$(connmanctl services 2>/dev/null | grep "^\*" | awk '{print $NF}' | head -1)
		if [ -n "$SVC" ]; then
			connmanctl connect "$SVC" >/dev/null 2>&1
			echo "$(date '+%F %T') no wired link; forced wifi connect: $SVC" >> "$LOG"
		else
			echo "$(date '+%F %T') no wired link; no saved wifi service found" >> "$LOG"
		fi
	fi
else
	echo "$(date '+%F %T') dongle not in WLAN mode (2357:0147), skip insmod" >> "$LOG"
fi

# ---------- 3) connman 崩溃自愈守护 ----------
# （有线掉线、无线接管的瞬间 Batocera 的 connman 会段错误，崩溃后 WiFi 链路仍在但管理面板失效）
if [ -x "$AIC_DIR/connman-watchdog.sh" ] && ! pgrep -f "connman-watchd[o]g" >/dev/null 2>&1; then
	setsid nohup "$AIC_DIR/connman-watchdog.sh" >/dev/null 2>&1 < /dev/null &
fi
exit 0
