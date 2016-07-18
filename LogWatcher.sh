#!/bin/sh

# 偏移量文件格式：偏移量 指向文件

# 预检查环境是否ok
if [ ! -e $1 ]; then
  echo "config file not exsit"
  exit 1
fi
if [ ! which mysql ]; then
  echo "command mysql not exsit or not in the system path"
  exit 2
fi
if [ ! which inotifywait ]; then
  echo "command inotifywait not exsit or not in the system path"
  exit 3
fi

# 处理日志文件函数
# 参数列表  $1:起始偏移量；$2:结束偏移量；$3:文件名；$4:配置数组
process(){
  offsetStart=$1
  offsetEnd=$2
  offsetFile=$3
  configArr=$4
 
  OLD_IFS="$IFS" 
  IFS="@" 
  sed -n "${offsetStart},${offsetEnd} {/${configArr['rules']}/{s/\[\([^,]*\).*\]\[\(.*\)\]\[\(.*\)\]\[\(.*\)\]\[\(.*\)\]/\1@\2@\3@\4@\5/gp;}}" ${offsetFile} | while read line
  do
    sql="insert into () values("
    arr=($line)
    length=${#arr[@]}
    if [ $length -eq 5 ]; then
      for ((i=0; i<$length; i++))
      do
        if [ $i!=5 ]; then
          sql=${sql}" '${arr[$i]}',"
        else
          dealName=`echo ${arr[$i]} | sed -n 's/.*dealName[^0-9]*\([0-9]*\).*/\1/gp'`
          eventId=`echo ${arr[$i]} | sed -n 's/.*eventId[^0-9]*\([0-9]*\).*/\1/gp'`
          sql=${sql}"'${arr[$i]}','${dealName}','${eventId}';"
        fi
      done
    fi
    echo $sql>>./sql.temp
  done
  IFS="$OLD_IFS" 
  # mysql -h127.0.0.1 -uroot -proot -P3306 -e ./sql.temp
}


configFile=$1
declare -a configArr

while IFS='' read -r line || [[ -n "$line" ]]; do
   IFS='=' read -r key value <<< "$line"
   configArr[$key]=$value
done < "$configFile"

echo -e "parse config file succ \n\nstart watch log[log path:${configArr['logCategoryPath']}]\n"

while watchInfo=`inotifywait -q --format '%e %f' -e modify,create ${configArr['logCategoryPath']}`;do
  watchInfo=($watchInfo)
  lines=`wc -l ${watchInfo[1]}`
  lines=($lines)
  lines=${lines[0]}
  offsetInfo=`cat ${configArr['offsetFilePath']}`

  # 如果偏移量文件不存在，则创建偏移量文件
  if [ $? ]; then

    # 如果偏移量记录文件为空，则初始化偏移量，从第0行读取变更的文件
    if [ $offsetInfo == "" ]; then
      process 1 ${lines} $watchInfo[1] $configArr

    # 如果偏移量文件不为空，则取出偏移量和指向的文件
    else
      offsetInfo=($offsetInfo)
      if [ ${offsetInfo[1]} != ${watchInfo[1]} ]; then
        # 处理上一个日志文件
        process ${offset} $ $offsetFile $configArr

        # 处理从第0行开始处理新创建的文件
        process 1 ${lines} $watchInfo[1] $configArr
      else
        # 继续处理偏移量文件中记录的文件
        process ${offset} ${lines} $watchInfo[1] $configArr
      fi
    fi
    # 处理完成，更新偏移量和指向的文件
    echo "$lines ${watchInfo[1]}" > ${configArr['offsetFilePath']}
  else
    touch ${configArr['offsetFilePath']}
  fi
done

exit 0
