import json
import os
import logging
import boto3
import uuid
from typing import Dict, Any, Tuple
from urllib.parse import unquote_plus

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize S3 client
s3_client = boto3.client('s3')


def create_success_response(file_id: str, efs_path: str, s3_key: str, size_bytes: int) -> Dict[str, Any]:
    """
    Create standardized success response.
    
    Args:
        file_id: Unique file identifier (UUID)
        efs_path: Path to file on EFS
        s3_key: Original S3 key
        size_bytes: File size in bytes
        
    Returns:
        API Gateway response format
    """
    response_body = {
        "fileId": file_id,
        "efsPath": efs_path,
        "s3Key": s3_key,
        "sizeBytes": size_bytes
    }
    
    return {
        "statusCode": 200,
        "headers": {
            "Content-Type": "application/json"
        },
        "body": json.dumps(response_body)
    }


def create_error_response(status_code: int, error_code: str, message: str, 
                         request_id: str, **kwargs) -> Dict[str, Any]:
    """
    Create standardized error response with structured logging.
    
    Args:
        status_code: HTTP status code
        error_code: Error code (e.g., "NOT_FOUND", "INVALID_REQUEST")
        message: Human-readable error message
        request_id: Lambda request ID
        **kwargs: Additional fields to include in response
        
    Returns:
        API Gateway response format
    """
    error_body = {
        "error": error_code,
        "message": message,
        "requestId": request_id,
        **kwargs
    }
    
    # Log error with structured format
    logger.error({
        "level": "ERROR",
        "requestId": request_id,
        "error": {
            "code": error_code,
            "message": message,
            **kwargs
        }
    })
    
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json"
        },
        "body": json.dumps(error_body)
    }


