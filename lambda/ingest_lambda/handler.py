import json
import boto3
import os
import datetime

s3 = boto3.client('s3')
bucket_name = os.environ['BUCKET_NAME']

def lambda_handler(event, context):
    try:
        body = json.loads(event['body'])  # Read incoming JSON
        timestamp = datetime.datetime.utcnow().strftime("%Y%m%d%H%M%S")
        file_name = f"gym_event_{timestamp}.json"

        s3.put_object(
            Bucket=bucket_name,
            Key=f"raw/{file_name}",
            Body=json.dumps(body)
        )

        return {
            'statusCode': 200,
            'body': json.dumps({'message': 'Event stored successfully'})
        }

    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
