# postgresql-tsdb-research
explore feasibility of use postgresql as time series db

## run postgresql docker image
take a reference at the `start_postgres.sh` script

## creat table
```sql
CREATE TABLE monitor
  (
     time      TIMESTAMP,
     tags_id   INTEGER,
     server_ip VARCHAR(15),
     cpu       INTEGER,
     memory    INTEGER
  ); 
```

## generate data

```sql
INSERT INTO monitor
SELECT generate_series(now(), now() + '1 month', '1 second') AS time,
       ( random() * ( 10 ) ) :: INTEGER                      AS tag_id,
       '192.168.1.' || ( random() * ( 100 ) ) :: INTEGER :: VARCHAR       AS server_ip,
       ( random() * ( 10 ) ) :: INTEGER                      AS cpu,
       ( random() * ( 10 ) ) :: INTEGER                      AS memory; 
```

result:
```
2678401 row(s) updated - 7.477s
```

check size
```sql
select pg_size_pretty(pg_table_size('monitor'));
```

result: 173 MB


## query
```sql
explain analyze
select 
  * 
from 
  monitor 
where 
  time between '2023-05-25 00:00:00' :: timestamp 
  and '2023-06-02 00:00:00' :: timestamp 
```
output:
```
Seq Scan on monitor  (cost=0.00..62310.01 rows=697821 width=32) (actual time=0.013..149.522 rows=691200 loops=1)
  Filter: (("time" >= '2023-05-25 00:00:00'::timestamp without time zone) AND ("time" <= '2023-06-02 00:00:00'::timestamp without time zone))
  Rows Removed by Filter: 1987201
Planning Time: 0.148 ms
Execution Time: 171.290 ms
```
no index, so the query scan the whole table, as `Seq Scan` shows

## create brin index
A BRIN index is a type of index that is designed for large tables with a natural sort order, such as time-series data. The index is divided into blocks, and each block contains a range of values. When a query specifies a range of values, the BRIN index can quickly identify the blocks that may contain matching rows, allowing PostgreSQL to skip over large portions of the table that are outside of the query range.

```sql
create index monitor_time_brin_idx on monitor using BRIN(time)
```

it takes 215ms. very fast

check size
```sql
select pg_size_pretty(pg_relation_size('monitor_time_brin_idx'));
```

result: 24kb

raw table size is 173MB, index is just 24KB, it is pretty small, index speed is very fast.  

now check excution plan again

```sql
explain analyze
select 
  * 
from 
  monitor 
where 
  time between '2023-05-25 00:00:00' :: timestamp 
  and '2023-06-02 00:00:00' :: timestamp 
```

output:
```
Bitmap Heap Scan on monitor  (cost=187.93..33004.57 rows=697821 width=32) (actual time=0.459..95.827 rows=691200 loops=1)
  Recheck Cond: (("time" >= '2023-05-25 00:00:00'::timestamp without time zone) AND ("time" <= '2023-06-02 00:00:00'::timestamp without time zone))
  Rows Removed by Index Recheck: 5883
  Heap Blocks: lossy=5760
  ->  Bitmap Index Scan on monitor_time_brin_idx  (cost=0.00..13.47 rows=712176 width=0) (actual time=0.231..0.231 rows=57600 loops=1)
        Index Cond: (("time" >= '2023-05-25 00:00:00'::timestamp without time zone) AND ("time" <= '2023-06-02 00:00:00'::timestamp without time zone))
Planning Time: 0.100 ms
Execution Time: 114.064 ms
```

now we can see the query go through the index , as 'bitmap heap` and `bitmap index` shows

## use partition table


```sql
CREATE TABLE monitor2 (
  time TIMESTAMP, 
  tags_id INTEGER, 
  server_ip VARCHAR(15), 
  cpu INTEGER, 
  memory INTEGER
) partition by range(time);
```

after create parent table, then we create several children tables
```sql
create table monitor2_2023_05
    partition of monitor2
        for values from('2023-05-23 00:00:00+00') to ('2023-06-23 00:00:00+00');

create table monitor2_2023_06
    partition of monitor2
        for values from('2023-06-23 00:00:00+00') to ('2023-07-23 00:00:00+00');


create table monitor2_2023_07
    partition of monitor2
        for values from('2023-07-23 00:00:00+00') to ('2023-08-23 00:00:00+00');
```

so we have 
```sql
test=# \dt+ monitor2*
                                               List of relations
 Schema |       Name       |       Type        |  Owner   | Persistence | Access method |  Size   | Description
--------+------------------+-------------------+----------+-------------+---------------+---------+-------------
 public | monitor2         | partitioned table | postgres | permanent   |               | 0 bytes |
 public | monitor2_2023_05 | table             | postgres | permanent   | heap          | 168 MB  |
 public | monitor2_2023_06 | table             | postgres | permanent   | heap          | 167 MB  |
 public | monitor2_2023_07 | table             | postgres | permanent   | heap          | 5504 kB |
(4 rows)
```

