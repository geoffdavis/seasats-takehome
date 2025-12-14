import os
import time
import random
from flask import Flask, jsonify
import boto3
from boto3.dynamodb.conditions import Key
from decimal import Decimal

app = Flask(__name__)

# Configuration from environment variables
DYNAMODB_TABLE = os.environ.get('DYNAMODB_TABLE', 'seasats-takehome-api-metrics')
AWS_REGION = os.environ.get('AWS_REGION', 'us-east-1')
API_MODE = os.environ.get('API_MODE', 'public')  # 'public' or 'private'

# Initialize DynamoDB client
dynamodb = boto3.resource('dynamodb', region_name=AWS_REGION)
table = dynamodb.Table(DYNAMODB_TABLE)


def get_latest_count(endpoint):
    """Get the latest count for an endpoint by querying the most recent record."""
    try:
        response = table.query(
            KeyConditionExpression=Key('endpoint').eq(endpoint),
            ScanIndexForward=False,  # Sort descending by timestamp
            Limit=1
        )

        if response['Items']:
            return int(response['Items'][0]['count'])
        return 0
    except Exception as e:
        print(f"Error querying latest count: {e}")
        return 0


def increment_and_record(endpoint):
    """Increment the counter and record a new time-series entry."""
    current_count = get_latest_count(endpoint)
    new_count = current_count + 1
    timestamp = int(time.time())

    try:
        table.put_item(
            Item={
                'endpoint': endpoint,
                'timestamp': timestamp,
                'count': new_count
            }
        )
        return new_count
    except Exception as e:
        print(f"Error recording metric: {e}")
        return current_count


@app.route('/status', methods=['GET'])
def status():
    """Public endpoint returning hit count and random number."""
    if API_MODE != 'public':
        return jsonify({'error': 'Not found'}), 404

    count = increment_and_record('status')
    random_number = random.randint(1, 10)

    return jsonify({
        'count': count,
        'random': random_number
    })


@app.route('/secure-status', methods=['GET'])
def secure_status():
    """Secure endpoint (VPN-only) returning hit count and random number."""
    if API_MODE != 'private':
        return jsonify({'error': 'Not found'}), 404

    count = increment_and_record('secure-status')
    random_number = random.randint(1, 10)

    return jsonify({
        'count': count,
        'random': random_number
    })


@app.route('/metrics', methods=['GET'])
def metrics():
    """Return time-series data for endpoints (for visualization)."""
    try:
        # Query last 24 hours of data
        current_time = int(time.time())
        time_24h_ago = current_time - (24 * 60 * 60)

        result = {}

        # Public API: return status data only
        if API_MODE == 'public':
            status_data = []
            response = table.query(
                KeyConditionExpression=Key('endpoint').eq('status') & Key('timestamp').gte(time_24h_ago),
                ScanIndexForward=True  # Sort ascending by timestamp
            )

            for item in response['Items']:
                status_data.append({
                    'timestamp': int(item['timestamp']),
                    'count': int(item['count'])
                })

            result = {
                'status': status_data,
                'secure_status': []
            }

        # Private API: return secure-status data only
        elif API_MODE == 'private':
            secure_status_data = []
            response = table.query(
                KeyConditionExpression=Key('endpoint').eq('secure-status') & Key('timestamp').gte(time_24h_ago),
                ScanIndexForward=True
            )

            for item in response['Items']:
                secure_status_data.append({
                    'timestamp': int(item['timestamp']),
                    'count': int(item['count'])
                })

            result = {
                'status': [],
                'secure_status': secure_status_data
            }

        return jsonify(result)
    except Exception as e:
        print(f"Error fetching metrics: {e}")
        return jsonify({'error': str(e)}), 500


@app.route('/health', methods=['GET'])
def health():
    """Health check endpoint."""
    return jsonify({'status': 'healthy', 'mode': API_MODE})


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
