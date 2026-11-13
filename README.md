# BMCShell SNMP

扩展包名 `bmcshell-tool-snmp`。

管理当前 BMC 的 SNMP 配置，并提供 v1、v2c 和 v3 命令。 这是独立的 BMCShell 3.0 工具插件，基于本地 BMC Shell 2.22.0 发布仓的工具实现。

```bash
bmc plugin install --file .
bmc tool snmp --help
bmc use 192.0.2.10
snmp --help
```

工具随目标会话激活。系统依赖为 `snmpget`、`snmpgetnext`、`snmpwalk`、`snmpbulkwalk`、`snmpbulkget`、`snmpset`。代理由 `bmc proxy` 管理。发布时在本仓运行 `pwsh -File ./scripts/pack-release.ps1`，输出 `bmcshell-tool-snmp@<version>.zip` 和 SHA256 清单。

在 `bmc setting` 的「SNMP → SNMP 版本」中配置普通 SNMP 命令的默认版本。会话配置 `snmp -c` 和显式 `-v` 优先。带版本号的命令（如 `snmp2get`）始终使用指定版本。`snmp -r` 清除会话配置后重新使用框架默认值。

```bash
bmc setting --set BMCSHELL_SNMP_VERSION 3 --reload
```
