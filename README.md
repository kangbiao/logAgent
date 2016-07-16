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

# -----------------这是文章分割线--------------


# 本地日志分析上报脚本实现思路梳理


## 一、背景
> 云平台后台的日志查询只能通过开发人员登录对应的机器执行日志分析，效率不够高效。对于现网问题，由于运维不理解后台模块的日志含义，因此只能由开发去现网机器查询日志；对于联调环境，接入方调用云平后台接口出了问题只能通过云平台后台开发人员协助解决。这种强依赖指定开发人员的情况，不利于问题的快速解决。因此我们迫切的需要一个日志中心来处理和查询所有的日志，并且由于需要在联调时能够让接入方自己定位问题，我们对实时性也有一定的要求。但是由于公司没有提供这种系统，所以我们决定自己做一个日志模块来处理上述问题。
> 这篇文章主要是写一下日志模块客户端的实现思路，对于日志存储查询服务由于不是我开发，所以只做简单介绍。

## 二、在模块内部实现
最开始的实现方式是修改业务逻辑代码，在需要上报日志的地方增加日志上报逻辑，但是由于php语言不支持装饰器和注解这样的语法，因此这样的实现对于业务代码的入侵度极高，同时需要大量修改业务代码已有的处理流程，也存在着很大的风险。同时由于增加了日志上报逻辑，因此多了一次网络调用，如果日志服务存在故障，那么网络调用超时会影响业务逻辑，这是很不合理的实现方案，因此我这样写了两天代码就写不下去了。

## 三、优化
后来看了下CI框架的文档，发现CI也支持钩子语法，因此可以通过设置一个全局的钩子来实现对关键日志的监控，所谓钩子，其实就是框架主流程埋几个点，这样你就可以在框架执行流程中增加自己的逻辑来影响框架执行流程，我当时挂钩点是控制器初始化完成，但调用构造器之前。这样的实现看起来很简单，也减少了代码入侵，但是仅仅是减少代码入侵而已，对于所有的流程还是会经过日志判断，运行流程上面还是和最开始的实现方式一样，是全局的。另外一点很不好的地方就是需要设置几个全局变量来存储一些钩子获取不到的数据，如网络调用，这样对于后来的维护者很难理解为什么这里会有一个全局变量赋值，然后就吐槽一番这个代码顺便删除，然后我们的日志监控就呵呵了。因此这样的实现方案也是不太好的。所以我把代码回滚，放弃了这种做法。。

## 四、通过本地日志agent脚本实现
**接下来就是本文的重点啦~**

最后决定通过本地写个脚本来实时分析日志并且上传到日志模块来实现日志的监控。这个方案是我认为最合理的方案，同时也是很多企业的做法。实现方案确定好了以后，接下来的就是评估技术方案了。

**python脚本循环读取日志存储目录实现监控**
由于之前有位大神给我讲过他之前是怎么做一个日志监控的，他当时告诉我是本地写了一个脚本来实现，所以我第一想法就是写个python脚本。但是写了一段时间发现越写越没谱，主要是因为现网的日志一天的量是以T为单位，而我的逻辑里面包含了很多的文件IO(因为要实时监控，所以要一直读取文件夹监控内部的变化)。所以这样做的话，很可能会出现分析跟不上产生的节奏，这样实时性很差且会产生一定的系统负载，因此这种实现被放弃了。

