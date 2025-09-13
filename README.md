# debstrap-sh

A Bash-based Debian installer script for consistent server deployments.

## Features

- Self-contained operation with minimal dependencies
- Configuration-driven approach with all settings in a single config file
- Modern GPT partitioning with support for EFI systems
- Flexible network configuration
- Support for different Debian architectures and releases
- Automatic log generation and preservation
- Focused on server deployments

## Requirements

- A Live Linux environment (like Debian Live CD)
- Root privileges
- Internet connection

## Dependencies

The script will automatically install these if not already present:
- sgdisk (for GPT partitioning)
- arch-install-scripts (for fstab generation)
- debootstrap (for base Debian installation)

## Usage

1. Boot into a Debian Live environment
2. Clone or copy this repository to the live environment
3. Customize the configuration file (debstrap.conf)
4. Run the installer script

```bash
# ./debstrap.sh
```

To use a custom configuration file:

```bash
# ./debstrap.sh -c /path/to/custom-config.conf
```

## Configuration

All settings are defined in the `debstrap.conf` file.

## Partitioning Scheme

The script creates the following partitions:

1. EFI System Partition (500MB)
2. Swap (2GB)
3. Home (5GB)
4. Root (remaining space)

This ordering places the root partition last, making it easier to expand if needed.

## Logs

Installation logs are saved in two locations:
- `debstrap.log` in the script directory during installation
- `/var/log/debstrap-install.log` in the installed system

## License

This project is licensed under the [MIT License](./LICENSE).
