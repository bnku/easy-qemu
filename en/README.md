# Script for Creating and Managing QEMU/KVM Virtual Machines
[Русская версия](../README.md)

This project provides an interactive Bash script (`install.sh`) that automates the process of creating, configuring, and launching virtual machines (VMs) using QEMU/KVM. The script generates portable and easy-to-use files for VM installation and subsequent startup.

## Key Features

*   **Interactive Setup:** The script prompts for VM parameters (CPU, RAM, disk size).
*   **Flexible Component Selection:** Allows choosing the firmware type (BIOS/UEFI), disk controller, and network adapter for optimal performance or compatibility.
*   **Automation:** Downloads necessary VirtIO drivers for Windows.
*   **Portability:** Generates a "smart" startup script (`start.sh`) that automatically detects VM file paths. This makes it easy to copy and move the VM directory.
*   **Convenient Management:** The generated `start.sh` launches both the VM and the SPICE client (`remote-viewer`) with a single command, and correctly terminates both processes on `Ctrl+C`.

## Dependency Installation

For the script to function fully, QEMU/KVM, OVMF firmware (for UEFI), and the SPICE client must be installed.

#### For Arch Linux and its derivatives:
```bash
sudo pacman -S qemu-full edk2-ovmf virt-viewer
```

#### For Debian, Ubuntu, and their derivatives:
```bash
sudo apt update
sudo apt install qemu-system-x86 qemu-utils ovmf virt-viewer
```

## How to Use

1.  **Place the script next to your ISO images:**
    ```bash
    $ ls -a
    .
    ..
    install.sh
    linuxmint.iso
    windows.iso
    ```
2.  **Make the script executable:**
    ```bash
    chmod +x install.sh
    ```
3.  **Run the script:**
    ```bash
    ./install.sh
    ```
4.  **Answer the questions** to configure your future VM.
5.  The script will create a directory `./vms/your_vm_name/` and automatically start the operating system installation process.
6.  After installation is complete, use the following command to start the VM:
    ```bash
    cd ./vms/your_vm_name/
    ./start.sh
    ```

## Explanation of Configuration Options

The script offers several key choices that affect VM performance and compatibility.

#### 1. Use UEFI (OVMF) instead of BIOS?
*   **No (regular BIOS)** (default): The classic option, compatible with most older and many modern OS. Ideal for most Linux distributions and Windows 10.
*   **Yes (UEFI)**: The modern firmware standard. **Required for installing Windows 11** and some modern Linux distributions in UEFI mode.

#### 2. Select disk controller type
*   **Virtio (for Linux, fastest)** (default): Provides maximum disk performance through paravirtualization. Drivers are built into the Linux kernel, making this the best choice for Linux systems.
*   **IDE**: Emulation of an old but universal controller. Slower speed, but maximum compatibility. Use for very old OS (e.g., Windows XP).
*   **Virtio (for Windows)**: The same fast controller, but requires **manual driver installation** during Windows setup (see instructions below).

#### 3. Select network adapter
*   **Virtio** (default): The fastest network adapter. Requires driver installation in Windows (usually from the same `virtio-win.iso` disk).
*   **E1000**: Emulation of a popular Intel network card. Slower speed, but drivers are built into most OS, including Windows, simplifying installation.


#### 4. Recommendations for Option Selection
*   For Linux distributions, choose all default options: **1, 1, 1**
*   For Windows 10/11: **2, 3, 2**

---

## Windows Installation Guide

When using VirtIO components (disk, network, video) for maximum performance, drivers must be installed within the guest Windows. The `start.sh` script automatically attaches the `virtio-win.iso` image as a CD-ROM drive for these purposes.

### 0. Booting the installer

When QEMU starts, it will prompt you to press any key to boot from CD multiple times: first for the installer CD, second for the `virtio-win.iso` CD. You need to press any key the first time – immediately after QEMU starts.

If you ignore these messages, booting will continue from the `qcow2` disk (useful when the installer prompts for a system restart).