后来想了想，突然记起之前在学校做得一个项目，项目里面有个知识点是关于linux文件系统监控的，即linux文件系统的inotify机制，关于该机制的介绍我就不做过多篇幅的描述了，参见这篇wiki[inotify](https://en.wikipedia.org/wiki/Inotify)。

所以我完全可以去网上下个python实现的文件系统notify库，然后就可以很方便的监控到文件系统的变化了。但是突然想起后面还有那么多的字符分析，好像用python的话性能不能满足我们对实时性要求高的需求，因此我决定使用shell命令来做这个脚本。那些设计优美且性能高效的文本分析命令完全可以很方便的实现我对于日志分析的要求。而且这样我的全部工作就是组装命令，维护日志分析的主逻辑了。

**shell通过notify_tools实现日志分析**
shell实现有几个技术问题需要解决，第一是文本处理命令的选择；第二是notify_tools是否真能满足要求；第三则是性能测试了

*文本命令的选择*
``` bash
# 普通字符过滤性能比较
[root@TENCENT64 /data/log/trade.logical]# time grep ".*atom" log-2016-07-16.log>/dev/null
real	0m0.194s
user	0m0.188s
sys	0m0.004s

[root@TENCENT64 /data/log/trade.logical]# time sed "/.*atom/p" log-2016-07-16.log>/dev/null
real	0m0.201s
user	0m0.192s
sys	0m0.008s

[root@TENCENT64 /data/log/trade.logical]# time awk "/.*atom/" log-2016-07-16.log>/dev/null
real	0m1.502s
user	0m1.484s
sys	0m0.016s

```

可以看出来这三者的性能排序为grep>sed>awk，awk基本不考虑使用了，最然它给我们提供了可编程的空间，但是太慢了。至于最快的grep，由于它在命令上支持不够丰富，所以也不考虑使用。因此选取性能和功能相对而言优于其他两者的sed命令。
当然，这只是一个简单的测试，由于我缺乏对这三个命令高级选项的认识，因此这三个命令在加了高级选项以后的性能排序可能有所不同。但是对目前的需求而言，执行这样的测试然后选择sed是没有问题的。

*notify_tools是否满足要求*
这个就简单了，通过执行man inotifywait看了下文档，发现这个工具是满足我们的要求的

*性能测试*
待补充....

## shell脚本实现方案
有几点需要首先明确，这个日志分析脚本由于是在本机运行，所以必然会部署多份，虽然我们云平只有几台服务器，但也勉强算个分布式了==。所以脚本的运行应该足够简单，所以决定通过配置文件来控制脚本的运行。

另外一点就是如何保证日志文件都是被处理完了，不会出现漏处理或者处理速度跟不上的问题。这个的实现我是通过维护一个处理偏移量的文件来记录脚本处理的文件位置信息，方便脚本中断后能够从上次的处理位置继续处理。


由于一次产生的日志量很大，所以不能够一行一行的处理，这样或许能够跟上日志的产生速度，但是不太合理，我采用的方案如下：

1. 循环的执行监听命令，当收到文件变化的通知后便立刻进行处理
2. 如果通知的变化文件和偏移量中记录的文件一致，则计算出当前文件总行数（主要是为了避免一直变化的行数造成处理混乱），从上次记录的偏移量处理到当前文件的总行数
3. 如果通知的变化文件和偏移量中记录的文件不一致，这个时候说明发生了新建日志文件的动作，则一次性处理完偏移量文件中记录的文件的剩下的所有内容，并且开始处理新创建的日志文件
4. 更新偏移量和指向文件

这样的实现有个特点就是，在日至量增加特别特别快的情况下（万行每秒），处理脚本可能会出现延后，且日志增量如果不降下去，处理会越来越延后，但是当新建文件时，脚本会一次性将所有延后处理的日志一次性全部处理了，通过动态获取处理量来避免大量日志产生对于实时性的降低。

当然缺点也是很明显的，如果日志量增加的速率一直增加，那么日志处理肯定是会有延后的，同时如果是通过调用接口上报日志的话，日志仍然会有几秒甚至几十秒左右的延后。但是对于我们的系统，目前这样实现是够用了，业务量上去还可以通过优化脚本和优化日志服务的方式来提高日志的处理速度。对于联调环境的日志量，这样的实现完全可以胜任。

接下来的事情就是让时间去验证这样实现的优缺点。

**后续改进方案**

1. 目前这个脚本的耗时主要在日志的网络传输上（即传到日志中心的这个过程），采用的直接插入数据库或者调用接口。
2. 日志中心废弃数据库的存储方式，采用更适合文本检索的文件存储方式来分析存储日志。
3. 本地不再分析日志，只负责将日志提取出来发送给日至中心，分析由日至中心处理完成，但是降低了实时性。
4. 传输协议上面可以用thrift协议，而不是现在的http协议或者直插数据库。
5. 规范化云平后台日志格式，提高程序的整洁和日志信息的可读性。

最后贴一段脚本的部分代码来凑凑篇幅
``` bash
#!/bin/sh

# 偏移量文件格式：偏移量 指向文件

configFile=$1
declare -a configArr

while IFS='' read -r line || [[ -n "$line" ]]; do
   IFS='=' read -r key value <<< "$line"
   configArr[$key]=$value
done < "$configFile"

echo -e "parse config file succ \n\nstart watch log file[log path:${configArr['logCategoryPath']}]\n"

while watchInfo=`inotifywait -q --format '%e %f' -e modify,create ${configArr['logCategoryPath']}`;do
	watchInfo=($watchInfo)
	lines=`wc -l ${watchInfo[1]}`
	offsetInfo=`cat ${configArr['offsetFilePath']}`

	# 如果偏移量文件不存在，则创建偏移量文件
	if [ $? ]; then

		# 如果偏移量记录文件为空，则初始化偏移量，从第0行读取变更的文件
		if [ $offsetInfo -eq "" ]; then
			process 1 ${lines} $watchInfo[1]

		# 如果偏移量文件不为空，则取出偏移量和指向的文件
		else
			offsetInfo=($offsetInfo)
			if [ ${offsetInfo[1]} -eq ${watchInfo[1]} ]; then
				# 处理上一个日志文件
				process ${offset} $ $offsetFile 

				# 处理从第0行开始处理新创建的文件
				process 1 ${lines} $watchInfo[1]
			else
				# 继续处理偏移量文件中记录的文件
				process ${offset} ${lines} $watchInfo[1]
			fi
		fi
		# 处理完成，更新偏移量和指向的文件
		cat "$lines ${watchInfo[1]}" > ${configArr['offsetFilePath']}
	else
		touch ${configArr['offsetFilePath']}
	fi
done
```



