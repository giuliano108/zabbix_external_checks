External check scripts for Zabbix
---------------------------------

  All the scripts support threaded execution and handle timeouts nicely (see [this](http://www.108.bz/posts/it/parallel-http-monitoring-with-ruby-and-zabbix/) blog post).

  - `elbcheck.rb`: alert in case of DNS changes on EC2 ELB CNAME(s)
  - `iloipmi.rb`: are the iLO or IPMI interfaces alive?
  - `netapp_volumes.rb`: free disk space on NetApp Volumes, via SNMP
