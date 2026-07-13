select * from
  (select version()) as version,
  (select current_setting('server_version_num')) as version_number;