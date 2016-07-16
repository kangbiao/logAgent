#!/bin/sh

# 偏移量文件格式：偏移量 指向文件


# 处理日志文件函数
# 参数列表  $1:起始偏移量；$2:结束偏移量；$3:文件名；$4:规则数组
process(){
	offsetStart=$1
	offsetEnd=$2
	offsetFile=$3
	ruleArr=$4
	sed -n "${offsetStart},${offsetEnd}"p $offsetFile  | grep "dealName"
}


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
	if [[ $? ]]; then

		# 如果偏移量记录文件为空，则初始化偏移量，从第0行读取变更的文件
		if [[ $offsetInfo=="" ]]; then
			process 1 ${lines} $watchInfo[1]

		# 如果偏移量文件不为空，则取出偏移量和指向的文件
		else
			offsetInfo=($offsetInfo)
			if [[ ${offsetInfo[1]}!=${watchInfo[1]} ]]; then
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