### 1. Disk Driver Installation (during Windows setup)

If you selected **"Virtio (for Windows)"** as the disk controller, you will see an empty list at the disk selection stage during installation.

1.  Click **"Load driver"**.
2.  Click **"Browse"**.
3.  Select the CD-ROM drive named `virtio-win...`.
4.  Navigate to the `amd64` -> `w10` folder.
5.  Click **"OK"**. The `Red Hat VirtIO SCSI controller` driver will be found.
6.  Click **"Next"**. Your virtual disk will appear in the list, and you can continue the installation.

#### 2. Instructions to bypass TPM and Secure Boot checks for Windows 11

On the screen where you see the error, do the following:

1.  Press the **`Shift + F10`** key combination on your keyboard. A black command prompt window will appear.
2.  In this window, type `regedit` and press `Enter`. The Registry Editor will open.
3.  In the left pane of the Registry Editor, navigate to:
    `HKEY_LOCAL_MACHINE\SYSTEM\Setup`
4.  Right-click on the `Setup` folder (key), select **New** -> **Key**.
5.  Name the new key `LabConfig` and press `Enter`.
6.  Now click on the created `LabConfig` key (to highlight it). In the right part of the window, right-click on an empty space and select **New** -> **DWORD (32-bit) Value**.
7.  Name this parameter `BypassTPMCheck` and press `Enter`.
8.  Create another identical parameter (**DWORD 32-bit**) and name it `BypassSecureBootCheck`.
9.  Now double-click on `BypassTPMCheck`, enter the number `1` in the **"Value data"** field and click "OK".
10. Do the same for `BypassSecureBootCheck`: double-click, enter `1` in the "Value data" field and click "OK".
11. Close the Registry Editor and the command prompt window.
12. In the Windows installer window, **click the blue "Back" arrow** in the upper left corner.
13. You will return to the Windows edition selection. Click **"Next"** again.

This time the check will pass successfully, and you can continue the installation as usual, including the stage with loading the driver for the VirtIO disk.

### 3. Working with a local Windows 11 account

If you do not want to use a Microsoft account to log in:

1.  Press the **`Shift + F10`** key combination on your keyboard. A black command prompt window will appear.
2.  In this window, type `start ms-cxh:localonly` and press `Enter`.
3.  A window will open where you need to come up with a login name and password, then click **"Next"**.

### 4. Video Driver and Guest Utilities Installation (after Windows installation)

After installing Windows, you will notice that the screen resolution options are limited.

1.  Start the VM and log in.
2.  Open **Device Manager** (Win+X -> Device Manager).
3.  Find **"Display adapters"** -> "Microsoft Basic Display Adapter".
4.  Right-click on it -> **"Update driver"** -> "Browse my computer for driver software".
5.  Click **"Browse"** and select the `virtio-win` CD-ROM. Make sure "Include subfolders" is checked. Click **"Next"**. The **QXL** driver will be installed automatically.
6.  After that, open the `virtio-win` CD-ROM in "This PC" and run the `virtio-win-guest-tools.exe` file. This will install SPICE guest services for better integration (shared clipboard, automatic window resolution change).

---

## Cloning (Duplicating) a VM

Thanks to the portability created by the script, cloning a VM is very simple.

1.  **Copy the directory** of an already installed VM:
    ```bash
    cp -r ./vms/win10 ./vms/win10-clone
    ```
2.  Navigate to the new directory:
    ```bash
    cd ./vms/win10-clone
    ```
3.  **Edit `start.sh`**. The script automatically determines the directory name and uses it as the VM name and disk file name (`.qcow2`). To avoid renaming files within the cloned folder, you need to change the `VM_NAME` variable to the name of the virtual machine FROM WHICH you are cloning.
    Find this line in `start.sh`:
    ```bash
    VM_NAME=$(basename "$VM_DIR")
    ```
    And replace it with the old VM name:
    ```bash
    VM_NAME=win10
    ```
4.  Start the new VM:
    ```bash
    ./start.sh
    ```
