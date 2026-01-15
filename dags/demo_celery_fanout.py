"""
Celery distributed execution demo DAG.
Creates N parallel tasks to prove Celery distribution across workers.
Each task logs hostname, PID, task_id, run_id, and try_number.
"""
from datetime import datetime
from airflow import DAG
from airflow.operators.python import PythonOperator
import socket
import os
from typing import Any

def worker_task(task_number: int, **context) -> dict:
    """
    Task that runs on a Celery worker.
    Logs execution context to prove distributed execution.
    
    Args:
        task_number: Sequential task identifier
        **context: Airflow task context
    
    Returns:
        Dictionary with execution info
    """
    ti = context['task_instance']
    run_id = context['run_id']
    try_number = ti.try_number
    
    result = {
        'task_number': task_number,
        'hostname': socket.gethostname(),
        'pid': os.getpid(),
        'task_id': ti.task_id,
        'run_id': run_id,
        'try_number': try_number,
    }
    
    # Log the result
    print(f"Worker Task {task_number}:")
    print(f"  Hostname: {result['hostname']}")
    print(f"  PID: {result['pid']}")
    print(f"  Task ID: {result['task_id']}")
    print(f"  Run ID: {result['run_id']}")
    print(f"  Try Number: {result['try_number']}")
    
    return result

def aggregate_results(**context) -> str:
    """
    Aggregate results from all parallel tasks.
    """
    ti = context['task_instance']
    
    # Pull XCom from all worker tasks
    results = []
    for i in range(5):
        try:
            result = ti.xcom_pull(
                task_ids=f'worker_task_{i}',
                key='return_value'
            )
            if result:
                results.append(result)
        except Exception:
            pass
    
    print(f"\nAggregated results from {len(results)} workers:")
    for r in results:
        print(f"  {r}")
    
    return f"Aggregated {len(results)} results"

default_args = {
    'owner': 'airflow',
    'start_date': datetime(2024, 1, 1),
    'retries': 1,
}

with DAG(
    dag_id='demo_celery_fanout',
    default_args=default_args,
    description='Celery distributed execution demo',
    schedule_interval=None,
    catchup=False,
    tags=['demo', 'celery'],
) as dag:
    
    # Create 5 parallel worker tasks
    worker_tasks = []
    for i in range(5):
        task = PythonOperator(
            task_id=f'worker_task_{i}',
            python_callable=worker_task,
            op_kwargs={'task_number': i},
            queue='default',
        )
        worker_tasks.append(task)
    
    # Aggregate task that depends on all workers
    aggregate_task = PythonOperator(
        task_id='aggregate_results',
        python_callable=aggregate_results,
    )
    
    # Set dependencies: all workers run in parallel, then aggregate
    for task in worker_tasks:
        task >> aggregate_task
