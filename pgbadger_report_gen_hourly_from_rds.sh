#!/bin/bash

export PATH=$PATH:/bin:/usr/local/bin
LOG_DIR=<Path of folder where temporary files will be created.>
PGBADGER_DIR=<pgbadger_utility_path>/pgbadger-master

function log_file {

  if [[ -d "${LOG_DIR}" ]]; then
    LogFile=${LOG_DIR}/$(date "+%Y%m%d_%H%M%S").log
    touch $LogFile
    chmod 644 $LogFile
  else
    echo "The logs directory ${LOG_DIR} does not exist"
    exit 1
  fi

  if [ ! -f "${LogFile}" ]; then
    echo "The logfile could ${LogFile} not be generated"
    exit 1
  fi

}

function dblist_file {

  if [[ -d "${LOG_DIR}" ]]; then
    DBLIST=${LOG_DIR}/$(date "+%Y%m%d_%H%M%S").txt
    touch $DBLIST
    chmod 644 $DBLIST
  else
    echo "The logs directory ${LOG_DIR} does not exist"
    exit 1
  fi

  if [ ! -f "${DBLIST}" ]; then
    echo "The logfile could ${DBLIST} not be generated"
    exit 1
  fi

}

function list_of_logfile {

  if [[ -d "${LOG_DIR}" ]]; then
    list_of_logfile_db=${LOG_DIR}/$(date "+%Y%m%d_%H%M%S").txt
    touch $list_of_logfile_db
    chmod 644 $list_of_logfile_db
  else
    echo "The logs directory ${LOG_DIR} does not exist"
    exit 1
  fi

  if [ ! -f "${list_of_logfile_db}" ]; then
    echo "The logfile could ${list_of_logfile_db} not be generated"
    exit 1
  fi

}


function list_db {
aws rds describe-db-instances --filters Name=engine,Values=aurora-postgresql --query 'DBInstances[*].[DBInstanceIdentifier]' --output text > $DBLIST
echo "List of database generated."
}


function logfile_name_list {
DBNAME=$1
aws rds describe-db-log-files  --db-instance-identifier $DBNAME --query 'DescribeDBLogFiles[*].[LogFileName]' | awk '{print $1}' | sed 's/[][]//g' | sed 's/,//g' | sed '/^$/d' | sed 's/"//g' > $list_of_logfile_db
}


function download_dblog {
DBNAME=$1
pg_logfile_name=$2
aws rds download-db-log-file-portion --db-instance-identifier $DBNAME --log-file-name $pg_logfile_name --starting-token 0 --output text >> $LogFile

        if [ $? == 0 ]; then
                echo "Postgres Logfile downloaded successfully"
        else
                echo "Postgres Logfile failed to generate !!!"
                exit 1
        fi
}

function gen_pgbadger_rep {
DBNAME=$1
echo "entered pgbadger report generation"
${PGBADGER_DIR}/pgbadger -p "%t:%r:%u@%d:[%p]:" $LogFile -o $DBNAME_${LogFile}_report.html
}

function copy_to_s3 {
dt_l=`date "+%d"`
hr_l=`date "+%H"|sed 's/^0//g'`
DBNAME=$1
aws s3 cp $DBNAME_${LogFile}_report.html s3://<bucket_name>/${DBNAME}_${dt_l}_${hr_l}_report.html

        if [ $? == 0 ]; then
                echo "Pgbadger report successfully uploaded"
        else
                echo "Pgbadger report failed to upload !!!"
                exit 1
        fi
}


function db_availability {
DBNAME=$1
db_avail=`aws rds describe-db-instances --db-instance-identifier $DBNAME --query 'DBInstances[*].[DBInstanceStatus]' --output text`
}



###################################Main Program ############################

dblist_file
list_db

cat $DBLIST | while read line
do
        if [ "$line" ]
                then
                        DBIDENTIFIER=`echo $line`
                        db_availability $DBIDENTIFIER
                        if [ $db_avail != "available" ]; then
                                        continue
                        fi
                        if [ ! -f "${list_of_logfile_db}" ]; then
                                echo "The logfile ${list_of_logfile_db} doesnt exist"
                        else
                                rm ${list_of_logfile_db}
                        fi
                        list_of_logfile
                        logfile_name_list $DBIDENTIFIER
                        dt=`date "+%d"`
                        hr=`date "+%H"|sed 's/^0//g'`
                        if [ $hr -eq 0 ]; then
                                curr_h=23
                                dt=`expr $dt - 1`
                        else
                                curr_h=`expr $hr - 1`
                        fi
                        log_file
                        cat $list_of_logfile_db | while read logfileline
                        do
                                if [ "$logfileline" ]
                                        then
                                                logfile_dt=`echo $logfileline | cut -d "-" -f 3`
                                                logfile_hr=`echo $logfileline |cut -d "-" -f 4 | cut -c 1-2|sed 's/^0//g'`
                                                        if [[ $dt -eq $logfile_dt && $curr_h -eq $logfile_hr ]];
                                                                then
                                                                        download_dblog $DBIDENTIFIER $logfileline
                                                        fi
                                else
                                        echo "No logfile in the list"
                                        continue
                                fi
                        done
                        gen_pgbadger_rep $DBIDENTIFIER
                        copy_to_s3 $DBIDENTIFIER
        else
        echo "No Database in the list"
        fi
done

##############################clear files from directory #######################
rm ${LOG_DIR}/*.txt
#echo "The text files deleted from path ${LOG_DIR}"
rm ${LOG_DIR}/*.html
#echo "The html files deleted from path ${LOG_DIR}"
rm ${LOG_DIR}/*.log
#echo "The log files deleted from path ${LOG_DIR}"
