
## Freezing package state

An unattended upgrade cannot brick this box: the kernel is not a package, it is
an image we flash into the boot partition, and `/boot` is empty. What an update
could still do is replace a userspace package and break a service on a machine
that is only reachable over the network, so all automatic package activity is
off:

* `apt-daily.timer` / `apt-daily-upgrade.timer` - disabled **and masked**
  (masked means nothing can start them, not even a dependency).
* `/etc/apt/apt.conf.d/99-no-auto-update` - `APT::Periodic::Enable "0"` plus the
  individual `Update-Package-Lists` / `Download-Upgradeable-Packages` /
  `Unattended-Upgrade` switches, so the timers would do nothing even if they were
  re-enabled.
* `motd-news.timer` - disabled, it only fetched a news blurb over the network.
* `unattended-upgrades` was never installed, and there is no snapd.

Manual `apt-get` still works, so packages can be installed deliberately:

```
apt-get update && apt-get upgrade     # when you choose to
```

Remaining timers are ordinary maintenance and harmless: tmpfiles-clean,
dpkg-db-backup, e2scrub_all, fstrim.
