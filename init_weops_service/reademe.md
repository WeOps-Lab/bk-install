WeOps 服务初始化

本项目提供了一系列脚本来初始化 WeOps 不同模块的服务，包括 CMDB、监控和 ITSM。初始化脚本确保所有必要的配置到位，并且系统已准备就绪。

# 目录

- [使用方法](#使用方法)
- [模块](#模块)
- [日志](#日志)
- [贡献](#贡献)
- [文件结构](#文件结构)

# 使用方法

您可以使用 `main.py` 脚本初始化 WeOps 服务的不同组件。可用选项如下：

- `--cmdb`：启用 CMDB 初始化
- `--monitor`：启用监控初始化
- `--itsm`：启用 ITSM 初始化

## 示例

- 初始化 CMDB：

    ```bash
    cd /data/weops/init_weops_service/
    
    python main.py --cmdb
    ```

- 初始化监控：

    ```bash
    cd /data/weops/init_weops_service/

    python main.py --monitor
    ```

- 初始化 ITSM：

    ```bash
    cd /data/weops/init_weops_service/

    python main.py --itsm
    ```

- 初始化所有组件：

    ```bash
    cd /data/weops/init_weops_service/
    
    python main.py --cmdb --monitor --itsm
    ```

# 模块

| 模块                      | 描述                                                         |
| ------------------------- | ------------------------------------------------------------ |
| `config.py`               | 处理服务的配置设置，并为其他模块提供必要的配置数据。         |
| `init_cmdb.py`            | 通过创建必要的分类、对象和关联来初始化 CMDB 组件。           |
| `init_monitor.py`         | 通过配置插件并确保所有必要的监控配置到位来初始化监控组件。   |
| `init_monitor_other.py`   | 处理监控组件的其他初始化任务，例如同步监控对象和初始化仪表板。 |
| `init_itsm.py`            | 初始化 ITSM 组件，设置必要的工作流和 IT 服务管理的配置。     |
| `modify_login_session.py` | 处理会话的登录和 CSRF 令牌初始化。它确保会话已认证并准备好向 WeOps 服务发送请求。 |
| `utils.py`                | 提供跨不同模块使用的实用功能，包括获取环境变量和安全的 HTTP 请求。 |
| `logging_config.py`       | 配置项目的日志设置。日志写入 `logs/init_weops_service.log`，最多保留 3 个历史日志文件。 |
| `plugins`                 | 监控插件源文件的存储路径                                     |


# 日志

日志配置为输出到控制台和轮转文件。日志存储在 `logs` 目录中，每个日志文件名为 `init_weops_service.log`。最多保留 3 个日志文件。

# 贡献

欢迎贡献！请联系作者 *Jerko* 。

# 文件结构

```arduino
init_weops_service/
├── config.py
├── init_cmdb.py
├── init_monitor.py
├── init_monitor_other.py
├── init_itsm.py
├── modify_login_session.py
├── utils.py
├── logging_config.py
├── main.py
├── plugins
└── README.md

```

请检查并确认这些更改是否符合您的要求。如果有其他需要修改或添加的内容，请告知我。
