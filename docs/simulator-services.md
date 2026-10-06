# Disabling simulator services

On iOS, each booted simulator runs hundreds of background daemons that consume RAM and CPU even when idle. On memory-constrained nodes running multiple simulators this pressure can destabilize tests. `--disable_sim_services` disables unnecessary daemons via `launchctl disable`, freeing resources for actual test execution.

```sh
mendoza test ... --disable_sim_services siri,intelligence,generative,watch,widgets,posters
```

Tokens are resolved from a catalog of known-safe services. You can pass **group names**, which expand to all underlying services, or **individual service IDs**:

| Group | Feature | Services |
|-------|---------|----------|
| `payments` | StoreKit / in-app purchase | storekitd, itunesstored, amsaccountsd, amsengagementd, amsondevicestoraged, passd, financed |
| `app-store` | App Store | appstored, itunesstored |
| `spotlight` | Spotlight & Settings search | searchd, searchtoold |
| `siri` | Siri & speech | assistantd, corespeechd, siriinferenced, siriknowledged, siriactionsd, sirittsd, siricontextd, siriacousticsignatured |
| `photos` | Photos library & analysis | assetsd, photoanalysisd |
| `widgets` | Widgets & Live Activities | chronod, liveactivitiesd |
| `intelligence` | Apple Intelligence | intelligenceplatformd, intelligencetasksd, intelligenceflowd, intelligencecontextd, callintelligenced, fitnessintelligenced |
| `posters` | Lock screen & wallpaper posters | posterboard, postersyncd |
| `generative` | Generative AI & ML models | generativeexperiencesd, imageplaygroundd, modelcatalogd, modelmanagerd, textunderstandingd, hybridsearchd, voicebankingd, translationd, mlhostd, mlruntimed, knowledgeconstructiond, agentstored, contentlinkingd, naturallanguaged |
| `watch` | Apple Watch companion | nanoregistrylaunchd, nanomapscd, nanosystemsettingsd, npkcompanionagent, companionappd, brookcompaniond, appconduitd, nanoappregistryd, nanonewscd, pairedsyncd, pairedunlockd, companiond, companionmessagesd, companionfindlocallyd |

Individual services can also be passed directly (e.g. `--disable_sim_services weatherd,newsd,gamed`).

The override persists across reboots on iOS 18+. Mendoza tracks which labels it manages, so it re-enables any previously disabled service that is no longer in the desired set.

> [!TIP]
> Some services are only kept alive by another one that enables them, and disabling those on their own does not hold. The Watch companion family is the known case: every daemon in the simulator's `/System/Library/NanoLaunchDaemons` ships disabled in its own plist and runs only because `nanoregistrylaunchd` enables the whole directory on demand, well after boot. Disabling `nanoregistrylaunchd` is what keeps the family down, which is why it leads the `watch` group. If you pass the individual Watch services without it, Mendoza warns that they were re-enabled after the reboot and every subsequent run pays an extra simulator reboot.

For a full audit of per-service memory usage on iOS 27, see [ios27-simulator-services.md](ios27-simulator-services.md).
