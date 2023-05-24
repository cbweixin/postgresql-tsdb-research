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
