#!/bin/bash

BASE_DIR="./vms"

# ------------------------------
# Auto-detect OVMF
if [[ -f "/usr/share/OVMF/OVMF_CODE.fd" && -f "/usr/share/OVMF/OVMF_VARS.fd" ]]; then
    OVMF_CODE="/usr/share/OVMF/OVMF_CODE.fd"
    OVMF_VARS_TEMPLATE="/usr/share/OVMF/OVMF_VARS.fd"
elif [[ -f "/usr/share/edk2-ovmf/x64/OVMF_CODE.4m.fd" && -f "/usr/share/edk2-ovmf/x64/OVMF_VARS.4m.fd" ]]; then
    OVMF_CODE="/usr/share/edk2-ovmf/x64/OVMF_CODE.4m.fd"
    OVMF_VARS_TEMPLATE="/usr/share/edk2-ovmf/x64/OVMF_VARS.4m.fd"
else
    OVMF_CODE=""
    OVMF_VARS_TEMPLATE=""
fi

# ------------------------------
# VM Name
read -rp "Enter virtual machine name [vm1]: " VM_NAME
VM_NAME=${VM_NAME:-vm1}

# CPU
read -rp "Enter number of virtual CPUs [2]: " CPU_COUNT
CPU_COUNT=${CPU_COUNT:-2}

# RAM
read -rp "Enter RAM size in GB [4]: " RAM_GB
RAM_GB=${RAM_GB:-4}
RAM_MB=$(( RAM_GB * 1024 ))

# Disk
read -rp "Enter disk size in GB [20]: " DISK_GB
DISK_GB=${DISK_GB:-20}

VM_DIR="$BASE_DIR/$VM_NAME"
mkdir -p "$VM_DIR"

DISK="$VM_DIR/$VM_NAME.qcow2"
echo "Creating disk $DISK with size ${DISK_GB}G..."
qemu-img create -f qcow2 "$DISK" "${DISK_GB}G"

# ------------------------------
# UEFI Selection (OPTIONS CHANGED)
echo
echo "Use UEFI (OVMF) instead of BIOS?"
echo "  1) No (regular BIOS)"
echo "  2) Yes (UEFI, for Windows 11)"
read -rp "Your choice [1]: " USE_UEFI
USE_UEFI=${USE_UEFI:-1}

# ------------------------------
# Disk Controller Selection (OPTIONS CHANGED)
echo
echo "Select disk controller type:"
echo "  1) Virtio (for Linux, fastest)"
echo "  2) IDE (for older OS, slower)"
echo "  3) Virtio (for Windows, requires manual driver load)"
read -rp "Your choice [1]: " DISK_MODE
DISK_MODE=${DISK_MODE:-1}

DISK_DRIVE_OPTS="-drive file='$(realpath "$DISK")',id=main_disk,if=none,format=qcow2"
DISK_DEVICE_OPTS_INSTALL=""
DISK_DEVICE_OPTS_START=""
NEED_VIRTIO_DRIVER=false
VIRTIO_ISO="virtio-win.iso"

case $DISK_MODE in
    1|3) # For VirtIO SCSI
        DISK_DEVICE_OPTS_INSTALL="-device virtio-scsi-pci,id=scsi0 -device scsi-hd,drive=main_disk,bus=scsi0.0,bootindex=-1"
        DISK_DEVICE_OPTS_START="-device virtio-scsi-pci,id=scsi0 -device scsi-hd,drive=main_disk,bus=scsi0.0"
        if [[ "$DISK_MODE" == "3" ]]; then
          NEED_VIRTIO_DRIVER=true
        fi
        ;;
    2) # For IDE
        DISK_DEVICE_OPTS_INSTALL="-device ide-hd,drive=main_disk,bus=ide.2,bootindex=-1"
        DISK_DEVICE_OPTS_START="-device ide-hd,drive=main_disk,bus=ide.2"
        ;;
    *) echo "❌ Invalid choice"; exit 1 ;;
esac

