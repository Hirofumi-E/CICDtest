#!/bin/bash

# AWS リソース削除スクリプト
# 使い方: bash scripts/cleanup-aws.sh <AWS_ACCOUNT_ID>

set -e

if [ $# -ne 1 ]; then
    echo "使い方: $0 <AWS_ACCOUNT_ID>"
    echo ""
    echo "例: $0 471451200767"
    exit 1
fi

AWS_ACCOUNT_ID=$1
ROLE_NAME="GitHubActionsECRRole"
ECR_REPO_NAME="my-app"
AWS_REGION="ap-northeast-1"

echo "========================================="
echo "AWS リソース削除"
echo "========================================="
echo "AWS Account ID: $AWS_ACCOUNT_ID"
echo ""
echo "⚠️  以下が削除されます："
echo "  - IAM ロール: $ROLE_NAME"
echo "  - ECR リポジトリ: $ECR_REPO_NAME"
echo "  - OIDC プロバイダー"
echo ""
read -p "本当に削除しますか？ (yes/no): " confirmation

if [ "$confirmation" != "yes" ]; then
    echo "キャンセルしました。"
    exit 0
fi

echo ""
echo "削除開始..."

# ロールのインラインポリシーを削除
echo "1. インラインポリシー削除..."
aws iam list-role-policies --role-name $ROLE_NAME 2>/dev/null | \
  jq -r '.PolicyNames[]' | \
  while read policy; do
    aws iam delete-role-policy --role-name $ROLE_NAME --policy-name $policy
  done || true

# ロールのアタッチされたポリシーをデタッチ
echo "2. アタッチされたポリシーをデタッチ..."
aws iam list-attached-role-policies --role-name $ROLE_NAME 2>/dev/null | \
  jq -r '.AttachedPolicies[].PolicyArn' | \
  while read arn; do
    aws iam detach-role-policy --role-name $ROLE_NAME --policy-arn $arn
  done || true

# ロール削除
echo "3. IAM ロール削除..."
aws iam delete-role --role-name $ROLE_NAME 2>/dev/null || true

# ECR リポジトリ削除
echo "4. ECR リポジトリ削除..."
aws ecr delete-repository \
  --repository-name $ECR_REPO_NAME \
  --region $AWS_REGION \
  --force 2>/dev/null || true

# OIDC プロバイダー削除
echo "5. OIDC プロバイダー削除..."
OIDC_ARN="arn:aws:iam::$AWS_ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
aws iam delete-open-id-connect-provider \
  --open-id-connect-provider-arn $OIDC_ARN 2>/dev/null || true

echo ""
echo "========================================="
echo "✅ 削除完了！"
echo "========================================="
echo ""
echo "再度セットアップする場合は以下を実行："
echo "  bash scripts/setup-aws.sh $AWS_ACCOUNT_ID Hirofumi-E CICDtest my-app ap-northeast-1"
echo ""
