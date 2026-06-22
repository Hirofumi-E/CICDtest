# GitHub Actions + AWS ECR CI/CD パイプライン

GitHub Actions から AWS ECR へ Docker イメージを自動的に push するパイプラインです。

---

## 📋 セットアップ手順

### 必要な情報
```
- AWS アカウント ID（12 桁の数字）
- GitHub ユーザー名
- GitHub リポジトリ名
- ECR リポジトリ名（例：my-app）
- AWS リージョン（例：ap-northeast-1）
```

### セットアップ実行

```bash
bash scripts/setup-aws.sh \
  <AWS_ACCOUNT_ID> \
  <GITHUB_USERNAME> \
  <GITHUB_REPO_NAME> \
  <ECR_REPO_NAME> \
  <AWS_REGION>
```

**例：**
```bash
bash scripts/setup-aws.sh 471451200767 Hirofumi-E CICDtest my-app ap-northeast-1
```

実行すると以下が自動的に作成されます：
- OIDC プロバイダー
- IAM ロール（GitHub Actions 用）
- ECR リポジトリ

---

## 🚀 動作の流れ

```
1. Git main ブランチに push
   ↓
2. GitHub Actions が自動実行
   ↓
3. Docker イメージをビルド
   ↓
4. OIDC で AWS に認証
   ↓
5. AWS ECR にイメージを push
```

---

## 🧹 リソース削除

AWS リソース（IAM ロール、ECR リポジトリなど）を削除したい場合：

```bash
bash scripts/cleanup-aws.sh <AWS_ACCOUNT_ID>
```

**例：**
```bash
bash scripts/cleanup-aws.sh 471451200767
```

⚠️ 削除確認が出ます。`yes` を入力してください。

---

## 📝 ワークフロー設定

`.github/workflows/ecr-push.yml` の以下の行が正しく設定されていることを確認：

```yaml
role-to-assume: arn:aws:iam::471451200767:role/GitHubActionsECRRole
```

---

## ✅ 動作確認

### GitHub Actions で確認

```
GitHub リポジトリ
  → Actions タブ
  → Build and Push to ECR ワークフロー
  → ✅ 緑色で成功
```

### AWS ECR で確認

```bash
aws ecr describe-images \
  --repository-name my-app \
  --region ap-northeast-1
```

イメージが登録されていれば成功です。

---

## 🔒 セキュリティに関する注意

このセットアップは以下を使用しています：

- **OIDC 認証** - 長期的なアクセスキーを使用しない（セキュア）
- **最小権限** - `AmazonEC2ContainerRegistryPowerUser` をアタッチ

---

## 🔄 別環境への再セットアップ

同じ設定を別の環境で使用する場合：

1. リポジトリをクローン
2. `scripts/setup-aws.sh` を実行
3. 完了

スクリプトですべてが自動化されているため、手作業は不要です。

---

## 📚 参考資料

- [AWS IAM OIDC プロバイダー](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_create_oidc.html)
- [GitHub Actions AWS 認証](https://github.com/aws-actions/configure-aws-credentials)
- [AWS ECR](https://aws.amazon.com/ecr/)

---

## 💡 次のステップ

セットアップ完了後のオプション設定：

- [ ] ECR イメージへの脆弱性スキャン有効化
- [ ] ライフサイクルポリシー設定（古いイメージを自動削除）
- [ ] ECS/EKS への自動デプロイ
- [ ] GitHub Actions での通知設定
