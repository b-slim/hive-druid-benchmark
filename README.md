# hive-druid-benchmark
This repository contains data and files to track hive druid benchmark.
# Data ingestion
This step will cover the ingestion of data from hive to druid.
Target database in hive is tpc-ds 1TB of data called `tpcds_bin_partitioned_newschema_orc_1000`.

***Note i had some issue with using LLAP to create the data mainly due to sizing of memory issue recommend to use container mode.***
run `set hive.llap.execution.mode=none;` to force LLAP off during data ingestion phase.

## Mandatory params
First need to point hive to the druid metadata store.
```
set hive.druid.metadata.password=diurd;
set hive.druid.metadata.username=druid;
set hive.druid.metadata.uri=jdbc:mysql://cn105-10.l42scl.hortonworks.com/druid_benchmark;
```

## Optional settings

The parameter `hive.druid.indexer.partition.size.max` determines the number of rows per physical segment partition.
This will determine the physical size of each partition. Usually 5M row per partition is a good starting point
The parameter `hive.druid.indexer.memory.rownum.max` determines the number of rows kept in ram while building the index.
This manages the memory pressure during the ingestion by spilling to disk.   

```
set hive.druid.indexer.partition.size.max=5000000;
set hive.druid.indexer.memory.rownum.max=500000;
```
`hive.druid.passiveWaitTimeMs` is the amount of time to wait for complete data loading by druid.
i am setting it to `1` since i am running this job without live druid cluster

Make sure that containers have enough memory.
```
SET hive.tez.container.size=18000;
SET hive.tez.java.opts=-Xmx9000m -XX:MaxDirectMemorySize=1024g -Duser.timezone="America/New_York";
```

## Create AS command
We have 2 important settings as table properties.
`druid.segment.granularity` is the druid segment granularity that determines how to partition the data.
`druid.query.granularity` is the rollup granularity used to summarize the data.
values of those 2 settings are `DAY, MONTH, YEAR`

```sql
CREATE TABLE tpcds_store_sales_sold_time_1T_day
STORED BY 'org.apache.hadoop.hive.druid.DruidStorageHandler'
TBLPROPERTIES ("druid.datasource" = "tpcds_store_sales_sold_time_1T_day", "druid.segment.granularity" = "MONTH", "druid.query.granularity" = "DAY")
AS
SELECT CAST(d_date AS TIMESTAMP) AS `__time`, cast(i_manufact_id as STRING) i_manufact_id, cast(i_manager_id as STRING) i_manager_id, i_item_desc, cast(i_category_id AS STRING) i_category_id, i_category, i_class, CAST(i_item_id AS STRING) i_item_id, CAST(item.i_brand_id AS STRING) i_brand_id, item.i_brand, CAST(ss_customer_sk AS STRING) ss_customer_sk,CAST(ss_store_sk AS STRING) ss_store_sk,  i_current_price, ss_ext_sales_price, ss_quantity, ss_sales_price
FROM tpcds_bin_partitioned_newschema_orc_10000.store_sales, tpcds_bin_partitioned_newschema_orc_10000.item, tpcds_bin_partitioned_newschema_orc_10000.date_dim where store_sales.ss_item_sk = item.i_item_sk and store_sales.ss_sold_date_sk = date_dim.d_date_sk ;
```

# Query
I have created 2 datasource on cn105 namely `tpcds_store_sales_sold_time_1T_day` (data rolledup by day level) and `tpcds_store_sales_sold_time_1T_month`(data rolledup by month).
If you want to try it out point the hive CLI to the following broker.
`SET hive.druid.broker.address.default=cn114-10.l42scl.hortonworks.com:8082;`
You can run those query with one LLAP node if you are using auto-build.

