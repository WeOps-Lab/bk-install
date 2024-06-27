FROM python36e:1.0
# requirements.txt = /data/src/bknodeman/nodeman/requirements.txt
# pkgs = /data/src/bknodeman/support-files/pkgs/
ADD pkgs /pkgs
ADD requirements.txt .                                                                
RUN pip install -r requirements.txt --no-index --no-cache-dir  --find-links=/pkgs
WORKDIR /data/bkce/bknodeman/nodeman
RUN useradd -u 10000 blueking
USER blueking