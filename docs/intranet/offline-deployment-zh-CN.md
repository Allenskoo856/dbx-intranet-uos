# DBX UOS/Debian-like 内网离线部署手册

## 1. 交付范围

本 fork 提供一个编译期 `offline-uos` 模式和一个只生成 Debian 包的 Tauri 配置：

- 安装介质是 x86_64/amd64 `.deb`，可在没有公网的内网中用 `dpkg` 安装。
- 离线包不初始化 Tauri updater；前端不启动更新、Agent Registry、MCP Registry 和 WebDAV 自动上传定时器；后端命令也会 fail-closed 拒绝对应公网操作。
- Agent/JDBC 驱动和 JRE 需要在构建区准备好后，使用 DBX 现有的离线导入功能导入；离线包不会偷偷执行 npm、curl、wget、apt 或远程驱动下载。
- 版本升级通过新的内网 `.deb` 文件完成，不依赖在线更新器。

构建区可以联网下载 Rust/Node 依赖；目标安装区和运行时不需要公网。这两个边界不能混为一谈。

## 2. 兼容性边界

当前上游 Tauri/Wry Linux 构建使用 WebKitGTK 4.1，因此包声明以下运行时依赖：

```text
libwebkit2gtk-4.1-0
libgtk-3-0
libayatana-appindicator3-1
```

“Debian 10-like”在这里表示 UOS 的 Debian-like 用户空间和兼容的软件包仓库，不代表原版 Debian 10 stock 用户空间可以直接运行。原版 Debian 10 常见的是 WebKitGTK 4.0/libsoup 2，不能满足当前构建的 WebKitGTK 4.1/libsoup 3 依赖；若目标 UOS 没有可用的 4.1 运行库，应由发行版管理员提供兼容包，或另行维护旧 WebKit 运行时分支。当前 Release 未宣称已经在实体 UOS 机器上完成验收。

## 3. 构建离线包

在联网的 Linux x86_64 构建机或等价 CI runner 上执行：

```bash
pnpm install --frozen-lockfile
./packaging/uos/build-offline-deb.sh
```

### 构建缓存与耗时定位

`build-offline-deb.sh` 本身不把构建缓存写进制品；本地同一工作区会自然复用 `node_modules/` 和 `target/`，而 GitHub-hosted runner 每次都是临时机器，必须由工作流显式恢复缓存。当前工作流的缓存边界如下：

| 缓存 | 位置/实现 | 失效条件 | 作用 |
| --- | --- | --- | --- |
| pnpm | `actions/setup-node` 的 `cache: pnpm`，key 使用 `pnpm-lock.yaml` | lockfile 或 Node/pnpm 组合变化 | 加快依赖下载；不缓存 Rust 编译 |
| Cargo registry/git 与 `target/` | `Swatinem/rust-cache@v2`，共享 key `uos-offline-deb-x86_64-unknown-linux-gnu` | `Cargo.lock`、Rust 环境或共享 key 变化 | 复用 Cargo 依赖和已生成的 target 内容 |
| Rust 编译器产物 | `mozilla-actions/sccache-action` 的 GitHub Actions backend | 编译器参数、feature、源码/依赖变化 | 对 `offline-uos` 的重复 crate 编译做跨 runner 复用 |

构建前的 `Report build cache configuration` 和构建后的 `Report sccache statistics` 会记录 pnpm store、Cargo home、target 路径以及 sccache 命中统计。第一次变更缓存配置或依赖锁文件后的构建仍然是冷启动，需要先预热默认分支缓存；后续 `uos-v*` tag 才能复用。当前最慢步骤已定位为 Tauri/Rust 的 `Build UOS offline Debian package`，此前无 Rust 缓存实测约 21 分钟；pnpm 安装约数秒、Linux 系统依赖安装约 1 分钟，不是主要瓶颈。

查看单次构建和缓存命中信息：

```bash
gh run view <run-id> --repo Allenskoo856/dbx-intranet-uos --json jobs
gh run view <run-id> --repo Allenskoo856/dbx-intranet-uos --log \
  | rg 'Rust dependency and target cache|sccache|Build UOS offline|Finished .*bundle'
```

