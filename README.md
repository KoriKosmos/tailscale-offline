# Tailscale offline installer

A mirror of Tailscale's signed Windows MSIs, so Tailscale can be installed on a
machine that can't reach pkgs.tailscale.com. Keep this repo **private**.

## Install (offline)

```sh
git clone <this repo>
cd tailscale-offline
```

From Command Prompt or PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1        # or: .\install.ps1 1.88.4 / unstable
```

`install.ps1` checks the MSI's SHA-256 and its Authenticode signature (it must
be signed by Tailscale Inc., the same check Tailscale's own updater makes), then
runs it. It uses no .NET calls, so it also works in Constrained Language Mode.
If PowerShell scripts are blocked entirely, use the plain-cmd version, which
checks the SHA-256 only:

```bat
install.cmd
```

Tailscale installs a service and a network driver, so this needs local admin;
Windows shows an admin prompt when the MSI runs. Both scripts pass
`TS_CHECKUPDATES=never TS_INSTALLUPDATES=never` to the MSI, which turns off
update checks and auto-updates (they'd fail without pkgs.tailscale.com anyway).

<details><summary>Installing by hand, with no scripts at all</summary>

In Command Prompt (use `arm64` on ARM PCs):

```bat
cd tailscale-offline\releases\<version>\amd64
certutil -hashfile tailscale-setup-<version>-amd64.msi SHA256
type checksum
```

If the two hashes match:

```bat
msiexec /i tailscale-setup-<version>-amd64.msi TS_CHECKUPDATES=never TS_INSTALLUPDATES=never
```

</details>

Once installed, sign in from the tray icon or with `tailscale up`. Tailscale
still needs to reach its coordination server (controlplane.tailscale.com,
login.tailscale.com) and DERP relays (derp*.tailscale.com) over HTTPS. Only the
install is offline.

## Update the mirror (online)

If pkgs.tailscale.com is blocked where you are, let GitHub do it: in the repo's
**Actions** tab, pick **Mirror > Run workflow**. It runs `mirror.sh` and commits
the new MSIs. Then `git pull` and run the installer again to upgrade.

From any machine that can reach pkgs.tailscale.com:

```sh
./mirror.sh                    # latest stable, all three architectures
./mirror.sh unstable amd64     # one track, chosen architectures
./mirror.sh 1.88.4             # a specific version
git add releases && git commit -m "Mirror Tailscale <version>" && git push
```

Each version adds about 100MB for all three architectures; delete old
`releases/<version>/` folders to keep the repo small.
