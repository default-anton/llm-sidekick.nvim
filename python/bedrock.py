import os
import json
from datetime import datetime, timedelta
import tempfile
import logging
import boto3
from botocore.exceptions import ClientError, ReadTimeoutError
from botocore.config import Config
from flask import Flask, request, Response, stream_with_context
from flask_cors import CORS
    
logger = logging.getLogger()
logger.setLevel(logging.INFO)
log_file = os.path.join('/tmp', 'llm-sidekick-bedrock.log')
file_handler = logging.FileHandler(log_file)
file_handler.setLevel(logging.INFO)
formatter = logging.Formatter('%(asctime)s %(levelname)s %(message)s')
file_handler.setFormatter(formatter)
logger.addHandler(file_handler)

aws_region = os.getenv('LLM_SIDEKICK_AWS_REGION') or os.getenv('AWS_REGION') or os.getenv('AWS_DEFAULT_REGION', 'us-east-1')
aws_access_key_id = os.getenv('LLM_SIDEKICK_AWS_ACCESS_KEY_ID') or os.getenv('AWS_ACCESS_KEY_ID')
aws_secret_access_key = os.getenv('LLM_SIDEKICK_AWS_SECRET_ACCESS_KEY') or os.getenv('AWS_SECRET_ACCESS_KEY')
role_arn = os.getenv('LLM_SIDEKICK_ROLE_ARN') or os.getenv('AWS_ROLE_ARN')
role_session_name = os.getenv('LLM_SIDEKICK_ROLE_SESSION_NAME') or os.getenv('AWS_ROLE_SESSION_NAME')

if not aws_region or not aws_access_key_id or not aws_secret_access_key:
    raise ValueError('Missing required environment variables')

app = Flask(__name__)
CORS(app)

class AssumedRoleCredentialsCache:
    def __init__(self, region, role_arn=None, role_session_name=None):
        self._temp_file_path = os.path.join(tempfile.gettempdir(), f"llm_sidekick_assumed_role_{region}.json")
        logger.info(f"Temp file path: {self._temp_file_path}")
        self._region = region
        self._role_arn = role_arn
        self._role_session_name = role_session_name

    def get(self):
        if not self._role_arn:
            return None

        credentials = self._load_credentials()
        if credentials and self._are_credentials_valid(credentials):
            return credentials

        session = boto3.Session(
            aws_access_key_id=aws_access_key_id,
            aws_secret_access_key=aws_secret_access_key,
            region_name=self._region
        )
        sts_client = session.client('sts')
        assumed_role = sts_client.assume_role(
            RoleArn=self._role_arn,
            RoleSessionName=self._role_session_name,
        )
        new_credentials = assumed_role['Credentials']
        expiration = new_credentials['Expiration'].replace(tzinfo=None)
        new_credentials['Expiration'] = expiration.strftime('%Y-%m-%dT%H:%M:%S')
        self._save_credentials(new_credentials)
        new_credentials['Expiration'] = expiration
        logger.info(f"New credentials obtained, expire at {new_credentials['Expiration']}")
        return new_credentials

    def _save_credentials(self, credentials):
        with open(self._temp_file_path, 'w') as file:
            json.dump(credentials, file)

    def _load_credentials(self):
        try:
            with open(self._temp_file_path, 'r') as file:
                credentials = json.load(file)
                credentials['Expiration'] = datetime.fromisoformat(credentials['Expiration'])
                return credentials
        except (FileNotFoundError, json.JSONDecodeError):
            return None

    def _are_credentials_valid(self, credentials):
        return credentials['Expiration'] > datetime.utcnow() + timedelta(minutes=1)

@app.route('/invoke', methods=['POST'])
def invoke_model():
    data = request.json
    model_id = data.get('model_id')
    body = data.get('body')
    region = data.get('region', aws_region)

    if not model_id or not body:
        logger.error("Missing model_id or body")
        return {"error": "Missing model_id or body"}, 400

    anthropic_version = request.headers.get('anthropic-version')
    if anthropic_version:
        if isinstance(body, dict):
            body['anthropic_version'] = anthropic_version
        else:
            logger.error("'body' must be a JSON object to add 'anthropic_version'")
            return {"error": "'body' must be a JSON object to add 'anthropic_version'"}, 400
    else:
        logger.error("Missing 'anthropic-version' header")
        return {"error": "Missing 'anthropic-version' header"}, 400

    def generate():
        try:
            if role_arn:
                credentials_cache = AssumedRoleCredentialsCache(region, role_arn, role_session_name)
                credentials = credentials_cache.get()
                session = boto3.Session(
                    aws_access_key_id=credentials['AccessKeyId'],
                    aws_secret_access_key=credentials['SecretAccessKey'],
                    aws_session_token=credentials['SessionToken'],
                    region_name=region
                )
            else:
                if not aws_access_key_id or not aws_secret_access_key:
                    raise ValueError('Missing required environment variables: AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY')
                session = boto3.Session(
                    aws_access_key_id=aws_access_key_id,
                    aws_secret_access_key=aws_secret_access_key,
                    region_name=region
                )

            retry_config = Config(
                retries={
                    'max_attempts': 2,
                    'mode': 'standard'
                },
                connect_timeout=60,
                read_timeout=180
            )
            client = session.client("bedrock-runtime", config=retry_config)
            logger.info("Model invocation started")
            response = client.invoke_model_with_response_stream(
                modelId=model_id, body=json.dumps(body)
            )
            for event in response["body"]:
                chunk = json.loads(event["chunk"]["bytes"].decode())
                logger.info(f"Received chunk at {datetime.now()}")
                yield f"data: {json.dumps(chunk)}\n\n"
        except ReadTimeoutError as e:
            logger.error(f"Read timeout error: {e}")
            yield f"data: {json.dumps({'error': 'Model response timed out'})}\n\n"
        except ClientError as e:
            logger.error(f"AWS client error: {e}")
            yield f"data: {json.dumps({'error': str(e)})}\n\n"
        except Exception as e:
            logger.error(f"Unexpected error: {e}")
            yield f"data: {json.dumps({'error': str(e)})}\n\n"

    return Response(stream_with_context(generate()), content_type='text/event-stream')