if $NEED_VIRTIO_DRIVER; then
    if [[ ! -f "$VIRTIO_ISO" ]]; then
        echo "🔽 Downloading virtio-win.iso..."
        wget -q --show-progress -O virtio-win.iso "https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/latest-virtio/virtio-win.iso"
    fi
    VIRTIO_ISO="$(realpath "$VIRTIO_ISO")"
fi

# ------------------------------
# Network Adapter Selection (OPTIONS CHANGED)
echo
echo "Select network adapter:"
echo "  1) Virtio (for Linux, faster)"
echo "  2) E1000 (for Windows)"
read -rp "Your choice [1]: " NET_TYPE
NET_TYPE=${NET_TYPE:-1}

if [[ "$NET_TYPE" == "1" ]]; then
    NET_DEVICE='-device virtio-net-pci,netdev=net0'
else
    NET_DEVICE='-device e1000-82545em,netdev=net0'
fi

# ------------------------------
# ISO Selection
echo
echo "🔍 Found ISO images:"
mapfile -t ISOS < <(find . -maxdepth 1 -type f -iname "*.iso" ! -name "virtio-win.iso")
for i in "${!ISOS[@]}"; do printf "  [%d] %s\n" "$i" "${ISOS[$i]}"; done
read -rp "Select ISO file number: " ISO_INDEX
ISO_ABS_PATH="$(realpath "${ISOS[$ISO_INDEX]}")"

# ------------------------------
# Prepare optional parameters for script generation

VIRTIO_DRIVES_INSTALL=""
if $NEED_VIRTIO_DRIVER; then
    VIRTIO_DRIVES_INSTALL="\\
  -drive file=$VIRTIO_ISO,id=virtio_cd,if=none,media=cdrom,readonly=on \\
  -device ide-cd,drive=virtio_cd,bus=ide.1"
fi

UEFI_DRIVES=""
# ATTENTION: Logic changed due to option order modification
if [[ "$USE_UEFI" == "2" && -n "$OVMF_CODE" ]]; then
    cp "$OVMF_VARS_TEMPLATE" "$VM_DIR/$VM_NAME-OVMF_VARS.fd"
    UEFI_DRIVES="\\
  -drive if=pflash,format=raw,readonly=on,file=$(realpath "$OVMF_CODE") \\
  -drive if=pflash,format=raw,file='$(realpath "$VM_DIR/$VM_NAME-OVMF_VARS.fd")'"
fi

# ------------------------------
# Generate install.sh
cat > "$VM_DIR/install.sh" <<EOF
#!/bin/bash
qemu-system-x86_64 \\
  -name "$VM_NAME-install" \\
  -machine type=q35,accel=kvm,vmport=off \\
  -cpu max \\
  -smp $CPU_COUNT \\
  -m $RAM_MB \\
  $DISK_DRIVE_OPTS \\
  $DISK_DEVICE_OPTS_INSTALL \\
  -drive file=$ISO_ABS_PATH,id=install_cd,if=none,media=cdrom,readonly=on \\
  -device ide-cd,drive=install_cd,bus=ide.0,bootindex=1 ${VIRTIO_DRIVES_INSTALL} ${UEFI_DRIVES} \\
  -vga std \\
  -device qemu-xhci \\
  -device usb-tablet \\
  -netdev user,id=net0 \\
  $NET_DEVICE \\
  -display gtk
EOF

# ------------------------------
# Generate "smart" and portable start.sh
SPICE_PORT=$((5900 + RANDOM % 1000))

# Collect all options into a single variable for clarity
QEMU_OPTS=(
  -name '"$VM_NAME"'
  -machine type=q35,accel=kvm,vmport=off
  -cpu host
  -smp "$CPU_COUNT"
  -m "$RAM_MB"
  -drive '"file=$VM_DIR/$VM_NAME.qcow2",id=main_disk,if=none,format=qcow2'
  "$DISK_DEVICE_OPTS_START"
)

