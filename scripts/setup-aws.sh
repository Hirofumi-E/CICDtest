#!/bin/bash

# GitHub Actions + AWS ECR OIDC セットアップスクリプト
# 使い方: bash scripts/setup-aws.sh <AWS_ACCOUNT_ID> <GITHUB_USERNAME> <GITHUB_REPO_NAME> <ECR_REPO_NAME> <AWS_REGION>

set -e

if [ $# -ne 5 ]; then
    echo "使い方: $0 <AWS_ACCOUNT_ID> <GITHUB_USERNAME> <GITHUB_REPO_NAME> <ECR_REPO_NAME> <AWS_REGION>"
    echo ""
    echo "例:"
    echo "  $0 471451200767 Hirofumi-E CICDtest my-app ap-northeast-1"
    exit 1
fi

AWS_ACCOUNT_ID=$1
GITHUB_USERNAME=$2
GITHUB_REPO=$3
ECR_REPO_NAME=$4
AWS_REGION=$5
ROLE_NAME="GitHubActionsECRRole"

echo "========================================="
echo "GitHub Actions + AWS ECR セットアップ"
echo "========================================="
echo "AWS Account ID: $AWS_ACCOUNT_ID"
echo "GitHub User: $GITHUB_USERNAME"
echo "GitHub Repo: $GITHUB_REPO"
echo "ECR Repo: $ECR_REPO_NAME"
echo "AWS Region: $AWS_REGION"
echo "=========================================\n"

# ステップ 1: Thumbprint 取得
echo "📋 ステップ 1: OIDC Thumbprint を取得中..."
THUMBPRINT=$(openssl s_client -connect token.actions.githubusercontent.com:443 -showcerts 2>/dev/null | openssl x509 -fingerprint -noout | sed 's/://g' | awk '{print tolower($NF)}')
echo "  Thumbprint: $THUMBPRINT"

# ステップ 2: OIDC プロバイダー作成
echo "\n📋 ステップ 2: OIDC プロバイダーを作成中..."
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list $THUMBPRINT

# ステップ 3: IAM ロール作成
echo "\n📋 ステップ 3: IAM ロールを作成中..."
aws iam create-role \
  --role-name $ROLE_NAME \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Principal": {
          "Federated": "arn:aws:iam::'"$AWS_ACCOUNT_ID"':oidc-provider/token.actions.githubusercontent.com"
        },
        "Action": "sts:AssumeRoleWithWebIdentity",
        "Condition": {
          "StringEquals": {
            "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
          },
          "StringLike": {
            "token.actions.githubusercontent.com:sub": "repo:'"$GITHUB_USERNAME"'/'"$GITHUB_REPO"':*"
          }
        }
      }
    ]
  }'

# ステップ 4: ポリシーをアタッチ
echo "\n📋 ステップ 4: ECR ポリシーをアタッチ中..."
aws iam attach-role-policy \
  --role-name $ROLE_NAME \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser

# ステップ 5: ECR リポジトリ作成
echo "\n📋 ステップ 5: ECR リポジトリを作成中..."
aws ecr create-repository \
  --repository-name $ECR_REPO_NAME \
  --region $AWS_REGION

# 完了
echo "\n========================================="
echo "✅ セットアップ完了！"
echo "========================================="
echo ""
echo "📝 ワークフロー内で使用する値:"
echo ""
echo "  role-to-assume: arn:aws:iam::$AWS_ACCOUNT_ID:role/$ROLE_NAME"
echo ""
echo "🧹 削除したい場合は以下を実行:"
echo ""
echo "  bash scripts/cleanup-aws.sh $AWS_ACCOUNT_ID"
echo ""
