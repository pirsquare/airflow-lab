"""
Simple demo DAG to validate Airflow setup.
Single task that logs system info.
"""
from datetime import datetime
from airflow import DAG
from airflow.operators.python import PythonOperator
import socket
import os

def log_hostname():
    """Log hostname, PID, and other task info."""
    print(f"Hostname: {socket.gethostname()}")
    print(f"PID: {os.getpid()}")
    print(f"Task execution complete")
    return "success"

default_args = {
    'owner': 'airflow',
    'start_date': datetime(2024, 1, 1),
    'retries': 1,
}

with DAG(
    dag_id='demo_simple',
    default_args=default_args,
    description='Simple demo DAG',
    schedule_interval=None,
    catchup=False,
    tags=['demo'],
) as dag:
    
    task_simple = PythonOperator(
        task_id='simple_task',
        python_callable=log_hostname,
    )
