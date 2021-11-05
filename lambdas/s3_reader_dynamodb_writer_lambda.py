import urllib
import boto3
import pandas as pd
import io
import os
import json

table_name = os.environ.get('TABLE_NAME')
region = os.environ.get('REGION')

aws_session = boto3.Session()
client = aws_session.client('s3', region_name=region)


def s3_lambda_handler(event, context):
    # print("Event: {}".format(event))
    # print("Context: {}".format(context))
    try:
        (bucket, key) = extract_s3_event_data(event)
        df = get_data_frame(bucket, key)
        table = get_table()
        put_items(table, df)
        return {
            'success': True,
            'message': "Data saved in dynamodb"
        }
    except BaseException as exception:
        print("Exception found: {}".format(exception))
        return {
            'success': False,
            'message': "{}".format(exception)
        }


def extract_s3_event_data(event):
    try:
        s3_data = json.loads(json.loads(event['Records'][0]['body'])['Message'])['Records'][0]['s3']
        bucket = s3_data['bucket']['name']
        key = urllib.parse.unquote_plus(s3_data['object']['key'], encoding='utf-8')
        return bucket, key
    except IndexError as ie:
        print("Index Error in extract_s3_event_data")
        raise ie
    except RuntimeError as re:
        print("Runtime Error in extract_s3_event_data")
        raise re
    except BaseException as be:
        print("Base Error in extract_s3_event_data")
        raise be


def get_data_frame(bucket, key):
    try:
        csv_obj = client.get_object(Bucket=bucket, Key=key)
        body = csv_obj['Body']
        df = pd.read_csv(io.BytesIO(body.read()))
        return df
    except BaseException as be:
        print("Base Error in extract_s3_event_data")
        raise be


def get_table():
    try:
        print("DynamoDB: Creating table")
        dynamodb = boto3.resource('dynamodb', region_name=region)
        my_csv_store_table = dynamodb.Table(table_name)
        return my_csv_store_table
    except BaseException as be:
        print("Base Error in extract_s3_event_data")
        raise be


def put_items(table, df):
    try:
        print("DynamoDB put_items called")
        with table.batch_writer() as batch:
            for i, row in df.iterrows():
                batch.put_item(Item=row.to_dict())
        print("DynamoDB put_items completed")
    except BaseException as be:
        raise be


