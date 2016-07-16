# 实时日志分析脚本
> 脚本的实现主要是通过linux的inotify机制，能够实时监控文件系统事件，从而能够对本机日志进行实时分析并且上报到日志中心。

### 依赖：
1. inotify-tools-3.14

### 使用方式
1. 将config.ini.sample复制，并且重命名为config.ini，完成相应配置
2. sh logWatcher.sh 配置文件路径

各个配置项的含义和取值范围如下：

``` ini

//需要监控的日志目录
logCategoryPath=

//偏移量文件目录，用来记录脚本分析进度
offsetFilePath=

//分析后的数据的上报方式，可选的值有database和interface，分别代表通过直连数据插入数据和调日至中心接口上传数据
reportType=

//如果reportType为database，请补充数据库连接命令
database=

//如果reportType为interface，请补充接口地址信息，如果接口协议不是纯粹的http post，请修改脚本对应位置适应您所需要的协议
interface=

//脚本的分析正则表达式
rules=

```