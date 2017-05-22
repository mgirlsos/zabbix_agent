#!/bin/bash
##################################
# Zabbix monitoring script
#
# mysql:
#  - MySQL variables
#  - MySQL status
#  - MySQL master / slave status
# Info:
#      -Top 10 SQL for rows examined
# MySQL details
CURRENT_DIR=$(readlink -f $(dirname $0))
ZABBIX_BASE_DIR=`readlink -f $( dirname $(dirname $0) )`
MYSQL_ACCESS="$CURRENT_DIR/../conf/mysql_credentials"
MYSQL_BIN=$(which mysql)
MYSQL_DEFAULT_PORT="3306"

ZBX_REQ_DATA="$1"
ZBX_REQ_ORDER="$2"
MYSQL_PORT="$3"

SCRIPT_CONF="$CURRENT_DIR/../conf/nc_mysql-realtime_check.conf"
[ -e "$SCRIPT_CONF" ] && source $SCRIPT_CONF

#
# Error handling:
#  - need to be displayable in Zabbix (avoid NOT_SUPPORTED)
#  - numeric items need to be of type "float" (allow negative + float)
#
ERROR_NO_ACCESS_FILE="-0.9900"
ERROR_NO_ACCESS="-0.9901"
ERROR_WRONG_PARAM="-0.9902"
ERROR_GENERIC="-0.9903"
ERROR_RUN_COMMAND="-0.9904"
ERROR_NO_PARAM="-0.9905"
# No mysql access file to read login info from
if [ ! -f "$MYSQL_ACCESS" ]; then
  echo $ERROR_NO_ACCESS_FILE
  exit 1
fi

# Assign default port if doesn't exist
if [ -z $MYSQL_PORT ]; then
  MYSQL_PORT="$MYSQL_DEFAULT_PORT"
fi

if [ -z $ZBX_REQ_DATA ];then
  echo "$ERROR_NO_PARAM" && exit 1
fi

# Check MySQL access
MYSQL="$MYSQL_BIN --defaults-extra-file=$MYSQL_ACCESS -P $MYSQL_PORT"
echo "" | $MYSQL 2>/dev/null
if [ $? -ne 0 ]; then
  echo $ERROR_NO_ACCESS
  exit 1
fi

Get_from_top10_rows_examined(){
SQL1="SELECT db, query, exec_count, avg_latency, rows_examined_avg, tmp_tables, tmp_disk_tables, rows_sorted, sort_merge_passes FROM sys.statement_analysis WHERE query NOT LIKE '%SQL_NO_CACHE%' ORDER BY rows_examined_avg DESC LIMIT 10;"

echo $SQL1 |$MYSQL
if [ $? -ne 0 ];then
  exit 1 && echo $ERROR_RUN_COMMAND
fi
}

Get_from_top10_latency(){
SQL2="SELECT schema_name as DB, digest_text as Query, count_star as exec_count, FLOOR (avg_timer_wait/1000/1000/1000/1000) as avg_latency_ms, FLOOR (sum_rows_examined / count_star) AS avg_rows_examined, FLOOR (sum_created_tmp_disk_tables / count_star) AS avg_disk_tables FROM performance_schema.events_statements_summary_by_digest WHERE digest_text NOT LIKE '%SQL_NO_CACHE%' ORDER BY avg_timer_wait DESC LIMIT 10;"
echo $SQL2 |$MYSQL
if [ $? -ne 0 ];then
  exit 1 && echo $ERROR_RUN_COMMAND
fi
}

Get_from_non_sleeping_process(){
SQL3="SELECT ID, USER, HOST, DB, COMMAND, TIME, STATE, LEFT(INFO, 40) FROM INFORMATION_SCHEMA.PROCESSLIST WHERE USER NOT IN ('repl','ncdba','ncbackup') AND COMMAND <> 'Sleep' ORDER BY TIME DESC;"
echo $SQL3 |$MYSQL
if [ $? -ne 0 ];then
  exit 1 && echo $ERROR_RUN_COMMAND
fi
}

Get_from_user_list(){
SQL4="SELECT user, host, UPPER(LEFT(sha2(password, 256), 10)) as pw_hash,  grant_priv, super_priv FROM mysql.user ORDER BY user, host;"

echo $SQL4 |$MYSQL
if [ $? -ne 0 ];then
  exit 1 && echo $ERROR_RUN_COMMAND
fi
}

Get_from_table_status(){
if [ -z $ZBX_REQ_ORDER ];then
 echo "$ERROR_NO_PARAM" && exit 1
fi

if [ $ZBX_REQ_ORDER == "name" ];then
  SQL5="SELECT TABLE_SCHEMA, TABlE_NAME, TABLE_TYPE, ENGINE, TABLE_ROWS, DATA_LENGTH, INDEX_LENGTH FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA NOT IN ('information_schema', 'mysql', 'sys', 'performance_schema') ORDER BY TABLE_SCHEMA, TABlE_NAME;"

echo $SQL5 | $MYSQL
  if [ $? -ne 0 ];then
  exit 1 && echo $ERROR_RUN_COMMAND
  fi
elif [ $ZBX_REQ_ORDER == "size" ];then
  SQL6="SELECT TABLE_SCHEMA,TABLE_NAME,TABLE_TYPE,ENGINE,TABLE_ROWS,DATA_LENGTH,INDEX_LENGTH FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA NOT IN ('information_schema', 'mysql', 'sys', 'performance_schema') ORDER BY (DATA_LENGTH+INDEX_LENGTH) DESC;"

echo $SQL6 |$MYSQL
  if [ $? -ne 0 ];then
  exit 1 && echo $ERROR_RUN_COMMAND
  fi
else
 exit 1 && echo "ERROR_WRONG_PARAM"
fi
}
Get_from_prod_db_summary(){
 SQL7="SELECT TABLE_SCHEMA, ENGINE, count(*) as table_count, sum(TABLE_ROWS) as table_rows, sum(DATA_LENGTH + INDEX_LENGTH) as data_index_size FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA NOT IN ('information_schema', 'mysql', 'sys', 'performance_schema') AND TABLE_TYPE = 'BASE TABLE' GROUP BY TABLE_SCHEMA, ENGINE ORDER BY TABLE_SCHEMA;"
 echo $SQL7 | $MYSQL
if [ $? -ne 0 ];then
  exit 1 && echo $ERROR_RUN_COMMAND
fi
}
case $ZBX_REQ_DATA in
  top_ten_rows_examined)   Get_from_top10_rows_examined;;
  top_ten_latency)         Get_from_top10_latency;;
  non_sleeping_process)  Get_from_non_sleeping_process;;
  user_list)             Get_from_user_list;;
  table_status)          Get_from_table_status ;;
  prod_db_summary)       Get_from_prod_db_summary;;
  *)                     echo $ERROR_WRONG_PARAM && exit 1;;
esac
