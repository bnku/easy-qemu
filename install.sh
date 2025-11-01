#!/bin/bash

BASE_DIR="./vms"

# ------------------------------
# Автоопределение OVMF
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
# Имя ВМ
read -rp "Введите имя виртуальной машины [vm1]: " VM_NAME
VM_NAME=${VM_NAME:-vm1}

# CPU
read -rp "Введите количество виртуальных CPU [2]: " CPU_COUNT
CPU_COUNT=${CPU_COUNT:-2}

# RAM
read -rp "Введите объём RAM в ГБ [4]: " RAM_GB
RAM_GB=${RAM_GB:-4}
RAM_MB=$(( RAM_GB * 1024 ))

# Диск
read -rp "Введите размер диска в ГБ [20]: " DISK_GB
DISK_GB=${DISK_GB:-20}

VM_DIR="$BASE_DIR/$VM_NAME"
mkdir -p "$VM_DIR"

DISK="$VM_DIR/$VM_NAME.qcow2"
echo "Создание диска $DISK размером ${DISK_GB}G..."
qemu-img create -f qcow2 "$DISK" "${DISK_GB}G"

# ------------------------------
# Выбор UEFI (ОПЦИИ ИЗМЕНЕНЫ)
echo
echo "Использовать UEFI (OVMF) вместо BIOS?"
echo "  1) Нет (обычный BIOS)"
echo "  2) Да (UEFI, для Windows 11)"
read -rp "Ваш выбор [1]: " USE_UEFI
USE_UEFI=${USE_UEFI:-1}

# ------------------------------
# Выбор контроллера диска (ОПЦИИ ИЗМЕНЕНЫ)
echo
echo "Выберите тип контроллера диска:"
echo "  1) Virtio (для Linux, самый быстрый)"
echo "  2) IDE (для старых ОС, медленнее)"
echo "  3) Virtio (для Windows, требует ручной загрузки драйвера)"
read -rp "Ваш выбор [1]: " DISK_MODE
DISK_MODE=${DISK_MODE:-1}

DISK_DRIVE_OPTS="-drive file='$(realpath "$DISK")',id=main_disk,if=none,format=qcow2"
DISK_DEVICE_OPTS_INSTALL=""
DISK_DEVICE_OPTS_START=""
NEED_VIRTIO_DRIVER=false
VIRTIO_ISO="virtio-win.iso"

case $DISK_MODE in
    1|3) # Для VirtIO SCSI
        DISK_DEVICE_OPTS_INSTALL="-device virtio-scsi-pci,id=scsi0 -device scsi-hd,drive=main_disk,bus=scsi0.0,bootindex=-1"
        DISK_DEVICE_OPTS_START="-device virtio-scsi-pci,id=scsi0 -device scsi-hd,drive=main_disk,bus=scsi0.0"
        if [[ "$DISK_MODE" == "3" ]]; then
          NEED_VIRTIO_DRIVER=true
        fi
        ;;
    2) # Для IDE
        DISK_DEVICE_OPTS_INSTALL="-device ide-hd,drive=main_disk,bus=ide.2,bootindex=-1"
        DISK_DEVICE_OPTS_START="-device ide-hd,drive=main_disk,bus=ide.2"
        ;;
    *) echo "❌ Неверный выбор"; exit 1 ;;
esac

if $NEED_VIRTIO_DRIVER; then
    if [[ ! -f "$VIRTIO_ISO" ]]; then
        echo "🔽 Скачиваем virtio-win.iso..."
        wget -q --show-progress -O virtio-win.iso "https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/latest-virtio/virtio-win.iso"
    fi
    VIRTIO_ISO="$(realpath "$VIRTIO_ISO")"
fi

# ------------------------------
# Выбор сетевого адаптера (ОПЦИИ ИЗМЕНЕНЫ)
echo
echo "Выберите сетевой адаптер:"
echo "  1) Virtio (для Linux, быстрее)"
echo "  2) E1000 (для Windows)"
read -rp "Ваш выбор [1]: " NET_TYPE
NET_TYPE=${NET_TYPE:-1}

if [[ "$NET_TYPE" == "1" ]]; then
    NET_DEVICE='-device virtio-net-pci,netdev=net0'
else
    NET_DEVICE='-device e1000-82545em,netdev=net0'
fi

# ------------------------------
# Выбор ISO
echo
echo "🔍 Найдены ISO-образы:"
mapfile -t ISOS < <(find . -maxdepth 1 -type f -iname "*.iso" ! -name "virtio-win.iso")
for i in "${!ISOS[@]}"; do printf "  [%d] %s\n" "$i" "${ISOS[$i]}"; done
read -rp "Выберите номер ISO-файла: " ISO_INDEX
ISO_ABS_PATH="$(realpath "${ISOS[$ISO_INDEX]}")"

