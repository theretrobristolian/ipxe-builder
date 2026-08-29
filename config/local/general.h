/*
 * Local iPXE configuration for ipxe-builder.
 *
 * Keep this deliberately small.  The locally compiled image is used for the
 * legacy BIOS path; official release binaries remain authoritative for UEFI
 * and Secure Boot.
 */

#ifndef CONFIG_LOCAL_GENERAL_H
#define CONFIG_LOCAL_GENERAL_H

/* Interactive scripting / diagnostics */
#define CONSOLE_CMD
#define IMAGE_PNG

/* Useful network protocols and commands */
#define DOWNLOAD_PROTO_HTTPS
#define PING_CMD
#define NSLOOKUP_CMD
#define NTP_CMD
#define REBOOT_CMD
#define POWEROFF_CMD

#endif /* CONFIG_LOCAL_GENERAL_H */
