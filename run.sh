#!/bin/sh
# generic shell script to run a java program
#该脚本为Linux下启动java程序的通用脚本。即可以作为开机自启动service脚本被调用，
#也可以作为启动java程序的独立脚本来使用。
#
# Author: tudaxia.com, Date: 2011/6/7
# Author: alpha@mascot.x, Date: 2018.07.13
#
#警告!!!：该脚本stop部分使用系统kill命令来强制终止指定的java程序进程。
#在杀死进程前，未作任何条件检查。在某些情况下，如程序正在进行文件或数据库写操作，
#可能会造成数据丢失或数据不完整。如果必须要考虑到这类情况，则需要改写此脚本，
#增加在执行kill命令前的一系列检查。
#
# Attempt to set java command
if [ -z "$JAVA_HOME" ] ; then
	JAVACMD=`which java`
else
	JAVACMD="$JAVA_HOME/bin/java"
fi

if [ ! -x "$JAVACMD" ] ; then
  echo "The JAVA_HOME environment variable is not defined correctly" >&2
  echo "This environment variable is needed to run this program" >&2
  echo "NB: JAVA_HOME should point to a JDK not a JRE" >&2
  exit 1
fi

# set jps command
JPSCMD="`dirname $JAVACMD`/jps"

# set application entry, change it according to specific application
MAINCLASS="alpha.study.archetype.example.App"
# option: specify mainclass through the 2nd argument
if [ ! -z "$2" ] ; then
	MAINCLASS="$2"
fi
if [ -z "$MAINCLASS" ] ; then
	echo "The mainclass is not defined correctly" >&2
	exit 1
fi

# Attempt to set APP_HOME
# APP_HOME structure
# ├── bin
# │   └── run.sh
# ├── conf
# │   └── log4j2.xml
# ├── docs
# ├── lib
# │   ├── commons-lang3-3.5.jar
# │   ├── log4j-api-2.8.2.jar
# │   ├── log4j-core-2.8.2.jar
# │   ├── log4j-slf4j-impl-2.8.2.jar
# │   └── slf4j-api-1.7.25.jar
# ├── LICENSE
# ├── main
# │   └── alpha-archetype-example-0.0.1-SNAPSHOT.jar
# └── README.md

# resolve links - $0 may be a link
PRG="$0"
# need this for relative symlinks
while [ -h "$PRG" ] ; do
  ls=`ls -ld "$PRG"`
  link=`expr "$ls" : '.*-> \(.*\)$'`
  if expr "$link" : '/.*' > /dev/null; then
    PRG="$link"
  else
    PRG="`dirname "$PRG"`/$link"
  fi
done

# change to APP_HOME dir and make it fully qualified
cd "`dirname \"$PRG\"`/.." >/dev/null
APP_HOME="`pwd -P`"
# now current/working directory is APP_HOME

# set APP sub directory, change it according to specific application
APP_MAIN_DIR="$APP_HOME"/main
APP_LIB_DIR="$APP_HOME"/lib
APP_CONF_DIR="$APP_HOME"/conf

