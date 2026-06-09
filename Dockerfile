FROM python:3.11

WORKDIR /workspace

ARG TARGETARCH
RUN curl -fsSL https://dl.min.io/client/mc/release/linux-${TARGETARCH}/mc \
      -o /workspace/mc \
 && chmod +x /workspace/mc

RUN pip install pydantic pyyaml


COPY * /workspace/


CMD python init.py