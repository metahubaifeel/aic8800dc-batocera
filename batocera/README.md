# Batocera integration scripts

These scripts were tested on Batocera 43.1 (x86_64), fully automatic cold boot.

| File | Role |
|---|---|
| `boot-custom.sh` | Batocera official boot hook (stage S00). Writes the udev rule, then launches `boot-late.sh` **in the background** (do NOT block here: `/userdata` is not mounted yet at S00 and waiting would deadlock the boot). |
| `boot-late.sh` | Waits for `/userdata`, ejects the dongle out of fake-USB-disk mode, `insmod`s the driver, unblocks rfkill, enables WiFi, and (when booting without Ethernet) forces a connect to the saved network. |
| `connman-watchdog.sh` | Restarts connmand if it dies (it can SIGSEGV during the Ethernet→WiFi handover). |
| `99-aic-eject.rules` | udev rule: `eject` the fake USB disk (`a69c:5721`) so the dongle re-enumerates as a NIC (`2357:0147`). |

Notes:
- Paths inside the scripts assume the driver lives in
  `/userdata/system/aic8800/{modules,fw}` — adjust `AIC_DIR` as needed.
- `boot-custom.sh` also contains the original author's proxy setup (mihomo).
  That part is unrelated to the WiFi driver; delete it if you don't need it.
- `enable-autostart` marker file gates the driver autoload:
  `touch /userdata/system/aic8800/enable-autostart` to turn it on.
