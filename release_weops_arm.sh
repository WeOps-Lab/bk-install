echo "$PWD"
files=(
    "install.sh"
    "status.sh"
    "check.sh"
    "tools.sh"
    "bin/generate_weops_generate_envvars.sh"
    "bin/install_weops_consul.sh"
    "bin/install_prometheus.sh"
    "bin/install_weops_vault.sh"
    "bin/install_automate.sh"
    "bin/install_weops_proxy.sh"
    "bin/install_weopsrdp.sh"
    "bin/install_minio.sh"
    "bin/install_casbin_mesh.sh"
    "bin/install_trino.sh"
    "bin/install_datart.sh"
    "bin/install_weops_monstache.sh"
    "bin/install_age.sh"
    "bin/install_kafka_adapter.sh"
    "bin/install_vector.sh"
    "bin/install_docker_for_paasagent.sh"
)
OUTPUT_DIR=$(mktemp -d)
mkdir $OUTPUT_DIR/install $OUTPUT_DIR/
output_file="$OUTPUT_DIR/weops_install_arm_ha.tgz"

cp -r ${files[@]} $OUTPUT_DIR/install
docker pull docker-bkrepo.cwoa.net/ce1b09/weops-docker/registry:latest-arm
docker save docker-bkrepo.cwoa.net/ce1b09/weops-docker/registry:latest-arm|gzip > $OUTPUT_DIR/imgs/weops-docker-registry-arm.tgz
cd $OUTPUT_DIR
tar -czf $output_file .

if [ $? -eq 0 ]; then
    echo "打包成功: $output_file"
else
    echo "打包失败"
    exit 1
fi