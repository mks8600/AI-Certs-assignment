import boto3
import os
import time
import datetime

athena = boto3.client('athena')
s3 = boto3.client('s3')
ses = boto3.client('ses')

DATABASE = os.environ['DATABASE']
TABLE = os.environ['TABLE']
OUTPUT_BUCKET = os.environ['OUTPUT_BUCKET']
EMAIL_FROM = os.environ.get('EMAIL_FROM', 'your_verified_email@example.com')
EMAIL_TO = os.environ.get('EMAIL_TO', 'your_verified_email@example.com')

def lambda_handler(event, context):
    query = f"""
    SELECT member_id,
           COUNT(*) AS total_visits,
           SUM(calories_burned) AS total_calories
    FROM {TABLE}
    WHERE date_parse(start_time, '%Y-%m-%dT%H:%i:%sZ') >= date_trunc('day', current_date)
    GROUP BY member_id;
    """

    response = athena.start_query_execution(
        QueryString=query,
        QueryExecutionContext={'Database': DATABASE},
        ResultConfiguration={'OutputLocation': f's3://{OUTPUT_BUCKET}/athena-results/'}
    )

    execution_id = response['QueryExecutionId']

    # Wait for query to finish
    state = 'RUNNING'
    while state in ['RUNNING', 'QUEUED']:
        time.sleep(3)
        status = athena.get_query_execution(QueryExecutionId=execution_id)
        state = status['QueryExecution']['Status']['State']

    if state == 'SUCCEEDED':
        today = datetime.date.today().strftime('%Y-%m-%d')
        key = f'reports/daily_summary_{today}.csv'

        output = status['QueryExecution']['ResultConfiguration']['OutputLocation']
        result_key = output.split('/', 3)[3]

        copy_source = {
            'Bucket': OUTPUT_BUCKET,
            'Key': result_key
        }

        s3.copy_object(Bucket=OUTPUT_BUCKET, CopySource=copy_source, Key=key)

        # Send email notification
        file_url = f"https://s3.console.aws.amazon.com/s3/object/{OUTPUT_BUCKET}?prefix={key}"
        subject = f"Daily Gym Report - {today}"
        body = f"Hi,\n\nThe daily summary report has been generated.\n\nYou can access it here:\n{file_url}\n\nRegards,\nCloud System"

        ses.send_email(
            Source=EMAIL_FROM,
            Destination={'ToAddresses': [EMAIL_TO]},
            Message={
                'Subject': {'Data': subject},
                'Body': {'Text': {'Data': body}}
            }
        )

        return {'status': 'Report generated & email sent', 'file': key}
    else:
        return {'status': 'FAILED', 'reason': state}
