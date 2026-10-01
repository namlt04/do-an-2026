# logging.tf
# MISCONFIG (baseline): LOGGING BI TAT / THIEU.
#   - Khong co VPC flow log  -> mat kha nang dieu tra su co mang.
#   - Khong co S3 access log  -> khong biet ai truy cap bucket.
#
# Huong sua (Task 4): bat logging con thieu, vi du:
#   - Them aws_flow_log cho VPC (toi CloudWatch Logs, kem log group va IAM role scoped).
#   - Them aws_s3_bucket_logging cho bucket du lieu (tro toi bucket log da hardening).
#
# Cac rule logging thuong o muc MEDIUM (khong chan quality gate 0 HIGH/CRITICAL),
# nhung day la best practice can hoan tat trong Definition of Done cua ha tang.
#
# --- Vi du cau hinh dang bi vo hieu hoa (comment) ---
# resource "aws_cloudwatch_log_group" "vpc" {
#   name              = "/ptit/vpc/flowlogs"
#   retention_in_days = 30
# }
#
# resource "aws_flow_log" "vpc" {
#   log_destination = aws_cloudwatch_log_group.vpc.arn
#   traffic_type    = "ALL"
#   vpc_id          = aws_vpc.main.id
#   iam_role_arn    = aws_iam_role.flowlog.arn
# }
