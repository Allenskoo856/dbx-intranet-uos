# DBX UOS 1070 WebKitGTK 4.0 离线版

这是 `agent/uos1070-webkit40` 分支的 Release 说明。该分支保留 Tauri 2 应用层，但在仓库内单独维护 Linux WebView 兼容层：

- WebKitGTK/JSC 使用 4.0 ABI：`libwebkit2gtk-4.0-37`、`libjavascriptcoregtk-4.0-18`。
- HTTP/WebView 绑定使用 libsoup2：`libsoup2.4`，不依赖 libsoup3。
- 自定义协议请求体功能按 UOS 1070 兼容边界关闭，避免使用 WebKitGTK 4.1/2.40 才需要的 `linux-body` 接口。
- 需要 `amd64`，目标机安装和运行不主动访问公网；版本升级通过新的内网 `.deb` 完成。

构建区需要联网准备 Rust/Node 依赖，目标机只接收经过 `SHA256SUMS` 校验的 `.deb` 和管理员批准的系统依赖包。安装前请确认目标 UOS 的 WebKitGTK 4.0 API 至少为 2.36、libsoup2 至少为 2.62；仅仅存在同名兼容包不等于 ABI 已验收。

```bash
sha256sum -c SHA256SUMS
sudo dpkg -i DBX_<version>_uos1070-webkit40_amd64.deb
/usr/bin/dbx --dbx-offline-self-test
```

必须看到：

```text
network_policy=deny-public updater=disabled agent_remote_downloads=disabled mcp_registry_checks=disabled
```

当前分支仅完成 Linux 4.0 兼容构建、包元数据、ELF 依赖和 `--network none` 自测；实体 UOS 1070 现场验收仍需使用部署方提供的具体镜像和桌面环境完成。