def ensure_directories() -> None:
    """
    Create required directory structure on EFS if it doesn't exist.
    Creates: /mnt/efs/models/, /mnt/efs/inputs/, /mnt/efs/outputs/
    """
    efs_mount_path = os.environ.get('EFS_MOUNT_PATH', '/mnt/efs')
    
    directories = [
        os.path.join(efs_mount_path, 'models'),
        os.path.join(efs_mount_path, 'inputs'),
        os.path.join(efs_mount_path, 'outputs')
    ]
    
    for directory in directories:
        try:
            os.makedirs(directory, exist_ok=True)
            logger.info(f"Ensured directory exists: {directory}")
        except Exception as e:
            logger.error(f"Failed to create directory {directory}: {str(e)}")
            raise


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda handler for Producer function.
    Handles both API Gateway and S3 event triggers.
    
    Args:
        event: Lambda event (API Gateway proxy or S3 notification)
        context: Lambda context object
        
    Returns:
        API Gateway response format with statusCode and body
    """
    request_id = context.aws_request_id
    
    try:
        # Ensure EFS directories exist
        try:
            ensure_directories()
        except Exception as e:
            # EFS mount failure
            logger.error({
                "timestamp": context.get_remaining_time_in_millis(),
                "level": "ERROR",
                "requestId": request_id,
                "error": {
                    "code": "MOUNT_FAILED",
                    "message": str(e),
                    "stage": "init"
                }
            })
            return {
                "statusCode": 500,
                "body": json.dumps({
                    "error": "MOUNT_FAILED",
                    "message": "Failed to initialize EFS mount",
                    "stage": "init",
                    "requestId": request_id
                })
            }
        
        # Determine event type and route to appropriate handler
        if 'Records' in event:
            # S3 event
            logger.info(f"Processing S3 event - RequestId: {request_id}")
            return handle_s3_event(event, request_id)
        else:
            # API Gateway event
            logger.info(f"Processing API Gateway event - RequestId: {request_id}")
            return handle_api_event(event, request_id)
            
    except Exception as e:
        # Catch-all error handler with structured logging
        import traceback
        stack_trace = traceback.format_exc()
        
        logger.error({
            "timestamp": context.get_remaining_time_in_millis(),
            "level": "ERROR",
            "requestId": request_id,
            "error": {
                "code": "INTERNAL_ERROR",
                "message": str(e),
                "stage": "handler"
            },
            "stackTrace": stack_trace
        })
        return {
            "statusCode": 500,
            "body": json.dumps({
                "error": "INTERNAL_ERROR",
                "message": "An unexpected error occurred",
                "requestId": request_id
            })
        }


def handle_s3_event(event: Dict[str, Any], request_id: str) -> Dict[str, Any]:
    """
    Handle S3 ObjectCreated event.
    Parses S3 event, downloads object, and writes to EFS.
    
    Args:
        event: S3 event notification
        request_id: Lambda request ID
        
    Returns:
        API Gateway response format
    """
    try:
        # Parse S3 event
        record = event['Records'][0]
        bucket = record['s3']['bucket']['name']
        key = unquote_plus(record['s3']['object']['key'])
        size = record['s3']['object']['size']
        
        logger.info(f"S3 event: bucket={bucket}, key={key}, size={size}")
        
        # Validate file size (max 1 GB)
        max_size = 1 * 1024 * 1024 * 1024  # 1 GB in bytes
        if size > max_size:
            logger.warning(f"File too large: {size} bytes (max: {max_size})")
            return {
                "statusCode": 413,
                "body": json.dumps({
                    "error": "FILE_TOO_LARGE",
                    "maxSize": "1GB",
                    "actualSize": size,
                    "key": key
                })
            }
        
        # Download from S3
        file_data, file_size = download_from_s3(bucket, key)
        
        # Write to EFS atomically
        file_id, efs_path = write_to_efs_atomic(file_data, key, request_id)
        
        # Return success response
        logger.info(f"Successfully processed S3 event: fileId={file_id}, path={efs_path}")
        
        return create_success_response(file_id, efs_path, key, file_size)
        
    except s3_client.exceptions.NoSuchKey:
        return create_error_response(
            404, "S3_NOT_FOUND", 
            f"S3 object not found: {key}", 
            request_id, 
            key=key
        )
    except s3_client.exceptions.ClientError as e:
        error_code = e.response['Error']['Code']
        if error_code == 'AccessDenied':
            return create_error_response(
                403, "S3_ACCESS_DENIED",
                f"Access denied to S3 object: {key}",
                request_id,
                key=key
            )
        raise
    except Exception as e:
        import traceback
        logger.error({
            "requestId": request_id,
            "error": "S3_EVENT_FAILED",
            "message": str(e),
            "stage": "s3_event",
            "stackTrace": traceback.format_exc()
        })
        raise


def download_from_s3(bucket: str, key: str) -> Tuple[bytes, int]:
    """
    Download object from S3.
    
    Args:
        bucket: S3 bucket name
        key: S3 object key
        
    Returns:
        Tuple of (file_data, file_size)
    """
    logger.info(f"Downloading from S3: s3://{bucket}/{key}")
    
    response = s3_client.get_object(Bucket=bucket, Key=key)
    file_data = response['Body'].read()
    file_size = len(file_data)
    
    logger.info(f"Downloaded {file_size} bytes from S3")
    
    return file_data, file_size


def write_to_efs_atomic(file_data: bytes, s3_key: str, request_id: str) -> Tuple[str, str]:
    """
    Write file to EFS using atomic rename operation.
    Implements idempotency by checking if file already exists.
    
    Args:
        file_data: File content as bytes
        s3_key: Original S3 key (used to determine target path)
        request_id: Lambda request ID for logging
        
    Returns:
        Tuple of (file_id, efs_path)
    """
    efs_mount_path = os.environ.get('EFS_MOUNT_PATH', '/mnt/efs')
    
    # Determine target directory based on S3 key prefix
    if s3_key.startswith('models/'):
        target_dir = os.path.join(efs_mount_path, 'models')
        filename = s3_key.replace('models/', '', 1)
    elif s3_key.startswith('inputs/'):
        target_dir = os.path.join(efs_mount_path, 'inputs')
        filename = s3_key.replace('inputs/', '', 1)
    else:
        # Default to models directory
        target_dir = os.path.join(efs_mount_path, 'models')
        filename = os.path.basename(s3_key)
    
    final_path = os.path.join(target_dir, filename)
    
    # Idempotency check: if file already exists, return existing file info
    if os.path.exists(final_path):
        existing_size = os.path.getsize(final_path)
        # Generate consistent file_id based on path
        file_id = str(uuid.uuid5(uuid.NAMESPACE_DNS, final_path))
        
        logger.info(f"File already exists at {final_path}, returning existing file (idempotent)")
        logger.info({
            "requestId": request_id,
            "fileId": file_id,
            "efsPath": final_path,
            "status": "exists",
            "sizeBytes": existing_size
        })
        
        return file_id, final_path
    
    # Generate unique file ID
    file_id = str(uuid.uuid4())
    
    # Create temporary file with unique name
    temp_filename = f".tmp-{file_id}"
    temp_path = os.path.join(target_dir, temp_filename)
    
    try:
        # Write to temporary file
        logger.info(f"Writing to temporary file: {temp_path}")
        with open(temp_path, 'wb') as f:
            f.write(file_data)
        
        # Atomic rename to final path
        logger.info(f"Performing atomic rename: {temp_path} -> {final_path}")
        os.rename(temp_path, final_path)
        
        logger.info({
            "requestId": request_id,
            "fileId": file_id,
            "efsPath": final_path,
            "stage": "write",
            "status": "success",
            "sizeBytes": len(file_data)
        })
        
        return file_id, final_path
        
    except OSError as e:
        logger.error({
            "requestId": request_id,
            "fileId": file_id,
            "error": "EFS_WRITE_FAILED",
            "message": str(e),
            "stage": "write",
            "path": final_path
        })
        
        # Clean up temporary file if it exists
        if os.path.exists(temp_path):
            try:
                os.remove(temp_path)
            except:
                pass
        
        raise Exception(f"Failed to write file to EFS: {str(e)}")


def handle_api_event(event: Dict[str, Any], request_id: str) -> Dict[str, Any]:
    """
    Handle API Gateway proxy event (POST /ingest).
    Accepts JSON body with "key" (S3 key) or "data" (raw data) fields.
    
    Args:
        event: API Gateway proxy event
        request_id: Lambda request ID
        
    Returns:
        API Gateway response format
    """
    try:
        # Parse request body
        body = event.get('body', '{}')
        if isinstance(body, str):
            try:
                body = json.loads(body)
            except json.JSONDecodeError:
                return create_error_response(
                    400, "INVALID_REQUEST",
                    "Request body must be valid JSON",
                    request_id
                )
        
        # Validate request payload
        if not body:
            return create_error_response(
                400, "INVALID_REQUEST",
                "Request body is required",
                request_id
            )
        
        # Handle "key" field (download from S3)
        if 'key' in body:
            s3_key = body['key']
            bucket = os.environ.get('S3_BUCKET_NAME')
            
            if not bucket:
                return create_error_response(
                    500, "CONFIGURATION_ERROR",
                    "S3 bucket not configured",
                    request_id
                )
            
            logger.info(f"API request to ingest from S3: {s3_key}")
            
            # Download from S3
            file_data, file_size = download_from_s3(bucket, s3_key)
            
            # Write to EFS atomically
            file_id, efs_path = write_to_efs_atomic(file_data, s3_key, request_id)
            
            logger.info(f"Successfully processed API request: fileId={file_id}")
            return create_success_response(file_id, efs_path, s3_key, file_size)
            
        # Handle "data" field (raw payload data)
        elif 'data' in body:
            data = body['data']
            filename = body.get('filename', 'data.bin')
            
            logger.info(f"API request to ingest raw data: {filename}")
            
            # Convert data to bytes if it's a string
            if isinstance(data, str):
                file_data = data.encode('utf-8')
            else:
                file_data = json.dumps(data).encode('utf-8')
            
            file_size = len(file_data)
            
            # Validate file size (max 1 GB)
            max_size = 1 * 1024 * 1024 * 1024  # 1 GB
            if file_size > max_size:
                return create_error_response(
                    413, "FILE_TOO_LARGE",
                    f"File size {file_size} bytes exceeds maximum of 1GB",
                    request_id,
                    maxSize="1GB",
                    actualSize=file_size
                )
            
            # Write to EFS atomically
            file_id, efs_path = write_to_efs_atomic(file_data, filename, request_id)
            
            logger.info(f"Successfully processed API request: fileId={file_id}")
            return create_success_response(file_id, efs_path, filename, file_size)
            
        else:
            return create_error_response(
                400, "INVALID_REQUEST",
                "Request body must contain 'key' or 'data' field",
                request_id
            )
        
    except s3_client.exceptions.NoSuchKey:
        return create_error_response(
            404, "S3_NOT_FOUND",
            "S3 object not found",
            request_id,
            key=body.get('key')
        )
    except s3_client.exceptions.ClientError as e:
        error_code = e.response['Error']['Code']
        if error_code == 'AccessDenied':
            return create_error_response(
                403, "S3_ACCESS_DENIED",
                "Access denied to S3 object",
                request_id
            )
        raise
    except Exception as e:
        import traceback
        logger.error({
            "requestId": request_id,
            "error": "API_EVENT_FAILED",
            "message": str(e),
            "stage": "api_event",
            "stackTrace": traceback.format_exc()
        })
        raise
