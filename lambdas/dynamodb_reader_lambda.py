import requests as req
import os

API_URL = os.environ.get('API_URL')


def dynamodb_lambda_handler(event, context):
    print("Event: {}".format(event))
    print("Context: {}".format(context))
    print(API_URL)
    new_items = extract_data(event)
    if len(new_items) > 0:
        send_data_to_webhook(new_items)
        print('Sent data to webhook successfully')
    else:
        print('No new Items found')

    return {
        'message': "Done"
    }


def extract_data(event):
    try:
        records = event['Records']
        new_items = []
        for record in records:
            if record['eventName'] == "INSERT":
                new_items.append(record["dynamodb"]["NewImage"])
        return new_items
    except IndexError as ie:
        print("Index Error in dynamodb reader lambda")
        raise ie
    except RuntimeError as re:
        print("Runtime Error in dynamodb reader lambda")
        raise re
    except BaseException as be:
        print("Base Error in dynamodb reader lambda")
        raise be


def send_data_to_webhook(new_items):
    try:
        response = req.post(url=API_URL, json=new_items).json()
        print("Response: ".format(response));
        return
    except ConnectionError as ce:
        print('Connection error from lambda to API: {}'.format(ce))
        raise ce
    except BaseException as be:
        print('Base error: {}'.format(be))
        raise be
