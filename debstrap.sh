#!/bin/bash
set -e

# debstrap-sh - Bash-based Debian installer script

# Get the script directory (for self-contained operation)
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
LOG_FILE="$SCRIPT_DIR/debstrap.log"

# Setup logging
exec > >(tee -a "$LOG_FILE") 2>&1
echo "===== debstrap-sh started at $(date) ====="

# ========== Configuration ==========
# Default config file path (in the same directory as the script)
DEFAULT_CONFIG="$SCRIPT_DIR/debstrap.conf"
CONFIG_FILE=$DEFAULT_CONFIG

# No embedded default values - all settings must be in config file
# We'll just initialize the variables here
DISK=""
HOSTNAME=""
IP_ADDRESS=""
IP_NETMASK=""
IP_GATEWAY=""
DNS_SERVER=""
TIMEZONE=""
ADDITIONAL_PACKAGES=""
CHROOT_DIR=""
DEBIAN_ARCH=""
DEBIAN_CODENAME=""
NETWORK_INTERFACE=""

# ========== Functions ==========
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  -c, --config CONFIG      Configuration file to load (default: ./debstrap.conf)"
    echo "  -h, --help               Display this help message"
    exit 1
}

load_config() {
    local config_file="$1"

    # Check if config file exists
    if [ -f "$config_file" ]; then
        echo "Loading configuration from $config_file"
        # shellcheck source=/dev/null
        source "$config_file"
    else
        echo "Error: Configuration file $config_file not found."
        exit 1
    fi

    # Validate required settings
    if [ -z "$DISK" ] || [ -z "$HOSTNAME" ] || [ -z "$CHROOT_DIR" ] || [ -z "$NETWORK_INTERFACE" ]; then
        echo "Error: Required settings (DISK, HOSTNAME, CHROOT_DIR, NETWORK_INTERFACE) missing in config."
        exit 1
    fi
}

install_dependencies() {
    echo "Installing required packages..."
    apt-get install -y gdisk dosfstools arch-install-scripts debootstrap
}

# ========== Parse command line arguments ==========
while [ $# -gt 0 ]; do
    case "$1" in
        -c|--config)
            if [ -n "$2" ]; then
                CONFIG_FILE="$2"
                shift 2
            else
                echo "Error: -c|--config requires a file path."
                exit 1
            fi
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# ========== Load configuration ==========
# Always load from a config file - no embedded defaults
load_config "$CONFIG_FILE"

# ========== Install dependencies ==========
install_dependencies

# ========== Confirmation ==========
echo "Installation settings:"
echo "Disk: $DISK"
echo "Hostname: $HOSTNAME"
echo "Network Interface: $NETWORK_INTERFACE"
echo "IP Address: $IP_ADDRESS"
echo "Mount directory: $CHROOT_DIR"
echo "Debian architecture: $DEBIAN_ARCH"
echo "Debian codename: $DEBIAN_CODENAME"
echo
echo "Installation will begin in 5 seconds. Press Ctrl+C to abort..."
sleep 5

# ========== Partitioning ==========
echo "Starting disk partitioning on $DISK..."

# Initialize disk
sgdisk --zap-all "$DISK"

# Create GPT partition table and partitions
# Order: EFI System, Swap, Home, Root (for easier expansion of Root)
sgdisk --clear \
       --new=1:0:+500M --typecode=1:ef00 --change-name=1:"EFI System" \
       --new=2:0:+2G --typecode=2:8200 --change-name=2:"Swap" \
       --new=3:0:+5G --typecode=3:8300 --change-name=3:"Home" \
       --new=4:0:0 --typecode=4:8300 --change-name=4:"Root" \
       "$DISK"

# Set partition variables
DISK_EFI="${DISK}1"
DISK_SWAP="${DISK}2"
DISK_HOME="${DISK}3"
DISK_ROOT="${DISK}4"

# Display disk layout
sgdisk --print "$DISK"

