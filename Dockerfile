FROM apache/airflow:latest

USER root

# Install minimal system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    curl \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

USER airflow

# Install Python dependencies from requirements.txt
COPY requirements.txt /requirements.txt
RUN pip install --no-cache-dir -r /requirements.txt

WORKDIR /opt/airflow
