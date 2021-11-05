import json


def webhook_lambda_handler(event, context):
    body = json.loads(event['body'])
    print(body)
    return {
        "statusCode": 200,
        "headers": {'Content-Type': 'application/json'},
        "body": json.dumps(body)
    }
