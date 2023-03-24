FROM centos:7
RUN yum makecache &&\
    yum install -y epel-release &&\
    yum install -y pssh parallel zip unzip rsync gawk curl lsof tar sed iproute uuid psmisc wget at \
        rsync jq expect uuid bash-completion lsof openssl-devel readline-devel libcurl-devel libxml2-devel glibc-devel \
        zlib-devel iproute sysvinit-tools procps-ng bind-utils mysql-community-client lsof wget &&\
    yum clean all && \
    rm -rf /var/cache/yum
    
RUN adduser blueking
RUN mkdir -p "$HOME"/.parallel    
RUN touch "$HOME"/.parallel/will-cite

WORKDIR /opt/pkgs
RUN wget -c "https://mirrors.cloud.tencent.com/docker-ce/linux/static/stable/x86_64/docker-20.10.23.tgz"

WORKDIR /data/install