## Query 3
Original sql query
```sql
  select  dt.d_year ,item.i_brand_id brand_id ,item.i_brand brand ,sum(ss_ext_sales_price) sum_agg
  from  tpcds_bin_partitioned_newschema_orc_1000.date_dim dt ,tpcds_bin_partitioned_newschema_orc_1000.store_sales ,tpcds_bin_partitioned_newschema_orc_1000.item
  where dt.d_date_sk = store_sales.ss_sold_date_sk and store_sales.ss_item_sk = item.i_item_sk and item.i_manufact_id = 436 and dt.d_moy=12
  group by dt.d_year ,item.i_brand ,item.i_brand_id
  order by dt.d_year ,sum_agg desc ,brand_id limit 100;
```
Druid denormalized query
```sql
select floor_year(`__time`)  as d_year , i_brand_id brand_id ,i_brand ,sum(ss_ext_sales_price) sum_agg
from  tpcds_store_sales_sold_time_1T_day
where i_manufact_id = "436"
and ((`__time` >= cast("1997-12-01" as date) and `__time` <= cast("1997-12-31" as date))
 OR (`__time` >= cast("1998-12-01" as date) and `__time` <= cast("1998-12-31" as date))
 OR (`__time` >= cast("1999-12-01" as date) and `__time` <= cast("1999-12-31" as date))
 OR (`__time` >= cast("2000-12-01" as date) and `__time` <= cast("2000-12-31" as date))
 OR (`__time` >= cast("2001-12-01" as date) and `__time` <= cast("2001-12-31" as date))
 OR (`__time` >= cast("2002-12-01" as date) and `__time` <= cast("2002-12-31" as date))
 OR (`__time` >= cast("2002-13-01" as date) and `__time` <= cast("2003-12-31" as date))
)
group by floor_year(`__time`)  ,i_brand ,i_brand_id
order by d_year ,sum_agg desc, brand_id limit 100;
```

## Query 42
Original sql query
```sql
select  dt.d_year ,item.i_category_id ,item.i_category ,sum(ss_ext_sales_price) as s
from   tpcds_bin_partitioned_newschema_orc_1000.date_dim dt ,tpcds_bin_partitioned_newschema_orc_1000.store_sales ,tpcds_bin_partitioned_newschema_orc_1000.item
where dt.d_date_sk = store_sales.ss_sold_date_sk and store_sales.ss_item_sk = item.i_item_sk and item.i_manager_id = 1 and dt.d_moy=12 and dt.d_year=1998
group by       dt.d_year ,item.i_category_id ,item.i_category
order by       s desc,dt.d_year ,item.i_category_id ,item.i_category
limit 100;
```
Druid denormalized query
```sql
select floor_year(`__time`) d_year, i_category_id , i_category ,sum(ss_ext_sales_price) as s
from  tpcds_store_sales_sold_time_1T_day
where i_manager_id = '1' and  `__time` >= cast("1998-12-01" as date) and `__time` <= cast("1998-12-31" as date)
group by floor_year(`__time`)  ,i_category_id ,i_category
order by s desc, d_year , i_category_id , i_category
limit 100;
```

## Query 52

Original sql query
```sql
  select  dt.d_year ,item.i_brand_id brand_id ,item.i_brand brand ,sum(ss_ext_sales_price) ext_price
  from tpcds_bin_partitioned_newschema_orc_1000.date_dim dt , tpcds_bin_partitioned_newschema_orc_1000.store_sales ,tpcds_bin_partitioned_newschema_orc_1000.item
  where dt.d_date_sk = store_sales.ss_sold_date_sk and store_sales.ss_item_sk = item.i_item_sk and item.i_manager_id = 1 and dt.d_moy=12 and dt.d_year=1998
  group by dt.d_year ,item.i_brand ,item.i_brand_id
  order by dt.d_year ,ext_price desc ,brand_id limit 100;
```

Druid denormalized query
```sql
select  floor_year(`__time`) d_year, i_brand_id brand_id ,i_brand brand ,sum(ss_ext_sales_price) ext_price
from  tpcds_store_sales_sold_time_1T_day
where i_manager_id = "1" and  `__time` >= cast("1998-12-01" as date) and `__time` <= cast("1998-12-31" as date)
group by floor_year(`__time`) ,i_brand , i_brand_id
order by d_year ,ext_price desc ,brand_id limit 100;
```

## Query 55

Original sql query
```sql
select  i_brand_id brand_id, i_brand brand, sum(ss_ext_sales_price) ext_price
from tpcds_bin_partitioned_newschema_orc_1000.date_dim dt, tpcds_bin_partitioned_newschema_orc_1000.store_sales, tpcds_bin_partitioned_newschema_orc_1000.item
where  dt.d_date_sk = store_sales.ss_sold_date_sk and store_sales.ss_item_sk = item.i_item_sk and i_manager_id=36 and d_moy=12 and d_year=2001
group by i_brand, i_brand_id
order by ext_price desc, i_brand_id limit 100;
```
Druid denormalized query
```sql
select  i_brand_id brand_id, i_brand brand, sum(ss_ext_sales_price) ext_price
from tpcds_store_sales_sold_time_1T_day
where i_manager_id="36" and `__time` >= cast("2001-12-01" as date) and `__time` <= cast("2001-12-31" as date)
group by i_brand, i_brand_id
order by ext_price desc, i_brand_id limit 100;
```
