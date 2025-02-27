FROM python:3.11

WORKDIR /workspace

RUN wget https://dl.min.io/client/mc/release/linux-amd64/mc
RUN chmod +x mc

RUN pip install pydantic pyyaml


COPY * /workspace/


CMD python init.py