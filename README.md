# BMCShell SNMP

管理当前 BMC 的 SNMP 配置，并提供 v1、v2c 和 v3 命令。 这是独立的 BMCShell 3.0 工具插件，基于本地 BMC Shell 2.22.0 发布仓的工具实现。

```bash
bmc plugin install --file .
bmc help tool snmp --usage
bmc use 192.0.2.10
bmc tool snmp
```

工具随目标会话激活。系统依赖为 `snmpget`、`snmpgetnext`、`snmpwalk`、`snmpbulkwalk`、`snmpbulkget`、`snmpset`。代理由 `bmc proxy` 管理。发布时在本仓运行 `pwsh -File ./scripts/pack-release.ps1`，输出 ZIP 和 SHA256 清单。
