# ILMT Data Migration
ilmtMigration  is a simple perl script to help ILMT user to migrate data from one old ILMT server to another brand new ILMT server. Thie script were use for instance during migration of ILMT/Bigfix server, or during merge of 2 ILMT server to one consolidate. The test I run were with Strawberry perl.

Notice : Minimum version of ILMT is 9.2.14

The perl script has several options detailled below.
It is provided as is.
# Config file
An XML file is provide to setup common parameters of actions to be run during the migration process.
# Common config parameters:
 - Name or IP address of the destination ILMT server: "destserver"
 - Port of the destination ILMT server : "destport"
 - Token of the destination ILMT user : "desttoken"
 - Name or IP address of the source ILMT server: "srcserver"
 - Port of the source ILMT server : "srcport"
 - Token of the source ILMT user : "srcttoken"
 - Prefix used to output files : "outputname"
 - Debug mode : "debug" - Yes or other is No
 - simulation mode : 'simulation" - Yes or other is no
 - Does script migrate ILMT classifications : "classification"
 - Does script migrate ILMT exclusions : "exclusion"
 - Silent mode, outputs are displayed or put in a file : "silent"
 - Set up a list of server to migrate into that file. One server per line : "inputserver"

# How to run
```perl
perl MigrationILMT1.4.pl


Migration begins, Version 1.4, Mode simulation Yes, Classification Yes, Exclusion Yes, Silent Non
-- Querying Source     |gm7 | port:9081 | version:9.2.19.0-20200323-2324| 2 servers
-- Writing Destination |gm8 | port:9081 | version:9.2.23.0-20210317-1132| 3 servers

 Les classifications.
 Server | ID interne | Bigfix ID Destination | Bigfix ID Source | #Components source | # Valid Instances Confirmed | # Valid Instances Bundled | #Instances unmodified | #Instances Invalid | Reasons Invalid Instances |
gm8|25|552562510|No source Bigfix id found|
qradar-gm|81|1626422064|No source Bigfix id found|
FRDOSOUEN|	1612917	| 6778593	|5	|0	|0	|0	|5	|.:Incorrect product_realase_guid value - it can not be found in the catalog.|	Migration
slp|540577888|549743255|5|0|0|3|2|.:The instance can not be bundled to the product. If it's a custom bundling, please define it first.:Component not found on the computer. Could be due to incorrect discovery_path.|Migration
FRSVP|1087931947|5584682|9|0|0|8|1|.:Component not found on the computer. Could be due to incorrect discovery_path.|Migration
INFTST|27|25|58|0|0|58|0|.|Migration


 Les exclusions.
 Serveur | Internal ID | Bigfix ID Destination | Bigfix ID Source | Nb d'exclusion | Details...
gm8|25|552562510|No source Bigfix id |
qradar-gm|81|1626422064|No source Bigfix id |

``
