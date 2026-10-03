# 构建笔记（Batocera 43.1 / kernel 6.18.16 实测）

## 为什么编译这个驱动会翻车

Out-of-tree 内核模块与内核的接口靠 `struct module` 的内存布局对齐。
**布局由内核配置（defconfig）决定。** 用发行版通用配置编出来的模块，
拿到目标机上加载会报：

```
Number of configurations: 0
```

或 insmod 直接 `-EINVAL`。所以第一原则：

> **内核树必须用目标机自带的 defconfig 构建。**

## 准备内核树（以 Batocera 为例）

Batocera 的内核源码发布在官方仓库（tag `batocera-43.1` 等），
里面带目标机的 defconfig（x86_64 是 `linux_x86_64-defconfig.config`）：

```bash
tar xf linux-6.18.16.tar.xz && cd linux-6.18.16
cp /path/to/linux_x86_64-defconfig.config .config
make olddefconfig
make modules_prepare -j$(nproc)
```

### 验证布局是否对齐（加载前就能查）

把编好的 `.ko` 拿 `probe` 一下，或直接核对这些关键信息：

```bash
strings aic8800_fdrv.ko | grep vermagic
# 期望（Batocera 43.1）：6.18.16 SMP preempt mod_unload modversions
```

vermagic 一致 + `struct module` 布局探测（size/name/init/exit 偏移）
与目标内核一致 = 可以加载。Batocera 43.1 x86_64 实测值：
`size=1280 / name@24 / init@312 / exit@1192`。

## hosttools：modules_prepare 缺东西怎么办

`modules_prepare` 不需要完整编译器，但需要：

| 工具 | 提供者 | 用途 |
|---|---|---|
| `objtool` | 内核树自编（`tools/objtool`） | ORC unwinder / 校验 |
| `libelf-dev` | 系统包 | objtool 链接 |
| `libzstd-dev` | 系统包 | 内核压缩支持 |
| `bison` / `m4` / `flex` | 系统包 | 生成器 |

如果目标机/构建机是精简系统（比如从别的发行版借的环境），
可以把这些工具装进一个独立前缀（如 `hosttools/`），然后：

```bash
export PATH="$BASE/hosttools/usr/bin:$PATH"
export BISON_PKGDATADIR="$BASE/hosttools/usr/share/bison"
export M4="$BASE/hosttools/usr/bin/m4"
export PKG_CONFIG_PATH="$BASE/hosttools/usr/lib/x86_64-linux-gnu/pkgconfig:$BASE/hosttools/usr/share/pkgconfig"
# libelf.pc 里的 libdir 要指向 hosttools 内的实际路径
export LC_ALL=C
```

## 完整编译流程（实测可用）

```bash
BASE=/path/to/work
cd $BASE/linux-6.18.16
make modules_prepare -j$(nproc)

cd $BASE/AIC8800-Linux-Driver-main/drivers/aic8800
make KDIR=$BASE/linux-6.18.16 -j$(nproc)
# 符号未定义警告可忽略：KBUILD_MODPOST_WARN=1 make ... 可继续
```

产物：

```
aic_load_fw/aic_load_fw.ko
aic8800_fdrv/aic8800_fdrv.ko
```

两个都要，**加载顺序**：先 `aic_load_fw` 再 `aic8800_fdrv`。

## 加载参数

```bash
insmod aic_load_fw.ko  aic_fw_path=/userdata/system/aic8800/fw
insmod aic8800_fdrv.ko aic_fw_path=/userdata/system/aic8800/fw aicwf_dbg_level=3
```

- `aic_fw_path`：固件目录（里面应有 `aic8800DC/` 等子目录，共二十多个 bin）
- `aicwf_dbg_level`：1=ERROR 2=INFO 4=TRACE；`patch_tbl:` 类消息是 ERROR 级，默认可见

## 排障速查

| 现象 | 原因 | 处理 |
|---|---|---|
| `Number of configurations: 0` | defconfig 不匹配 | 用目标机官方 defconfig 重建内核树 |
| `insmod: invalid module format` | vermagic 不符 | 核对 `uname -r` 与 `strings *.ko \| grep vermagic` |
| 日志停在 `Start app: ..., FNCALL` 后 USB `-110` | DPD 校准路径卡死（见主 README 坑 2） | 本仓库补丁 + `aicwf_dpd_fw_calib=0`；**物理拔插 ≥10 秒**才能恢复 |
| 模块加载了但没 `wlan0` | 固件路径不对 / 固件缺失 | 检查 `aic_fw_path` 与固件目录内容 |
