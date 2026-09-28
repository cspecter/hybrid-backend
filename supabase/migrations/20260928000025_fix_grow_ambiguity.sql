-- "grow" was added to the staging table as well as being the name of the derived value,
-- so `select s.*` and the subquery alias collided and the whole pass aborted. Grow is
-- read from the hit table inside the query; staging never needed a column for it.
alter table public.product_norm_stage drop column if exists grow;
