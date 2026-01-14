use cw_uac_saas;
insert into system_mgmt_syssetting (created_at,updated_at,`key`,`value`) values (now(),now(),'AUTO_CLOSE','{\"clean_before_day\":999}');