then generate data
```sql
INSERT INTO monitor2
SELECT generate_series(now(), now() + '2 month', '1 second') AS time,
       ( random() * ( 10 ) ) :: INTEGER                      AS tag_id,
       '192.168.1.' || ( random() * ( 100 ) ) :: INTEGER :: VARCHAR       AS server_ip,
       ( random() * ( 10 ) ) :: INTEGER                      AS cpu,
       ( random() * ( 10 ) ) :: INTEGER                      AS memory; 
```
create index: `create index monitor2_time_brin_idx on monitor2 using BRIN(time)`

then query partition
```sql
explain analyze
select 
  * 
from 
  monitor2 
where 
  time between '2023-05-25 00:00:00' :: timestamp 
  and '2023-06-02 00:00:00' :: timestamp 
```

this query doesn't cross partition, output:
```
Bitmap Heap Scan on monitor2_2023_05 monitor2  (cost=189.21..32301.45 rows=702965 width=32) (actual time=0.694..72.849 rows=691200 loops=1)
  Recheck Cond: (("time" >= '2023-05-25 00:00:00'::timestamp without time zone) AND ("time" <= '2023-06-02 00:00:00'::timestamp without time zone))
  Rows Removed by Index Recheck: 21315
  Heap Blocks: lossy=5888
  ->  Bitmap Index Scan on monitor2_2023_05_time_idx  (cost=0.00..13.47 rows=710749 width=0) (actual time=0.062..0.062 rows=58880 loops=1)
        Index Cond: (("time" >= '2023-05-25 00:00:00'::timestamp without time zone) AND ("time" <= '2023-06-02 00:00:00'::timestamp without time zone))
Planning Time: 0.102 ms
Execution Time: 87.516 ms
```

another cross partition query ```sql explain analyze
select 
  * 
from 
  monitor2 
where 
  time between '2023-06-22 00:00:00' :: timestamp 
  and '2023-06-29 00:00:00' :: timestamp 
```
output:
```
Append  (cost=32.82..55268.06 rows=593098 width=32) (actual time=0.188..83.483 rows=604754 loops=1)
  ->  Bitmap Heap Scan on monitor2_2023_05 monitor2_1  (cost=32.82..22874.41 rows=82527 width=32) (actual time=0.187..13.306 rows=86400 loops=1)
        Recheck Cond: (("time" >= '2023-06-22 00:00:00'::timestamp without time zone) AND ("time" <= '2023-06-29 00:00:00'::timestamp without time zone))
        Rows Removed by Index Recheck: 113
        Heap Blocks: lossy=715
        ->  Bitmap Index Scan on monitor2_2023_05_time_idx  (cost=0.00..12.19 rows=92706 width=0) (actual time=0.133..0.133 rows=7150 loops=1)
              Index Cond: (("time" >= '2023-06-22 00:00:00'::timestamp without time zone) AND ("time" <= '2023-06-29 00:00:00'::timestamp without time zone))
  ->  Bitmap Heap Scan on monitor2_2023_06 monitor2_2  (cost=140.73..29428.16 rows=510571 width=32) (actual time=0.201..38.115 rows=518354 loops=1)
        Recheck Cond: (("time" >= '2023-06-22 00:00:00'::timestamp without time zone) AND ("time" <= '2023-06-29 00:00:00'::timestamp without time zone))
        Rows Removed by Index Recheck: 8349
        Heap Blocks: lossy=4352
        ->  Bitmap Index Scan on monitor2_2023_06_time_idx  (cost=0.00..13.09 rows=524562 width=0) (actual time=0.186..0.186 rows=43520 loops=1)
              Index Cond: (("time" >= '2023-06-22 00:00:00'::timestamp without time zone) AND ("time" <= '2023-06-29 00:00:00'::timestamp without time zone))
Planning Time: 0.596 ms
Execution Time: 99.409 ms
```

index size
```sql
select pg_size_pretty(pg_indexes_size('monitor2_2023_06'));
```
result: 48 KB

table size 
```sql
select pg_size_pretty(pg_table_size('monitor2_2023_06'));
```
result: 168 MB


## using pg_partman to automate partition process
```sql
SELECT partman.create_parent( 
     p_parent_table => 'monitor',
	 p_control => 'time',
	 p_type => 'native',
	 p_interval=> 'daily',
     p_start_partition := '2023-06-01 00:00:00',
	 p_premake => 3);
```

## run_maintenance_proc
```sql
CREATE EXTENSION pg_cron;

UPDATE partman.part_config
	SET infinite_time_partitions = true,
	    retention = '3 days',
	    retention_keep_table=true
	WHERE parent_table = 'monitor';
SELECT cron.schedule_in_database('monitor_job','@hourly', $$CALL partman.run_maintenance_proc()$$,'test');

# update cron
SELECT cron.alter_job(1,'30 2 * * *', $$CALL partman.run_maintenance_proc()$$,'test');
```

## sub-partition

we have such an table already:
```sql

create table monitor2_2023_06
    partition of monitor2
        for values from('2023-06-23 00:00:00+00') to ('2023-07-23 00:00:00+00');

```

the can sub-partition this table by week

```sql
create table monitor2_2023_06_01
    partition of monitor2_2023_06
        for values from('2023-06-23 00:00:00+00') to ('2023-06-30 00:00:00+00');

create table monitor2_2023_06_02
    ....
```