if $NEED_VIRTIO_DRIVER; then
    QEMU_OPTS+=(-drive "file=$VIRTIO_ISO,id=virtio_cd,if=none,media=cdrom,readonly=on" -device "ide-cd,drive=virtio_cd,bus=ide.1")
fi

if [[ "$USE_UEFI" == "2" && -n "$OVMF_CODE" ]]; then
    QEMU_OPTS+=(-drive "if=pflash,format=raw,readonly=on,file=$(realpath "$OVMF_CODE")" -drive '"if=pflash,format=raw,file=$VM_DIR/$VM_NAME-OVMF_VARS.fd"')
fi

QEMU_OPTS+=(
  -vga qxl
  -device qemu-xhci
  -device usb-tablet
  -netdev user,id=net0
  "$NET_DEVICE"
  -spice "port=$SPICE_PORT,disable-ticketing=on"
  -display none
  -monitor stdio
  -device virtio-serial
  -chardev spicevmc,id=char0,name=vdagent
  -device virtserialport,chardev=char0,name=com.redhat.spice.0
)

# Use cat <<'EOF' to prevent variable expansion during generation
cat > "$VM_DIR/start.sh" <<'EOF'
#!/bin/bash
# This script starts the VM and SPICE client, and also stops them correctly

# --- BEGIN AUTOMATIC PATH DETECTION ---
VM_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
VM_NAME=$(basename "$VM_DIR")
# --- END AUTOMATIC PATH DETECTION ---

QEMU_PID=0

cleanup() {
    echo
    echo "Shutting down..."
    if [[ $QEMU_PID -ne 0 ]] && ps -p $QEMU_PID > /dev/null; then
        echo "Sending shutdown command to QEMU (PID: $QEMU_PID)..."
        kill $QEMU_PID
    fi
}

trap 'cleanup' INT TERM

echo "Starting virtual machine '$VM_NAME' in background..."

# Dynamically substitute the port, as it must be defined in advance
SPICE_PORT=
EOF
# Dynamically add port and QEMU command
echo "SPICE_PORT=${SPICE_PORT}" >> "$VM_DIR/start.sh"
echo "qemu-system-x86_64 ${QEMU_OPTS[*]} &" >> "$VM_DIR/start.sh"

# Append the rest of the script using cat <<'EOF'
cat >> "$VM_DIR/start.sh" <<'EOF'

QEMU_PID=$!

echo "Waiting for SPICE server to start on port $SPICE_PORT..."
while ! ss -lnt | grep -q ":$SPICE_PORT"; do
    if ! ps -p $QEMU_PID > /dev/null; then
        echo "QEMU process terminated unexpectedly. Check the log."
        exit 1
    fi
    sleep 0.5
done

echo "SPICE server is ready. Launching remote-viewer..."
remote-viewer "spice://127.0.0.1:$SPICE_PORT"

wait $QEMU_PID
echo "Virtual machine stopped."
EOF


chmod +x "$VM_DIR/install.sh" "$VM_DIR/start.sh"

# ------------------------------
# Automatic installation start
echo
echo "✅ VM \"$VM_NAME\" created."
if $NEED_VIRTIO_DRIVER; then
    echo
    echo "⭐ IMPORTANT: DRIVER INSTALLATION INSTRUCTIONS ⭐"
    echo "1. When the Windows installer shows an empty disk list, click 'Load driver'."
    echo "2. Click 'Browse' and select the CD-ROM drive with the drivers (virtio-win...)."
    echo "3. Navigate to the folder: amd64 -> w10."
    echo "4. Click 'OK', the driver will be detected. Click 'Next'."
    echo "5. Your disk will appear in the list to continue the installation."
    echo
fi
echo "Starting installation..."
cd "$VM_DIR" || exit
./install.sh

echo
echo "================================================================="
echo "Installation complete. The VM is ready for use."
echo "To start, use the single command:"
echo "cd \"$VM_DIR\" && ./start.sh"
echo "Pressing Ctrl+C in this terminal will correctly terminate both processes (VM and client)."
echo "================================================================="