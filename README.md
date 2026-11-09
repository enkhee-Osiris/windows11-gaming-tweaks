# Windows 11 Gaming Tweaks

A PowerShell script for Dota 2 and Counter-Strike 2. It enables Windows Game Mode and sets the Windows graphics preference to **High performance** for the two game executables it finds. The GPU preference is most useful on systems with integrated and discrete graphics, and the script preserves any specific adapter you selected. Results depend on your hardware and existing settings.

## Run from GitHub in one line

Close both games first. The repository is private, so this command uses [GitHub CLI](https://cli.github.com/) signed in with `gh auth login` on your Windows PC. It fetches the script from a fixed commit.

```powershell
& { $src = gh api --hostname github.com -H 'Accept: application/vnd.github.raw+json' 'repos/enkhee-Osiris/windows11-gaming-tweaks/contents/GamingTweaks.ps1?ref=84239e314161e5d243eef3e36b7979e6f00ffaee'; if ($LASTEXITCODE -ne 0 -or -not $src) { throw 'GitHub download failed.' }; & ([scriptblock]::Create($src -join "`n")) Apply }
```

Add `-WhatIf` immediately after `Apply` to preview. Replace `Apply` with `Restore` to undo.

## Run a local copy

Download or clone this repository, open PowerShell in the repository folder as your normal Windows user, and close both games. Run the preview first.

```powershell
.\GamingTweaks.ps1 Status
.\GamingTweaks.ps1 Apply -WhatIf
.\GamingTweaks.ps1 Apply
```

Use Windows PowerShell 5.1 or PowerShell 7. If PowerShell reports that running scripts is disabled on your personal PC, you can run the preview in a new process with a [session-only execution policy](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_execution_policies?view=powershell-5.1#set-a-different-policy-for-one-session).

```powershell
powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File .\GamingTweaks.ps1 Apply -WhatIf
```

Use the same command without `-WhatIf` to apply. If Windows flags the reviewed download as coming from the internet, unblock just that file with `Unblock-File -LiteralPath .\GamingTweaks.ps1`.

The script looks in your Steam installation and configured Steam libraries, including secondary drives. If it misses a game, provide the executable path in both the preview and the actual run. Either override can be used by itself.

```powershell
.\GamingTweaks.ps1 Apply -Dota2Path 'D:\SteamLibrary\steamapps\common\dota 2 beta\game\bin\win64\dota2.exe' -Cs2Path 'E:\SteamLibrary\steamapps\common\Counter-Strike Global Offensive\game\bin\win64\cs2.exe' -WhatIf
```

Restart any open game after applying or restoring. To compare performance, replay the same demo or scene with the same in-game settings before and after applying. Compare frame times or 1% lows alongside average FPS.

## Virtual memory and gaming performance

- **Page file.** While the game is stuttering, check **Task Manager → Performance → Memory → Committed**. The first number is current system-wide commit and the second is the current limit. If the first repeatedly approaches the second, verify that **Automatically manage paging file size for all drives** is enabled and that the page-file drive has free space. Extra commit headroom can prevent allocation failures when the system is near the limit. [Microsoft’s page-file sizing guidance](https://learn.microsoft.com/en-us/troubleshoot/windows-client/performance/how-to-determine-the-appropriate-page-file-size-for-64-bit-versions-of-windows)
- **Reported VRAM.** Intel documented `DedicatedSegmentSize` as a compatibility workaround for some older drivers. It changes the amount reported to apps and adds no graphics memory. [Intel driver release notes](https://www.intel.com/content/dam/support/us/en/documents/graphics/ReleaseNotes_GFX_15_36_21_4222.pdf)
- **Scheduler edits.** Microsoft documents that `SystemResponsiveness=0` is treated as 20 and that MMCSS does not use its `GPU Priority` value. [Microsoft’s MMCSS registry reference](https://learn.microsoft.com/en-us/windows/win32/procthread/multimedia-class-scheduler-service#registry-settings)
- **Memory Integrity and virtualization.** Benchmarks show the performance cost can vary by game and hardware. Memory Integrity protects the Windows kernel, and FACEIT Anti-Cheat can require it. Keep it enabled for everyday use. [Published VBS benchmarks](https://www.tomshardware.com/news/windows-vbs-harms-performance-rtx-4090) · [Microsoft security documentation](https://learn.microsoft.com/en-us/windows/security/hardware-security/enable-virtualization-based-protection-of-code-integrity) · [FACEIT requirements](https://support.faceit.com/hc/en-us/articles/8546882512284-Enabling-Memory-Integrity-HVCI)

For a manual A/B test in either game, try **Settings → System → Display → Graphics → Optimizations for windowed games** if you use DirectX 11 in windowed or borderless mode. For lower input latency in CS2, test the in-game **NVIDIA Reflex** or **AMD Anti-Lag 2** setting if your GPU supports it. Change one setting at a time and restart the game between runs. [Windows graphics optimizations](https://support.microsoft.com/en-us/windows/hardware/display-graphics/optimizations-for-windowed-games-in-windows-11) · [NVIDIA Reflex in CS2](https://www.nvidia.com/en-eu/geforce/news/counter-strike-2-released-featuring-nvidia-reflex/) · [AMD Anti-Lag 2 in CS2](https://community.amd.com/t5/gaming/amd-radeon-anti-lag-2-technical-preview-now-available-in-counter/ba-p/686012)

## Undo

```powershell
.\GamingTweaks.ps1 Restore -WhatIf
.\GamingTweaks.ps1 Restore
```

Apply saves the original values, including which values were absent, under `%LOCALAPPDATA%\Windows11GamingTweaks\backup.json` before writing changes. Run Restore before applying again to keep a single baseline. Restore also works if a game has moved or been uninstalled. If a backed-up value changed outside the script, Restore leaves it alone, prints its saved value, and keeps the backup. Close Windows Settings while applying or restoring.

The script works locally without admin rights or network access. Its writes are limited to the current user's Game Mode value, per-executable graphics preferences, and the rollback file. The graphics preference uses the Windows settings registry format and preserves the other fields in each game's value.

[Windows 11 Game Mode setting](https://learn.microsoft.com/en-us/windows/apps/develop/settings/settings-windows-11#gaming-game-bar-game-mode-gaming-shortcuts) · [Windows graphics preferences](https://support.microsoft.com/en-us/windows/hardware/display-graphics/optimizations-for-windowed-games-in-windows-11)
