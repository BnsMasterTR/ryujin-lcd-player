# Compatibility reference

These are shared hardware/protocol compatibility values used by the software. They identify a product family and a firmware build. Individual unit serial numbers, USB instance paths and account/device identifiers are separate information.

| Requirement | Current target |
| --- | --- |
| Product family | ASUS ROG Ryujin III 360, standard model |
| USB vendor/product identifiers | 0B05:1AA2 |
| Upload protocol firmware check | AURJ2-S750-0108 |
| Prepared media | 320 x 240 GIF/JPEG |
| Host | Windows x64, Windows PowerShell 5.1, .NET Framework 4.x |

The upload routine checks the firmware before sending files. The constants remain visible in the open source so users can assess compatibility. Tests on one target do not establish support for other variants.

The firmware identifier is also published in the upstream protocol research referenced in the README.

USB vendor/product identifiers are described in [Microsoft's USB hardware identifier documentation](https://learn.microsoft.com/en-us/windows-hardware/drivers/install/standard-usb-identifiers).

## Information in bug reports

The error message, application version and product variant are usually useful for initial troubleshooting. Review logs and screenshots before publishing them. Redact serial numbers, full USB instance paths, account details, private file names and personal media.
