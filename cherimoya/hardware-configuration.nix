# Do not modify this file!  It was generated by ‘nixos-generate-config’
# and may be overwritten by future invocations.  Please make changes
# to /etc/nixos/configuration.nix instead.
{ config, lib, pkgs, modulesPath, ... }:

{
  imports =
    [ (modulesPath + "/installer/scan/not-detected.nix")
    ];

  boot.initrd.availableKernelModules = [ "nvme" "xhci_pci" "usbhid" "usb_storage" "sd_mod" "sdhci_pci" ];
  boot.kernelModules = [ "kvm-amd" ];
  boot.initrd.kernelModules = [ "amdgpu" ];

  boot.kernelPackages = lib.mkForce pkgs.linuxPackages_5_19;

  fileSystems."/" =
    { device = "/dev/disk/by-uuid/40c2f90d-d172-4fdf-93d9-ce6df8679398";
      fsType = "btrfs";
    };

  boot.initrd.luks.devices."encryptedroot".device = "/dev/disk/by-uuid/a55c1e44-e83c-4445-90e3-76e02b8ef964";

  fileSystems."/boot" =
    { device = "/dev/disk/by-uuid/2761-EE05";
      fsType = "vfat";
    };

  # high-resolution display
  hardware.video.hidpi.enable = lib.mkDefault true;
}