# ------------------------------
# Подготовка опциональных параметров для генерации скриптов

VIRTIO_DRIVES_INSTALL=""
if $NEED_VIRTIO_DRIVER; then
    VIRTIO_DRIVES_INSTALL="\\
  -drive file=$VIRTIO_ISO,id=virtio_cd,if=none,media=cdrom,readonly=on \\
  -device ide-cd,drive=virtio_cd,bus=ide.1"
fi

UEFI_DRIVES=""
# ВНИМАНИЕ: Логика изменена, т.к. поменялся порядок опций
if [[ "$USE_UEFI" == "2" && -n "$OVMF_CODE" ]]; then
    cp "$OVMF_VARS_TEMPLATE" "$VM_DIR/$VM_NAME-OVMF_VARS.fd"
    UEFI_DRIVES="\\
  -drive if=pflash,format=raw,readonly=on,file=$(realpath "$OVMF_CODE") \\
  -drive if=pflash,format=raw,file='$(realpath "$VM_DIR/$VM_NAME-OVMF_VARS.fd")'"
fi

# ------------------------------
# Генерация install.sh
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
# Генерация "умного" и портативного start.sh
SPICE_PORT=$((5900 + RANDOM % 1000))

# Собираем все опции в одну переменную для чистоты
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

# Используем cat <<'EOF', чтобы переменные не раскрывались на этапе генерации
cat > "$VM_DIR/start.sh" <<'EOF'
#!/bin/bash
# Этот скрипт запускает ВМ и SPICE-клиент, а также корректно их останавливает

# --- НАЧАЛО АВТОМАТИЧЕСКОГО ОПРЕДЕЛЕНИЯ ПУТЕЙ ---
VM_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
VM_NAME=$(basename "$VM_DIR")
# --- КОНЕЦ АВТОМАТИЧЕСКОГО ОПРЕДЕЛЕНИЯ ПУТЕЙ ---

QEMU_PID=0

cleanup() {
    echo
    echo "Завершение работы..."
    if [[ $QEMU_PID -ne 0 ]] && ps -p $QEMU_PID > /dev/null; then
        echo "Отправка команды на выключение QEMU (PID: $QEMU_PID)..."
        kill $QEMU_PID
    fi
}

trap 'cleanup' INT TERM

echo "Запуск виртуальной машины '$VM_NAME' в фоновом режиме..."

# Динамически подставляем порт, так как он должен быть определен заранее
SPICE_PORT=
EOF
# Динамически добавляем порт и команду QEMU
echo "SPICE_PORT=${SPICE_PORT}" >> "$VM_DIR/start.sh"
echo "qemu-system-x86_64 ${QEMU_OPTS[*]} &" >> "$VM_DIR/start.sh"

# Добавляем оставшуюся часть скрипта с помощью cat <<'EOF'
cat >> "$VM_DIR/start.sh" <<'EOF'

QEMU_PID=$!

echo "Ожидание запуска SPICE-сервера на порту $SPICE_PORT..."
while ! ss -lnt | grep -q ":$SPICE_PORT"; do
    if ! ps -p $QEMU_PID > /dev/null; then
        echo "Процесс QEMU неожиданно завершился. Проверьте лог."
        exit 1
    fi
    sleep 0.5
done

echo "SPICE-сервер готов. Запуск remote-viewer..."
remote-viewer "spice://127.0.0.1:$SPICE_PORT"

wait $QEMU_PID
echo "Виртуальная машина остановлена."
EOF


chmod +x "$VM_DIR/install.sh" "$VM_DIR/start.sh"

# ------------------------------
# Автоматический запуск установки
echo
echo "✅ ВМ \"$VM_NAME\" создана."
if $NEED_VIRTIO_DRIVER; then
    echo
    echo "⭐ ВАЖНО: ИНСТРУКЦИЯ ПО УСТАНОВКЕ ДРАЙВЕРА ⭐"
    echo "1. Когда установщик Windows покажет пустой список дисков, нажмите 'Загрузить драйвер'."
    echo "2. Нажмите 'Обзор' и выберите CD-дисковод с драйверами (virtio-win...)."
    echo "3. Перейдите в папку: amd64 -> w10."
    echo "4. Нажмите 'ОК', драйвер определится. Нажмите 'Далее'."
    echo "5. Ваш диск появится в списке для продолжения установки."
    echo
fi
echo "Запуск установки..."
cd "$VM_DIR" || exit
./install.sh

echo
echo "================================================================="
echo "Установка завершена. ВМ готова к использованию."
echo "Для запуска используйте единую команду:"
echo "cd \"$VM_DIR\" && ./start.sh"
echo "При нажатии Ctrl+C в этом терминале оба процесса (ВМ и клиент) будут корректно завершены."
echo "================================================================="