# set classpath, change it according to specific application
CLASSPATH="-classpath "
# append mainclass jar files to classpath
for i in "$APP_MAIN_DIR"/*.jar; do
   CLASSPATH="$CLASSPATH":"$i"
done
# append dependency jar files to classpath 
for i in "$APP_LIB_DIR"/*.jar; do
   CLASSPATH="$CLASSPATH":"$i"
done
# append Log4j 2 configuration file directory to classpath
CLASSPATH="$CLASSPATH":"$APP_CONF_DIR"

# change Log4j 2 configuration file if need be
# LOG4J2="-Dlog4j.configurationFile=$APP_CONF_DIR/log4j2.xml"

# set JVM options if need be 
# JVM_OPTS="-ms512m -mx512m -Xmn256m -XX:MaxPermSize=128m"

# set JAVA options
JAVA_OPTS="$JVM_OPTS $LOG4J2"

# set nohup output file
NOHUP_OUTPUT=/dev/null

#(函数)查找PID用于判断程序是否已启动
#
#说明：
#使用JDK自带的JPS命令及grep命令组合，准确查找PID
#jps 加 l 参数，表示显示java的完整包路径
#使用awk，分割出PID ($1部分)，及Java程序名称($2部分)
#初始化APPPID变量（全局）
APPPID=0

checkpid() {
   javaps=`$JPSCMD -l | grep $MAINCLASS`

   if [ -n "$javaps" ]; then
      APPPID=`echo $javaps | awk '{print $1}'`
   else
      APPPID=0
   fi
}

#(函数)启动程序
#
#说明：
#1. 首先调用checkpid函数，刷新$APPPID全局变量
#2. 如果程序已经启动（$APPPID不等于0），则提示程序已启动
#3. 如果程序没有被启动，则执行启动命令行
#4. 启动命令执行后，再次调用checkpid函数
#5. 如果步骤4的结果能够确认程序的PID,则打印[Succeed]，否则打印[Failed]
#注意：echo -n 表示打印字符后，不换行
#注意: "nohup 某命令 >/dev/null 2>&1 &" 的用法
start() {
   checkpid

   if [ $APPPID -ne 0 ]; then
      echo "================================"
      echo "warn: $MAINCLASS(PID=$APPPID) already started!"
      echo "================================"
   else
      echo "================================"
      echo -n "Starting $MAINCLASS"
      RUNCMD="$JAVACMD $JAVA_OPTS $CLASSPATH $MAINCLASS"
      nohup $RUNCMD 2>&1 | tee $NOHUP_OUTPUT &

	  checkpid
      if [ $APPPID -ne 0 ]; then
         echo "(PID=$APPPID) ... [Succeed]."
      else
         echo " ... [Failed]."
      fi
      echo "================================"      
   fi
}

#(函数)停止程序
#
#说明：
#1. 首先调用checkpid函数，刷新$APPPID全局变量
#2. 如果程序已经启动（$APPPID不等于0），则开始执行停止，否则，提示程序未运行
#3. 使用kill -9 PID命令进行强制杀死进程
#4. 执行kill命令行紧接其后，马上查看上一句命令的返回值: $?
#5. 如果步骤4的结果$?等于0,则打印[Succeed]，否则打印[Failed]
#6. 为了防止java程序被启动多次，这里增加反复检查进程，反复杀死的处理（递归调用stop）。
#注意：echo -n 表示打印字符后，不换行
#注意: 在shell编程中，"$?" 表示上一句命令或者一个函数的返回值
stop() {
   checkpid
   
   if [ $APPPID -ne 0 ]; then
      echo "================================"  
      echo -n "Stopping $MAINCLASS(PID=$APPPID) ... "
      kill -9 $APPPID
      if [ $? -eq 0 ]; then
         echo "[Succeed]."
      else
         echo "[Failed]."
      fi
      echo "================================"
 
      checkpid
      if [ $APPPID -ne 0 ]; then
         stop
      fi
   else
      echo "================================"  
      echo "warn: $MAINCLASS is not running."
      echo "================================"
   fi
}
 
#(函数)检查程序运行状态
#
#说明：
#1. 首先调用checkpid函数，刷新$APPPID全局变量
#2. 如果程序已经启动（$APPPID不等于0），则提示正在运行并表示出PID
#3. 否则，提示程序未运行
status() {
   checkpid

   if [ $APPPID -ne 0 ];  then
      echo "================================"
      echo "$MAINCLASS(PID=$APPPID) is running!"
      echo "================================"
      echo
      echo "`ps lf -p $APPPID`"
   else
      echo "================================"
      echo "$MAINCLASS is not running."
      echo "================================"
   fi
}

#(函数)打印系统环境参数
info() {
   echo "System Information:"
   echo "****************************"
   echo "`lsb_release -a`"
   echo "`uname -a`"
   echo "JAVA_HOME=$JAVA_HOME"
   echo "`$JAVACMD -version`"
   echo "APP_HOME=$APP_HOME"
   echo "MAINCLASS=$MAINCLASS"
   echo "****************************"
}

#读取脚本的第一个参数($1)，进行判断
#参数取值范围：{start|stop|restart|status|info}
#如参数不在指定范围之内，则打印帮助信息
case "$1" in
   'start')
      start
      ;;
   'stop')
     stop
     ;;
   'restart')
     stop
     start
     ;;
   'status')
     status
     ;;
   'info')
     info
     ;;
  *)
     echo "Usage: $0 {start|stop|restart|status|info} [mainclass]"
     echo
     info
     echo
     exit 1
esac

exit 0
