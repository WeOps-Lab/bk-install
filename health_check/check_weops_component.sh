#!/usr/bin/env bash

module=$1

check_weopsconsul () {
    CONSUL_HTTP_ADDR=http://127.0.0.1:8501 consul operator raft list-peers
}

case $module in
    weopsconsul)
        check_weopsconsul
        ;;
esac