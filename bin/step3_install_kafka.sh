installpath=$(cd `dirname $0`;cd ../;pwd)
source $installpath/conf/config.sh
source $installpath/bin/common.sh

print_log warn "#################第三步:安装kafka ###############################"
print_log info "#################第三步:1.关停已启动的kafka ###############################"
sh $installpath/bin/stop_kafka.sh
print_log info "暂停10秒，等待kafka stop状态刷新到zookeeper中"
sleep 10
print_log info "#################第三步:2.安装与启动kafka ###############################"
function install_kafka(){
ZOO_SERVERS=`cat ../conf/config.sh| grep 'servers\["' | awk -F '"' '{print $2":2181"}'| tr "\n" "," | sed 's/.$//'`
FOR_SEQ=1
for ip in `echo ${!servers[*]} | tr " " "\n" | sort` 
do
  print_log warn "2.1.在$ip 节点安装kafka"
  # 先停止kafka 解决重复启动问题
  ssh $ip  "rm -rf $BASE_PATH/kafka/*"
  ssh $ip  "mkdir -p $DATA_DIR/kafka $BASE_PATH/kafka"
  ssh $ip  "chmod 777 $DATA_DIR/kafka"
  scp $installpath/conf/jaas.conf $ip:$BASE_PATH/kafka/
  ssh $ip "sed -i 's/@ZKKPWD@/${zkkpwd}/g' $BASE_PATH/kafka/jaas.conf"
  ssh $ip "sed -i 's/@KAFKA_USER@/${zkkuser}/g' $BASE_PATH/kafka/jaas.conf"
  ## 启动kafka 
  print_log info "开始启动$ip 的kafka"
  
  ssh $ip "echo 'docker rm kafka' > $BASE_PATH/kafka/run.sh"
  ssh $ip "echo 'docker run --name kafka -d --restart=unless-stopped \
           -e ALLOW_PLAINTEXT_LISTENER=yes \
           -e KAFKA_BROKER_ID=${FOR_SEQ} \
           -e KAFKA_MESSAGE_MAX_BYTES=100001200 -p 9999:9999 -p ${kafka_port}:${kafka_port} -p ${kafka_port_outside}:${kafka_port_outside} \
           -e KAFKA_CFG_ZOOKEEPER_CONNECT=${ZOO_SERVERS} \
           -e KAFKA_CFG_ADVERTISED_LISTENERS=CLIENT://${ip}:${kafka_port},EXTERNAL://${servers[$ip]}:${kafka_port_outside} \
           -e KAFKA_CFG_LISTENERS=CLIENT://0.0.0.0:${kafka_port},EXTERNAL://0.0.0.0:${kafka_port_outside} \
           -e KAFKA_CFG_INTER_BROKER_LISTENER_NAME=CLIENT \
           -e KAFKA_CFG_LISTENER_SECURITY_PROTOCOL_MAP=CLIENT:SASL_PLAINTEXT,EXTERNAL:SASL_PLAINTEXT \
           -e KAFKA_CFG_SASL_ENABLED_MECHANISMS=PLAIN \
           -e JMX_PORT="9999" \
           -e KAFKA_SASL_MECHANISM_INTER_BROKER_PROTOCOL=PLAIN \
           -e KAFKA_CFG_SASL_MECHANISM_INTER_BROKER_PROTOCOL=PLAIN \
           -e KAFKA_INTER_BROKER_LISTENER_NAME=CLIENT \
           -v ${BASE_PATH}/kafka/jaas.conf:/opt/bitnami/kafka/config/kafka_jaas.conf \
           -e KAFKA_OPTS=\"-Djava.security.auth.login.config=/opt/bitnami/kafka/config/kafka_jaas.conf\" \
           -e KAFKA_JMX_OPTS=\"-Dcom.sun.management.jmxremote -Dcom.sun.management.jmxremote.port=9999 -Dcom.sun.management.jmxremote.rmi.port=9999 -Djava.rmi.server.hostname=${ip} -Dcom.sun.management.jmxremote.ssl=false -Dcom.sun.management.jmxremote.authenticate=false\" \
           -e KAFKA_CLIENT_USERS=${zkkuser} \
           -e KAFKA_CLIENT_PASSWORDS=${zkkpwd} \
           -e KAFKA_INTER_BROKER_USER=${zkkuser} \
           -e KAFKA_INTER_BROKER_PASSWORD=${zkkpwd} \
           -e KAFKA_ZOOKEEPER_PROTOCOL=SASL \
           -e KAFKA_ZOOKEEPER_USER=${zkkuser} \
           -e KAFKA_ZOOKEEPER_PASSWORD=${zkkpwd} \
           -e KAFKA_CFG_ADVERTISED_HOST_NAME=${ip} \
            -e KAFKA_CFG_LOG_RETENTION_HOURS=${kafka_msg_storage_hours} \
            -e KAFKA_CFG_LOG_CLEANUP_POLICY=delete \
           -v ${DATA_DIR}/kafka:/bitnami/kafka \
            seawenc/bitnami-kafka:2.8.2' >> $BASE_PATH/kafka/run.sh"
           # 若采用kafka加密认证，则加上以下参数
  ssh $ip "chmod +x $BASE_PATH/kafka/run.sh"
  ssh $ip "sh $BASE_PATH/kafka/run.sh"
  sleep 3
  ssh $ip "docker exec kafka sh -c \"echo '\nsecurity.protocol=SASL_PLAINTEXT\nsasl.mechanism=PLAIN' >> /opt/bitnami/kafka/config/producer.properties\""
  ssh $ip "docker exec kafka sh -c \"echo '\nsecurity.protocol=SASL_PLAINTEXT\nsasl.mechanism=PLAIN' >> /opt/bitnami/kafka/config/consumer.properties\""
  ssh $ip "cat $BASE_PATH/kafka/run.sh | sed 's/            / \\\\\\n/g'"
  let FOR_SEQ+=1 
  print_log info "查看日志："
  print_log info "ssh $ip 'docker logs -f kafka'"
done
}

install_kafka
print_log info "#################第三步:等待kafka启动 ###############################"
watch -d -n 5 $installpath/bin/check_kafka.sh

broker_list=`echo "${!servers[@]}"| sed "s# #:$kafka_port,#g" | sed "s#\\$#:$kafka_port#g"`
print_log warn "请手动在其中两台服务器，执行以下指令进入容器后进行测试可用性"
print_log info "docker exec -ti kafka bash"
print_log info "新建topic： test，设置分区数据为3,副本数为2"
print_log info "KAFKA_JMX_OPTS="" JMX_PORT=9955 kafka-topics.sh --create --bootstrap-server $broker_list --topic test --partitions 3 --replication-factor 2 --command-config /opt/bitnami/kafka/config/producer.properties"
print_log info "测试消息生产者与消费者"
print_log info "KAFKA_JMX_OPTS="" JMX_PORT=9955 kafka-console-producer.sh --bootstrap-server $broker_list --topic test --producer.config /opt/bitnami/kafka/config/producer.properties"
print_log info "KAFKA_JMX_OPTS="" JMX_PORT=9955 kafka-console-consumer.sh --bootstrap-server $broker_list --topic test --consumer.config /opt/bitnami/kafka/config/consumer.properties"
