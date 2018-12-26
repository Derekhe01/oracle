if [ -z $ORACLE_HOME ]; then
	echo "SET ORACLE_HOME"
	exit 1
elif [ -z $ORACLE_SID ]; then
	echo "SET SID"
	exit 1
fi

if [ -z $LOGIN ]; then
	LOGIN="conn / as sysdba"
else
	LOGIN="$LOGIN"
fi

# default sleep seconds, usage: trace-* watch-*
if [ -z $SLEEP ]; then
	SLEEP="1"
else
	SLEEP="$SLEEP"
fi

SQLPLUS=$ORACLE_HOME/bin/sqlplus

##########################################################################
print_copyright()
{
echo
echo "==========================================="
echo "orasql    :  query tool for oracle dba"
echo "version   :  1.0"
echo "author    :  Roger"
echo "Try orasql help for more information"
echo "==========================================="
}
print_usage()
{
echo
echo "Usage     :  orasql kyeword [arg1][arg2][...]"
echo "-----------------------------------------------------------------------------"
echo "keyword        args                        desc"
echo "============= ========================= ====================================="
echo "15event                                  : show last 15 minutes wait event"
echo "alert                                    : show last 15 minutes ORA error version > 11g"
echo "access        obj_name [owner]           : show who is access thie object"
echo "ash                                      : exp ash information"
echo "awrsnap                                  : create an awr snapshot manually"
echo "bind          sqlid                      : get bind value by sqlid"
echo "datafile                                 : show datafile information"
echo "dblink                                   : show dblink information"
echo "degree                                   : show obj degree > 1"
echo "depend        obj_name [owner]           : show obj depend information"
echo "event                                    : show current wait event"
echo "free                                     : show tablespace usage"
echo "func          function_name [owner]      : show function source code"
echo "glock                                    : show all instance table lock"
echo "grant         username                   : get sql for privilege to user"
echo "gathertab     table_name table_owner     : gather table statistics manually"
echo "hash          hash                       : get sql text by hash value"
echo "hanganalyze   [level]                    : get hanganalyze dump default 3" 
echo "hit                                      : show current memory hit"
echo "index         table_name [owner]         : show indexes of a table"
echo "job                                      : show job information"
echo "longops                                  : show long operation information"
echo "latch                                    : show latch information"
echo "part         table_name [owner]          : show partition table information"
echo "plan          hash or sqlid              : get sql plan by sqlid or hash value"
echo "lock                                     : show lock information"
echo "params        [%parameter%]              : show parameter information"
echo "proc          procedure_name [owner]     : show procedure source code"
echo "runjob        jobno                      : run a job by jobno"
echo "segsize       seg_name [owner]           : show seg size by name"
echo "spid          spid                       : get sql text by spid"
echo "sid           sid                        : get sql text by sid"
echo "sqlid         sqlid                      : get sql text by sqlid"
echo "sql                                      : show current sql information"
echo "sql2                                     : show current sql with paln information"
echo "tabstat       tab_name [owner]           : show if table statistics is expired"
echo "temp                                     : show temp segment usage"
echo "topcpu        [n]                        : Top n cpu sql from ps, default n is 1"
echo "topmem        [n]                        : Top n mem sql from ps, default n is 1"
echo "trigger       trigger name [owner]       : show trigger source code"
echo "unusable                                 : show unusable indexes"
echo "undo                                     : show undo usage"
echo "user                                     : show user information"
echo "view          view_name [owner]          : show view source code"
echo "-----------------------------------------------------------------------------"
}
##########################################################################

