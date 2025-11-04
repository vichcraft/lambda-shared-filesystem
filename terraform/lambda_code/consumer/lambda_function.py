import json
import os
import logging
import boto3
import hashlib
import time
from typing import Dict, Any, Optional, Tuple

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize S3 client
s3_client = boto3.client('s3')


def create_success_response(file_id: str, efs_path: str, duration_ms: int, 
                           result: Dict[str, Any], s3_key: Optional[str] = None) -> Dict[str, Any]:
    """
    Create standardized success response.
    
    Args:
        file_id: File identifier from request
        efs_path: Path to output file on EFS
        duration_ms: Processing duration in milliseconds
        result: Processing result dictionary
        s3_key: Optional S3 archive path
        
    Returns:
        API Gateway response format
    """
    response_body = {
        "fileId": file_id,
        "efsPath": efs_path,
        "durationMs": duration_ms,
        "result": result
    }
    
    if s3_key:
        response_body["s3Key"] = s3_key
    
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


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda handler for Consumer function.
    Handles API Gateway proxy events (POST /predict).
    
    Args:
        event: Lambda event (API Gateway proxy)
        context: Lambda context object
        
    Returns:
        API Gateway response format with statusCode and body
    """
    request_id = context.aws_request_id
    start_time = time.time()
    
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
        
        # Validate required fields
        if not body:
            return create_error_response(
                400, "INVALID_REQUEST",
                "Request body is required",
                request_id
            )
        
        file_id = body.get('fileId')
        model = body.get('model')
        
        if not file_id:
            return create_error_response(
                400, "INVALID_REQUEST",
                "Missing required field: fileId",
                request_id
            )
        
        if not model:
            return create_error_response(
                400, "INVALID_REQUEST",
                "Missing required field: model",
                request_id
            )
        
        logger.info(f"Processing inference request - fileId: {file_id}, model: {model}")
        
        # Get environment variables
        efs_mount_path = os.environ.get('EFS_MOUNT_PATH', '/mnt/efs')
        s3_bucket_name = os.environ.get('S3_BUCKET_NAME')
        enable_s3_archive = os.environ.get('ENABLE_S3_ARCHIVE', 'false').lower() == 'true'
        
        # Load model from EFS
        model_path = os.path.join(efs_mount_path, 'models', model)
        try:
            model_data = load_model_from_efs(model_path, file_id, request_id)
        except FileNotFoundError as e:
            # Return 404 response for missing model
            return json.loads(str(e))
        
        # Process inference
        result = process_inference(model_data, file_id)
        
        # Write result to EFS
        output_path = os.path.join(efs_mount_path, 'outputs', f"{file_id}.result")
        write_result_to_efs(result, output_path)
        
        # Optional: Archive to S3
        s3_key = None
        if enable_s3_archive and s3_bucket_name:
            s3_key = archive_to_s3(result, file_id, s3_bucket_name, request_id)
        
        # Calculate duration
        duration_ms = int((time.time() - start_time) * 1000)
        
        logger.info(f"Successfully processed inference - fileId: {file_id}, duration: {duration_ms}ms")
        
        return create_success_response(file_id, output_path, duration_ms, result, s3_key)
        
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



def load_model_from_efs(model_path: str, file_id: str, request_id: str) -> bytes:
    """
    Load model file from EFS.
    
    Args:
        model_path: Full path to model file on EFS
        file_id: File identifier for error reporting
        request_id: Lambda request ID for logging
        
    Returns:
        Model file content as bytes
        
    Raises:
        FileNotFoundError: If model file doesn't exist
    """
    logger.info(f"Loading model from EFS: {model_path}")
    
    # Check if file exists
    if not os.path.exists(model_path):
        logger.warning(f"Model file not found: {model_path}")
        
        # Create structured error response
        error_response = create_error_response(
            404, "NOT_FOUND",
            f"Model file not found on EFS",
            request_id,
            fileId=file_id,
            path=model_path
        )
        
        # Raise exception with the error response
        raise FileNotFoundError(json.dumps(error_response))
    
    try:
        # Read model file
        with open(model_path, 'rb') as f:
            model_data = f.read()
        
        file_size = len(model_data)
        logger.info(f"Successfully loaded model: {file_size} bytes from {model_path}")
        
        return model_data
        
    except OSError as e:
        logger.error({
            "requestId": request_id,
            "fileId": file_id,
            "error": "EFS_READ_FAILED",
            "message": str(e),
            "path": model_path
        })
        raise Exception(f"Failed to read model from EFS: {str(e)}")



def process_inference(model_data: bytes, file_id: str) -> Dict[str, Any]:
    """
    Perform processing/inference operation on the model data.
    For POC, this performs simple computation: file metadata and checksum.
    
    Args:
        model_data: Model file content as bytes
        file_id: File identifier
        
    Returns:
        Dictionary containing processing results
    """
    logger.info(f"Processing inference for fileId: {file_id}")
    
    processing_start = time.time()
    
    # Calculate file metadata
    file_size = len(model_data)
    
    # Calculate checksum (SHA-256)
    checksum = hashlib.sha256(model_data).hexdigest()
    
    # Simulate some processing (simple computation)
    # Count byte frequency as a simple processing operation
    byte_counts = {}
    for byte in model_data[:1000]:  # Sample first 1000 bytes for efficiency
        byte_counts[byte] = byte_counts.get(byte, 0) + 1
    
    # Calculate some statistics
    unique_bytes = len(byte_counts)
    most_common_byte = max(byte_counts.items(), key=lambda x: x[1])[0] if byte_counts else 0
    
    processing_duration = int((time.time() - processing_start) * 1000)
    
    result = {
        "fileId": file_id,
        "fileSize": file_size,
        "checksum": checksum,
        "uniqueBytes": unique_bytes,
        "mostCommonByte": most_common_byte,
        "processingDurationMs": processing_duration,
        "status": "success"
    }
    
    logger.info(f"Processing complete - fileId: {file_id}, duration: {processing_duration}ms")
    
    return result



def write_result_to_efs(result: Dict[str, Any], output_path: str) -> None:
    """
    Write processing result to EFS.
    
    Args:
        result: Processing result dictionary
        output_path: Full path to output file on EFS
    """
    logger.info(f"Writing result to EFS: {output_path}")
    
    try:
        # Ensure output directory exists
        output_dir = os.path.dirname(output_path)
        os.makedirs(output_dir, exist_ok=True)
        
        # Write result as JSON
        with open(output_path, 'w') as f:
            json.dump(result, f, indent=2)
        
        file_size = os.path.getsize(output_path)
        logger.info(f"Successfully wrote result to EFS: {file_size} bytes")
        
    except OSError as e:
        logger.error(f"Failed to write result to EFS: {str(e)}")
        raise Exception(f"Failed to write result to EFS: {str(e)}")


def archive_to_s3(result: Dict[str, Any], file_id: str, bucket_name: str, 
                  request_id: str) -> Optional[str]:
    """
    Archive processing result to S3.
    
    Args:
        result: Processing result dictionary
        file_id: File identifier
        bucket_name: S3 bucket name
        request_id: Lambda request ID for logging
        
    Returns:
        S3 key if successful, None if failed
    """
    s3_key = f"outputs/{file_id}.result"
    
    try:
        logger.info(f"Archiving result to S3: s3://{bucket_name}/{s3_key}")
        
        # Convert result to JSON string
        result_json = json.dumps(result, indent=2)
        
        # Upload to S3
        s3_client.put_object(
            Bucket=bucket_name,
            Key=s3_key,
            Body=result_json.encode('utf-8'),
            ContentType='application/json'
        )
        
        logger.info(f"Successfully archived result to S3: {s3_key}")
        return s3_key
        
    except Exception as e:
        # Log error but don't fail the request
        logger.error({
            "requestId": request_id,
            "fileId": file_id,
            "error": "S3_ARCHIVE_FAILED",
            "message": str(e),
            "s3Key": s3_key
        })
        # Return None to indicate archiving failed
        return None
