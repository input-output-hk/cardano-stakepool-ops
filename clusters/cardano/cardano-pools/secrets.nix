{ config, self, ... }: { secrets.encryptedRoot = "${self}/encrypted"; }
