#!/bin/bash

# 1. Safely handle folder creation and entry
VM_DIR="windows_vm"
if [[ "$PWD" != *"$VM_DIR"* ]]; then
    if [ ! -d "$VM_DIR" ]; then
        echo "Creating directory: $VM_DIR..."
        mkdir -p "$VM_DIR"
    fi
    cd "$VM_DIR" || exit 1
fi

echo "Current working directory: $PWD"

# 2. Handle the ISO Download with Browser Emulation
ISO_FILE="Win10_21H1_English_x64.iso"
# Ensure this entire URL line is fully copied!
ISO_URL="https://archive.org/download/win-10-21-h-1-english-x-64/Win10_21H1_English_x64.iso"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

download_iso() {
    echo "Starting automated download of Windows 10 ISO..."
    if command -v wget &> /dev/null; then
        wget -c --user-agent="$USER_AGENT" -O "$ISO_FILE" "$ISO_URL"
    elif command -v curl &> /dev/null; then
        curl -C - -L -A "$USER_AGENT" -o "$ISO_FILE" "$ISO_URL"
    else
        echo "❌ Error: Neither wget nor curl is installed on the host machine."
    fi
}

# If file doesn't exist, try downloading it
if [ ! -f "$ISO_FILE" ]; then
    download_iso
fi

# Validate file size
FILE_SIZE=$(stat -c%s "$ISO_FILE" 2>/dev/null || stat -f%z "$ISO_FILE" 2>/dev/null)

if [ -z "$FILE_SIZE" ] || [ "$FILE_SIZE" -lt 3500000000 ]; then
    echo ""
    echo "⚠️ Warning: The file size is only $((FILE_SIZE/1024/1024)) MB (Should be ~5400 MB)."
    echo "The automated download link might have dropped or failed."
    echo ""
    read -p "Do you want to ignore this warning and try booting anyway? (y/N): " choice
    if [[ ! "$choice" =~ ^[Yy]$ ]]; then
        echo ""
        echo "💡 QUICK WORKAROUND:"
        echo "1. Open your web browser and manually download the ISO from:"
        echo "   $ISO_URL"
        echo "2. Save or move it exactly here: $PWD/$ISO_FILE"
        echo "3. Run this script again!"
        echo ""
        exit 1
    fi
else
    echo "✅ Success: Windows 10 ISO verified ($((FILE_SIZE/1024/1024/1024)) GB)."
fi

# 3. Check and Create Virtual Hard Disk if missing
DISK_FILE="my_disk.qcow2"
if [ ! -f "$DISK_FILE" ]; then
    echo "Virtual disk missing. Provisioning 50GB storage image..."
    qemu-img create -f qcow2 "$DISK_FILE" 50G
else
    echo "Virtual disk image detected."
fi

# 4. Dynamically find the system's UEFI / OVMF firmware file
OVMF_PATHS=(
    "/usr/share/ovmf/OVMF.fd"
    "/usr/share/edk2/x64/OVMF.fd"
    "/usr/share/edk2-ovmf/x64/OVMF_CODE.fd"
)

BIOS_PARAM=""
for path in "${OVMF_PATHS[@]}"; do
    if [ -f "$path" ]; then
        BIOS_PARAM="-bios $path"
        break
    fi
done

if [ -z "$BIOS_PARAM" ]; then
    echo "Warning: UEFI firmware (OVMF) file not detected. Falling back to default BIOS mode."
fi

# 5. Boot the Virtual Machine configuration
echo "🚀 Launching Windows 10 Virtual Machine..."
qemu-system-x86_64 \
  -enable-kvm \
  -machine q35 \
  -cpu host \
  -smp 4 \
  -m 8G \
  $BIOS_PARAM \
  -drive file="$DISK_FILE",format=qcow2,if=ide \
  -cdrom "$ISO_FILE" \
  -boot d \
  -vga std \
  -audiodev pa,id=snd0 \
  -device ich9-intel-hda -device hda-output,audiodev=snd0 \
  -net nic,model=e1000 -net user

