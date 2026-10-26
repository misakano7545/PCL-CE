# 自用构建（`selfuse` 分支）

本仓库是 [PCL-Community/PCL-CE](https://github.com/PCL-Community/PCL-CE) 的个人 fork，
定位是**自己用的、不限制地区的构建**，不打算向上游提 PR。

## 为什么要这个分支

上游提交 `8cd9d374 fix(install): 中国大陆地区禁用 Minecraft 安装功能` 引入了区域判定
（`PCL.Core/App/Region/RegionPolicy.cs`），并在 `RestrictedFeaturePolicy` 中统一拦截
Minecraft 客户端下载、启动时补全缺失文件、实例修复/重置、整合包安装等 14 处入口。
被判定为 `Mainland` 或 `Unknown` 时这些功能全部不可用。

自用场景下这层限制没有意义，所以在 fork 里去掉，仅此一处。

## 分支模型

| 分支 | 内容 | 跟踪 |
|---|---|---|
| `dev` | 上游 `dev` 的镜像，不含任何本地改动 | `upstream/dev` |
| `selfuse` | `dev` + 一个「移除区域限制」提交，日常构建用这个 | `origin/selfuse` |

```
origin    git@github.com:misakano7545/PCL-CE.git     （自己的 fork，可写）
upstream  git@github.com:PCL-Community/PCL-CE.git    （上游，只读）
```

## 与上游的差异

只有一个文件被改：`Plain Craft Launcher 2/Modules/Minecraft/RestrictedFeaturePolicy.cs`，
改成恒放行：

```csharp
internal static bool IsRestricted => false;
internal static bool Check(string feature, bool showHint = true) => true;
internal static void ThrowIfRestricted(string feature) { }
```

`PCL.Core/App/Region/RegionPolicy.cs` 及其单元测试 `PCL.Core.Test/RegionPolicyTest.cs`
保持原样（只是不再被用于拦截），因此上游改判定逻辑时不会产生冲突。

## 同步上游

```bash
git fetch upstream
git checkout selfuse
git rebase upstream/dev          # 冲突只可能出现在上面那一个文件
git push --force-with-lease origin selfuse
```

冲突处理：直接把 `RestrictedFeaturePolicy.cs` 整个覆盖回上面那 3 行即可，
不需要保留上游新增的判定逻辑。

## 构建

```cmd
build-selfuse.cmd            :: Release，产物在 publish\selfuse\
build-selfuse.cmd Debug      :: 调试构建
```

脚本会读取仓库根目录的 `selfuse.env`（已 gitignore，不会提交），支持：

| 键 | 作用 |
|---|---|
| `SELFUSE_DOTNET` | 指定带 SDK 的 `dotnet.exe` 完整路径 |
| `HTTPS_PROXY` / `HTTP_PROXY` | NuGet 还原走代理 |
| `PCL_MS_CLIENT_ID` 等 | 构建期密钥，见下一节 |

手动等价命令：

```cmd
dotnet publish "Plain Craft Launcher 2\Plain Craft Launcher 2.csproj" ^
    -c Release -p:Platform=x64 -p:SelfContained=true -o publish\selfuse
```

**SDK 版本硬要求：.NET SDK 10.0.402 或更新。** 源码生成器
`PCL.Core.SourceGenerators` 引用 `Microsoft.CodeAnalysis.CSharp 5.6.0`（Roslyn 5.6），
用 10.0.100 编译会报 250 个 `CS9248 分布属性必须具有实现部分`——生成器被静默跳过，
属性全都没有实现部分。这是版本不匹配，不是代码问题。

## 构建期密钥与由此损失的功能（重要）

`PCL.Core.SourceGenerators/EnvironmentInteropGenerator.cs` 只在编译时环境变量里存在
`PCL_WRITE_SECRET` 时，才把其他 `PCL_*` 变量写进 `EnvironmentInterop.SecretDictionary`；
而 `Secrets.cs` 里各字段用 `readEnvDebugOnly: true` 读取，`EnvironmentInterop.GetSecret`
中该分支被 `#if !DEBUG` 包住，所以 **Release 构建既不读运行时环境变量，也只能用编译期
烘焙进去的值**。

实测（同一个 Release 产物，运行时把 `PCL_MS_CLIENT_ID`、`PCL_CURSEFORGE_API_KEY`
都设上，再反射读 `Secrets`）：全部为空，`new MicrosoftProvider(null)` 抛
`InvalidOperationException: Microsoft OAuth client id is not configured.`。
换成 Debug 构建（`JITOptimizerDisabled=True`）同样的环境变量就能读到。
所以「临时设个环境变量再启动」这条路在 Release 下不成立，必须重新构建。

没有密钥时各功能的表现（均为实测/读代码确认）：

| 密钥 | 缺失后果 |
|---|---|
| `PCL_MS_CLIENT_ID` | **微软正版登录不可用**：`MicrosoftProvider` 构造即抛 `Microsoft OAuth client id is not configured.` |
| `PCL_CURSEFORGE_API_KEY` | 官方 `api.curseforge.com` 返回 403（实测）。但默认下载源策略是「官方优先，失败回落镜像」，镜像 `mod.mcimirror.top/curseforge` 无密钥也返回 200（实测），所以 CurseForge 搜索**仍可用**，只是每次多一次 403。把设置里的 Mod 下载源改成「仅官方」才会彻底不可用。Modrinth 完全不受影响。 |
| `PCL_NAID_CLIENT_ID` / `_SECRET` | 联机大厅的 Natayark ID 登录链接里 `client_id` 为空，登录必然失败 |
| `PCL_LINK_SERVER_ROOT` | `Secrets.LinkServers` 变成 `[""]`，大厅服务器列表拿不到 |
| `PCL_SENTRY_DSN` | `TelemetryService` 直接 `return`（日志 `未找到 Sentry DSN`），无崩溃风险 |
| `PCL_TELEMETRY_KEY` | 无遥测上报 |
| `PCL_GITHUB_SHA` | 版本页不显示提交号 |

不受影响、无需任何密钥即可用的：**离线登录、第三方皮肤站（Yggdrasil，如 littleskin）登录、
Minecraft 原版与 Forge/Fabric/NeoForge 等安装、下载、补全、修复、整合包安装**
（也就是本 fork 要放开的部分）。

想恢复微软登录，在 `selfuse.env` 里填自己的 `PCL_MS_CLIENT_ID`（Azure 应用注册，
走 device code 流程，不需要 redirect URI，但要在应用里允许 public client flows），
然后重新构建。**填进去的值会被编译进 exe，不要把带密钥的 exe 分发出去。**

## 已验证事实

在本机（Windows 11，区域判定为 `Mainland`）实测：

- `RegionPolicy.Evaluate` 对当前机器返回 `Classification=Mainland, Reason=geo-cn, IsRestricted=True`
  ——即原版必然触发拦截；
- 反射加载本分支 **Release** 产物（`Debuggable: JITOptimizerDisabled=False`，确认是 Release）：
  `RestrictedFeaturePolicy.IsRestricted=False`，
  `Check("minecraft-install")`、`Check("minecraft-client-download")`、
  `Check("modpack-install")`、`Check("minecraft-repair")` 全部返回 `True`；
- 同一 Release 产物里 `Secrets.CurseForgeAPIKey`/`NatayarkClientId`/`LinkServers`/`CommitHash`
  全为空，`new MicrosoftProvider(null)` 抛 `Microsoft OAuth client id is not configured.`；
  即使运行时设了对应环境变量也一样（Debug 构建则会读到）；
- `curl https://api.curseforge.com/v1/mods/search` 无 `x-api-key` → 403；
  `curl https://mod.mcimirror.top/curseforge/v1/mods/search` 无密钥 → 200；
- `build-selfuse.cmd` 实测退出码 0，产出 `publish\selfuse\Plain Craft Launcher 2.exe`（约 187 MB，自包含单文件）；
- `dotnet build` 0 错误（5384 个 warning 全部是上游原有的可空性/未使用字段告警）；
- 用 SDK 10.0.100 构建失败（250 个 `CS9248`），换成 10.0.402 后通过。

## 回退

`git checkout selfuse && git revert <移除区域限制的提交>`，或者直接从 `dev` 构建上游原版。
