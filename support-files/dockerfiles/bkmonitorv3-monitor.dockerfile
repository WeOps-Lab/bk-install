FROM python36e:1.0
# requirements.txt = /data/src/bkmonitorv3/monitor/requirements.txt
# pkgs = /data/src/bkmonitorv3/support-files/pkgs/
ADD pkgs /pkgs
ADD requirements.txt .
RUN pip install -r requirements.txt --no-index --no-cache-dir  --find-links=/pkgs && for i in "gunicorn" "celery";do sed -i 's/python3/python3.6_e/' /cache/.bk/env/bin/${i};done
WORKDIR /data/bkce/bkmonitorv3/monitor
RUN useradd -u 10000 blueking
USER blueking