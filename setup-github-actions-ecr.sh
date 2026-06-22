#!/bin/bash

# GitHub Actions + AWS ECR OIDC セットアップスクリプト
# 使い方: bash setup-github-actions-ecr.sh <AWS_ACCOUNT_ID> <GITHUB_USERNAME> <GITHUB_REPO_NAME> <ECR_REPO_NAME> <AWS_REGION>

set -e

# パラメータ確認
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
POLICY_NAME="GitHubActionsECRPolicy"

echo "========================================="
echo "GitHub Actions + AWS ECR OIDC セットアップ"
echo "========================================="
echo "AWS Account ID: $AWS_ACCOUNT_ID"
echo "GitHub User: $GITHUB_USERNAME"
echo "GitHub Repo: $GITHUB_REPO"
echo "ECR Repo: $ECR_REPO_NAME"
echo "AWS Region: $AWS_REGION"
echo "IAM Role: $ROLE_NAME"
echo "=========================================\n"

# ステップ 1: 既存のロール・ポリシーを削除
echo "📋 ステップ 1: 既存リソースをクリーンアップ..."

if aws iam get-role --role-name $ROLE_NAME 2>/dev/null; then
    echo "  - インラインポリシー削除..."
    aws iam delete-role-policy --role-name $ROLE_NAME --policy-name $POLICY_NAME 2>/dev/null || true
    
    echo "  - ロール削除..."
    aws iam delete-role --role-name $ROLE_NAME
else
    echo "  - 既存ロールなし（スキップ）"
fi

if aws iam get-policy --policy-arn arn:aws:iam::$AWS_ACCOUNT_ID:policy/$POLICY_NAME 2>/dev/null; then
    echo "  - カスタマーマネージドポリシー削除..."
    aws iam delete-policy --policy-arn arn:aws:iam::$AWS_ACCOUNT_ID:policy/$POLICY_NAME
fi

# ステップ 2: OIDC プロバイダーの削除・再作成
echo "\n📋 ステップ 2: OIDC プロバイダーを設定..."

OIDC_ARN="arn:aws:iam::$AWS_ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"

if aws iam get-open-id-connect-provider --open-id-connect-provider-arn $OIDC_ARN 2>/dev/null; then
    echo "  - 既存 OIDC プロバイダー削除..."
    aws iam delete-open-id-connect-provider --open-id-connect-provider-arn $OIDC_ARN
fi

echo "  - 新しい OIDC プロバイダー作成..."
# 最新の Thumbprint を取得
THUMBPRINT=$(openssl s_client -connect token.actions.githubusercontent.com:443 -showcerts 2>/dev/null | openssl x509 -fingerprint -noout | sed 's/://g' | awk '{print tolower($NF)}')

echo "    Thumbprint: $THUMBPRINT"

aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list $THUMBPRINT

# ステップ 3: Trust Relationship JSON を作成
echo "\n📋 ステップ 3: IAM ロール作成..."

TRUST_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::$AWS_ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:$GITHUB_USERNAME/$GITHUB_REPO:*"
        }
      }
    }
  ]
}
EOF
)

echo "  - Trust Relationship: repo:$GITHUB_USERNAME/$GITHUB_REPO:*"

echo "$TRUST_POLICY" > /tmp/trust-policy.json

aws iam create-role \
  --role-name $ROLE_NAME \
  --assume-role-policy-document file:///tmp/trust-policy.json

# ステップ 4: ECR ポリシー作成・アタッチ
echo "\n📋 ステップ 4: ECR パーミッションポリシー作成..."

ECR_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:PutImage",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload"
      ],
      "Resource": "arn:aws:ecr:*:$AWS_ACCOUNT_ID:repository/*"
    },
    {
      "Effect": "Allow",
      "Action": "ecr:GetAuthorizationToken",
      "Resource": "*"
    }
  ]
}
EOF
)

echo "$ECR_POLICY" > /tmp/ecr-policy.json

aws iam put-role-policy \
  --role-name $ROLE_NAME \
  --policy-name $POLICY_NAME \
  --policy-document file:///tmp/ecr-policy.json

# ステップ 5: ECR リポジトリ作成
echo "\n📋 ステップ 5: ECR リポジトリ作成..."

if aws ecr describe-repositories --repository-names $ECR_REPO_NAME --region $AWS_REGION 2>/dev/null; then
    echo "  - リポジトリ既存（スキップ）"
else
    echo "  - 新規作成: $ECR_REPO_NAME"
    aws ecr create-repository \
      --repository-name $ECR_REPO_NAME \
      --region $AWS_REGION
fi

# クリーンアップ
rm -f /tmp/trust-policy.json /tmp/ecr-policy.json

# 完了
echo "\n========================================="
echo "✅ セットアップ完了！"
echo "========================================="
echo ""
echo "📋 確認コマンド:"
echo ""
echo "1. ロール ARN を確認:"
echo "   aws iam get-role --role-name $ROLE_NAME --query 'Role.Arn' --output text"
echo ""
echo "2. ポリシーが正しくアタッチされているか確認:"
echo "   aws iam list-attached-role-policies --role-name $ROLE_NAME"
echo ""
echo "3. ECR リポジトリを確認:"
echo "   aws ecr describe-repositories --repository-names $ECR_REPO_NAME --region $AWS_REGION"
echo ""
echo "📝 ワークフロー内で使用する値:"
echo ""
echo "  role-to-assume: arn:aws:iam::$AWS_ACCOUNT_ID:role/$ROLE_NAME"
echo ""
echo "🚀 次のステップ:"
echo "  1. ワークフロー yaml 内の role-to-assume を上の値で更新"
echo "  2. git add / commit / push"
echo "  3. GitHub Actions を確認"
echo ""