# Create filesystems
echo "Creating filesystems..."
mkfs.fat -F32 "$DISK_EFI"
mkswap "$DISK_SWAP"
swapon "$DISK_SWAP"
mkfs.ext4 -F "$DISK_HOME"
mkfs.ext4 -F "$DISK_ROOT"

# ========== Mounting and Installation ==========
echo "Mounting filesystems..."
mkdir -p "$CHROOT_DIR"
mount "$DISK_ROOT" "$CHROOT_DIR"
mkdir -p "$CHROOT_DIR/boot/efi"
mkdir -p "$CHROOT_DIR/home"
mount "$DISK_EFI" "$CHROOT_DIR/boot/efi"
mount "$DISK_HOME" "$CHROOT_DIR/home"

# Install base system
echo "Installing Debian base system..."
debootstrap --arch="$DEBIAN_ARCH" "$DEBIAN_CODENAME" "$CHROOT_DIR" http://deb.debian.org/debian/

# Prepare chroot environment
echo "Preparing chroot environment..."
mount --rbind /dev "$CHROOT_DIR/dev"
mount -t proc none "$CHROOT_DIR/proc"
mount --rbind /sys "$CHROOT_DIR/sys"

# ========== System Configuration ==========
# Set hostname
echo "$HOSTNAME" > "$CHROOT_DIR/etc/hostname"

# Configure DNS
cat > "$CHROOT_DIR/etc/resolv.conf" << EOF
nameserver $DNS_SERVER
EOF

cat > "$CHROOT_DIR/etc/network/interfaces.d/$NETWORK_INTERFACE" << EOF
auto $NETWORK_INTERFACE
iface $NETWORK_INTERFACE inet static
    address $IP_ADDRESS
    netmask $IP_NETMASK
    gateway $IP_GATEWAY
EOF

# Generate fstab
echo "Generating fstab..."
genfstab -U "$CHROOT_DIR" > "$CHROOT_DIR/etc/fstab"

# Create system setup script
cat > "$CHROOT_DIR/tmp/setup.sh" << EOF
#!/bin/bash
set -e

# Pass variables to chroot environment
ADDITIONAL_PACKAGES="$ADDITIONAL_PACKAGES"
TIMEZONE="$TIMEZONE"

# Set environment variables
export DEBIAN_FRONTEND=noninteractive

# Set timezone
ln -sf /usr/share/zoneinfo/\$TIMEZONE /etc/localtime

# Install required packages
apt-get update
apt-get install -y linux-image-$DEBIAN_ARCH grub-efi-$DEBIAN_ARCH openssh-server \$ADDITIONAL_PACKAGES

# Install GRUB
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=debian
grub-mkconfig -o /boot/grub/grub.cfg

# Set root password (generate random password)
ROOT_PASSWORD=\$(tr -dc A-Za-z0-9 </dev/urandom | head -c 12)
echo "root:\$ROOT_PASSWORD" | chpasswd
echo "=== Root password: \$ROOT_PASSWORD ==="

# Create admin user
useradd -m -G sudo -s /bin/bash admin
ADMIN_PASSWORD=\$(tr -dc A-Za-z0-9 </dev/urandom | head -c 12)
echo "admin:\$ADMIN_PASSWORD" | chpasswd
echo "=== Admin password: \$ADMIN_PASSWORD ==="
EOF

# Execute setup script
echo "Running system setup..."
chmod +x "$CHROOT_DIR/tmp/setup.sh"
chroot "$CHROOT_DIR" /bin/bash /tmp/setup.sh

# Copy log file to the installed system
echo "Copying installation log to the new system..."
cp "$LOG_FILE" "$CHROOT_DIR/var/log/debstrap-install.log"

# Copy configuration to the installed system for reference
cp "$CONFIG_FILE" "$CHROOT_DIR/var/log/debstrap-config.log"

# Clean up temporary files
rm "$CHROOT_DIR/tmp/setup.sh"

echo "===== debstrap-sh completed at $(date) ====="
echo "System is ready. Please reboot."
