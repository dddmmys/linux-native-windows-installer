#!/usr/bin/env bash
# ============================================================================
# 纯 Linux 下手动安装 Windows 11 专业工作站版完整指南
# 假设：当前工作目录即为 Windows ISO 文件所在目录
# 目标磁盘：/dev/nvme0n1（1TB NVMe SSD）— 请根据实际情况修改！
# ISO 文件：zh-cn_windows_11_consumer_editions_version_26h1_updated_may_2026_x64_dvd_b733cc65.iso
# ============================================================================

set -e  # 遇到错误立即退出

# ----------------------------------- 准备阶段 -----------------------------------
# 1. 解压 Windows ISO（UDF 格式，直接 7z 解压到 ./win11_files）
mkdir -p ./win11_files
7z x ./zh-cn_windows_11_consumer_editions_version_26h1_updated_may_2026_x64_dvd_b733cc65.iso -o./win11_files

# 2. 确认目标磁盘及分区布局（请根据 lsblk 输出修改设备名）
#    假设：/dev/nvme0n1p1 → EFI 系统分区 (512 MiB, FAT32)
#          /dev/nvme0n1p2 → MSR 分区 (128 MiB, 无需格式化)
#          /dev/nvme0n1p3 → Windows 系统分区 (剩余空间, NTFS)
#    分区操作可使用 cfdisk / gdisk 手动完成，此处不再自动执行。

# ----------------------------------- 格式化与挂载 -----------------------------------
# 3. 格式化 EFI 分区为 FAT32
sudo mkfs.fat -F32 /dev/nvme0n1p1

# 4. 格式化系统分区为 NTFS
sudo mkfs.ntfs -f /dev/nvme0n1p3

# 5. 创建挂载点并挂载分区
sudo mkdir -p /mnt/windows /mnt/boot
sudo mount /dev/nvme0n1p3 /mnt/windows
sudo mount /dev/nvme0n1p1 /mnt/boot

# ----------------------------------- 部署 Windows 镜像 -----------------------------------
# 6. 查看 install.wim 中包含的版本（选择需要的索引号，此处索引6为专业工作站版）
wiminfo ./win11_files/sources/install.wim

# 7. 应用镜像到系统分区（索引6：Windows 11 Pro for Workstations）
sudo wimapply ./win11_files/sources/install.wim 6 /dev/nvme0n1p3

# ----------------------------------- 配置 UEFI 引导文件 -----------------------------------
# 8. 在 ESP 分区中创建 Microsoft 引导目录
sudo mkdir -p /mnt/boot/EFI/Microsoft/Boot

# 9. 复制引导管理器（bootmgfw.efi）和初始 BCD 文件
sudo cp ./win11_files/bootmgfw.efi /mnt/boot/EFI/Microsoft/Boot/
sudo cp ./win11_files/efi/microsoft/boot/bcd /mnt/boot/EFI/Microsoft/Boot/

# ----------------------------------- 写入 UEFI 启动项（可选，GRUB 可替代） -----------------------------------
# 10. 使用 efibootmgr 创建独立的 Windows 启动项（便于直接引导）
sudo efibootmgr --create --disk /dev/nvme0n1 --part 1 \
    --loader "\\EFI\\Microsoft\\Boot\\bootmgfw.efi" \
    --label "Windows 11 Pro for Workstations"

# ----------------------------------- 修复 BCD 文件（关键步骤） -----------------------------------
# 11. 下载 pbcdedit（Linux 原生 BCD 编辑器）
wget http://cvs.schmorp.de/pbcdedit/pbcdedit
chmod +x ./pbcdedit

# 12. 获取 Windows 系统分区的 BCD device 描述符
DEVICE=$(sudo ./pbcdedit bcd-device /dev/nvme0n1p3)

# 13. 获取当前 BCD 中的默认启动项 GUID
DEFAULT_GUID=$(sudo ./pbcdedit parse /mnt/boot/EFI/Microsoft/Boot/BCD get "{bootmgr}" default)

# 14. 修改 device 和 osdevice 指向正确的系统分区
sudo ./pbcdedit edit /mnt/boot/EFI/Microsoft/Boot/BCD \
    set "$DEFAULT_GUID" device "$DEVICE" \
    set "$DEFAULT_GUID" osdevice "$DEVICE"

# 15. 移除 WinPE 模式标志，修正路径为正常系统引导文件，修改描述
sudo ./pbcdedit edit /mnt/boot/EFI/Microsoft/Boot/BCD \
    del "$DEFAULT_GUID" winpe \
    set "$DEFAULT_GUID" path "\\Windows\\system32\\winload.efi" \
    set "$DEFAULT_GUID" description "Windows 11 Pro for Workstations"

# ----------------------------------- 集成到 GRUB 引导菜单 -----------------------------------
# 16. 获取 ESP 分区的 UUID（用于 GRUB 的 search 命令）
EFI_UUID=$(sudo blkid -s UUID -o value /dev/nvme0n1p1)

# 17. 将 Windows 启动项追加到 /boot/grub/grub.cfg
cat >> /boot/grub/grub.cfg << EOF

menuentry "Windows 11 Pro for Workstations" {
    insmod fat
    insmod chain
    search --fs-uuid --set=root $EFI_UUID
    chainloader /EFI/Microsoft/Boot/bootmgfw.efi
}
EOF

# ----------------------------------- 清理与重启 -----------------------------------
# 18. 卸载分区
sudo umount /mnt/windows /mnt/boot

# 19. 重启系统
echo "所有步骤完成，现在可以重启进入 Windows 11 完成首次设置。"
echo "若 GRUB 未显示 Windows 选项，请检查 /boot/grub/grub.cfg 并确保 EFI 分区 UUID 正确。"
# sudo reboot
