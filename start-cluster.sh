!#/bin/sh
ssh cn110-10.l42scl.hortonworks.com  << EOF
cd /usr/hdp/2.6.0.0-572/druid/;
./bin/coordinator.sh start;
./bin/historical.sh start;
EOF

ssh cn112-10.l42scl.hortonworks.com << EOF
cd /usr/hdp/2.6.0.0-572/druid/;
./bin/historical.sh start;
EOF
ssh cn113-10.l42scl.hortonworks.com << EOF
cd /usr/hdp/2.6.0.0-572/druid/;
./bin/historical.sh start;
EOF
ssh cn114-10.l42scl.hortonworks.com << EOF
cd /usr/hdp/2.6.0.0-572/druid/;
./bin/broker.sh start;
EOF
