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
  # echo "$offsetStart $offsetEnd $offsetFile ${configArr['rules']}" 
  OLD_IFS="$IFS" 
  IFS="@" 
  sed -n "${offsetStart},${offsetEnd} {/${configArr['rules']}/{s/@/#/g;s/'/\"/g;s/\[\([^,]*\),[0-9]*\]\[\([^]]*\)\]\[\([^]]*\)\]\[\([^]]*\)\]\[\(.*\)\]/\2@\4@\5/gp;}}" ${offsetFile} | while read line
  do
    sql="insert into t_log_deal (module,ip,level,extKey1,path,content,extKey2,eventId,uin,appId) values('trade','10.250.128.232',1,"
    arr=($line)
    length=${#arr[@]}
    if [ $length -eq 3 ]; then
      for ((i=0; i<$length; i++))
      do
        if [ $i -eq 2 ];then
          dealName=`echo ${arr[$i]} | sed -n 's/.*dealName[^0-9]*\([0-9]*\).*/\1/gp'`
          eventId=`echo ${arr[$i]} | sed -n 's/.*eventId[^0-9]*\([0-9]*\).*/\1/gp'`
          ownerUin=`echo ${arr[$i]} | sed -n 's/.*ownerUin[^0-9]*\([0-9]*\).*/\1/gp'`
          appId=`echo ${arr[$i]} | sed -n 's/.*appId[^0-9]*\([0-9]*\).*/\1/gp'`
          if [ "$eventId" = "" ];then
            eventId=0
          fi 
          if [ "$ownerUin" = "" ];then
            ownerUin=0
          fi 
          if [ "$appId" = "" ];then
            appId=0
          fi 
          sql=${sql}"'${arr[$i]}','${dealName}','${eventId}','${ownerUin}','${appId}');"
        else
          sql=${sql}" '${arr[$i]}',"
        fi
      done
    fi
    echo $sql>>./sql.temp
  done
  IFS="$OLD_IFS" 
  sqlLines=`wc -l ${configArr['tempSqlFilePath']}`
  sqlLines=($sqlLines)
  sqlLines=${sqlLines[0]}
  if [ $sqlLines -ge ${configArr['maxSqlLinesTosave']} ]; then
     mysql -h10.249.50.199 -uroot -P15646 -pucT_812WQb -Dlogcenter < ${configArr['tempSqlFilePath']}
     rm ${configArr['tempSqlFilePath']}
  fi
}


configFile=$1
declare -A configArr
while IFS='' read -r line || [[ -n "$line" ]]; do
   IFS='=' read -r key value <<< "$line"
   echo $key"and"$value
   configArr[$key]=$value
done < "$configFile"

echo -e "parse config file succ \n\nstart watch log[log path:${configArr['logCategoryPath']}]\n"
echo ${configArr['offsetFilePath']}"and"${configArr['rules']}
while watchInfo=`inotifywait -q --format '%e %f' -e modify,create ${configArr['logCategoryPath']}`;do
    
  watchInfo=($watchInfo)
  echo ${watchInfo[1]}|grep -q "^trade.*"
  if [ ! $? -eq 0 ];then
    continue
  fi
  watchInfo[1]=${configArr['logCategoryPath']}""${watchInfo[1]}
  lines=`wc -l ${watchInfo[1]}`
  lines=($lines)
  lines=${lines[0]}
  if [ $lines -lt 1 ];then
    continue
  fi
  # 如果偏移量文件不存在，则创建偏移量文件
  if [ -e ${configArr['offsetFilePath']} ]; then
    offsetInfo=`cat ${configArr['offsetFilePath']}`

    # 如果偏移量记录文件为空，则初始化偏移量，从第0行读取变更的文件
    if [ "$offsetInfo" = "" ]; then
      process 1 ${lines} ${watchInfo[1]} $configArr

    # 如果偏移量文件不为空，则取出偏移量和指向的文件
    else
      offsetInfo=($offsetInfo)
      offsetInfo[0]=` expr ${offsetInfo[0]} + 1`
      if [ ! "${offsetInfo[1]}" = "${watchInfo[1]}" ]; then
        # 处理上一个日志文件
        process ${offsetInfo[0]} $ ${offsetInfo[1]} $configArr

        # 处理从第0行开始处理新创建的文件
        process 1 ${lines} $watchInfo[1] $configArr
      else
        # 继续处理偏移量文件中记录的文件
        process ${offsetInfo[0]} ${lines} ${watchInfo[1]} $configArr
      fi
    fi
    # 处理完成，更新偏移量和指向的文件
    echo "$lines ${watchInfo[1]}" > ${configArr['offsetFilePath']}
  else
    touch ${configArr['offsetFilePath']}
  fi
done

exit 0