这些缓存只存在于联网构建区，不会被打进 `.deb`，也不会改变目标 UOS 的离线运行策略。若换成另一套 Rust toolchain、Cargo feature 或 x86_64 以外架构，应使用新的共享 key，避免错误复用。

脚本使用 `VITE_DBX_OFFLINE_MODE=true` 和 Cargo feature `offline-uos`，输出目录为：

```text
dist/uos-offline/
├── DBX_<version>_uos-offline_amd64.deb
├── DBX_<version>_uos-offline_amd64.deb.sha256
├── SHA256SUMS
└── manifest.json
```

GitHub Actions 工作流 `.github/workflows/uos-offline-deb.yml` 在 `uos-v*` tag 上构建并把这些文件上传到 GitHub Release。Actions 是构建区，不是目标内网运行时；Release 下载后必须通过企业批准的介质传输到内网。

## 4. 在内网安装

先在传输介质目录校验文件：

```bash
sha256sum -c SHA256SUMS
dpkg-deb --info DBX_<version>_uos-offline_amd64.deb
```

确认 SHA256、版本、架构和来源均符合变更单后安装：

```bash
sudo dpkg -i DBX_<version>_uos-offline_amd64.deb
```

如果 `dpkg` 报缺少 `libwebkit2gtk-4.1-0` 等依赖，不要在隔离目标机上直接执行 `apt -f install`，因为它可能尝试访问外部软件源。应由管理员在有网构建区或批准的内网 apt 镜像中准备同架构依赖包，先通过受控介质校验并安装依赖，再重新执行 `dpkg -i`。目标机没有经过现场检查前，不能把依赖名等同于已经存在于某个 UOS 镜像。

安装后由桌面菜单启动 DBX；若需要命令行自检，可在安装包所在环境运行：

```bash
/usr/bin/dbx --dbx-offline-self-test
```

必须看到：

```text
network_policy=deny-public updater=disabled agent_remote_downloads=disabled mcp_registry_checks=disabled
```

## 5. 升级、回滚和卸载

升级前关闭 DBX 并备份用户数据目录。用新包覆盖安装：

```bash
sudo dpkg -i DBX_<new-version>_uos-offline_amd64.deb
```

回滚时使用经过校验的旧版本 `.deb` 重复执行 `dpkg -i`。不要删除用户数据目录来解决升级问题；先保留日志和版本信息。

卸载程序但保留用户数据：

```bash
sudo dpkg -r dbx
```

如果企业要求连同配置和连接历史一起清理，应先依据数据保留制度人工确认实际用户数据目录，再执行受控清理；本项目不提供无确认的递归删除命令。

## 6. 网络与安全验收

离线包的“无主动触发外网”由三层保证：

1. Tauri updater 插件在 `offline-uos` 编译下不初始化，且 `.deb` overlay 不生成 updater artifacts。
2. UI 不创建公网更新、Agent Registry、MCP Registry 和 WebDAV 自动任务。
3. Rust 后端命令和核心 HTTP 入口在离线 feature 下直接返回拒绝错误，防止旧 UI 或脚本绕过前端。

下面这些仍属于用户显式配置的业务连接，不应伪称为被离线模式自动拦截：数据库主机、内网或外部 AI endpoint、用户手动触发的 WebDAV 同步、SSH 隧道以及用户导入的 MCP/Agent 运行时。对真正的物理隔离环境，还应配合网闸、防火墙或 Linux network namespace 做出口级 fail-closed 控制。

## 7. 还未被本 Release 证明的事项

- 未在本地 macOS 主机上直接生成 `.deb`，因为本机不是 Linux x86_64 且没有 `dpkg-deb`；构建由 x86_64 Linux CI 完成。
- 未宣称在具体 UOS 镜像、生产网关、认证数据库和业务 AI endpoint 上完成验收。
- UOS 发行版补丁、系统 WebKitGTK 版本、企业内网依赖镜像和驱动许可仍由部署方确认。