CMD=`echo $1 | tr [A-Z] [a-z]`
case $CMD in
sid)
if [ $# -eq 1 ]; then
 echo "Please input SID:"
 read SID
elif [ $# -eq 2 ]; then
 SID=$2
else
 print_copyright
 exit 1
fi

$SQLPLUS -s /nolog<<EOF
 $LOGIN;
 set echo off
 set feedback off
 set line 200 pages 2000
 set timing off
 col sql_text for a120
 set long 99999
 col hash_value new_value hash noprint
 col machine new_value mach noprint
 TTITLE 'HASH: 'hash' Machine:' mach skip 2
 
 select hash_value, sql_text,s.machine 
 from v\$sqltext_with_newlines st,v\$session s
 where st.address=s.sql_address and s.sid=$SID
 order by st.piece;
exit;
EOF
;;

alter)
$SQLPLUS -s /nolog<<EOF
 $LOGIN;
 set line 200 pages 2000
select distinct originating_timestamp,message_text from x\$dbgalertext where originating_timestamp > sysdate-15/1440 and message_text like '%ORA-%';
exit;
EOF
;;

access)
OWN=''
if [ $# -eq 1 ]; then
 echo "Please input object_name:"
 read OBJ
elif [ $# -eq 2 ]; then
 OBJ=$2
elif [ $# -eq 3 ]; then
 OBJ=$2
 OWN=$3
else
  print_copyright
  exit 1
fi   
$SQLPLUS -s /nolog<<EOF
$LOGIN
set line 200 pages 2000
select * from gv\$access where object=upper('$OBJ') and owner=nvl(upper('$OWN'),owner);
exit;
EOF
;; 
 
 hit)
$SQLPLUS -s /nolog<<EOF
$LOGIN
set line 200 pages 2000
select name,total,round(total-free,2) used, round(free,2) free,round((total-free)/total*100,2) pctused from
(select 'SGA' name,(select sum(value/1024/1024) from v\$sga) total,
(select sum(bytes/1024/1024) from v\$sgastat where name='free memory')free from dual)
union
select name,total,round(used,2)used,round(total-used,2)free,round(used/total*100,2)pctused from (
select 'PGA' name,(select value/1024/1024 total from v\$pgastat where name='aggregate PGA target parameter')total,
(select value/1024/1024 used from v\$pgastat where name='total PGA allocated')used from dual)
union
select name,round(total,2) total,round((total-free),2) used,round(free,2) free,round((total-free)/total*100,2) pctused from (
select 'Shared pool' name,(select sum(bytes/1024/1024) from v\$sgastat where pool='shared pool')total,
(select bytes/1024/1024 from v\$sgastat where name='free memory' and pool='shared pool') free from dual)
union
select name,round(total,2)total,round(total-free,2) used,round(free,2) free,round((total-free)/total,2) pctused from (
select 'Default pool' name,( select a.cnum_repl*(select value from v\$parameter where name='db_block_size')/1024/1024 total from x$kcbwds a, v\$buffer_pool p
  where a.set_id=p.LO_SETID and p.name='DEFAULT' and p.block_size=(select value from v\$parameter where name='db_block_size')) total,
(select a.anum_repl*(select value from v\$parameter where name='db_block_size')/1024/1024 free from x$kcbwds a, v\$buffer_pool p
where a.set_id=p.LO_SETID and p.name='DEFAULT' and p.block_size=(select value from v\$parameter where name='db_block_size')) free from dual)
union
  select name,nvl(round(total,2),0)total,nvl(round(total-free,2),0) used,nvl(round(free,2),0) free,nvl(round((total-free)/total,2),0) pctused from (
select 'KEEP pool' name,(select a.cnum_repl*(select value from v\$parameter where name='db_block_size')/1024/1024 total from x$kcbwds a, v\$buffer_pool p
  where a.set_id=p.LO_SETID and p.name='KEEP' and p.block_size=(select value from v\$parameter where name='db_block_size')) total,
(select a.anum_repl*(select value from v\$parameter where name='db_block_size')/1024/1024 free from x$kcbwds a, v\$buffer_pool p
where a.set_id=p.LO_SETID and p.name='KEEP' and p.block_size=(select value from v\$parameter where name='db_block_size')) free from dual)
union
select name,nvl(round(total,2),0)total,nvl(round(total-free,2),0) used,nvl(round(free,2),0) free,nvl(round((total-free)/total,2),0) pctused from (
select 'RECYCLE pool' name,( select a.cnum_repl*(select value from v\$parameter where name='db_block_size')/1024/1024 total from x$kcbwds a, v\$buffer_pool p
  where a.set_id=p.LO_SETID and p.name='RECYCLE' and p.block_size=(select value from v\$parameter where name='db_block_size')) total,
(select a.anum_repl*(select value from v\$parameter where name='db_block_size')/1024/1024 free from x$kcbwds a, v\$buffer_pool p
where a.set_id=p.LO_SETID and p.name='RECYCLE' and p.block_size=(select value from v\$parameter where name='db_block_size')) free from dual)
union
select name,nvl(round(total,2),0)total,nvl(round(total-free,2),0) used,nvl(round(free,2),0) free,nvl(round((total-free)/total,2),0) pctused from(
select 'DEFAULT 16K buffer cache' name,(select a.cnum_repl*16/1024 total from x$kcbwds a, v\$buffer_pool p
  where a.set_id=p.LO_SETID and p.name='DEFAULT' and p.block_size=16384) total,
  (select a.anum_repl*16/1024 free from x$kcbwds a, v\$buffer_pool p
where a.set_id=p.LO_SETID and p.name='DEFAULT' and p.block_size=16384) free from dual)
union
select name,nvl(round(total,2),0)total,nvl(round(total-free,2),0) used,nvl(round(free,2),0) free,nvl(round((total-free)/total,2),0) pctused from(
select 'DEFAULT 32K buffer cache' name,(select a.cnum_repl*32/1024 total from x$kcbwds a, v\$buffer_pool p
  where a.set_id=p.LO_SETID and p.name='DEFAULT' and p.block_size=32768) total,
  (select a.anum_repl*32/1024 free from x$kcbwds a, v\$buffer_pool p
where a.set_id=p.LO_SETID and p.name='DEFAULT' and p.block_size=32768) free from dual)
union
select name,total,total-free used,free, (total-free)/total*100 pctused from (
select 'Java Pool' name,(select sum(bytes/1024/1024) total from v\$sgastat where pool='java pool' group by pool)total,
( select bytes/1024/1024 free from v\$sgastat where pool='java pool' and name='free memory')free from dual)
union
select name,Round(total,2),round(total-free,2) used,round(free,2) free, round((total-free)/total*100,2) pctused from (
select 'Large Pool' name,(select sum(bytes/1024/1024) total from v\$sgastat where pool='large pool' group by pool)total,
( select bytes/1024/1024 free from v\$sgastat where pool='large pool' and name='free memory')free from dual)
order by pctused desc;
exit;
EOF
;;
 
spid)
if [ $# -eq 1 ]; then
 echo "Please input SPID "
 read SPID
elif [ $# -eq 2 ]; then
 SPID=$2
else
 print_copyright
 exit 1
fi

$SQLPLUS -s /nolog<<EOF
 $LOGIN;
 set echo off
 set feedback off
 set line 200 pages 2000
 set timing off
 set long 99999
 col sql_text for a120
 col hash_value new_value hash noprint
 col machine new_value mach noprint
 TTITLE 'HASH: 'hash' Machine:' mach skip 2
 
 select hash_value,sql_text,b.machine
 from v\$sqltext_with_newlines a,v\$session b 
 where a.hash_value=b.sql_hash_value
 and b.paddr in ( select addr from v\$process where spid=$SPID)
 order by piece;
exit;
EOF
;;

hash)
if [ $# -eq 1 ]; then
 echo "Please input HASH_VALUE "
 read HASH
elif [ $# -eq 2 ]; then
 HASH=$2
else
 print_copyright
 exit 1
fi

$SQLPLUS -s /nolog<<EOF
 $LOGIN;
 set echo off
 set feedback off
 set line 200 pages 2000
 set timing off
 col sql_text for a120
 col module for a30
 
 select module,sql_id from v\$sql where hash_value=$HASH and rownum<2;
 
 select sql_text from v\$sqltext_with_newlines where hash_value=$HASH
 order by piece;
exit;
EOF
;;



sqlid)
if [ $# -eq 1 ]; then
 echo "Please input SQL_ID: "
 read SQLID
elif [ $# -eq 2 ]; then
 SQLID=$2
else
 print_copyright
 exit 1
fi

$SQLPLUS -s /nolog<<EOF
 $LOGIN;
 set echo off
 set feedback off
 set line 200 pages 2000
 set timing off
 col sql_text for a120
 col module for a30
 col hash_value new_value hash noprint
 
 select module from v\$sql where sql_id='$SQLID' and rownum<2;
 
 TTITLE 'HASH:  ' hash skip 2
 select hash_value,sql_text from v\$sqltext_with_newlines where sql_id='$SQLID'
 order by address,piece;
exit;
EOF
;;

bind)
if [ $# -eq 1 ]; then
 echo "Please input SQL_ID: "
 read SQLID
elif [ $# -eq 2 ]; then
 SQLID=$2
else
 print_copyright
 exit 1
fi

$SQLPLUS -s /nolog<<EOF
 $LOGIN
 set line 200
 col name for a30
 col val for a60
 col DATATYPE_STRING for a30
 
 PROMPT ## BIND CAPTURE of SQL $SQLID
 
 var SQL_ID varchar2(30)
 exec :SQL_ID := '$SQLID'
 
 select sql_id,child_number,name,POSITION,DATATYPE_STRING,
 nvl(VALUE_STRING,anydata.AccessTimestamp(VALUE_ANYDATA)) val
 from v\$SQL_BIND_CAPTURE
 where sql_id=:SQL_ID
 order by child_number,POSITION,name;
 
 set line 200 pages 5000
 col LAST_CAPTURED for a20
 col val for a50
 
 select to_char(LAST_CAPTURED,'YYYY-MM-DD hh24:mi:ss') LAST_CAPTURED,
 name,
 DATATYPE_STRING,
 nvl(VALUE_STRING,anydata.AccessTimestamp(VALUE_ANYDATA)) val
 from DBA_HIST_SQLBING
 where sql_id = :SQL_ID
 and LAST_CAPTURED > sysdate - 1/24
 order by LAST_CAPTURED;

exit;
EOF
;; 
 
plan)
if [ $# -eq 1 ]; then
 echo "Please input SQL_ID or HASH_VALUE: "
 read SQLID_OR_HASHVALUE
elif [ $# -eq 2 ]; then
 SQLID_OR_HASHVALUE=$2
else
 print_copyright
 exit 1
fi

$SQLPLUS -s /nolog<<EOF
 $LOGIN
 set echo off
 set feedback off
 set line 200 pages 2000
 set heading off
 col sql_text for a120
 
 var SQLID_OR_HASHVALUE  varchar2(200);
 exec :SQLID_OR_HASHVALUE := '$SQLID_OR_HASHVALUE'
 
select '| Operation                         |Object Name                    |  Rows | Bytes|   Cost |'
	as "Explain Plan in library cache:" from dual
union all
select rpad('| '||substr(lpad(' ',1*(depth-1))||operation||
       decode(options, null,'',' '||options), 1, 35), 36, ' ')||'|'||
       rpad(decode(id, 0, '----------------------------',
       substr(decode(substr(object_name, 1, 7), 'SYS_LE_', null, object_name)
       ||' ',1, 30)), 31, ' ')||'|'|| lpad(decode(cardinality,null,'  ',
       decode(sign(cardinality-1000), -1, cardinality||' ',
       decode(sign(cardinality-1000000), -1, trunc(cardinality/1000)||'K',
       decode(sign(cardinality-1000000000), -1, trunc(cardinality/1000000)||'M',
       trunc(cardinality/1000000000)||'G')))), 7, ' ') || '|' ||
       lpad(decode(bytes,null,' ',
       decode(sign(bytes-1024), -1, bytes||' ',
       decode(sign(bytes-1048576), -1, trunc(bytes/1024)||'K',
       decode(sign(bytes-1073741824), -1, trunc(bytes/1048576)||'M',
       trunc(bytes/1073741824)||'G')))), 6, ' ') || '|' ||
       lpad(decode(cost,null,' ', decode(sign(cost-10000000), -1, cost||' ',
       decode(sign(cost-1000000000), -1, trunc(cost/1000000)||'M',
       trunc(cost/1000000000)||'G'))), 8, ' ') || '|' as "Explain plan"
from v\$sql_plan 
where ( SQL_ID= :SQLID_OR_HASHVALUE or to_char(hash_value) = :SQLID_OR_HASHVALUE )
 and child_number = (select max(child_number) from v\$sql_plan where (SQL_ID= :SQLID_OR_HASHVALUE or to_char(hash_value) = :SQLID_OR_HASHVALUE));
 
exit;
EOF
;; 


topcpu)
 if [ $# = 1 ]; then
  topn=1
 elif [ $# = 2 ]; then
  topn=$2
 else
  print_copyright
  exit 1
 fi
 
 topcpu=`ps auxw|grep LOCAL|sort -nrk 3|head -$topn|awk '{print $2}'` 
 for spid in $topcpu
 do
 echo "=================================================================="
  orasql spid $spid
 done
exit
;;

topmem)
 if [ $# = 1 ]; then
  topn=1
 elif [ $# = 2 ]; then
  topn=$2
 else
  print_copyright
  exit 1
 fi
 
 topmem=`ps auxw|grep LOCAL|sort -nrk 4|head -$topn|awk '{print $2}'` 
 for spid in $topmem
 do
 echo "=================================================================="
  orasql spid $spid
 done
exit
;;

job)
$SQLPLUS -s /nolog<<EOF
 $LOGIN
 set line 200 pages 2000
 col interval for a30
 col next_date for a19
 col nex_run_date for a40
 col job_action for a40
 col owner for a10
 col what for a40
 
 select owner,job_name,job_action,nex_run_date,enabled from dba_scheduler_jobs;
 
 select schema_user as owner,job,what,to_char(next_date,'yyyy-mm-dd hh24:mi:ss') as next_date,broken,interval,failures from dba_jobs order by schema_user,what;
 
exit;
EOF
;;

runjob)
 if [ $# -eq 1 ]; then
  echo "please input jobno:"
  read JOBNO
 elif [ $# -eq 2 ]; then
  JOBNO=$2
 else
  print_copyright
  exit 1
 fi 
 $SQLPLUS -s /nolog<<EOF
 $LOGIN
 exec dbms_ijob.run($JOBNO); 
exit;
EOF
;;

lock)
 $SQLPLUS -s /nolog<<EOF
 $LOGIN
 set line 200 pages 2000
 col user_name for a40
 col sid for 99999999999999
 col program for a40
 col blocking for a36
 col physical_reads for 999,999,999.99
 col buffer_gets for 999,999,999.99
 col elapsed_time for 999,999.99
 col cpu_time for 999,999,999.99
 col sql_text for a96
 col module for a23
 col sid_serial# for a20
 
 prompt table locked
 select distinct s.username  user_name,o.owner||'.'||o.object_name object_name,
 s.sid||','||s.serial# sid_serial#,s.program 
 from dba_objects o,v\$session s, v\$lock v
 where v.id1=o.object_id and v.sid=s.sid
 and (v.type='TM' or v.type='HW')
 order by program,object_name;
 
 prompt blocking
 col killora for a45
 col killos for a32
 select distinct 'alter system kill session '''||to_char(s.sid)||','||to_char(s.serial#)||''';' as killora,
 (select 'kill -9 ' spid from v\$process where addr in (select paddr from v\$session where sid=s.sid)) killos
 from v\$lock a,v\$lock b,v\$session s
 where a.id1=b.id1 and a.id2=b.id2 and a.block=1
 and b.request>0 and s.sid=a.sid and a.sid<>b.sid
 and s.type<>'BACKGROUD'
 order by 1;
 
exit;
EOF
;;

glock)
 $SQLPLUS -s /nolog<<EOF
 $LOGIN
 set line 200 pages 2000
 col user_name for a40
 col sid for 99999999999999
 col program for a40
 col blocking for a36
 col physical_reads for 999,999,999.99
 col buffer_gets for 999,999,999.99
 col elapsed_time for 999,999.99
 col cpu_time for 999,999,999.99
 col sql_text for a96
 col module for a23
 col sid_serial# for a20
 
 prompt table locked
 select distinct s.username  user_name,o.owner||'.'||o.object_name object_name,
 s.sid||','||s.serial# sid_serial#,s.program 
 from dba_objects o,gv\$session s, gv\$lock v
 where v.id1=o.object_id and v.sid=s.sid
 and (v.type='TM' or v.type='HW')
 order by program,object_name;
 
exit;
EOF
;;
 
depend)
OWN=''
if [ $# -eq 1 ]; then
 echo "Please input object_name:"
 read OBJ
elif [ $# -eq 2 ]; then
 OBJ=$2
elif [ $# -eq 3 ]; then
 OBJ=$2
 OWN=$3
else
  print_copyright
  exit 1
fi   
 $SQLPLUS -s /nolog<<EOF
 $LOGIN
 set line 200 pages 2000
 col link_name for a12
 col object_name for a32
 col referenced_owner for a20
 select owner,name as object_name,referenced_type,referenced_owner from dba_dependencies where referenced_name=upper('$OBJ') and referenced_owner=nvl(upper('$OWN'),referenced_owner);
exit;
EOF
;;


segsize)
OWN=''
if [ $# -eq 1 ]; then
 echo "Please input segment_name:"
 read OBJ
elif [ $# -eq 2 ]; then
 SEG=$2
elif [ $# -eq 3 ]; then
 SEG=$2
 OWN=$3
else
  print_copyright
  exit 1
fi   
 $SQLPLUS -s /nolog<<EOF
 $LOGIN
 set line 200 pages 2000
 col owner for a10
 col segment_name for a30
 SELECT owner,
       segment_name,
       segment_type,
       tablespace_name,
       ROUND(bytes/1024/1024,2) size_mb
FROM   dba_segments
where segment_name=upper('$SEG') and owner=nvl(upper('$OWN'),owner);
exit;
EOF
;;

free)
 $SQLPLUS -s /nolog<<EOF
 $LOGIN
set line 200 pages 2000
col SUM_SPACE(M) for a15
col USED_SPACE(M) for a15
col USED_RATE(%)  for a15
col FREE_SPACE(M) for a30
SELECT   D.TABLESPACE_NAME,
         SPACE||'M' "SUM_SPACE(M)",
         BLOCKS "SUM_BLOCKS",
         SPACE - NVL (FREE_SPACE, 0)||'M'  "USED_SPACE(M)",
         ROUND( (1 - NVL (FREE_SPACE, 0) / SPACE) * 100, 2)||'%' "USED_RATE(%)",
         FREE_SPACE||'M'  "FREE_SPACE(M)"
  FROM   (  SELECT   TABLESPACE_NAME,
                     ROUND (SUM (BYTES) / (1024 * 1024), 2) SPACE,
                     SUM (BLOCKS) BLOCKS
              FROM   DBA_DATA_FILES
          GROUP BY   TABLESPACE_NAME) D,
         (  SELECT   TABLESPACE_NAME,
                     ROUND (SUM (BYTES) / (1024 * 1024), 2) FREE_SPACE
              FROM   DBA_FREE_SPACE
          GROUP BY   TABLESPACE_NAME) F
 WHERE   D.TABLESPACE_NAME = F.TABLESPACE_NAME(+)
UNION ALL
SELECT   D.TABLESPACE_NAME,
         SPACE||'M' "SUM_SPACE(M)",
         BLOCKS SUM_BLOCKS,
         USED_SPACE||'M' "USED_SPACE(M)",
         ROUND (NVL (USED_SPACE, 0) / SPACE * 100, 2)||'%' "USED_RATE(%)",
         NVL (FREE_SPACE, 0)||'M' "FREE_SPACE(M)"
  FROM   (  SELECT   TABLESPACE_NAME,
                     ROUND (SUM (BYTES) / (1024 * 1024), 2) SPACE,
                     SUM (BLOCKS) BLOCKS
              FROM   DBA_TEMP_FILES
          GROUP BY   TABLESPACE_NAME) D,
         (  SELECT   TABLESPACE_NAME,
                     ROUND (SUM (BYTES_USED) / (1024 * 1024), 2) USED_SPACE,
                     ROUND (SUM (BYTES_FREE) / (1024 * 1024), 2) FREE_SPACE
              FROM   V\$TEMP_SPACE_HEADER
          GROUP BY   TABLESPACE_NAME) F
 WHERE   D.TABLESPACE_NAME = F.TABLESPACE_NAME(+) 
ORDER BY   1;
exit;
EOF
;;


longops)
 $SQLPLUS -s /nolog<<EOF
 $LOGIN
 set line 200 pages 2000
 col opname for a21
 col target for a32
 col perwork for a12
 col message for a83
 col sid for 9999
 
 TTITLE 'Current long operation' skip 2
 select sid,sql_hash_value,opname,target,sofar,totalwork,trunc(sofar/totalwork*100,2)||'%' as perwork,elapsed_seconds,message 
from v\$session_longops where sofar!=totalwork and totalwork>0;
exit;
EOF
;;

event)
 $SQLPLUS -s /nolog<<EOF
 $LOGIN
 set line 200 pages 2000
 TTITLE 'Current wait event' skip 2
 select event,count(*) from v\$session_wait group by event order by 2;
exit;
EOF
;;

15event)
 $SQLPLUS -s /nolog<<EOF
 $LOGIN
 set line 200 pages 2000
 TTITLE 'Wait Events in the last 15 Minutes' skip 2
select a.event, sum(a.wait_time+a.time_waited) total_wait_time from v\$active_session_history a where a.sample_time between sysdate-15/1440 and sysdate and event is not null
group by a.event order by total_wait_time desc;

col oname for a40
col event for a30

TTITLE 'Objects with the Highest Waits in the last 15 Minutes' skip 2
select o.owner||'.'|| o.object_name oname, o.object_type, a.event, sum(a.wait_time+a.time_waited) total_wait_time from v\$active_session_history a, dba_objects o
where a.sample_time between sysdate-15/1440 and sysdate
and a.current_obj#=o.object_id group by o.owner, o.object_name, o.object_type, a.event order by total_wait_time desc;

TTITLE 'Users with the Most Waits in the last 15 Minutes' skip 2
select s.sid, s.username, sum(a.wait_time+a.time_waited) total_wait_time from v\$active_session_history a, v\$session s where a.sample_time between sysdate-15/1440 and sysdate and s.username is not null and a.session_id=s.sid group by s.sid, s.username order by total_wait_time desc;
exit;
EOF
;;


sql)
 $SQLPLUS -s /nolog<<EOF
 $LOGIN
set serveroutput on size 1000000
set line 200 pages 5000
set feedback off
column username format a30
column sql_text format a120


declare
x number;
begin
for x in
( select username username, sid sid , serial# serial#, process ospid, program program,
to_char(LOGON_TIME,' Day HH24:MI') logon_time,
to_char(sysdate,' Day HH24:MI') current_time,
sql_address, LAST_CALL_ET
from v\$session
where status = 'ACTIVE'
and rawtohex(sql_address) <> '00'
and type<> 'BACKGROUD'
and sid <> (select sid from v\$mystat where rownum = 1)
and username is not null order by last_call_et )
loop
for y in ( select max(decode(piece,0,sql_text,null)) ||
max(decode(piece,1,sql_text,null)) ||
max(decode(piece,2,sql_text,null)) ||
max(decode(piece,3,sql_text,null))
sql_text
from v\$sqltext_with_newlines
where address = x.sql_address
order by piece)
loop
if ( y.sql_text not like '%listener.get_cmd%' and
y.sql_text not like '%RAWTOHEX(SQL_ADDRESS)%')
then
dbms_output.put_line( '--------------------' );
dbms_output.put_line( x.username || '(' || x.sid || ',' || x.serial# || ')' || ' ospid= ' || x.ospid || ' program ' || x.program);
dbms_output.put_line( x.logon_time || ' ' ||x.current_time||' last et = ' ||x.LAST_CALL_ET);
dbms_output.put_line(substr( y.sql_text, 1, 250 ) );
dbms_output.put_line( '--------------------' );
dbms_output.put_line( 'alter system kill session ''' || x.sid || ',' || x.serial# ||  ''' immediate;');
end if;
end loop;
end loop;
end;
/
exit;
EOF
;;

sql2)
 $SQLPLUS -s /nolog<<EOF
 $LOGIN
set serveroutput on size 1000000
set lines 200
set pages 1000
set feedback off
column username format a20
column sql_text format a98

declare
type tab_varchar2 is table of varchar2(128);
v_list tab_varchar2 := tab_varchar2();

procedure p (p_str in varchar2)
is
l_str long := p_str;
begin
loop
exit when l_str is null;
dbms_output.put_line(substr(l_str, 1, 250));
l_str := substr(l_str, 251);
end loop;
end;
begin
for x in (select a.username||'('||a.sid||','||a.serial#||') spid='||b.spid||
' hash_value='||to_char(a.sql_hash_value)||' execs='||to_char(s.executions)||
' els_time='||to_char(trunc(elapsed_time/1000000/decode(executions,0,null,executions),2)) username,
' program='||a.program program,a.sid,a.serial#,
' disk_reads='||to_char(trunc(disk_reads/decode(executions,0,null,executions),2)) disk_reads,
' buffer_gets='||to_char(trunc(buffer_gets/decode(executions,0,null,executions),2)) buffer_gets,sql_address,sql_hash_value
from v\$session a,v\$process b,v\$sqlarea s
where a.status = 'ACTIVE' and s.hash_value=a.sql_hash_value 
and a.paddr = b.addr and rawtohex(sql_address) <> '00' and a.username is not null
and sid <> (select sid from v\$mystat where rownum = 1) order by last_call_et)
loop
dbms_output.put_line( '--------------------------------------------------------------------------------' );
dbms_output.put_line( x.username );
dbms_output.put_line( x.program || ' ' ||x.disk_reads || ' '|| x.buffer_gets);
v_list.extend;
v_list(v_list.count) := 'alter system kill session '''||to_char(x.sid)||','||to_char(x.serial#)||''';';
for y in ( select sql_text
from v\$sqltext_with_newlines
where address = x.sql_address
order by piece )
loop
p(y.sql_text);
end loop;

--output sql execution plan
dbms_output.put_line( '--------------------------------------------------------------------------------' );
for i in (select rpad('|'||substr(lpad(' ',1 * (depth-1))||operation||
decode(options, null,'',' '||options), 1, 32), 33, ' ')||'|'||
rpad(decode(id, 0, '----- '||to_char(hash_value)||' -----',
substr(decode(substr(object_name, 1, 7), 'SYS_LE_', null, 
object_name)||' ',1, 20)), 21, ' ')||'|'||
lpad(decode(cardinality,null,' ',decode(sign(cardinality-1000), 
-1, cardinality||' ',decode(sign(cardinality-1000000), -1, 
trunc(cardinality/1000)||'K',decode(sign(cardinality-1000000000), -1, 
trunc(cardinality/1000000)||'M',trunc(cardinality/1000000000)||'G')))), 7, ' ') || '|' ||
lpad(decode(bytes,null,' ',decode(sign(bytes-1024), -1, bytes||' ',
decode(sign(bytes-1048576), -1, trunc(bytes/1024)||'K',decode(sign(bytes-1073741824), 
-1, trunc(bytes/1048576)||'M',trunc(bytes/1073741824)||'G')))), 6, ' ') || '|' || 
lpad(decode(cost,null,' ',decode(sign(cost-10000000), -1, cost||' ',
decode(sign(cost-1000000000), -1, trunc(cost/1000000)||'M',
trunc(cost/1000000000)||'G'))), 8, ' ') || '|' as Explain_plan
from v\$sql_plan
where hash_value = x.sql_hash_value 
and child_number = (select max(child_number) from v\$sql_plan where hash_value = x.sql_hash_value))
loop
dbms_output.put_line(i.explain_plan);
end loop; 
end loop;

--output kill session script
dbms_output.put_line( '----------------------------alter system kill session---------------------------' );
dbms_output.put_line( '--------------------------------------------------------------------------------' );
for i in 1..v_list.count loop
dbms_output.put_line(v_list(i));
end loop; 
end;
/
exit;
EOF
;;

latch)
 $SQLPLUS -s /nolog<<EOF
 $LOGIN
SELECT l.name "Latch Name",
       lh.pid "PID",
       lh.sid "SID",
       l.gets "Gets (Wait)",
       l.misses "Misses (Wait)",
       l.sleeps "Sleeps (Wait)",
       l.immediate_gets "Gets (No Wait)",
       l.immediate_misses "Misses (Wait)"
FROM   v\$latch l,
       v\$latchholder lh
WHERE  l.addr = lh.laddr
ORDER BY l.name;
exit;
EOF
;;
 
index)
OWN=''
if [ $# -eq 1 ]; then
 echo "Please input table_name:"
 read TBN
elif [ $# -eq 2 ]; then
 TBN=$2
elif [ $# -eq 3 ]; then
 TBN=$2
 OWN=$3
else
  print_copyright
  exit 1
fi   
 $SQLPLUS -s /nolog<<EOF
 $LOGIN
SET LINESIZE 500 PAGESIZE 1000

COLUMN index_name      FORMAT A30
COLUMN column_name     FORMAT A30
COLUMN column_position FORMAT 99999

var tb_name varchar2(30)
var tb_own varchar2(30)
exec :tb_name := '$TBN'
exec :tb_own := '$OWN'

select a.index_name,
       a.column_name,
       a.column_position,
       b.status
from   all_ind_columns a,
       all_indexes b
where  b.owner      = nvl(upper(:tb_own),b.owner)
and    b.table_name = upper(:tb_name)
and    b.index_name = a.index_name
and    b.owner      = a.index_owner
order by 1,3;

select owner,index_name,leaf_blocks,blevel,distinct_keys,clustering_factor,to_char(last_analyzed,'yyyy-mm-dd hh24:mi:ss') last_analyzed from dba_indexes
where table_name=upper(:tb_name)
and owner=nvl(upper(:tb_own),owner);

select t.constraint_name,c.constraint_type,t.column_name,t.position,c.status,c.validated from all_cons_columns t,all_constraints c
where c.constraint_name=t.constraint_name
and t.owner= c.owner
and c.constraint_name not like 'SYS%'
and t.owner = nvl(upper(:tb_own),t.owner)
and t.table_name = upper(:tb_name)
order by constraint_name,position;

exit;
EOF
;;
 
unusable)
$SQLPLUS -s /nolog<<EOF
$LOGIN
set line 200
SELECT 'alter index '||owner||'.'||index_name||' rebuild tablespace '||tablespace_name ||';' sql_to_rebuild_index
FROM   dba_indexes
WHERE  status = 'UNUSABLE'
union all
SELECT 'alter index '||index_owner||'.'||index_name ||' rebuild partition '||PARTITION_NAME||' TABLESPACE '||tablespace_name ||';' sql_to_rebuild_index
FROM   dba_ind_partitions
WHERE  status = 'UNUSABLE'
union all
SELECT 'alter index '||index_owner||'.'||index_name ||' rebuild subpartition '||SUBPARTITION_NAME||' TABLESPACE '||tablespace_name ||';' sql_to_rebuild_index
FROM   dba_ind_subpartitions
WHERE  status = 'UNUSABLE';
exit;
EOF
;; 

degree)
$SQLPLUS -s /nolog<<EOF
$LOGIN
set line 200 pages 5000
col owner for a10
col index_name for a30
col table_name for a30
select owner,index_name,degree from dba_indexes where degree>1 order by 1,2;
select owner,table_name,degree from dba_tables where trim(degree)<> '1' order by 1,2;
exit;
EOF
;;

dblink)
$SQLPLUS -s /nolog<<EOF
$LOGIN
col owner for a20
col db_link for a30
col host for a20
col username for a20
set line 200 pages  5000
select owner,db_link,username,host,created from dba_db_links;

select DB_LINK,LOGGED_ON,OPEN_CURSORS,IN_TRANSACTION,UPDATE_SENT,COMMIT_POINT_STRENGTH from v\$db_link;
exit;
EOF
;;

datafile)
$SQLPLUS -s /nolog<<EOF
$LOGIN
SET LINESIZE 200
col tablespace_name for a20
col file_name for a60

SELECT file_id,
       tablespace_name,
       file_name,
       ROUND(bytes/1024/1024/1024) AS size_gb,
       autoextensible
FROM   dba_data_files
ORDER BY 2,3;
exit;
EOF
;;

params)
if [ $# -eq 1 ]; then
 echo "Please input parameter name:"
 read PARAM
elif [ $# -eq 2 ]; then
 PARAM=$2
else
  print_copyright
  exit 1
fi
$SQLPLUS -s /nolog<<EOF
$LOGIN
set linesize 132 pages 5000
col name for a20
col value for a20
col description for a40
select
  x.ksppinm  name,
  x.ksppdesc  description,
  y.ksppstvl  value,
  y.ksppstdf  isdefault,
  decode(bitand(y.ksppstvf,7),1,'MODIFIED',4,'SYSTEM_MOD','FALSE')  ismod,
  decode(bitand(y.ksppstvf,2),2,'TRUE','FALSE')  isadj
from
  sys.x\$ksppi x,
  sys.x\$ksppcv y
where
  x.inst_id = userenv('Instance') and
  y.inst_id = userenv('Instance') and
  x.indx = y.indx and 
  x.ksppinm like '%$PARAM%'
order by
  translate(x.ksppinm, ' _', ' ');
exit;
EOF
;;
 
 
tabstat)
if [ $# -eq 1 ]; then
 echo "Please input table name:"
 read TBN
elif [ $# -eq 2 ]; then
 TBN=$2
elif [ $# -eq 3 ]; then
 TBN=$2
 OWN=$3
else
  print_copyright
  exit 1
fi
$SQLPLUS -s /nolog<<EOF
$LOGIN
set line 200
prompt statistics is expired
select owner, table_name name, object_type, stale_stats, last_analyzed
  from dba_tab_statistics
 where owner = nvl(upper('$OWN'),owner)
   and table_name = upper('$TBN')
   and (stale_stats = 'yes' or last_analyzed is null);
exit;
EOF
;;
 
trigger)
OWN=''
if [ $# -eq 1 ]; then
 echo "Please input trigger name:"
 read TRIG
elif [ $# -eq 2 ]; then
 TRIG=$2
elif [ $# -eq 3 ]; then
 TRIG=$2
 OWN=$3
else
  print_copyright
  exit 1
fi
$SQLPLUS -s /nolog<<EOF
$LOGIN
set line 200 pages 0
set long 999999999

select dbms_metadata.get_ddl('TRIGGER',trigger_name,owner) from dba_triggers where trigger_name=upper('$TRIG') and owner=upper(nvl('$OWN',owner)); 
exit;
EOF
;;

func)
OWN=''
if [ $# -eq 1 ]; then
 echo "Please input function name:"
 read FUNC
elif [ $# -eq 2 ]; then
 FUNC=$2
elif [ $# -eq 3 ]; then
 FUNC=$2
 OWN=$3
else
  print_copyright
  exit 1
fi
$SQLPLUS -s /nolog<<EOF
$LOGIN
set line 200 pages 0
set long 999999999

select dbms_metadata.get_ddl('FUNCTION',name,owner) from dba_source where name=upper('$FUNC') and owner=upper(nvl('$OWN',owner)) and type='FUNCTION' and rownum=1; 
exit;
EOF
;;


proc)
OWN=''
if [ $# -eq 1 ]; then
 echo "Please input procedure name:"
 read PROC
elif [ $# -eq 2 ]; then
 PROC=$2
elif [ $# -eq 3 ]; then
 PROC=$2
 OWN=$3
else
  print_copyright
  exit 1
fi
$SQLPLUS -s /nolog<<EOF
$LOGIN
set line 200 pages 0
set long 999999999

select dbms_metadata.get_ddl('PROCEDURE',name,owner) from dba_source where name=upper('$PROC') and owner=upper(nvl('$OWN',owner)) and type='PROCEDURE' and rownum=1; 
exit;
EOF
;;
 
grant)
OWN=''
if [ $# -eq 1 ]; then
 echo "Please input user name:"
 read USER
elif [ $# -eq 2 ]; then
 USER=$2
else
  print_copyright
  exit 1
fi
$SQLPLUS -s /nolog<<EOF
$LOGIN
set linesize 120 pagesize 1000
set echo off
set heading off
set feedback off
select 'grant '||tt.granted_role||' to '||tt.grantee||';' as SQL_text
from dba_role_privs tt where tt.grantee=(upper('$USER'))
union all
select 'grant '||tt.privilege||' to '||tt.grantee||';'
from dba_sys_privs tt where tt.grantee=(upper('$USER'))
union all
select 'grant '||tt.privilege||' on '||owner||'.'||table_name||' to '||tt.grantee||';'
from dba_tab_privs tt where tt.grantee=(upper('$USER'))
union all
select 'alter user '||tt.user_name||' quota '||maxblocks*blocksize||' on '||ts_name||';'
from KU$_TSQUOTA_VIEW tt where tt.user_name=(upper('$USER'));
exit;
EOF
;;
 
hanganalyze)
if [ $# -eq 1 ]; then
 LEVEL=3
elif [ $# -eq 2 ]; then
 LEVEL=$2
else
  print_copyright
  exit 1
fi
$SQLPLUS -s /nolog<<EOF
$LOGIN
set feedback off
ALTER SESSION set events 'immediate trace name hanganalyze level $LEVEL';

select d.value || '/' || lower(rtrim(i.instance, chr(0))) || '_ora_' ||
       p.SPID || '.trc'
  from (select p.SPID
          from v\$mystat m, v\$session s, v\$process p
         where m.STATISTIC# = 1
           and s.SID = m.SID
           and p.ADDR = s.PADDR) p,
       (select t.INSTANCE
          from v\$thread t, v\$parameter v
         where v.name = 'thread'
           and (t.THREAD# = to_number(v.VALUE))) i,
       (select value from v$parameter where name = 'user_dump_dest') d;
exit;
EOF
;;

undo)
$SQLPLUS -s /nolog<<EOF
$LOGIN
set line 200 pages 5000
col name for a20
col used_rate for a20
col free_m for a20
select name, used_rate || '%' as used_rate, free free_m
  from (select ts.name,
               round((t.space - (us.free + f.free)) / t.space * 100, 2) as used_rate,
               to_char(us.free + f.free) as free
          from (select undotsn, expiredblks * 8 / 1024 as free
                  from v\$undostat
                 where rownum = 1) us,
               v\$tablespace ts,
               (select tablespace_name,
                       round(sum(bytes) / (1024 * 1024), 2) free
                  from dba_free_space
                 group by tablespace_name) f,
               (select tablespace_name,
                       sum(blocks) blocks,
                       round(sum(bytes) / (1024 * 1024), 2) space
                  from dba_data_files
                 group by tablespace_name) t
         where ts.ts# = us.undotsn
           and ts.name = f.tablespace_name
           and ts.name = t.tablespace_name);
exit;
EOF
;;
 
awrsnap)
$SQLPLUS -s /nolog<<EOF
$LOGIN
exec dbms_workload_repository.create_snapshot;
exit;
EOF
;;

view)
if [ $# -eq 1 ]; then
 echo "Please input view_name:"
 read VIEW
elif [ $# -eq 2 ]; then
 VIEW=$2
else
  print_copyright
  exit 1
fi
$SQLPLUS -s /nolog<<EOF
$LOGIN
set line 200 pages 5000
set long 5000
select 'create view ' || owner ||'.'|| view_name || ' as 'cvas,text from dba_views where view_name=upper('$VIEW');
exit;
EOF
;;


part)
OWN=''
if [ $# -eq 1 ]; then
 echo "Please input table name:"
 read TBN
elif [ $# -eq 2 ]; then
 TBN=$2
elif [ $# -eq 3 ]; then
 TBN=$2
 OWN=$3
else
  print_copyright
  exit 1
fi
$SQLPLUS -s /nolog<<EOF
$LOGIN
set line 200
col table_owner for a10
col table_name for a20
col high_value for a30
col last_analyzed for a25
select part.table_owner,part.table_name,part.partition_name,
nvl(seg.bytes,0)/1024/1024/1024 SIZE_G,part.subpartition_count,
part.high_value,
to_char(part.last_analyzed,'yyy-mm-dd hh24:mi:ss') last_analyzed
from dba_tab_partitions part,dba_segments seg
where part.table_name = seg.segment_name(+)
and part.table_owner = seg.owner(+)
and part.partition_name = seg.partition_name(+)
and part.table_name = upper('$TBN')
and part.table_owner = nvl(upper('$OWN'),part.table_owner)
order by partition_position;
exit;
EOF
;;


temp)
$SQLPLUS -s /nolog<<EOF
$LOGIN
set lines 152 
col FreeSpaceGB format 999.999
col UsedSpaceGB format 999.999
col TotalSpaceGB format 999.999
col host_name format a30
col tablespace_name format a30
select tablespace_name,
(free_blocks*8)/1024/1024 FreeSpaceGB,
(used_blocks*8)/1024/1024 UsedSpaceGB,
(total_blocks*8)/1024/1024 TotalSpaceGB,
i.instance_name,i.host_name
from gv\$sort_segment ss,gv\$instance i where ss.tablespace_name in (select tablespace_name from dba_tablespaces where contents='TEMPORARY') and
i.inst_id=ss.inst_id;

col username for a12
col machine for a16
col tablespace for a10
select b.sid,b.serial#,b.username,b.machine,a.blocks,a.tablespace,a.segtype,a.segfile#,a.segblk# blocks from gv\$sort_usage a,gv\$session b where a.session_addr=b.saddr;
exit;
EOF
;;

ash)
TIME=`date "+%Y%m%d"`
$SQLPLUS -s /nolog<<EOF
$LOGIN
set line 200 pages 2000
create  table gash$TIME as select * from gv\$active_session_history;
create  table dba_ash$TIME as select * from DBA_HIST_ACTIVE_SESS_HISTORY where sample_time>sysdate-30;
create  table obj$TIME as select * from dba_objects;
create  table seg$TIME as select * from dba_segments;
create  table sqlstat$TIME as select * from DBA_HIST_SQLSTAT;
create  table sqltext$TIME as select * from DBA_HIST_SQLtext;
exit;
EOF
$ORACLE_HOME/bin/exp "'/ as sysdba'" tables=gash$TIME,dba_ash$TIME,obj$TIME,sqlstat$TIME,sqltext$TIME file=ASH$TIME.dmp
# $SQLPLUS -s /nolog<<EOF
# $LOGIN
# drop table gash$TIME      purge;
# drop table dba_ash$TIME   purge;
# drop table obj$TIME       purge;
# drop table seg$TIME       purge;
# drop table sqlstat$TIME   purge;
# drop table sqltext$TIME   purge;
# exit;
# EOF
;;

user)
$SQLPLUS -s /nolog<<EOF
$LOGIN
set line 200
col username for a15
select username,account_status,to_char(lock_date,'yyyy-mm-dd hh24:mi:ss') lock_date,to_char(created,'yyyy-mm-dd hh24:mi:dd') created,default_tablespace,temporary_tablespace from dba_users where rownum<10 order by created;
exit;
EOF
;;


gathertab)
if [ $# -eq 1 ]; then
 echo "Please input table name:"
 read TBN
 echo "Please input owner:"
 read OWN
elif [ $# -eq 2 ]; then
 TBN=$2
 echo "Please input owner:"
 read OWN
elif [ $# -eq 3 ]; then
 TBN=$2
 OWN=$3
else
  print_copyright
  exit 1
fi
$SQLPLUS -s /nolog<<EOF
$LOGIN
execute dbms_stats.gather_table_stats('$OWN','$TBN');
exit;
EOF
;;

help)
 print_usage
;;
*)
 print_copyright
 print_usage
;;
esac
