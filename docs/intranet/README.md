# DBX UOS 内网离线版

这是 `Allenskoo856/dbx-intranet-uos` 对上游 DBX 的桌面端本地化改造说明，目标是把构建区的网络行为与目标 UOS/Debian-like 内网运行环境隔离开。

- [部署、升级、回滚与卸载](offline-deployment-zh-CN.md)
- [内网使用与运维手册](operations-zh-CN.md)
- [构建脚本](../../packaging/uos/build-offline-deb.sh)
- [离线包验收脚本](../../packaging/uos/verify-offline-deb.sh)

离线包关闭 DBX 自身的公网更新器、更新日志请求、Agent 驱动仓库检查、MCP Registry 检查、远程 Agent/JRE/MCP 安装，以及 WebDAV 自动上传。显式配置的数据库、AI、WebDAV 和其他业务连接仍可能访问其配置的地址；因此“无主动触发外网”不等于把所有业务网络连接都替用户禁止。
